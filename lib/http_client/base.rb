module HttpClient
  class Base
    attr_reader :client_options

    def initialize(options = {})
      @client_options = options.freeze
    end

    def get(url, headers: {}, options: {})
      raise NotImplementedError, "Subclasses must implement #get"
    end

    def post(url, body: nil, headers: {}, options: {})
      raise NotImplementedError, "Subclasses must implement #post"
    end

    def put(url, body: nil, headers: {}, options: {})
      raise NotImplementedError, "Subclasses must implement #put"
    end

    def delete(url, headers: {}, options: {})
      raise NotImplementedError, "Subclasses must implement #delete"
    end

    # Override this in subclasses to provide default options
    def default_options
      {}
    end

    # Merges default options with client options and per-request options
    # Returns a new hash with the merged options
    def options(request_options = {})
      default_options.merge(client_options).merge(request_options)
    end
  end
end
