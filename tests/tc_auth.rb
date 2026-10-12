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
  URL = 'https://odoo.catice.co/jsonrpc'
  OK = [200, '{"jsonrpc":"2.0","id":1,"result":7}', nil].freeze
  BAD = [200, '{"jsonrpc":"2.0","id":1,"result":false}', nil].freeze
  DOWN = [nil, nil, 'network error'].freeze
  NO_DB = [200, '{"jsonrpc":"2.0","id":1,"error":{"code":200,"message":"Odoo Server Error",' \
                '"data":{"name":"psycopg2.OperationalError","message":"connection to server at \\"10.0.0.9\\" failed: ' \
                '\\nFATAL:  database \\"x\\" does not exist\\n"}}}', nil].freeze

  def rpc(database, user, pass)
    { 'jsonrpc' => '2.0', 'method' => 'call', 'id' => 1,
      'params' => { 'service' => 'common', 'method' => 'authenticate', 'args' => [database, user, pass, {}] } }
  end

  # Each queued response answers one POST. :hold keeps it open — answer later with @held.call(*OK)
  def stub_post(*responses)
    @posts = []
    posts = @posts
    test = self
    H.define_singleton_method(:post_json) do |url, payload, &blk|
      posts << [url, payload]
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
    assert_equal 7, A.uid
    assert_equal 'a@b.c', A.username
    assert_equal [[URL, rpc('odoo_ci', 'a@b.c', 'pw')]], @posts
    assert_equal [true, 'pw'], [S.load['verified'], S.load['password']]
    refute_includes File.read(S.path), 'uid', 'uid must never be written to disk'
  end

  def test_rejected_login_locks_and_keeps_username
    stub_post(OK, BAD)
    login
    ok, err = login('a@b.c', 'wrong')
    assert_equal false, ok
    assert_match(/ไม่ถูกต้อง/, err)
    refute A.logged_in?
    assert_nil A.uid
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
    assert_nil A.uid
  end

  def test_unexpected_reply_is_server_problem
    odd = ['<html>proxy</html>', '{"x":1}', '{"result":0}', '{"result":"7"}', '{"result":true}']
    stub_post(OK, *odd.map { |body| [200, body, nil] }, [404, 'Not Found', nil])
    login
    (odd.size + 1).times { refute login.first }
    assert A.logged_in?, 'saved account must survive a broken server reply'
    assert_nil A.uid
  end

  def test_odoo_error_keeps_account_and_shows_message
    stub_post(OK, NO_DB)
    login
    ok, err = login
    assert_equal false, ok
    assert_match(/does not exist/, err)
    refute_includes err, '10.0.0.9', 'only the last line of the Odoo error is shown'
    assert A.logged_in?
    assert_nil A.uid
  end

  def test_logout
    stub_post(OK)
    login
    A.logout
    refute A.logged_in?
    assert_nil A.uid
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
    S.save('api_base_url' => 'https://x.test', 'database' => 'db2', 'username' => 'u', 'password' => 'p', 'verified' => true)
    A.reset!
    stub_post(OK)
    assert A.logged_in?, 'unlocked from the saved file before the server answers'
    A.auto_login
    assert_equal [['https://x.test/jsonrpc', rpc('db2', 'u', 'p')]], @posts
    assert_equal 7, A.uid
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
                 'api_base_url' => 'https://odoo.catice.co', 'database' => 'odoo_ci', 'busy' => false }
    assert_equal expected, A.status
  end

  def test_listeners_called_only_on_change_and_errors_isolated
    stub_post(OK, OK)
    calls = []
    A.on_change { |_| raise 'boom' }
    A.on_change { |v| calls << v }
    login
    login # same uid again → nothing changed
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

  def test_save_connection
    stub_post(OK, OK)
    login
    calls = []
    A.on_change { |v| calls << v }
    assert_equal false, A.save_connection('ftp://x.test', 'db')
    assert_equal false, A.save_connection('', 'db')
    assert_equal false, A.save_connection('https://new.test', ' ')
    assert_equal false, A.save_connection('https://new.test', 'my db')
    assert_equal 7, A.uid
    assert_equal true, A.save_connection(' https://new.test/ ', ' db_2 ')
    assert_nil A.uid, 'a uid from the old server is useless'
    assert_equal [true], calls
    assert_equal ['https://new.test', 'db_2'], [S.load['api_base_url'], S.load['database']]
    A.relogin {}
    assert_equal ['https://new.test/jsonrpc', rpc('db_2', 'a@b.c', 'pw')], @posts.last
  end

  # --- a pending login must not override what happened after it was sent ---

  def test_logout_during_login_is_not_undone
    stub_post(:hold)
    login
    A.logout
    @held.call(*OK)
    refute A.logged_in?
    assert_nil A.uid
    assert_equal '', S.load['password']
  end

  def test_url_change_during_login_uses_new_server
    stub_post(OK, :hold, [200, '{"jsonrpc":"2.0","id":1,"result":8}', nil])
    login
    A.relogin {}
    old_reply = @held
    A.save_connection('https://new.test', 'odoo_ci')
    A.relogin {}
    assert_equal 'https://new.test/jsonrpc', @posts.last[0]
    assert_equal 8, A.uid
    old_reply.call(*OK)
    assert_equal 8, A.uid, 'a reply from the old server must be ignored'
  end

  def test_different_credentials_send_their_own_request
    stub_post(:hold, OK)
    first = nil
    A.import_credentials('old', 'pw') { |ok, err| first = [ok, err] }
    old_reply = @held
    assert_equal [true, nil], login('new@b.c', 'pw2')
    assert_equal %w[old new@b.c], @posts.map { |p| p[1]['params']['args'][1] }
    assert_equal false, first[0], 'the replaced request is answered as cancelled'
    old_reply.call(*BAD)
    assert A.logged_in?
    assert_equal 'new@b.c', A.username
  end
end
