# frozen_string_literal: true

# Run (no SketchUp needed): ruby tests/tc_auth.rb
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require_relative 'stub_sketchup'
require_relative '../skp_cm_extensions_hub/auth'

class TestAuth < Minitest::Test
  A = SkpCm::ExtensionsHub::Auth
  S = SkpCm::ExtensionsHub::AuthStore
  H = SkpCm::ExtensionsHub::Http
  URL = 'https://odoo.catice.co/auth/login/access-token'
  OK = [200, '{"access_token":"tok1","token_type":"bearer"}', nil].freeze
  BAD = [401, '{"detail":"Incorrect username or password"}', nil].freeze
  DOWN = [nil, nil, 'network error'].freeze

  # Each queued response answers one POST. :hold keeps it open — answer later with @held.call(*OK)
  def stub_post(*responses)
    @posts = []
    posts = @posts
    test = self
    H.define_singleton_method(:post_form) do |url, fields, &blk|
      posts << [url, fields]
      r = responses.shift
      r == :hold ? test.instance_variable_set(:@held, blk) : blk.call(*r)
    end
  end

  def setup
    @tmp = Dir.mktmpdir
    @old_home = ENV['HOME']
    ENV['HOME'] = @tmp
    Sketchup.platform = :platform_osx
    A.reset!
  end

  def teardown
    ENV['HOME'] = @old_home
    FileUtils.rm_rf(@tmp)
  end

  def login(user = 'a@b.c', pass = 'pw')
    result = nil
    A.login(user, pass) { |ok, err| result = [ok, err] }
    result
  end

  def test_login_success
    stub_post(OK)
    assert_equal [true, nil], login
    assert A.logged_in?
    assert_equal 'tok1', A.token
    assert_equal 'a@b.c', A.username
    assert_equal [[URL, { 'username' => 'a@b.c', 'password' => 'pw' }]], @posts
    assert_equal [true, 'pw'], [S.load['verified'], S.load['password']]
    refute_includes File.read(S.path), 'tok1', 'token must never be written to disk'
  end

  def test_rejected_login_locks_and_keeps_username
    stub_post(OK, BAD)
    login
    ok, err = login('a@b.c', 'wrong')
    assert_equal false, ok
    assert_match(/ไม่ถูกต้อง/, err)
    refute A.logged_in?
    assert_nil A.token
    assert_equal 'a@b.c', A.username
    assert_equal '', S.load['password']
  end

  def test_network_error_keeps_unlock_but_drops_token
    stub_post(OK, DOWN)
    login
    result = nil
    A.relogin { |ok, _| result = ok }
    assert_equal false, result
    assert A.logged_in?
    assert_nil A.token
  end

  def test_200_without_token_is_server_problem
    stub_post(OK, [200, '<html>proxy</html>', nil], [200, '{"x":1}', nil])
    login
    refute login.first
    refute login.first
    assert A.logged_in?, 'saved account must survive a broken server reply'
    assert_nil A.token
  end

  def test_logout
    stub_post(OK)
    login
    A.logout
    refute A.logged_in?
    assert_nil A.token
    assert_equal 'a@b.c', A.username
    assert_equal '', S.load['password']
  end

  def test_no_account_sends_nothing
    stub_post
    A.auto_login
    result = nil
    A.relogin { |ok, _| result = ok }
    assert_equal false, result
    assert_equal false, login(' ', 'pw').first
    assert_equal false, login('a', '').first
    assert_empty @posts
  end

  def test_auto_login_uses_saved_account
    S.save('api_base_url' => 'https://x.test', 'username' => 'u', 'password' => 'p', 'verified' => true)
    A.reset!
    stub_post(OK)
    assert A.logged_in?, 'unlocked from the saved file before the server answers'
    A.auto_login
    assert_equal [['https://x.test/auth/login/access-token', { 'username' => 'u', 'password' => 'p' }]], @posts
    assert_equal 'tok1', A.token
  end

  def test_overlapping_relogin_sends_one_request
    stub_post(OK, :hold)
    login
    results = []
    A.relogin { |ok, _| results << ok }
    assert A.status['busy']
    A.relogin { |ok, _| results << ok }
    assert_equal 2, @posts.size
    @held.call(*OK)
    assert_equal [true, true], results
    refute A.status['busy']
  end

  def test_status_has_no_secrets
    stub_post(OK)
    login
    expected = { 'logged_in' => true, 'username' => 'a@b.c', 'online' => true,
                 'api_base_url' => 'https://odoo.catice.co', 'busy' => false }
    assert_equal expected, A.status
  end

  def test_listeners_called_only_on_change_and_errors_isolated
    stub_post(OK, OK)
    calls = []
    A.on_change { |_| raise 'boom' }
    A.on_change { |v| calls << v }
    login
    login # same token again → nothing changed
    assert_equal [true], calls
    A.logout
    assert_equal [true, false], calls
  end

  def test_off_change
    stub_post(OK)
    calls = []
    listener = A.on_change { |v| calls << v }
    A.off_change(listener)
    login
    assert_empty calls
  end

  def test_import_refused_when_account_exists
    stub_post(OK)
    login
    result = nil
    A.import_credentials('other', 'x') { |ok, err| result = [ok, err] }
    assert_equal [false, 'already has account'], result
    assert_equal 1, @posts.size
    assert_equal 'a@b.c', A.username
  end

  def test_import_when_hub_has_no_account
    stub_post(OK)
    result = nil
    A.import_credentials('old@b.c', 'pw') { |ok, _| result = ok }
    assert_equal true, result
    assert_equal 'old@b.c', A.username
  end

  def test_save_api_base_url
    stub_post(OK, OK)
    login
    calls = []
    A.on_change { |v| calls << v }
    assert_equal false, A.save_api_base_url('ftp://x.test')
    assert_equal false, A.save_api_base_url('')
    assert_equal 'tok1', A.token
    assert_equal true, A.save_api_base_url(' https://new.test/ ')
    assert_nil A.token, 'a token from the old server is useless'
    assert_equal [true], calls
    assert_equal 'https://new.test', S.load['api_base_url']
    A.relogin {}
    assert_equal 'https://new.test/auth/login/access-token', @posts.last[0]
  end
end
