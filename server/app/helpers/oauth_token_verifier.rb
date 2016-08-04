module OAuth2TokenVerifier

  ##
  # Validate access token in request headers
  #
  def validate_access_token
    unless current_user 
      # The middleware handles this already.
      halt_request(403, {error: 'Access denied'})
    end
  end

  def current_user
    ENV[TokenAuthentication::CURRENT_USER]
  end

  def current_access_token
    ENV[TokenAuthentication::CURRENT_TOKEN]
  end
end
