require 'json'
require 'excon'
require_relative 'errors'
require_relative 'cli/version'

module Kontena
  class Client

    class ConfigParser
      include Kontena::Cli::Common
    end

    attr_accessor :default_headers, :path_prefix
    attr_reader :http_client
    attr_reader :last_response
    attr_reader :options

    # Initialize api client
    #
    # @param [String] api_url
    # @param [Hash] default_headers
    def initialize(api_url, default_headers = {})
      @options = 
      @options = default_headers.delete(:options)
      Excon.defaults[:ssl_verify_peer] = false if ignore_ssl_errors?
      @http_client = Excon.new(api_url)
      @default_headers = {
        'Accept' => 'application/json',
        'Content-Type' => 'application/json',
        'User-Agent' => "kontena-cli/#{Kontena::Cli::VERSION}"
      }.merge(default_headers)
      @api_url = api_url
      @path_prefix = '/v1/'
    end

    # Return server version from a Kontena master
    #
    # @return [String] version_string
    def server_version
      request_options = {
          method: :get,
          expects: [200],
          path: '/',
          headers: { 'Accept' => 'application/json' },
          body: nil,
          query: nil
      }
      @last_response = http_client.request(request_options)
      data = parse_response
      data['version']
    rescue
      nil
    end

    # Get request
    #
    # @param [String] path
    # @param [Hash,NilClass] params
    # @param [Hash] headers
    # @return [Hash]
    def get(path, params = nil, headers = {})
      request(:get, path, nil, params, headers)
    end

    # Get request
    #
    # @param [String] path
    # @param [Lambda] response_block
    # @param [Hash,NilClass] params
    # @param [Hash] headers
    def get_stream(path, response_block, params = nil, headers = {})
      http_client.request(
        method: :get,
        expects: [200],
        read_timeout: 360,
        path: request_uri(path),
        query: params,
        headers: request_headers(headers),
        response_block: response_block
      )
    rescue Excon::Errors::Unauthorized 
      refresh_token and retry
      handle_error_response(@last_response)
    rescue
      handle_error_response(@last_response)
    end

    # Post request
    #
    # @param [String] path
    # @param [Object] obj
    # @param [Hash] params
    # @param [Hash] headers
    # @return [Hash]
    def post(path, obj, params = {}, headers = {})
      request(:post, path, obj, params, headers)
    end

    # Put request
    #
    # @param [String] path
    # @param [Object] obj
    # @param [Hash] params
    # @param [Hash] headers
    # @return [Hash]
    def put(path, obj, params = {}, headers = {})
      request(:put, path, obj, params, headers)
    end

    # Delete request
    #
    # @param [String] path
    # @param [Hash,String] body
    # @param [Hash] params
    # @param [Hash] headers
    # @return [Hash]
    def delete(path, body = nil, params = {}, headers = {})
      request(:delete, path, body, params, headers)
    end

    # HTTP request
    #
    # @param [Symbol] http_method
    # @param [String] path
    # @param [Object] obj
    # @param [Hash] params
    # @param [Hash] headers
    # @return [Hash]
    def request(http_method, path, obj = nil, params = {}, headers = {})
      retried ||= false
      request_headers = request_headers(headers)
      request_options = {
          method: http_method,
          expects: [200, 201],
          path: request_uri(path),
          headers: request_headers,
          body: obj.nil? ? nil : encode_body(obj, request_headers['Content-Type']),
          query: params
      }
      @last_response = http_client.request(request_options)
      parse_response
    rescue Excon::Errors::Unauthorized
      unless retried
        retried = true
        token = refresh_token_from_config
        if token
          refresh_token(token) and retry
        end
      end
      handle_error_response(@last_response)
    rescue
      handle_error_response(@last_response)
    end

    def refresh_token_from_config
      return nil if ENV['KONTENA_TOKEN']
      token = default_headers.fetch('Authorization', '').split(' ').last
      config = ConfigParser.new
      server_data = config.settings['servers'].find{|s| s['url'] == api_url && s['token'] == token}
      server_data ? server_data['refresh_token'] : nil
    end

    def refresh_token(refresh_token, refresh_endpoint = '/v1/auth/token', expires_in = 10800, client_id=nil, client_secret=nil)
      ENV["DEBUG"] && puts('Refreshing master access token')
      request_options = {
        method: :post,
        expects: [200],
        path: refresh_endpoint,
        headers: request_headers.reject{|k,_| k == 'Authorization'},
        body: nil,
        params: {
          grant_type: 'refresh_token',
          expires_in: expires_in,
          client_id: client_id,
          client_secret: client_secret,
          refresh_token: refresh_token
        }
      }
      @last_response = http_client.request(request_options)
      data = parse_response
      if data['access_token'] && data['refresh_token'] && data['expires_in']
        old_token = default_headers.fetch('Authorization', '').split(' ').last
        default_headers['Authorization'] = "Bearer #{data['access_token']}"
        config = ConfigParser.new
        server_index = config.settings['servers'].find_index{|s| s['url'] == api_url && s['token'] == old_token}
        master_config = config.settings['servers'][server_index]
        master_config['token']         = data['access_token']
        master_config['refresh_token'] = data['refresh_token']
        master_config['expires_at']    = data['expires_in'].to_i + Time.now.utc.to_i
        config.settings['servers'][server_index] = master_config
        config.save_settings
        master_config
      else
        ENV["DEBUG"] && puts('Master access token refresh failed, response does not have required keys')
        nil
      end
    rescue
      ENV["DEBUG"] && puts("Master access token refresh exception: #{$!} - #{$!.message}")
      nil
    end

    private

    ##
    # Get full request uri
    #
    # @param [String] path
    # @return [String]
    def request_uri(path)
      "#{path_prefix}#{path}"
    end

    ##
    # Get request headers
    #
    # @param [Hash] headers
    # @return [Hash]
    def request_headers(headers = {})
      @default_headers.merge(headers)
    end

    ##
    # Encode body based on content type
    #
    # @param [Object] body
    # @param [String] content_type
    def encode_body(body, content_type)
      if content_type == 'application/json'
        dump_json(body)
      else
        body
      end
    end

    ##
    # Parse response
    #
    # @param [HTTP::Message]
    # @return [Object]
    def parse_response
      if response.headers['Content-Type'].include?('application/json')
        parse_json(last_response.body)
      else
        last_response.body
      end
    end

    ##
    # Parse json
    #
    # @param [String] json
    # @return [Hash,Object,NilClass]
    def parse_json(json)
      JSON.parse(json) rescue nil
    end

    ##
    # Dump json
    #
    # @param [Object] obj
    # @return [String]
    def dump_json(obj)
      JSON.dump(obj)
    end

    # @return [Boolean]
    def ignore_ssl_errors?
      ENV['SSL_IGNORE_ERRORS'] == 'true'
    end

    # @param [Excon::Response] response
    def handle_error_response(response)
      message = response.body
      if response.status == 404 && message == ''
        message = 'Not found'
      end
      raise Kontena::Errors::StandardError.new(response.status, message)
    end
  end
end
