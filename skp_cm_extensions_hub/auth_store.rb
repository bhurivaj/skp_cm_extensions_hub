# frozen_string_literal: true

require 'json'
require 'base64'
require 'fileutils'

module SkpCm
  module ExtensionsHub
    # Saved account for Auth: <user data>/SkpCm/extensions_hub/auth.json. The token is never saved.
    module AuthStore
      DEFAULT_API_URL = 'https://odoo.catice.co'
      # XOR + Base64 only hides the password from casual reading — it is not encryption
      KEY = 'SkpCmExtensionsHub'

      class << self
        def data_dir
          base =
            if Sketchup.platform == :platform_win
              appdata = ENV['APPDATA']
              appdata.nil? || appdata.empty? ? File.join(Dir.home, 'AppData', 'Roaming') : appdata
            else
              File.join(Dir.home, 'Library', 'Application Support')
            end
          File.join(base, 'SkpCm', 'extensions_hub')
        end

        def path
          File.join(data_dir, 'auth.json')
        end

        def defaults
          { 'api_base_url' => DEFAULT_API_URL, 'username' => '', 'password' => '', 'verified' => false }
        end

        # Always a full state hash; a missing or broken file gives the defaults
        def load
          return defaults unless File.exist?(path)

          data = JSON.parse(File.read(path, encoding: 'UTF-8'))
          return defaults unless data.is_a?(Hash)

          url = data['api_base_url'].to_s
          {
            'api_base_url' => url.empty? ? DEFAULT_API_URL : url,
            'username' => data['username'].to_s,
            'password' => decrypt(data['password'].to_s),
            'verified' => data['verified'] == true
          }
        rescue JSON::ParserError, SystemCallError, IOError => e
          puts "[SKP CM Extensions Hub] could not read #{path}: #{e.message}"
          defaults
        end

        def save(state)
          FileUtils.mkdir_p(data_dir)
          File.write(path, JSON.pretty_generate(state.merge('password' => encrypt(state['password'].to_s))))
          true
        rescue SystemCallError, IOError => e
          puts "[SKP CM Extensions Hub] could not save #{path}: #{e.message}"
          false
        end

        def encrypt(text)
          return '' if text.empty?

          Base64.strict_encode64(xor(text.b))
        end

        def decrypt(text)
          return '' if text.empty?

          xor(Base64.strict_decode64(text)).force_encoding('UTF-8')
        rescue ArgumentError
          ''
        end

        private

        def xor(bytes)
          bytes.bytes.each_with_index.map { |b, i| b ^ KEY.getbyte(i % KEY.bytesize) }.pack('C*')
        end
      end
    end
  end
end
