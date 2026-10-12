# frozen_string_literal: true

require 'json'
require_relative 'catalog'
require_relative 'installer'
require_relative 'auth'

module SkpCm
  module ExtensionsHub
    module Dialog
      class << self
        def show
          if @dialog && @dialog.visible?
            @dialog.bring_to_front
          else
            @dialog = create_dialog
            @dialog.show
          end
        end

        private

        def create_dialog
          dialog = UI::HtmlDialog.new(
            dialog_title: "#{PLUGIN_NAME} #{VERSION}",
            preferences_key: 'skp_cm_extensions_hub_dialog',
            width: 640, height: 720, min_width: 480, min_height: 400,
            style: UI::HtmlDialog::STYLE_DIALOG
          )
          dialog.set_file(File.join(PLUGIN_DIR, 'dialog.html'))
          dialog.add_action_callback('ready') do |_ctx|
            guard do
              js("hub.title(#{JSON.generate("#{PLUGIN_NAME} v#{VERSION}")})")
              push_auth
              refresh
            end
          end
          dialog.add_action_callback('login') { |_ctx, json| guard { login(json) } }
          dialog.add_action_callback('logout') { |_ctx| guard { Auth.logout; push_auth } }
          dialog.add_action_callback('reconnect') { |_ctx| guard { reconnect } }
          dialog.add_action_callback('save_connection') { |_ctx, json| guard { save_connection(json) } }
          watch_auth
          dialog.add_action_callback('refresh') { |_ctx| guard { refresh } }
          dialog.add_action_callback('install') { |_ctx, id| guard { install(id) } }
          dialog.add_action_callback('remove') { |_ctx, id| guard { remove(id) } }
          dialog.add_action_callback('enable') { |_ctx, id| guard { set_enabled(id, true) } }
          dialog.add_action_callback('disable') { |_ctx, id| guard { set_enabled(id, false) } }
          dialog
        end

        def guard
          yield
        rescue StandardError => e
          puts "[#{PLUGIN_NAME}] #{e.class}: #{e.message}\n#{e.backtrace.first(3).join("\n")}"
          message("เกิดข้อผิดพลาด: #{e.message}", 'error')
        end

        def refresh
          js('hub.loading()')
          Catalog.load do |entries, error|
            guard do
              @entries = Catalog.mark_pending(entries || [], pending_restart)
              js("hub.render(#{JSON.generate(@entries)})")
              message(error, 'error') if error
            end
          end
        end

        def install(id)
          entry = find(id)
          return unless entry

          js("hub.busy(#{JSON.generate(id)}, 'กำลังดาวน์โหลด…')")
          Installer.install(entry) do |ok, text|
            guard do
              # an update only takes effect after restart; a fresh install loads immediately
              pending_restart << id if ok && entry['installed']
              message(text, ok ? 'info' : 'error')
              refresh
            end
          end
        end

        def set_enabled(id, on)
          entry = find(id)
          return unless entry

          ok, text = Installer.set_enabled(entry, on)
          message(text, ok ? 'info' : 'error')
          refresh
        end

        def remove(id)
          entry = find(id)
          return unless entry
          return message("ปิดใช้งาน #{entry['name']} ก่อนถอน", 'error') unless Catalog.can_remove?(entry)

          answer = UI.messagebox("ถอน #{entry['name']} ออกจาก SketchUp?\n\nไฟล์ของ plugin จะถูกลบจากโฟลเดอร์ Plugins", MB_YESNO)
          return unless answer == IDYES

          ok, text = Installer.remove(entry)
          pending_restart << id if ok
          message(text, ok ? 'info' : 'error')
          refresh
        end

        def login(json)
          data = JSON.parse(json.to_s)
          Auth.login(data['username'], data['password']) do |ok, error|
            guard do
              push_auth
              message(error, 'error') unless ok
            end
          end
          push_auth # shows "กำลัง login…" while the request is in flight
        end

        # Logged in but offline (e.g. SketchUp started before the network was up)
        def reconnect
          Auth.relogin do |ok, error|
            guard do
              push_auth
              message(error, 'error') unless ok
            end
          end
          push_auth
        end

        def save_connection(json)
          data = JSON.parse(json.to_s)
          if Auth.save_connection(data['url'], data['database'])
            message('บันทึกการเชื่อมต่อแล้ว', 'info')
            Auth.relogin # with the saved account, if any
          else
            message('API Base URL ต้องขึ้นต้นด้วย http:// หรือ https:// และชื่อ Database ห้ามว่าง/มีช่องว่าง', 'error')
          end
          push_auth
        end

        def push_auth
          js("hub.auth(#{JSON.generate(Auth.status)})")
        end

        # One listener for the whole session; js() does nothing while the dialog is closed
        def watch_auth
          @auth_listener ||= Auth.on_change { |_logged_in| guard { push_auth } }
        end

        def find(id)
          (@entries || []).find { |e| e['id'] == id }
        end

        def pending_restart
          @pending_restart ||= []
        end

        def message(text, kind)
          js("hub.message(#{JSON.generate(text)}, #{JSON.generate(kind)})")
        end

        def js(code)
          @dialog.execute_script(code) if @dialog && @dialog.visible?
        end
      end
    end
  end
end
