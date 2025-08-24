module Registerable
  extend ActiveSupport::Concern

  class_methods do
    def register(klass)
      key = extract_key_from_class(klass)
      display_name = key.humanize
      registered_items[key] = display_name
    end

    def available_options
      registered_items.map { |key, display_name| [display_name, key] }
    end

    private

    def registered_items
      @registered_items ||= {}
    end

    def extract_key_from_class(klass)
      class_name = klass.name.demodulize
      base_suffix = name.demodulize
      parent_name = name.split("::").first
      expected_suffix = parent_name.singularize

      key = class_name.gsub(/#{expected_suffix}$/, "")
      key.underscore
    end
  end
end
