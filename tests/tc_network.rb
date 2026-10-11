# frozen_string_literal: true

# Run (no SketchUp needed): ruby tests/tc_network.rb
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'json'
require_relative 'stub_sketchup'
require_relative '../skp_cm_extensions_hub/http'
require_relative '../skp_cm_extensions_hub/catalog'
require_relative '../skp_cm_extensions_hub/installer'

class TestNetwork < Minitest::Test
  H = SkpCm::ExtensionsHub::Http
  C = SkpCm::ExtensionsHub::Catalog
  I = SkpCm::ExtensionsHub::Installer

  INDEX = { 'schema' => 1, 'plugins' => [
    { 'id' => 'a', 'name' => 'A', 'repo' => 'u/a', 'files' => ['a.rb'] },
    { 'id' => 'b', 'name' => 'B', 'repo' => 'u/b', 'files' => ['b.rb'] }
  ] }.freeze

  def api(repo)
    "https://api.github.com/repos/#{repo}/releases/latest"
  end

  def release_json(tag)
    JSON.generate('tag_name' => tag, 'body' => '',
                  'assets' => [{ 'name' => 'x.rbz', 'browser_download_url' => "https://dl/#{tag}" }])
  end

  # responses: url => [status, body, error]
  def stub_http(responses)
    @requested = []
    requested = @requested
    H.define_singleton_method(:get) do |url, _headers = {}, &blk|
      requested << url
      blk.call(*responses.fetch(url))
    end
  end

  def setup
    @plugins = Dir.mktmpdir
    Sketchup.plugins_dir = @plugins
    Sketchup.extensions = {}
    Sketchup.archives = []
    Sketchup.install_error = nil
  end

  # each test file runs in its own ruby process, so the stubbed Http.get does not leak elsewhere
  def teardown
    FileUtils.remove_entry(@plugins)
  end

  def load_catalog
    result = nil
    C.load { |entries, error| result = [entries, error] }
    result
  end

  def test_load_merges_releases
    stub_http(C::INDEX_URL => [200, JSON.generate(INDEX), nil],
              api('u/a') => [200, release_json('v1.2.0'), nil],
              api('u/b') => [404, '{}', nil])
    entries, error = load_catalog
    assert_nil error
    assert_equal %w[a b], entries.map { |e| e['id'] }
    assert_equal '1.2.0', entries[0]['latest_version']
    assert_equal 'ยังไม่มี release', entries[1]['error']
  end

  def test_load_offline
    stub_http(C::INDEX_URL => [nil, nil, 'network error'])
    entries, error = load_catalog
    assert_nil entries
    assert_equal C::MSG_OFFLINE, error
  end

  def test_load_index_http_error
    stub_http(C::INDEX_URL => [404, 'nf', nil])
    entries, error = load_catalog
    assert_nil entries
    assert_includes error, 'HTTP 404'
  end

  def test_load_bad_schema
    stub_http(C::INDEX_URL => [200, '{"schema":9,"plugins":[]}', nil])
    assert_equal C::MSG_SCHEMA, load_catalog[1]
  end

  def test_load_index_not_json
    stub_http(C::INDEX_URL => [200, '<html>proxy</html>', nil])
    assert_equal C::MSG_BAD_INDEX, load_catalog[1]
  end

  def test_release_body_not_json_only_affects_that_card
    stub_http(C::INDEX_URL => [200, JSON.generate(INDEX), nil],
              api('u/a') => [200, '<html>proxy</html>', nil],
              api('u/b') => [200, release_json('v2.0.0'), nil])
    entries, error = load_catalog
    assert_nil error
    refute_nil entries[0]['error']
    assert_equal '2.0.0', entries[1]['latest_version']
  end

  def test_rate_limited_release
    stub_http(C::INDEX_URL => [200, JSON.generate(INDEX), nil],
              api('u/a') => [403, '{}', nil],
              api('u/b') => [nil, nil, 'timeout'])
    entries, = load_catalog
    assert_includes entries[0]['error'], 'เกินลิมิต'
    assert_equal C::MSG_OFFLINE, entries[1]['error']
  end

  def test_load_uses_installed_version
    File.write(File.join(@plugins, 'a.rb'), '#')
    Sketchup.extensions = { 'A' => Sketchup::FakeExtension.new('1.0.0') }
    stub_http(C::INDEX_URL => [200, JSON.generate(INDEX), nil],
              api('u/a') => [200, release_json('v1.2.0'), nil],
              api('u/b') => [404, '{}', nil])
    assert_equal 'update_available', load_catalog[0][0]['status']
  end

  def test_install_downloads_and_installs
    stub_http('https://dl/v1' => [200, 'RBZDATA', nil])
    result = nil
    I.install('id' => 'a', 'name' => 'A', 'installed' => false, 'latest_version' => '1',
              'asset_url' => 'https://dl/v1') { |ok, msg| result = [ok, msg] }
    assert result[0], result[1]
    assert_equal ['RBZDATA'], Sketchup.archives
  end

  def test_install_download_failure
    stub_http('https://dl/v1' => [500, '', nil])
    result = nil
    I.install('id' => 'a', 'name' => 'A', 'asset_url' => 'https://dl/v1') { |ok, msg| result = [ok, msg] }
    refute result[0]
    assert_includes result[1], 'ดาวน์โหลดไม่สำเร็จ'
    assert_empty Sketchup.archives
  end

  def test_install_without_asset
    result = nil
    I.install('id' => 'a', 'name' => 'A', 'asset_url' => nil) { |ok, msg| result = [ok, msg] }
    refute result[0]
  end

  def test_redirect_location
    assert_equal 'https://x', H.redirect_location(302, 'Location' => 'https://x')
    assert_equal 'https://y', H.redirect_location(301, 'location' => 'https://y')
    assert_nil H.redirect_location(200, 'location' => 'https://y')
    assert_nil H.redirect_location(302, {})
    assert_nil H.redirect_location(302, nil)
  end

  def test_load_bad_plugin_entry_calls_done_once
    [nil, 5].each do |bad|
      body = JSON.generate('schema' => 1, 'plugins' => [bad])
      stub_http(C::INDEX_URL => [200, body, nil])
      calls = []
      C.load { |entries, error| calls << [entries, error] }
      assert_equal [[nil, C::MSG_BAD_INDEX]], calls, "plugin entry: #{bad.inspect}"
    end
  end

  def test_load_build_entry_raising_calls_done_once
    stub_http(C::INDEX_URL => [200, JSON.generate(INDEX), nil],
              api('u/a') => [404, '{}', nil], api('u/b') => [404, '{}', nil])
    original = C.method(:build_entry)
    C.define_singleton_method(:build_entry) { |*_a, **_k| raise 'boom' }
    calls = []
    begin
      C.load { |entries, error| calls << [entries, error] }
    ensure
      C.define_singleton_method(:build_entry, original)
    end
    assert_equal [[nil, C::MSG_BAD_INDEX]], calls
  end

  def test_install_archive_raising_calls_done_once
    stub_http('https://dl/v1' => [200, 'RBZDATA', nil])
    original = I.method(:install_archive)
    I.define_singleton_method(:install_archive) { |*| raise 'boom' }
    calls = []
    begin
      I.install('id' => 'a', 'name' => 'A', 'asset_url' => 'https://dl/v1') { |ok, msg| calls << [ok, msg] }
    ensure
      I.define_singleton_method(:install_archive, original)
    end
    assert_equal 1, calls.size
    refute calls[0][0]
    assert_includes calls[0][1], 'boom'
  end
end
