# frozen_string_literal: true

require 'json'

module SkpCm
  module ExtensionsHub
    # Odoo JSON-RPC helpers for Auth — no network, no state
    module OdooRpc
      module_function

      # object.execute_kw (spec 2026-10-12-layout-generator-design.md §3.1)
      def execute_kw_payload(database, uid, password, model, method, args, kwargs)
        { 'jsonrpc' => '2.0', 'method' => 'call', 'id' => 1,
          'params' => { 'service' => 'object', 'method' => 'execute_kw',
                        'args' => [database, uid, password, model, method, args, kwargs] } }
      end

      # => [:ok, result] / [:error, message] / [:denied, message] (password no longer accepted)
      def parse_result(status, body, error)
        return [:error, "เชื่อมต่อ server ไม่ได้ (#{error})"] if status.nil?
        return [:error, "server ตอบกลับ HTTP #{status} — ตรวจ API Base URL"] unless status == 200

        data = JSON.parse(body.to_s)
        return [:error, 'server ตอบกลับไม่ถูกต้อง'] unless data.is_a?(Hash)

        if data.key?('error')
          kind = access_denied?(data['error']) ? :denied : :error
          return [kind, "Odoo แจ้ง error: #{error_line(data['error'])}"]
        end
        return [:error, 'server ตอบกลับไม่ถูกต้อง'] unless data.key?('result')

        [:ok, data['result']]
      rescue JSON::ParserError
        [:error, 'server ตอบกลับไม่ถูกต้อง (ไม่ใช่ Odoo JSON-RPC)']
      end

      # The last line says what is wrong; earlier lines may hold server internals
      def error_line(info)
        return 'ไม่ทราบสาเหตุ' unless info.is_a?(Hash)

        detail = info['data']
        text = (detail.is_a?(Hash) && detail['message']) || info['message']
        line = text.to_s.strip.lines.last.to_s.strip
        line.empty? ? 'ไม่ทราบสาเหตุ' : line
      end

      def access_denied?(info)
        info.is_a?(Hash) && info['data'].is_a?(Hash) && info['data']['name'].to_s.end_with?('AccessDenied')
      end
    end
  end
end
