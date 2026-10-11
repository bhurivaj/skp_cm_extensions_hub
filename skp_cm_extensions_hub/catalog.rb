# frozen_string_literal: true

require 'json'
require 'rubygems'

module SkpCm
  module ExtensionsHub
    # Plugin list (index.json) + latest GitHub release + local install state
    module Catalog
      HUB_ID = 'skp_cm_extensions_hub'
      INDEX_URL = 'https://raw.githubusercontent.com/bhurivaj/skp_cm_extensions_hub/main/index.json'
      SCHEMA = 1

      MSG_OFFLINE = 'เชื่อมต่อ GitHub ไม่ได้ — ตรวจ internet แล้วกดรีเฟรช'
      MSG_SCHEMA = 'รายการ plugins ใหม่กว่า Hub — กรุณาอัปเดต Hub จาก ' \
                   'https://github.com/bhurivaj/skp_cm_extensions_hub/releases'
      MSG_BAD_INDEX = 'อ่านรายการ plugins (index.json) ไม่ได้'

      class SchemaError < StandardError; end

      module_function

      def parse_index(json_text)
        data = JSON.parse(json_text)
        raise SchemaError, 'unsupported index schema' unless data.is_a?(Hash) && data['schema'] == SCHEMA

        Array(data['plugins'])
      end

      # -1 / 0 / 1, or nil when either side is not a version number
      def compare_versions(a, b)
        return nil if a.to_s.empty? || b.to_s.empty?

        Gem::Version.new(a) <=> Gem::Version.new(b)
      rescue ArgumentError
        nil
      end

      def release_error_message(status)
        case status
        when 404 then 'ยังไม่มี release'
        when 403, 429 then 'ตรวจเวอร์ชันไม่ได้ (เกินลิมิต GitHub) ลองใหม่ภายหลัง'
        else "ตรวจเวอร์ชันไม่ได้ (HTTP #{status})"
        end
      end

      def build_entry(item, plugins_dir:, installed_version:, release: nil, release_error: nil)
        files = Array(item['files'])
        installed = !files.empty? && !plugins_dir.nil? && File.exist?(File.join(plugins_dir, files.first))
        latest = release ? release['tag_name'].to_s.sub(/\Av/, '') : ''
        latest = nil if latest.empty?
        asset = release ? Array(release['assets']).find { |a| a['name'].to_s.end_with?('.rbz') } : nil
        error = release_error
        error ||= 'release ล่าสุดไม่มีไฟล์ .rbz' if release && asset.nil?

        {
          'id' => item['id'], 'name' => item['name'], 'description' => item['description'],
          'repo' => item['repo'], 'files' => files,
          'installed' => installed, 'installed_version' => installed_version,
          'latest_version' => latest, 'notes' => release ? release['body'].to_s : '',
          'asset_url' => asset ? asset['browser_download_url'] : nil,
          'status' => status_for(installed, installed_version, latest),
          'error' => error, 'self' => item['id'] == HUB_ID
        }
      end

      def status_for(installed, installed_version, latest)
        return 'not_installed' unless installed

        cmp = compare_versions(latest, installed_version)
        return 'unknown' if cmp.nil?

        cmp.positive? ? 'update_available' : 'up_to_date'
      end

      def mark_pending(entries, ids)
        entries.map { |e| e.merge('pending_restart' => ids.include?(e['id'])) }
      end
    end
  end
end
