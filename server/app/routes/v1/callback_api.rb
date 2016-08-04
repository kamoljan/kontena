module V1
  class CallbackApi < Roda
    include RequestHelpers

    route do |r|
      r.get do
        params = request.params

        if params['error']
          halt_request(502, "The authorization server returned an error: #{params['error']} #{params['error_description']} #{params['error_uri']}") and return
        end

        unless params['state']
          halt_request(400, 'invalid_request') and return
        end

        state = AuthorizationRequest.find_and_invalidate(params['state'])
        unless state
          halt_request(400, 'invalid_request') and return
        end

        if params['code']
          task = AccessTokens::CodeExchange.run(
            code: params['code'],
            user: state.user
          )
          access_token = task.result if task.success?
        elsif params['access_token']
          task = AccessTokens::Create.run(
            user: state.user,
            scope: params['scope'],
            token: params['access_token'],
            refresh_token: params['refresh_token'],
            expires_in: params['expires_in']
          )
          access_token = task.result if task.success?
        else
          halt_request(400, 'invalid_request') and return
        end

        unless task.success?
          halt_request(400, task.errors.message) and return
        end

        # Find or create a new user using tokeninfo
        client = access_token.client
        unless client
          halt_request(503, 'server_error') and return
        end

        user_info = AuthProvider.instance.user_info(client)
        unless user_info
          halt_request(503, 'server_error')
        end

        if User.count == 1 && current_user && current_user.email == 'admin'
          invite_code = SecureRandom.hex(4)
          new_user = User.create(invite_code: invite_code)
          new_user.roles << Role.master_admin
          user_info.merge(invite_code: invite_code)
        end

        task = Users::FromUserInfo.run(user_info)
        if task.success?
          # create new local access token
          @access_token = AccessTokens::Create.run(
            user: task.result,
            scope: state.scope,
            internal: true,
            expires_in: 7200
          )

          if state.redirect_uri
            response.headers['Location'] = @access_token.to_query(
              uri: state.redirect_uri, state: state.state
            )
            response.status = 302
            return nil
          else
            response.status = 201
            if request.headers['Accept'] == 'application/json'
              response.headers['Content-Type'] = 'application/json'
              render('auth/show')
            else
              response.headers['Content-Type'] = 'application/x-www-form-urlencoded'
              @access_token.to_query(state: state)
            end
          end
        else
          halt_request(*task.errors.symbolic.first, task.errors.message.first.last)
          return nil
        end
      end
    end
  end
end
