# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'
require_relative 'catalog'
require_relative 'http'

module SkpCm
  module ExtensionsHub
    # Installs .rbz archives and removes plugin files from the Plugins folder
    module Installer
      class << self
        # Absolute path inside plugins_dir, or nil if rel is empty / absolute / escapes the folder
        def safe_path(plugins_dir, rel)
          return nil unless rel.is_a?(String) && !rel.strip.empty?
          return nil if rel.start_with?('/', '\\') || rel =~ /\A[A-Za-z]:/

          parts = rel.split(%r{[/\\]})
          return nil if parts.include?('..') || parts.reject(&:empty?) == ['.']

          root = File.expand_path(plugins_dir)
          full = File.expand_path(rel, root)
          full.start_with?(root + '/') ? full : nil
        end

        def remove(entry, plugins_dir: Sketchup.find_support_file('Plugins'))
          return [false, 'ถอน Hub จากใน Hub ไม่ได้ — ใช้ Extension Manager ของ SketchUp'] if entry['id'] == Catalog::HUB_ID

          paths = Array(entry['files']).map { |rel| safe_path(plugins_dir, rel) }
          return [false, "index.json ไม่ถูกต้องสำหรับ #{entry['name']}"] if paths.empty? || paths.include?(nil)

          ext = Sketchup.extensions[entry['name']]
          ext.uncheck if ext

          paths.each do |path|
            next unless File.exist?(path)

            File.directory?(path) ? FileUtils.rm_rf(path) : File.delete(path)
          rescue SystemCallError => e
            puts "[SkpCm::ExtensionsHub] remove #{path}: #{e.message}"
          end

          failed = paths.select { |p| File.exist?(p) }
          return [false, "ลบไม่สำเร็จ:\n#{failed.join("\n")}"] unless failed.empty?

          [true, "ถอน #{entry['name']} แล้ว — ปิดแล้วเปิด SketchUp ใหม่ให้มีผลสมบูรณ์"]
        end

        def install_archive(entry, data)
          path = File.join(Dir.tmpdir, "#{entry['id']}_#{entry['latest_version']}.rbz")
          File.binwrite(path, data)
          Sketchup.install_from_archive(path, false)
          [true, install_message(entry)]
        # install_from_archive raises Interrupt (user declined) or plain Exception (bad archive)
        rescue Exception => e # rubocop:disable Lint/RescueException
          [false, "ติดตั้งไม่สำเร็จ: #{e.message.empty? ? e.class : e.message}"]
        ensure
          File.delete(path) if path && File.exist?(path)
        end

        def install_message(entry)
          if entry['installed']
            "อัปเดต #{entry['name']} แล้ว — ปิดแล้วเปิด SketchUp ใหม่เพื่อใช้เวอร์ชัน #{entry['latest_version']}"
          else
            "ติดตั้ง #{entry['name']} #{entry['latest_version']} แล้ว ใช้งานได้ทันที"
          end
        end

        # Yields (ok, message)
        def install(entry, &done)
          return done.call(false, 'ไม่มีไฟล์ .rbz ให้ดาวน์โหลด') unless entry['asset_url']

          Http.get(entry['asset_url']) do |status, body, error|
            if error || status != 200
              done.call(false, "ดาวน์โหลดไม่สำเร็จ (#{error || "HTTP #{status}"})")
            else
              done.call(*install_archive(entry, body))
            end
          end
        end
      end
    end
  end
end
