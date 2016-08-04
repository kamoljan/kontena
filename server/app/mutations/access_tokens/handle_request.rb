module AccessTokens
  class HandleRequest < Mutations::Command

    optional do
      model :current_access_token
      model :current_user
      string :grant_type
      string :refresh_token
      string :response_type
      string :scope
      string :code
      string :note
      string :redirect_uri
      string :client_id
      string :client_secret
      integer :expires_in
    end

    def validate
      %i(
        grant_type response_type scope code note redirect_uri client_id client_secret refresh_token
      ).each do |param|
        nillify_if_blank!(send(param))
      end

      # Implicit grant flow will never work without redirect_uri
      if self.response_type.to_s == 'token' && self.redirect_uri.nil?
        add_error(:http_400, :invalid_request, 'Redirect URI is required when using implicit grant flow')
        return false
      end

      # Attempting code exchange without code
      if self.grant_type.to_s == 'authorization_code' && self.code.nil?
        add_error(:http_400, :invalid_request, 'Code exchange requested, but code is missing')
        return false
      end

      if self.current_access_token.nil?
        if self.grant_type
          add_error(:http_403, :access_denied, 'Access denied')
          return false
        end
      end

      if self.current_access_token && !self.current_user
        self.current_user = self.current_access_token.user
      end
    end

    def scope_to_array
      scope.to_s.gsub(/\s+/, '').split(',')
    end

    def nillify_if_blank!(obj)
      obj = nil if blank?(obj)
    end

    def blank?(obj)
      obj.to_s.gsub(/\s+/, '') == ''
    end

    # Does the current access token have any of the listed scopes?
    def current_scopes_include?(*scopes)
      return false unless self.current_access_token
      scopes.any? { |scope| self.current_access_token.scopes.include?(scope) }
    end


    def execute
      if self.grant_type.nil? && self.response_type.nil?
        # User just wants to view the tokeninfo. We allow it if the token has 'user' scope.
        if current_scopes_include?('user', 'user:info')
          return self.current_access_token
        else
          add_error(:http_403, :access_denied, 'Access denied')
          return nil
        end
      end

      case self.response_type.to_s.gsub(/\s+/, '')
      when 'code'
        # create code
        
        unless self.current_access_token
          add_error(:http_403, :access_denied, 'Access denied')
          return nil
        end

        task = AccessTokens::Create.run(
          user: self.current_access_token.user,
          scopes: scope_to_array,
          expires_in: 1800,
          with_code: true
        )
        if task.success?
          return task.result
        else
          if task.errors.symbolic.keys.include?(:scope)
            add_error(:http_400, :invalid_scope, 'Invalid scope')
          else
            add_error(:http_500, :server_error, 'Internal server error')
          end
          return nil
        end
      when 'token'
        # implicit grant flow, create non refreshable token
        unless self.current_user
          add_error(:http_403, :access_denied, 'Access denied')
          return nil
        end
        task = AccessTokens::Create.run(
          user: self.current_user,
          scopes: scope_to_array,
          refreshable: false,
          expires_in: self.expires_in || 7200
        )
        if task.success?
          return task.result
        else
          if task.errors.symbolic.keys.include?(:scope)
            add_error(:http_400, :invalid_scope, 'Invalid scope')
          else
            add_error(:http_500, :server_error, 'Internal server error')
          end
          return nil
        end
      when ''
        # response_type not specified, so there must be a grant_type, go to next "case"
        nil
      else
        add_error(:http_400, :unsupported_response_type, 'Unsupported response type')
        return nil
      end

      case self.grant_type.to_s.gsub(/\s+/, '')
      when 'refresh_token'
        # refresh token flow
        unless self.refresh_token
          add_error(:http_400, :invalid_request, 'Missing refresh token')
          return nil
        end
        # create access token duplicate if refresh token valid
        task = AccessTokens::Refresh.run(
          refresh_token: self.refresh_token,
          scope: self.scope
        )
        if task.success?
          return task.result
        else
          add_error(:http_400, :invalid_request, 'Invalid request')
          return nil
        end
      when 'aurhorization_code'
        # authorization code flow
        unless self.code
          add_error(:http_400, :invalid_request, 'Missing code')
          return nil
        end

        #TODO validate client_id + client_secret if there are
        #applications in master.
        
        token = AccessToken.find_by_code(self.code)
        if token
          return token
        else
          add_error(:http_400, :invalid_request, 'Invalid request')
          return nil
        end
      else
        add_error(:http_400, :unsupported_grant_type, 'Unsupported grant type')
        return nil
      end

      # Execution should never end up here
      add_error(:http_500, :server_error, 'Should never happen')
      nil
    end
  end
end
