# frozen_string_literal: true

require 'sketchup.rb'
require_relative 'http'
require_relative 'catalog'
require_relative 'installer'
require_relative 'dialog'
require_relative 'update_check'
require_relative 'auth'

module SkpCm
  module ExtensionsHub
    unless file_loaded?(__FILE__)
      UI.menu('Extensions').add_item(PLUGIN_NAME) do
        begin
          Dialog.show
        rescue StandardError => e
          puts "[#{PLUGIN_NAME}] #{e.class}: #{e.message}"
        end
      end

      # wait a bit so the check does not compete with SketchUp start-up
      UI.start_timer(10, false) { UpdateCheck.run }

      # silent login with the saved account; plugins may ask Auth for the state right after loading
      UI.start_timer(1, false) do
        begin
          Auth.auto_login
        rescue StandardError => e
          puts "[#{PLUGIN_NAME}] auto-login: #{e.class}: #{e.message}"
        end
      end

      file_loaded(__FILE__)
    end
  end
end
