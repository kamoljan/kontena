class CreateInitialAuthProvider < Mongodb::Migration
  def self.up
    AuthProvider.create_indexes
    if AuthProvider.count == 0
      md = ENV['AUTH_API_URL'].to_s.match(/^(.+?):\/\/(.*)/)
      if md[1] == 'oauth2'
        credentials, provider = md[2].split('@')
        if credentials
          client_id, client_secret = credentials.split(':')
          auth_provider = AuthProvider.create(
            client_id:     client_id,
            client_secret: client_secret,
            provider:      provider
          )
        end
      end
    end
  end
end

