module Loaders
  class HttpLoader < Base
    def load
      # TBD
      {
        status: :success,
        data: "sample feed content",
        content_type: "application/xml"
      }
    end
  end
end
