module Normalizer
  # Profile sources hand the processor a permalink and an already-resolved
  # image list, so their normalizers read the same two fields.
  module ProfilePayload
    private

    def normalize_attachment_urls
      Array(raw_data["images"]).uniq
    end

    def original_url
      @original_url ||= raw_data["url"].to_s
    end
  end
end
