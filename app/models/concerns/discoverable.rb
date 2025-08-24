module Discoverable
  extend ActiveSupport::Concern

  class_methods do
    def display_name
      @display_name ||= key.humanize
    end

    def key
      @key ||= superclass.send(:extract_key_from_class, self)
    end

    def available_options
      descendants.map do |klass|
        [klass.display_name, klass.key]
      end
    end

    private

    def extract_key_from_class(klass)
      class_name = klass.name.demodulize
      parent_name = name.split("::").first
      expected_suffix = parent_name.singularize

      key = class_name.gsub(/#{expected_suffix}$/, "")
      key.underscore
    end
  end
end
