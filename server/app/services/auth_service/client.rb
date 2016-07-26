require 'httpclient'

module AuthService
  class Client

    class Error < StandardError
      attr_accessor :code, :message, :backtrace

      def initialize(code, message, backtrace = nil)
        self.code = code
        self.message = message
        self.backtrace = backtrace
      end
    end

    attr_accessor :default_headers
    attr_reader :http_client
    attr_reader :base_url

    # Initialize api client
    #
    def initialize(base_url=nil)
      @base_url = base_url || api_url
      @http_client = HTTPClient.new
      @http_client.ssl_config.ssl_version = :TLSv1_2
      @default_headers = {'Accept' => 'application/json', 'Content-Type' => 'application/json'}
    end

    def api_url
      AuthService.api_url
    end

    def authenticate(obj)
      response = post("v1/auth", obj)

      if response.nil?
        return nil
      end
      response['user']
    end

    def post(path, obj, params = {})
      request_options = {
          header: default_headers,
          body: JSON.dump(obj),
          query: params
      }
      handle_response(http_client.post([base_url.gsub(/\/$/, ''), path.gsub(/^\//, '')].join('/'), request_options))
    end

    def handle_response(response)
      if [200, 201].include?(response.status)
        JSON.parse(response.body) rescue nil
      else
        raise AuthService::Client::Error.new(response.status, response.body)
      end
    end

  end
end
