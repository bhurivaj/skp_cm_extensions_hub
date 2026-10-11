# frozen_string_literal: true

require 'sketchup.rb'
require_relative 'http'
require_relative 'catalog'
require_relative 'installer'
require_relative 'dialog'
require_relative 'update_check'

module SkpCm
  module ExtensionsHub
    unless file_loaded?(__FILE__)
      UI.menu('Extensions').add_item(PLUGIN_NAME) { Dialog.show }

      # wait a bit so the check does not compete with SketchUp start-up
      UI.start_timer(10, false) { UpdateCheck.run }

      file_loaded(__FILE__)
    end
  end
end
