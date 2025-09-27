module HttpClient
  class Base
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
  end
end
