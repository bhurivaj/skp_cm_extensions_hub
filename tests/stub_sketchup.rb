# frozen_string_literal: true

# Minimal stub of the SketchUp API used by the Hub — lets tests run with plain ruby
module Sketchup
  FakeExtension = Struct.new(:version) do
    attr_reader :unchecked

    def uncheck
      @unchecked = true
    end
  end

  class << self
    attr_accessor :plugins_dir, :extensions, :archives, :install_error

    def find_support_file(name)
      name == 'Plugins' ? plugins_dir : nil
    end

    def install_from_archive(path, _show_warning = true)
      raise install_error if install_error

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
