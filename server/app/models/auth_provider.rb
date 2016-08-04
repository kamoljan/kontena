require 'uri'
require 'bcrypt'
require 'omniauth'

Dir[File.expand_path('../auth_providers/*.rb', __FILE__)].each {|f| require f}

class AuthProvider
  include Mongoid::Document
  include Mongoid::Timestamps

  field :provider, type: String
  field :client_id, type: String
  field :client_secret, type: String
  field :salt, type: String

  validates_presence_of :provider
  validates_presence_of :client_id
  validates_presence_of :client_secret

  set_callback :save, :before do |doc|
    doc.salt ||= BCrypt::Engine.generate_salt
  end

  # Only have one of these always
  set_callback :save, :after do |doc|
    AuthProvider.all.reject{|ap| ap.id == doc.id}.map(&:destroy)
  end

  # Run the setter on initialize to load auth provider extensions
  set_callback :initialize, :after do |doc|
    doc.provider = doc.provider
  end

  class << self
    def instance
      @instance ||= AuthProvider.first
    end

    def salt
      @salt ||= instance.nil? ? nil : instance.salt
    end

    def encrypt(string)
      BCrypt::Engine.hash_secret(string, salt)
    end

    def valid_digest?(string, digest)
      BCrypt::Password.new(digest) == string
    end
  end

  # Automatically include provider specific extensions
  def provider=(provider_name)
    if provider_name && AuthProvider::const_defined?(provider_name.capitalize)
      extension = AuthProvider::const_get(provider_name.capitalize)
      self.extend(extension) if extension
    end
    super(provider_name)
  end

  def authorization_url(state, user: nil, redirect_uri: nil)
    AuthorizationRequest.create(
      state: state,
      user: user,
      redirect_uri: redirect_uri
    )
    strategy.client.auth_code.authorize_url(scope: provider_scope, state: state)
  rescue
    ENV["DEBUG"] && puts("Authorization url exception: #{$!} #{$!.message}")
    nil
  end

  def code_exchange(code)
    token = strategy.client.auth_code.get_token(code)
    token.token ? token : nil
  rescue
    ENV["DEBUG"] && puts("Code exchange exception: #{$!} #{$!.message}")
    nil
  end
end
