# frozen_string_literal: true

require 'json'
require_relative 'http'
require_relative 'auth_store'
require_relative 'odoo_rpc'

module SkpCm
  module ExtensionsHub
    # Shared Odoo login for all SKP CM plugins. Other plugins call the public methods —
    # do not rename them or change their arguments (docs/specs/2026-10-12-hub-auth-design.md §3.4, §7).
    module Auth
      RPC_PATH = '/jsonrpc'

      class << self
        # Odoo user id; nil until the server accepted the login in this SketchUp session
        attr_reader :uid

        # true after a successful login until logout or a rejected password — also while offline
        def logged_in?
          s = state
          s['verified'] && !s['username'].empty? && !s['password'].empty?
        end

        def username
          name = state['username']
          name.empty? ? nil : name
        end

        def api_base_url
          state['api_base_url']
        end

        def database
          state['database']
        end

        # For the Hub dialog — never contains the password
        def status
          { 'logged_in' => logged_in?, 'username' => username, 'online' => !@uid.nil?,
            'api_base_url' => api_base_url, 'database' => database, 'busy' => !@waiting.nil? }
        end

        def login(user, pass, &done)
          user = user.to_s.strip
          pass = pass.to_s
          return call_safely(done, false, 'กรอก username และ password') if user.empty? || pass.empty?

          request_login(user, pass, done)
        end

        # Login again with the saved account (e.g. SketchUp started offline)
        def relogin(&done)
          s = state
          return call_safely(done, false, 'ยังไม่มีบัญชีที่บันทึกไว้') if s['username'].empty? || s['password'].empty?

          request_login(s['username'], s['password'], done)
        end

        # Silent login on SketchUp start-up
        def auto_login
          relogin
        end

        def logout
          cancel_pending
          change do
            @uid = nil
            save('password' => '', 'verified' => false)
          end
        end

        # Moves an account saved by another plugin (BoQ 1.x) — only when the Hub has none yet
        def import_credentials(user, pass, &done)
          return call_safely(done, false, 'already has account') if username

          login(user, pass, &done)
        end

        # Odoo server + database. Returns false (nothing saved) unless the URL is http(s) and the name is valid
        def save_connection(url, name)
          url = url.to_s.strip.chomp('/')
          name = name.to_s.strip
          return false unless url =~ %r{\Ahttps?://\S+\z} && name =~ /\A[\w.-]+\z/

          cancel_pending
          change do
            @uid = nil
            save('api_base_url' => url, 'database' => name)
          end
          true
        end

        # listener.call(logged_in) whenever logged_in? or the uid changes; returns the listener for off_change
        def on_change(&listener)
          listeners << listener if listener
          listener
        end

        def off_change(listener)
          listeners.delete(listener)
        end

        def show_login
          Dialog.show
        end

        # Tests only: forget everything held in memory
        def reset!
          @state = @uid = @waiting = @waiting_key = @listeners = nil
        end

        private

        def state
          @state ||= AuthStore.load
        end

        def save(changes)
          @state = state.merge(changes)
          AuthStore.save(@state)
        end

        # The same login while one is in flight waits for that result (no second POST).
        # A different login, a logout or a connection change cancels the pending one: its reply is ignored.
        def request_login(user, pass, done)
          key = [user, pass, api_base_url, database]
          if @waiting && @waiting_key == key
            @waiting << done if done
            return
          end
          cancel_pending
          generation = @generation
          @waiting = done ? [done] : []
          @waiting_key = key
          Http.post_json(api_base_url + RPC_PATH, authenticate_payload(user, pass)) do |status, body, error|
            next unless generation == @generation

            waiting = @waiting || []
            @waiting = @waiting_key = nil
            ok = message = nil
            begin
              change { ok, message = apply_result(user, pass, status, body, error) }
            ensure
              waiting.each { |cb| call_safely(cb, ok, message) }
            end
          end
        end

        def cancel_pending
          @generation = @generation.to_i + 1
          waiting = @waiting || []
          @waiting = @waiting_key = nil
          waiting.each { |cb| call_safely(cb, false, 'ยกเลิกแล้ว') }
        end

        # Odoo JSON-RPC common.authenticate (spec §7)
        def authenticate_payload(user, pass)
          { 'jsonrpc' => '2.0', 'method' => 'call', 'id' => 1,
            'params' => { 'service' => 'common', 'method' => 'authenticate', 'args' => [database, user, pass, {}] } }
        end

        def apply_result(user, pass, status, body, error)
          kind, value = parse_reply(status, body, error)
          case kind
          when :ok
            @uid = value
            save('username' => user, 'password' => pass, 'verified' => true)
            [true, nil]
          when :rejected
            @uid = nil
            save('username' => user, 'password' => '', 'verified' => false)
            [false, 'username หรือ password ไม่ถูกต้อง']
          else
            # offline or server problem: keep the saved account and its verified flag
            @uid = nil
            [false, value]
          end
        end

        # => [:ok, uid] / [:rejected] / [:error, message]
        def parse_reply(status, body, error)
          return [:error, "เชื่อมต่อ server ไม่ได้ (#{error})"] if status.nil?
          return [:error, "server ตอบกลับ HTTP #{status} — ตรวจ API Base URL"] unless status == 200

          data = JSON.parse(body.to_s)
          return [:error, 'server ตอบกลับไม่ถูกต้อง'] unless data.is_a?(Hash)
          return [:error, "Odoo แจ้ง error: #{odoo_error(data['error'])} — ตรวจ API Base URL / Database"] if data.key?('error')

          result = data['result']
          return [:rejected] if result == false
          return [:ok, result] if result.is_a?(Integer) && result > 0

          [:error, 'server ตอบกลับไม่ถูกต้อง']
        rescue JSON::ParserError
          [:error, 'server ตอบกลับไม่ถูกต้อง (ไม่ใช่ Odoo JSON-RPC)']
        end

        def odoo_error(info)
          OdooRpc.error_line(info)
        end

        # Runs the block; tells listeners when logged_in? or the uid changed
        def change
          before = [logged_in?, @uid]
          yield
          notify if before != [logged_in?, @uid]
        end

        def notify
          now = logged_in?
          listeners.dup.each { |listener| call_safely(listener, now) }
        end

        def listeners
          @listeners ||= []
        end

        def call_safely(callback, *args)
          callback.call(*args) if callback
          nil
        rescue StandardError => e
          puts "[SKP CM Extensions Hub] auth callback error: #{e.class}: #{e.message}"
          nil
        end
      end
    end
  end
end
