# frozen_string_literal: true

# Run (no SketchUp needed): ruby tests/tc_auth_store.rb
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'json'
require_relative 'stub_sketchup'
require_relative '../skp_cm_extensions_hub/auth_store'

class TestAuthStore < Minitest::Test
  S = SkpCm::ExtensionsHub::AuthStore

  def setup
    @tmp = Dir.mktmpdir
    @old_home = ENV['HOME']
    @old_appdata = ENV['APPDATA']
    ENV['HOME'] = @tmp
    ENV.delete('APPDATA')
    Sketchup.platform = :platform_osx
  end

  def teardown
    ENV['HOME'] = @old_home
    if @old_appdata
      ENV['APPDATA'] = @old_appdata
    else
      ENV.delete('APPDATA')
    end
    FileUtils.rm_rf(@tmp)
  end

  def test_mac_path
    expected = File.join(@tmp, 'Library', 'Application Support', 'SkpCm', 'extensions_hub', 'auth.json')
    assert_equal expected, S.path
  end

  def test_windows_path_uses_appdata
    Sketchup.platform = :platform_win
    ENV['APPDATA'] = File.join(@tmp, 'Roaming')
    assert_equal File.join(@tmp, 'Roaming', 'SkpCm', 'extensions_hub', 'auth.json'), S.path
  end

  def test_missing_file_gives_defaults
    expected = { 'api_base_url' => 'https://odoo.catice.co', 'database' => 'odoo_ci', 'username' => '',
                 'password' => '', 'verified' => false }
    assert_equal expected, S.load
  end

  def test_save_and_load_round_trip_with_thai_password
    state = { 'api_base_url' => 'https://x.test', 'database' => 'db1', 'username' => 'a@b.c',
              'password' => 'รหัส#1"', 'verified' => true }
    assert_equal true, S.save(state)
    assert_equal state, S.load
  end

  def test_password_is_not_stored_in_plain_text
    S.save('api_base_url' => 'https://x.test', 'username' => 'a', 'password' => 'secret', 'verified' => true)
    refute_includes File.read(S.path), 'secret'
  end

  def test_broken_json_gives_defaults
    FileUtils.mkdir_p(File.dirname(S.path))
    File.write(S.path, '{"username": "ali')
    assert_equal '', S.load['username']
    assert_equal 'https://odoo.catice.co', S.load['api_base_url']
  end

  def test_non_hash_json_and_empty_url_give_defaults
    FileUtils.mkdir_p(File.dirname(S.path))
    File.write(S.path, '[1,2]')
    assert_equal false, S.load['verified']
    File.write(S.path, JSON.generate('api_base_url' => '', 'database' => '', 'username' => 'a', 'verified' => 'yes'))
    assert_equal 'https://odoo.catice.co', S.load['api_base_url']
    assert_equal 'odoo_ci', S.load['database']
    assert_equal false, S.load['verified'], 'only literal true counts'
  end

  def test_bad_base64_password_becomes_empty
    FileUtils.mkdir_p(File.dirname(S.path))
    File.write(S.path, JSON.generate('username' => 'a', 'password' => '%%%not-base64'))
    assert_equal '', S.load['password']
  end

  def test_save_failure_returns_false
    blocker = File.join(@tmp, 'file')
    File.write(blocker, 'x')
    ENV['HOME'] = blocker
    assert_equal false, S.save(S.defaults)
  end
end
