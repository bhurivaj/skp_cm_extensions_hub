# frozen_string_literal: true

# Run (no SketchUp needed): ruby tests/tc_auth_execute_kw.rb
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require_relative 'stub_sketchup'
require_relative '../skp_cm_extensions_hub/auth'

class TestAuthExecuteKw < Minitest::Test
  A = SkpCm::ExtensionsHub::Auth
  H = SkpCm::ExtensionsHub::Http
  URL = 'https://odoo.catice.co/jsonrpc'
  LOGIN_OK = [200, '{"jsonrpc":"2.0","id":1,"result":7}', nil].freeze
  DOWN = [nil, nil, 'network error'].freeze
  LEADS = [200, '{"jsonrpc":"2.0","id":1,"result":[{"id":5,"name":"P"}]}', nil].freeze
  DENIED = [200, '{"jsonrpc":"2.0","id":1,"error":{"code":200,"message":"x",' \
                 '"data":{"name":"odoo.exceptions.AccessDenied","message":"Access Denied"}}}', nil].freeze
  DOMAIN = [[['reference_code', '=', 'OPP-20261000074']]].freeze
  KW = { 'fields' => %w[name partner_id], 'limit' => 1 }.freeze

  def stub_post(*responses)
    @posts = []
    posts = @posts
    H.define_singleton_method(:post_json) do |url, payload, &blk|
      posts << [url, payload]
      blk.call(*responses.shift)
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

  def logged_in
    stub_post(LOGIN_OK)
    A.login('a@b.c', 'pw')
  end

  # Collects every callback call — each test asserts exactly one
  def run_kw(model = 'crm.lead', method = 'search_read', args = DOMAIN, kwargs = KW)
    calls = []
    A.execute_kw(model, method, args, kwargs) { |ok, value| calls << [ok, value] }
    assert_equal 1, calls.size, 'callback must be called exactly once'
    calls.first
  end

  def test_not_logged_in_sends_nothing
    stub_post
    ok, msg = run_kw
    assert_equal false, ok
    assert_match(/login/, msg)
    assert_empty @posts
  end

  def test_success_sends_execute_kw_with_hub_credentials
    logged_in
    stub_post(LEADS)
    assert_equal [true, [{ 'id' => 5, 'name' => 'P' }]], run_kw
    url, payload = @posts.first
    assert_equal URL, url
    assert_equal ['odoo_ci', 7, 'pw', 'crm.lead', 'search_read', DOMAIN, KW], payload['params']['args']
    assert_equal 'object', payload['params']['service']
  end

  def test_offline_start_relogs_in_first
    logged_in
    A.reset! # new SketchUp session: account saved on disk, uid unknown
    assert A.logged_in?
    assert_nil A.uid
    stub_post(LOGIN_OK, LEADS)
    ok, = run_kw
    assert ok
    assert_equal %w[common object], @posts.map { |_u, p| p['params']['service'] }
  end

  def test_offline_start_relogin_fails
    logged_in
    A.reset!
    stub_post(DOWN)
    ok, msg = run_kw
    assert_equal false, ok
    assert_match(/เชื่อมต่อ server ไม่ได้/, msg)
    assert_equal 1, @posts.size
  end

  def test_network_error_keeps_uid
    logged_in
    stub_post(DOWN)
    ok, = run_kw
    assert_equal false, ok
    assert_equal 7, A.uid
  end

  def test_access_denied_forgets_uid
    logged_in
    stub_post(DENIED)
    ok, msg = run_kw
    assert_equal false, ok
    assert_match(/Access Denied/, msg)
    assert_nil A.uid
    assert A.logged_in?, 'saved account stays; next call will relogin'
  end

  def test_bad_arguments_send_nothing
    logged_in
    stub_post
    [['', 'search_read', [], {}], ['crm.lead', nil, [], {}], ['crm.lead', 'read', 'x', {}],
     ['crm.lead', 'read', [], nil]].each do |m, meth, args, kw|
      ok, msg = run_kw(m, meth, args, kw)
      assert_equal false, ok
      assert_match(/argument/, msg)
    end
    assert_empty @posts
  end

  def test_kwargs_defaults_to_empty_hash
    logged_in
    stub_post(LEADS)
    A.execute_kw('crm.lead', 'search_read', DOMAIN) { |_ok, _v| nil }
    assert_equal({}, @posts.first[1]['params']['args'].last)
  end

  def test_callback_exception_does_not_escape
    logged_in
    stub_post(LEADS)
    out, = capture_io { A.execute_kw('crm.lead', 'search_read', DOMAIN, KW) { raise 'boom' } }
    assert_match(/boom/, out)
  end
end
