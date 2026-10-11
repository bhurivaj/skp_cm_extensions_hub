# frozen_string_literal: true

# Minimal stub of the SketchUp API used by the Hub — lets tests run with plain ruby
module Sketchup
  FakeExtension = Struct.new(:version) do
    attr_reader :unchecked, :checked
    attr_writer :loaded

    def uncheck
      @unchecked = true
    end

    def check
      @checked = true
    end

    def loaded?
      @loaded ? true : false
    end
  end

  class << self
    attr_accessor :plugins_dir, :extensions, :archives, :install_error, :archive_paths

    def find_support_file(name)
      name == 'Plugins' ? plugins_dir : nil
    end

    def install_from_archive(path, _show_warning = true)
      raise install_error if install_error

      (self.archive_paths ||= []) << path
      (self.archives ||= []) << File.binread(path)
      true
    end
  end
end

module SkpCm
  module ExtensionsHub
    VERSION = 'test' unless const_defined?(:VERSION)
  end
end
