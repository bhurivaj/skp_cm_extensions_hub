# frozen_string_literal: true

module SkpCm
  module ExtensionsHub
    # Async GET on top of Sketchup::Http; follows redirects itself (GitHub asset links redirect to another host)
    module Http
      MAX_REDIRECTS = 5
      REDIRECT_CODES = [301, 302, 303, 307, 308].freeze

      class << self
        # Yields (status_code, body, error_message); error_message is nil on success
        def get(url, headers = {}, redirects_left = MAX_REDIRECTS, &done)
          request = Sketchup::Http::Request.new(url, Sketchup::Http::GET)
          request.headers = default_headers.merge(headers)
          pending << request # keep a reference so the request is not garbage collected mid-flight
          request.start do |req, response|
            pending.delete(req)
            handle(response, headers, redirects_left, done)
          end
        rescue StandardError => e
          pending.delete(request) if request
          safe_call(done, nil, nil, e.message)
        end

        def redirect_location(status, headers)
          return nil unless REDIRECT_CODES.include?(status)

          pair = (headers || {}).find { |k, _| k.to_s.casecmp?('location') }
          pair ? pair[1] : nil
        end

        private

        def handle(response, headers, redirects_left, done)
          status = response ? response.status_code.to_i : 0
          return safe_call(done, nil, nil, 'network error') if status.zero?

          location = redirect_location(status, response.headers)
          if location.nil?
            safe_call(done, status, response.body, nil)
          elsif redirects_left <= 0
            safe_call(done, status, nil, 'too many redirects')
          else
            get(location, headers, redirects_left - 1, &done)
          end
        rescue StandardError => e
          safe_call(done, nil, nil, e.message)
        end

        def safe_call(done, *args)
          done.call(*args)
        rescue StandardError => e
          puts "[SkpCm::ExtensionsHub] callback error: #{e.class}: #{e.message}"
        end

        def pending
          @pending ||= []
        end

        def default_headers
          { 'User-Agent' => "skp_cm_extensions_hub/#{VERSION}" }
        end
      end
    end
  end
end
