# frozen_string_literal: true

require 'sketchup.rb'
require 'extensions.rb'

module SkpCm
  module ExtensionsHub
    PLUGIN_NAME = 'SKP CM Extensions Hub'
    VERSION = '0.5.1'

    file = __FILE__.dup
    file.force_encoding('UTF-8') if file.respond_to?(:force_encoding)
    PLUGIN_DIR = File.join(File.dirname(file), 'skp_cm_extensions_hub').freeze

    unless file_loaded?(__FILE__)
      EXTENSION = SketchupExtension.new(PLUGIN_NAME, File.join(PLUGIN_DIR, 'main'))
      EXTENSION.description = 'Install, update and remove SKP CM plugins from GitHub Releases.'
      EXTENSION.version = VERSION
      EXTENSION.creator = 'Bhurivaj Padcharaditthakul'
      EXTENSION.copyright = '© 2026 Bhurivaj Padcharaditthakul'
      Sketchup.register_extension(EXTENSION, true)
      file_loaded(__FILE__)
    end
  end
end
