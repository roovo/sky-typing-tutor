require "active_support"
require "active_support/rails"

require "nokogiri"

module ActionText
  extend ActiveSupport::Autoload

  autoload :Attachable
  autoload :BottomUpReducer

  module Attachables
    extend ActiveSupport::Autoload
  end

  class << self
    def html_document_class
      return @html_document_class if defined?(@html_document_class)
      @html_document_class =
        defined?(Nokogiri::HTML5) ? Nokogiri::HTML5::Document : Nokogiri::HTML4::Document
    end
  end
end
