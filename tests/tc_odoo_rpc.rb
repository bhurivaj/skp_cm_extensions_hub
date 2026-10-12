# frozen_string_literal: true

# Run (no SketchUp needed): ruby tests/tc_odoo_rpc.rb
require 'minitest/autorun'
require_relative 'stub_sketchup'
require_relative '../skp_cm_extensions_hub/odoo_rpc'

class TestOdooRpc < Minitest::Test
  R = SkpCm::ExtensionsHub::OdooRpc

  def odoo_error(name, message)
    JSON.generate('jsonrpc' => '2.0', 'id' => 1,
                  'error' => { 'code' => 200, 'message' => 'Odoo Server Error',
                               'data' => { 'name' => name, 'message' => message } })
  end

  def test_execute_kw_payload
    p = R.execute_kw_payload('odoo_ci', 7, 'pw', 'crm.lead', 'search_read', [[['a', '=', 1]]], { 'limit' => 1 })
    assert_equal({ 'jsonrpc' => '2.0', 'method' => 'call', 'id' => 1,
                   'params' => { 'service' => 'object', 'method' => 'execute_kw',
                                 'args' => ['odoo_ci', 7, 'pw', 'crm.lead', 'search_read',
                                            [[['a', '=', 1]]], { 'limit' => 1 }] } }, p)
  end

  def test_ok_result_including_empty_list_and_false
    assert_equal [:ok, [{ 'id' => 1 }]], R.parse_result(200, '{"jsonrpc":"2.0","id":1,"result":[{"id":1}]}', nil)
    assert_equal [:ok, []], R.parse_result(200, '{"jsonrpc":"2.0","id":1,"result":[]}', nil)
    assert_equal [:ok, false], R.parse_result(200, '{"jsonrpc":"2.0","id":1,"result":false}', nil)
  end

  def test_network_and_http_errors
    kind, msg = R.parse_result(nil, nil, 'network error')
    assert_equal :error, kind
    assert_match(/เชื่อมต่อ server ไม่ได้/, msg)
    kind, msg = R.parse_result(502, 'x', nil)
    assert_equal :error, kind
    assert_match(/HTTP 502/, msg)
  end

  def test_not_json_or_no_result
    assert_equal :error, R.parse_result(200, '<html>', nil).first
    assert_equal :error, R.parse_result(200, '[1]', nil).first
    assert_equal :error, R.parse_result(200, '{"jsonrpc":"2.0","id":1}', nil).first
  end

  def test_odoo_error_uses_last_line_only
    kind, msg = R.parse_result(200, odoo_error('odoo.exceptions.ValidationError', "secret 10.0.0.9\nInvalid field 'x'"), nil)
    assert_equal :error, kind
    assert_equal "Odoo แจ้ง error: Invalid field 'x'", msg
  end

  def test_access_denied_is_denied
    kind, msg = R.parse_result(200, odoo_error('odoo.exceptions.AccessDenied', 'Access Denied'), nil)
    assert_equal :denied, kind
    assert_match(/Access Denied/, msg)
  end

  def test_error_line_fallbacks
    assert_equal 'ไม่ทราบสาเหตุ', R.error_line(nil)
    assert_equal 'ไม่ทราบสาเหตุ', R.error_line('data' => { 'message' => "  \n" })
    assert_equal 'boom', R.error_line('message' => 'boom')
  end
end
