# frozen_string_literal: true

# Run (no SketchUp needed): ruby tests/tc_catalog.rb
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'json'
require_relative 'stub_sketchup'
require_relative '../skp_cm_extensions_hub/catalog'

class TestCatalog < Minitest::Test
  C = SkpCm::ExtensionsHub::Catalog

  ITEM = {
    'id' => 'ropefall', 'name' => 'Ropefall', 'repo' => 'bhurivaj/ropefall',
    'description' => 'rope', 'files' => ['sketchrope_ropefall.rb', 'sketchrope_ropefall/']
  }.freeze

  def setup
    @plugins = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry(@plugins)
  end

  def install_loader
    File.write(File.join(@plugins, 'sketchrope_ropefall.rb'), '#')
  end

  def release(tag, assets = [{ 'name' => 'ropefall_2.0.1.rbz', 'browser_download_url' => 'https://x/r.rbz' }])
    { 'tag_name' => tag, 'body' => "notes for #{tag}", 'assets' => assets }
  end

  def entry(installed_version: nil, release: nil, release_error: nil, item: ITEM)
    C.build_entry(item, plugins_dir: @plugins, installed_version: installed_version,
                        release: release, release_error: release_error)
  end

  # --- parse_index ---

  def test_parse_index_returns_plugins
    assert_equal 1, C.parse_index('{"schema":1,"plugins":[{"id":"a"}]}').size
  end

  def test_parse_index_rejects_other_schema
    assert_raises(C::SchemaError) { C.parse_index('{"schema":2,"plugins":[]}') }
  end

  def test_parse_index_rejects_non_json
    assert_raises(JSON::ParserError) { C.parse_index('<html>') }
  end

  def test_repo_index_json_is_valid_and_hub_first
    path = File.expand_path('../index.json', __dir__)
    plugins = C.parse_index(File.read(path))
    assert_equal C::HUB_ID, plugins.first['id']
    plugins.each do |p|
      %w[id name repo description author].each { |k| refute_empty p[k].to_s, "#{p['id']} missing #{k}" }
      refute_empty p['files'], "#{p['id']} has no files"
    end
    assert_equal plugins.size, plugins.map { |p| p['id'] }.uniq.size, 'duplicate ids'
  end

  # --- compare_versions ---

  def test_compare_versions_numeric_not_string
    assert_equal 1, C.compare_versions('1.0.10', '1.0.9')
    assert_equal 0, C.compare_versions('2.0.0', '2.0.0')
    assert_equal(-1, C.compare_versions('1.9.0', '2.0.0'))
  end

  def test_compare_versions_unparsable_is_nil
    assert_nil C.compare_versions('release-1', '1.0.0')
    assert_nil C.compare_versions(nil, '1.0.0')
    assert_nil C.compare_versions('1.0.0', '')
  end

  # --- build_entry ---

  def test_not_installed
    e = entry(release: release('v2.0.1'))
    assert_equal 'not_installed', e['status']
    assert_equal false, e['installed']
    assert_equal '2.0.1', e['latest_version']
    assert_equal 'https://x/r.rbz', e['asset_url']
    assert_equal 'notes for v2.0.1', e['notes']
  end

  def test_author_is_passed_through
    assert_equal 'Balazs Torma', entry(item: ITEM.merge('author' => 'Balazs Torma'))['author']
    assert_equal '', entry['author'], 'missing author becomes empty string'
  end

  def test_update_available
    install_loader
    assert_equal 'update_available', entry(installed_version: '2.0.0', release: release('v2.0.1'))['status']
  end

  def test_up_to_date_when_equal_or_newer_locally
    install_loader
    assert_equal 'up_to_date', entry(installed_version: '2.0.1', release: release('v2.0.1'))['status']
    assert_equal 'up_to_date', entry(installed_version: '2.1.0', release: release('v2.0.1'))['status']
  end

  def test_unknown_when_version_missing_or_unparsable
    install_loader
    assert_equal 'unknown', entry(installed_version: nil, release: release('v2.0.1'))['status']
    assert_equal 'unknown', entry(installed_version: '2.0.0', release: release('release-1'))['status']
    assert_equal 'unknown', entry(installed_version: '2.0.0', release_error: 'x')['status']
  end

  def test_first_rbz_asset_is_used
    assets = [{ 'name' => 'notes.txt', 'browser_download_url' => 'https://x/n' },
              { 'name' => 'a.rbz', 'browser_download_url' => 'https://x/a.rbz' },
              { 'name' => 'b.rbz', 'browser_download_url' => 'https://x/b.rbz' }]
    assert_equal 'https://x/a.rbz', entry(release: release('v1.0.0', assets))['asset_url']
  end

  def test_release_without_rbz_has_error
    e = entry(release: release('v1.0.0', []))
    assert_nil e['asset_url']
    assert_equal 'release ล่าสุดไม่มีไฟล์ .rbz', e['error']
  end

  def test_release_error_is_kept
    e = entry(release_error: 'เกินลิมิต')
    assert_equal 'เกินลิมิต', e['error']
    assert_nil e['latest_version']
  end

  def test_missing_files_means_not_installed_and_no_crash
    e = entry(item: ITEM.merge('files' => nil), release: release('v1.0.0'))
    assert_equal 'not_installed', e['status']
    assert_equal [], e['files']
  end

  def test_self_flag
    assert_equal true, entry(item: ITEM.merge('id' => C::HUB_ID))['self']
    assert_equal false, entry['self']
  end

  # --- release_error_message ---

  def test_release_error_messages
    assert_equal 'ยังไม่มี release', C.release_error_message(404)
    assert_includes C.release_error_message(403), 'เกินลิมิต'
    assert_includes C.release_error_message(429), 'เกินลิมิต'
    assert_includes C.release_error_message(500), 'HTTP 500'
  end

  # --- mark_pending ---

  def test_mark_pending
    entries = [{ 'id' => 'a' }, { 'id' => 'b' }]
    marked = C.mark_pending(entries, ['b'])
    assert_equal [false, true], marked.map { |e| e['pending_restart'] }
    assert_nil entries[0]['pending_restart'], 'must not mutate input'
  end
end
