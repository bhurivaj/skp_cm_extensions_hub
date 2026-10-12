# frozen_string_literal: true

# Run (no SketchUp needed): ruby tests/tc_installer.rb
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require_relative 'stub_sketchup'
require_relative '../skp_cm_extensions_hub/installer'

class TestInstaller < Minitest::Test
  I = SkpCm::ExtensionsHub::Installer

  def setup
    SkpCm::ExtensionsHub::Catalog.forget_enabled!
    @root = Dir.mktmpdir
    # real macOS path shape: spaces + non-ASCII
    @plugins = File.join(@root, 'Application Support', 'ปลั๊กอิน', 'Plugins')
    FileUtils.mkdir_p(@plugins)
    Sketchup.plugins_dir = @plugins
    Sketchup.extensions = {}
    Sketchup.archives = []
    Sketchup.install_error = nil
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def entry(overrides = {})
    { 'id' => 'ropefall', 'name' => 'Ropefall', 'installed' => true, 'latest_version' => '2.0.1',
      'files' => ['sketchrope_ropefall.rb', 'sketchrope_ropefall/'] }.merge(overrides)
  end

  def make_plugin
    File.write(File.join(@plugins, 'sketchrope_ropefall.rb'), '#')
    FileUtils.mkdir_p(File.join(@plugins, 'sketchrope_ropefall'))
    File.write(File.join(@plugins, 'sketchrope_ropefall', 'cable.rb'), '#')
    File.write(File.join(@plugins, 'other_plugin.rb'), '#')
  end

  # --- safe_path ---

  def test_safe_path_accepts_relative_inside
    assert_equal File.join(File.expand_path(@plugins), 'a', 'b.rb'), I.safe_path(@plugins, 'a/b.rb')
    assert_equal File.join(File.expand_path(@plugins), 'folder'), I.safe_path(@plugins, 'folder/')
  end

  def test_safe_path_rejects_escape_and_garbage
    ['../x.rb', 'a/../../b', '/etc/passwd', 'C:/Windows', '\\server\\x', '', '  ', nil, '.', 'a/..'].each do |bad|
      assert_nil I.safe_path(@plugins, bad), "should reject #{bad.inspect}"
    end
  end

  # --- remove ---

  def test_remove_deletes_listed_files_only
    make_plugin
    ext = Sketchup::FakeExtension.new('2.0.0')
    ext.uncheck
    Sketchup.extensions = { 'Ropefall' => ext }
    ok, msg = I.remove(entry)
    assert ok, msg
    refute File.exist?(File.join(@plugins, 'sketchrope_ropefall.rb'))
    refute File.exist?(File.join(@plugins, 'sketchrope_ropefall'))
    assert File.exist?(File.join(@plugins, 'other_plugin.rb'))
    assert ext.unchecked
    assert_includes msg, 'เปิด SketchUp ใหม่'
  end

  def test_remove_with_one_bad_path_deletes_nothing
    make_plugin
    ok, msg = I.remove(entry('files' => ['sketchrope_ropefall.rb', '../escape']))
    refute ok
    assert_includes msg, 'index.json ไม่ถูกต้อง'
    assert File.exist?(File.join(@plugins, 'sketchrope_ropefall.rb'))
  end

  def test_remove_with_no_files_is_refused
    ok, = I.remove(entry('files' => []))
    refute ok
  end

  def test_remove_refuses_hub_itself
    ok, msg = I.remove(entry('id' => SkpCm::ExtensionsHub::Catalog::HUB_ID))
    refute ok
    assert_includes msg, 'Hub'
  end

  def test_remove_refuses_enabled_extension
    make_plugin
    ext = Sketchup::FakeExtension.new('2.0.0')
    ext.loaded = true # checked extensions are loaded at start-up
    Sketchup.extensions = { 'Ropefall' => ext }
    ok, msg = I.remove(entry)
    refute ok
    assert_includes msg, 'ปิดใช้งาน'
    assert File.exist?(File.join(@plugins, 'sketchrope_ropefall.rb'))
  end

  # --- set_enabled ---

  def test_disable_unchecks_extension
    ext = Sketchup::FakeExtension.new('2.0.0')
    Sketchup.extensions = { 'Ropefall' => ext }
    ok, msg = I.set_enabled(entry, false)
    assert ok
    refute ext.load_on_start?
    assert_includes msg, 'restart'
  end

  def test_enable_checks_extension
    ext = Sketchup::FakeExtension.new('2.0.0')
    ext.uncheck
    Sketchup.extensions = { 'Ropefall' => ext }
    ok, = I.set_enabled(entry, true)
    assert ok
    assert ext.load_on_start?
  end

  def test_set_enabled_unknown_extension_fails
    ok, msg = I.set_enabled(entry, false)
    refute ok
    assert_includes msg, 'Ropefall'
  end

  def test_set_enabled_refuses_hub_itself
    Sketchup.extensions = { 'Hub' => Sketchup::FakeExtension.new('0.2.0') }
    ok, = I.set_enabled(entry('id' => SkpCm::ExtensionsHub::Catalog::HUB_ID, 'name' => 'Hub'), false)
    refute ok
  end

  def test_remove_missing_files_is_ok
    ok, = I.remove(entry)
    assert ok
  end

  # --- install_archive ---

  def test_install_archive_passes_bytes_and_cleans_temp
    data = "PK\x03\x04\xFF\x00binary".b
    ok, msg = I.install_archive(entry('installed' => false), data)
    assert ok, msg
    assert_equal [data], Sketchup.archives
    assert_empty Dir.glob(File.join(Dir.tmpdir, 'ropefall_2.0.1*.rbz'))
    assert_includes msg, 'ใช้งานได้ทันที'
  end

  def test_install_archive_update_asks_restart
    _ok, msg = I.install_archive(entry('installed' => true), 'x')
    assert_includes msg, 'เปิด SketchUp ใหม่'
    assert_includes msg, '2.0.1'
  end

  def test_install_archive_checks_registered_but_not_loaded_extension
    ext = Sketchup::FakeExtension.new('2.0.0')
    Sketchup.extensions = { 'Ropefall' => ext }
    ok, = I.install_archive(entry('installed' => false), 'x')
    assert ok
    assert ext.checked, 'disabled extension must be re-enabled after install'
  end

  def test_install_archive_does_not_check_loaded_extension
    ext = Sketchup::FakeExtension.new('2.0.0')
    ext.loaded = true
    Sketchup.extensions = { 'Ropefall' => ext }
    I.install_archive(entry, 'x')
    refute ext.checked
  end

  def test_install_archive_survives_temp_delete_failure
    real = File.method(:delete)
    File.define_singleton_method(:delete) { |*_a| raise Errno::EACCES, 'locked' }
    begin
      ok, = I.install_archive(entry('installed' => false), 'x')
      assert ok, 'delete failure in ensure must not turn success into failure'
    ensure
      File.define_singleton_method(:delete, &real)
      Sketchup.archive_paths.each { |p| FileUtils.rm_f(p) }
    end
  end

  def test_install_archive_sanitizes_temp_filename
    Sketchup.archive_paths = []
    I.install_archive(entry('id' => '../../evil', 'latest_version' => 'v/1'), 'x')
    path = Sketchup.archive_paths.last
    assert_equal File.expand_path(Dir.tmpdir), File.expand_path(File.dirname(path))
  end

  def test_install_archive_reports_failure
    Sketchup.install_error = Interrupt
    ok, msg = I.install_archive(entry, 'x')
    refute ok
    assert_includes msg, 'ติดตั้งไม่สำเร็จ'
    assert_empty Dir.glob(File.join(Dir.tmpdir, 'ropefall_2.0.1*.rbz'))
  end

  def test_set_enabled_is_remembered_for_the_card
    ext = Sketchup::FakeExtension.new('2.0.0')
    ext.loaded = true
    Sketchup.extensions = { 'Ropefall' => ext }
    I.set_enabled(entry, false)
    assert_equal false, SkpCm::ExtensionsHub::Catalog.extension_enabled(ext, 'Ropefall')
    I.set_enabled(entry, true)
    assert_equal true, SkpCm::ExtensionsHub::Catalog.extension_enabled(ext, 'Ropefall')
  ensure
    SkpCm::ExtensionsHub::Catalog.forget_enabled!
  end

  # SketchUp 2024 answers load_on_start? == false for a checked, running extension: the guard must still hold
  def test_remove_refuses_running_extension_even_if_load_on_start_is_false
    ext = Sketchup::FakeExtension.new('2.0.0')
    ext.loaded = true
    ext.define_singleton_method(:load_on_start?) { false }
    Sketchup.extensions = { 'Ropefall' => ext }
    File.write(File.join(@plugins, 'sketchrope_ropefall.rb'), 'x')
    ok, = I.remove(entry('files' => ['sketchrope_ropefall.rb']))
    refute ok
    assert File.exist?(File.join(@plugins, 'sketchrope_ropefall.rb'))
    I.set_enabled(entry, false)
    ok, = I.remove(entry('files' => ['sketchrope_ropefall.rb']))
    assert ok, 'removable once disabled in the Hub'
  ensure
    SkpCm::ExtensionsHub::Catalog.forget_enabled!
  end
end
