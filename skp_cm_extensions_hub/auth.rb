# frozen_string_literal: true

require 'json'
require_relative 'http'
require_relative 'auth_store'

module SkpCm
  module ExtensionsHub
    # Shared Odoo login for all SKP CM plugins. Other plugins call the public methods —
    # do not rename them or change their arguments (docs/specs/2026-10-12-hub-auth-design.md §3.4).
    module Auth
      LOGIN_PATH = '/auth/login/access-token'
      REJECTED_CODES = [400, 401, 403].freeze

      class << self
        # nil until the server gave a token in this SketchUp session
        attr_reader :token

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

        # For the Hub dialog — never contains the password or the token
        def status
          { 'logged_in' => logged_in?, 'username' => username, 'online' => !@token.nil?,
            'api_base_url' => api_base_url, 'busy' => !@waiting.nil? }
        end

        def login(user, pass, &done)
          user = user.to_s.strip
          pass = pass.to_s
          return call_safely(done, false, 'กรอก username และ password') if user.empty? || pass.empty?

          request_login(user, pass, done)
        end

        # Login again with the saved account (token expired / Odoo answered 401)
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
            @token = nil
            save('password' => '', 'verified' => false)
          end
        end

        # Moves an account saved by another plugin (BoQ 1.x) — only when the Hub has none yet
        def import_credentials(user, pass, &done)
          return call_safely(done, false, 'already has account') if username

          login(user, pass, &done)
        end

        # Returns false (nothing saved) unless the URL is http(s)
        def save_api_base_url(url)
          url = url.to_s.strip.chomp('/')
          return false unless url =~ %r{\Ahttps?://\S+\z}

          cancel_pending
          change do
            @token = nil
            save('api_base_url' => url)
          end
          true
        end

        # listener.call(logged_in) whenever logged_in? or the token changes; returns the listener for off_change
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
          @state = @token = @waiting = @waiting_key = @listeners = nil
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
        # A different login, a logout or a URL change cancels the pending one: its reply is ignored.
        def request_login(user, pass, done)
          key = [user, pass, api_base_url]
          if @waiting && @waiting_key == key
            @waiting << done if done
            return
          end
          cancel_pending
          generation = @generation
          @waiting = done ? [done] : []
          @waiting_key = key
          Http.post_form(api_base_url + LOGIN_PATH, 'username' => user, 'password' => pass) do |status, body, error|
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

        def apply_result(user, pass, status, body, error)
          new_token = status == 200 ? parse_token(body) : nil
          if new_token
            @token = new_token
            save('username' => user, 'password' => pass, 'verified' => true)
            [true, nil]
          elsif REJECTED_CODES.include?(status)
            @token = nil
            save('username' => user, 'password' => '', 'verified' => false)
            [false, 'username หรือ password ไม่ถูกต้อง']
          else
            # offline or server problem: keep the saved account and its verified flag
            @token = nil
            [false, "เชื่อมต่อ server ไม่ได้ (#{error || status})"]
          end
        end

        def parse_token(body)
          data = JSON.parse(body.to_s)
          value = data.is_a?(Hash) ? data['access_token'].to_s : ''
          value.empty? ? nil : value
        rescue JSON::ParserError
          nil
        end

        # Runs the block; tells listeners when logged_in? or the token changed
        def change
          before = [logged_in?, @token]
          yield
          notify if before != [logged_in?, @token]
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
