# frozen_string_literal: true

require 'json'
require 'rubygems'
require_relative 'http'

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

      # Yields (entries, nil) or (nil, error_message) when the plugin list itself cannot be loaded
      def load(&done)
        Http.get(INDEX_URL) do |status, body, error|
          next done.call(nil, MSG_OFFLINE) if error || status != 200

          items =
            begin
              parse_index(body)
            rescue SchemaError
              next done.call(nil, MSG_SCHEMA)
            rescue JSON::ParserError
              next done.call(nil, MSG_BAD_INDEX)
            rescue StandardError => e
              log_error(e)
              next done.call(nil, MSG_BAD_INDEX)
            end
          start_fetch(items, &done)
        end
      end

      # fetch_releases may raise on a malformed item before any request is sent; done is still called once
      def start_fetch(items, &done)
        started = false
        begin
          fetch_releases(items) { |*args| started = true; done.call(*args) }
        rescue StandardError => e
          log_error(e)
          done.call(nil, MSG_BAD_INDEX) unless started
        end
      end

      def log_error(error)
        puts "[SkpCm::ExtensionsHub] #{error.class}: #{error.message}"
      end

      def fetch_releases(items, &done)
        return done.call([], nil) if items.empty?

        results = {}
        items.each_with_index do |item, i|
          url = "https://api.github.com/repos/#{item['repo']}/releases/latest"
          Http.get(url, 'Accept' => 'application/vnd.github+json') do |status, body, error|
            results[i] = release_result(status, body, error)
            finish(items, results, &done) if results.size == items.size
          end
        end
      end

      # [release_hash_or_nil, error_message_or_nil]
      def release_result(status, body, error)
        return [nil, MSG_OFFLINE] if error
        return [nil, release_error_message(status)] unless status == 200

        [JSON.parse(body), nil]
      rescue JSON::ParserError
        [nil, 'ข้อมูล release จาก GitHub อ่านไม่ได้']
      end

      def finish(items, results, &done)
        entries =
          begin
            plugins_dir = Sketchup.find_support_file('Plugins')
            items.each_with_index.map do |item, i|
              release, error = results[i]
              ext = Sketchup.extensions[item['name']]
              build_entry(item, plugins_dir: plugins_dir, installed_version: ext ? ext.version : nil,
                                release: release, release_error: error)
            end
          rescue StandardError => e
            log_error(e)
            nil
          end
        entries ? done.call(entries, nil) : done.call(nil, MSG_BAD_INDEX)
      end
    end
  end
end
