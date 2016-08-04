class TokenAuthentication

  # Rack middleware oauth token authentication
  #
  # Add excluded paths, such as /v1/ping or /cb in the option :exclude.
  #
  # Use the option :soft_exclude to parse the token if it exists, but allow
  # request even without token
  attr_reader :logger
  attr_reader :opts

  CURRENT_USER              = 'auth.current_user'.freeze
  CURRENT_TOKEN             = 'auth.current_access_token'.freeze
  BEARER                    = 'Bearer'.freeze
  BASIC                     = 'Basic'.freeze
  HTTP_AUTHORIZATION        = 'HTTP_AUTHORIZATION'.freeze
  PATH_INFO                 = 'PATH_INFO'.freeze

  def initialize(app, options= {})
    @app    = app
    @opts   = options
    @logger = Logger.new(STDOUT)
    @logger.progname = 'AUTH'
    @logger.level = ENV['DEBUG'] ? Logger::DEBUG : Logger::INFO
  end

  def call(env)
    return @app.call(env) if path_included?(env, :exclude)

    request = Rack::Request.new(env)

    bearer = bearer_token(env)

    if bearer.nil?
      if path_included?(env, :soft_exclude)
        return @app.call(env)
      else
        return redirect_response(request.params['state'])
      end
    end

    access_token = token_from_db(bearer)

    return expiration_response    if access_token.expired?
    return access_denied_response if access_token.nil?

    if access_token
      env[CURRENT_USER]    = access_token.user
      env[CURRENT_TOKEN]   = access_token
    end

    @app.call(env)
  end

  def path_included?(env, opt_key)
    case opts[opt_key]
    when NilClass
      false
    when Array
      opts[opt_key].any?{|ex| path_matches?(ex, env[PATH_INFO])}
    when String || Regexp
      path_matches?(opts[opt_key], env[PATH_INFO])
    else
      raise TypeError, "Invalid #{opt_key} option. Use a String, Regexp or an Array including either."
    end
  end

  def path_matches?(matcher, path)
    if matcher.kind_of?(String)
      if matcher.end_with?('*')
        path.start_with?(matcher[0..-2])
      else
        path.eql?(matcher)
      end
    else
      path[matcher] ? true : false
    end
  end

  def redirect_response(state)
    if AuthProvider.instance
      [
        302,
        {
          'Location' => AuthProvider.instance.authorization_url(state)
        },
        []
      ]
    end
  end

  def error_response(msg=nil)
    [
      403,
      {
        'Content-Type'   => 'application/json',
        'Content-Length' => msg ? msg.bytesize.to_s : 0
      },
      [msg]
    ]
  end

  def access_denied_response
    error_response 'Access denied'
  end

  def expiration_response
    error_response 'Token expired'
  end

  def bearer_token(env)
    token_type, token = env[HTTP_AUTHORIZATION].to_s.split
    case token_type
    when BEARER 
      token
    when BASIC
      Base64.decode64(token).split(':').last rescue nil
    else
      nil
    end
  end

  def token_from_db(token)
    return nil unless token
    AccessToken.find_by_access_token(token)
  rescue
    logger.error "Exception while fetching token from db: #{$!} #{$!.message}"
    nil
  end
end
