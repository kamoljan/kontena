module OAuth2TokenVerifier

  attr_accessor :current_access_token

  ##
  # Validate access token in request headers
  #
  def validate_access_token
    authorization = request.env['HTTP_AUTHORIZATION']
    if authorization
      token_type, access_token = authorization.split(' ')
      if token_type != 'Bearer'
        halt_request(400, {error: 'Invalid authorization type'})
        return
      end
      token = AccessToken.where(token: access_token).first
      unless token
        halt_request(403, {error: 'Access denied'})
        return
      end

      if token.expired?
        halt_request(401, {error: 'Session expired'})
        return
      end
      self.current_access_token = token
    else
      halt_request(403, {error: 'Access denied'})
      return
    end
  end
end
