json.set! :provider, @auth_provider.provider
json.set! :client_id, @auth_provider.client_id.nil? ? nil : 'hidden'
json.set! :client_secret, @auth_provider.client_secret.nil? ? nil : 'hidden'
