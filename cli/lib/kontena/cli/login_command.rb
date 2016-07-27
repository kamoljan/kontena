class Kontena::Cli::LoginCommand < Clamp::Command
  include Kontena::Cli::Common

  parameter "[URL]", "Kontena Master URI. If not provided, login to authentication provider only."

  option ['-n', '--name'], 'NAME', 'Local alias name for the master. Default default'
  option ['-a', '--account'], 'NAME', 'Use account <name> as authentication provider. Default kontena'
  option ['-u', '--username'], '[USERNAME]', 'Username (optional)'
  option ['-p', '--password'], '[PASSWORD]', 'Password (optional)'

  def is_master?
    server_info['name'].eql?('Kontena Master')
  end

  def server_version
    @server_version ||= Gem::Version.new(server_info['version'])
  end

  def code_exchange_url
    [
      current_account.url.gsub(/\/$/, ''),
      current_account.code_exchange_path.gsub(/^\//, '')
    ].join('/')
  end

  def server_info
    return @server_info if @server_info
    logger.debug "Requesting information from #{self.url}"
    response = Kontena::Client.new(self.url).get('/')
    if response.kind_of?(Hash)
      @server_info = response
    else
      puts "Invalid response from server."
      exit 1
    end
    @server_info
  rescue 
    logger.debug "Server info exception: #{$!} #{$!.message}"
    if $!.message.include?('Unable to verify certificate')
      puts "The server uses a certificate signed by an unknown authority.".colorize(:red)
      puts "Protip: you can bypass the certificate check by setting #{'SSL_IGNORE_ERRORS=true'.colorize(:yellow)} env variable, but any data you send to the server could be intercepted by others."
    end

    puts 'Could not connect to server'.colorize(:red)
    exit(1)
  end

  def current_account
    @current_account ||= require_account
  end

  def require_account
    @current_account = config.find_account(self.account || 'kontena')

    unless @current_account
      puts 'Account not found in configuration.'.colorize(:red)
      exit 1
    end

    unless config.current_account.name == @current_account.name
      config.current_account = @current_account
    end

    logger.debug "Using account '#{@current_account.name}' as authentication provider."
    @current_account
  end

  def master_supports_external_auth?
    server_version >= Gem::Version.new('0.15.0')
  end

  def legacy_master?
    !master_supports_external_auth?
  end

  def current_server
    return @current_server if @current_server
    existing_server = config.find_server(self.name)
    if existing_server
      logger.debug "Found existing server in configuration"
      @current_server = existing_server
    else
      logger.debug "New server #{self.name} at #{self.url}"
      @current_server = Kontena::Cli::Config::Server.new(url: self.url, name: self.name)
    end
    @current_server
  end

  def current_server_token
    return current_server.token if current_server.token
    current_server.token = Kontena::Cli::Config::Token.new(parent_type: :master)
    current_server.token
  end

  def current_account_token
    return current_account.token if current_account.token
    current_account.token = Kontena::Cli::Config::Token.new(parent_type: :account)
    current_account.token
  end

  def current_token
    @current_token
  end

  def current_token=(token)
    @current_token = token
  end

  def update_server_to_config
    existing_server_index = config.find_server_index(name)
    if existing_server_index
      config.servers[existing_server_index] = current_server
    else
      config.servers << current_server
    end
  end

  def update_account_to_config
    existing_account_index = config.find_account_index(current_account.name)
    if existing_account_index
      config.accounts[existing_account_index] = current_account
    else
      config.accounts << current_account
    end
  end

  def login_client
    @login_client ||= Kontena::Client.new(current_account.url, current_token)
  end

  def master_client
    @master_client ||= Kontena::Client.new(current_server.url, current_server_token)
  end

  def reset_token
    current_token.access_token = nil
    current_token.refresh_token = nil
    current_token.expires_at = nil
  end

  def execute
    require 'highline/import'

    self.name ||= 'default'

    if self.url
      # If url was provided, see that it is a kontena master.
      if is_master?
        logger.debug "The server at #{self.url} is a Kontena Master version #{server_version}"
      else
        puts 'The server does not appear to be a Kontena Master.'.colorize(:red)
        exit 1
      end

      if legacy_master?
        puts "The server is running Kontena Master version #{server_version}. Upgrade the server or use CLI version < 0.15.0."
        exit 1
      end
    else
      logger.debug "No master url provided, performing auth provider login only."
    end

    # From this point forward we need an account to log in to.
    require_account
    self.current_token = current_account_token

    logger.debug "Testing if existing authentication is valid"

    if login_client.authentication_ok?(current_account.token_verify_path)
      logger.debug "Existing authentication to #{current_account.name} works, password login not required."
    else
      logger.debug "Login required"
      reset_token
      email = self.username || ask("Email: ")
      pass  = self.password || (ask("Password: ") { |q| q.echo = "*" })
      success = login_client.login(email, pass, current_account.resource_owner_credentials_path)
      if success
        config.current_account = current_account.name
        logger.debug "Resource owner password authentication to #{current_account.name} successful."
        current_server.account = current_account.name if self.url
        update_account_to_config
        config.write
      else
        puts 'Login failed'.colorize(:red)
        exit 1
      end
    end

    display_logo

    if self.url
      logger.debug "Logged in to authentication provider, need to authenticate to master."
    else
      logger.debug "Login to auth provider complete, no master selected, exiting."
      config.write
      exit 0
    end

    logger.debug "Requesting code generation from authentication provider"
    code = login_client.generate_code(
      current_account.authorization_path,
      nil,  # scopes
      7200, # expires_in
      "Kontena Master #{name} @ #{url}" # token note
    )

    if code
      logger.debug "Generated code '#{code}' from #{current_account.name}"
    else
      puts "Failed to generate authentication code from authorization server".colorize(:red)
      exit 1
    end

    logger.debug "Performing code login to #{current_server.url}"
    success = master_client.code_login(code, code_exchange_url)
    if success
      logger.debug "Master code login succesful."
      config.current_server = self.name
      puts "Authenticated to master at #{current_server.url}"
      puts
    else
      puts "Authentication to master at #{current_server.url} using authorization code from #{current_account.name} failed.".colorize(:red)
      exit 1
    end

    logger.debug "Getting list of grids"
    grids = master_client.get('grids')['grids']
    grid = grids.first

    if grid
      current_server.grid = grid['name']
      puts "Using grid #{grid['name'].cyan}"
      puts ""
      if grids.size > 1
        puts "You have access to following grids and can switch between them using 'kontena grid use <name>'"
        puts ""
        grids.each do |grid|
          puts "  * #{grid['name']}"
        end
        puts ""
      end
    else
      puts "The master does not have any grids configured. Next you can create one using: kontena grid create <name>"
      current_server.grid = nil
    end

    logger.debug "Updating config"
    config.write

    puts "Welcome! See 'kontena --help' to get started."
    exit 0
  end

  def display_logo
    logo = <<LOGO
 _               _
| | _____  _ __ | |_ ___ _ __   __ _
| |/ / _ \\| '_ \\| __/ _ \\ '_ \\ / _` |
|   < (_) | | | | ||  __/ | | | (_| |
|_|\\_\\___/|_| |_|\\__\\___|_| |_|\\__,_|
-------------------------------------
Copyright (c)2016 Kontena, Inc.
LOGO
    puts logo
    print "Logged in".colorize(:green)
    current_user = (current_token.parent && current_token.parent.username) || current_account.username
    if current_user
      print " as ".colorize(:green)
      print current_user.colorize(:yellow)
    else
      print " using token".colorize(:green)
    end
    print " to ".colorize(:green)
    if current_master.nil?
      print current_account.name.colorize(:yellow)
      puts " (#{current_account.url})"
    else
      print current_master.name.colorize(:yellow)
      print " (#{current_master.url})"
      print " using account on ".colorize(:green)
      puts current_master.account.colorize(:yellow)
    end
  end
end
