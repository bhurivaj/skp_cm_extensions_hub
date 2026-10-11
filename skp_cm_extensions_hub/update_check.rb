# frozen_string_literal: true

require_relative 'catalog'

module SkpCm
  module ExtensionsHub
    # Background check on SketchUp start: at most once per day, notify (non-modal) when updates exist
    module UpdateCheck
      PREF_SECTION = 'skp_cm_extensions_hub'
      INTERVAL = 24 * 60 * 60

      class << self
        def check_due?(last_check, now)
          last = last_check.to_i
          last <= 0 || last > now || now - last >= INTERVAL
        end

        def update_notice(entries)
          names = entries.select { |e| e['status'] == 'update_available' }
                         .map { |e| "#{e['name']} #{e['latest_version']}" }
          return nil if names.empty?

          "มีอัปเดต #{names.size} รายการ: #{names.join(', ')}"
        end

        # True when at least one release lookup worked (so a check is worth remembering)
        def successful?(entries)
          entries.any? { |e| e['error'].nil? }
        end

        def run
          return unless check_due?(Sketchup.read_default(PREF_SECTION, 'last_check', 0), Time.now.to_i)

          Catalog.load do |entries, error|
            begin
              if error
                log(error)
              else
                Sketchup.write_default(PREF_SECTION, 'last_check', Time.now.to_i) if successful?(entries)
                text = update_notice(entries)
                notify(text) if text
              end
            rescue StandardError => e
              log("#{e.class}: #{e.message}")
            end
          end
        rescue StandardError => e
          log("#{e.class}: #{e.message}")
        end

        private

        def notify(text)
          # keep a reference: the callbacks stop working if the notification is garbage collected
          @notification = UI::Notification.new(EXTENSION, text)
          @notification.on_accept('เปิด Hub') do
            begin
              Dialog.show
            rescue StandardError => e
              puts "[#{PLUGIN_NAME}] #{e.class}: #{e.message}"
            end
          end
          @notification.on_dismiss('ปิด') {}
          @notification.show
        end

        def log(text)
          puts "[#{PLUGIN_NAME}] update check: #{text}"
        end
      end
    end
  end
end
