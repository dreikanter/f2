module Discoverable
  extend ActiveSupport::Concern

  class_methods do
    def available_options
      descendants.map do |klass|
        key = extract_key_from_class(klass)
        display_name = key.humanize
        [display_name, key]
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
