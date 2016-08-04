module V1
  class TokenApi < Roda
    include RequestHelpers

    JSON_MIME    = 'application/json'.freeze
    FORM_MIME    = 'application/x-www-form-urlencoded'.freeze
    TEXT_MIME    = 'text/plain'.freeze
    ACCEPT       = 'Accept'.freeze
    CONTENT_TYPE = 'Content-Type'.freeze

    route do |r|
      r.is do
        if request.headers[CONTENT_TYPE] == JSON_MIME
          params = parse_json_body
        else
          params = request.params
        end

        task = AccessTokens::HandleRequest.run(
          params.merge(current_access_token: current_access_token)
        )

        # Prepare error message
        unless task.success?
          # in mutation you do:
          #   add_error(:http_400, :invalid_request, 'Foo missing')
          # and then:
          #   task.errors.message  returns  { :http_400 => 'Foo missing' }
          #   task.errors.symbolic returns: { :http_400 => :invalid_request }
          # so here we 
          #  ..parse http status from field name
          #  ..get the optional error_description from error message
          #  ..get standard oauth2 error message from mutation's symbolic error
          error_status, error_description = task.errors.message.first
          error_msg = task.errors.symbolic.first.last.to_s

          error_status = error_status.to_s.gsub(/^http_/, '').to_i

          # In case the muatation returns something exotic, the previous to_i
          # will quite certainly return 0
          if error_status == 0
            error_status = 500
            error_msg = 'server_error'
          end
        end

        if request.headers[ACCEPT] == JSON_MIME
          # User wants JSON, so we give JSON, simple enough.
          response.headers[CONTENT_TYPE] = JSON_MIME

          if task.success?
            response.status = 201
            @access_token = task.result
            render('auth/show')
          else
            response.status = error_status
            return { error: error_msg, error_description: error_description }.to_json
          end
        else
          # User no want JSON
          if params['redirect_uri']
            # User wants a redirect, let's give a redirect
            response.status = 302
            if task.success?
              response.headers['Location'] = @access_token.to_query(
                state: params['state'],
                # In implicint grant flow the response is returned in
                # the uri anchor / fragment
                as_fragment: params['response_type'].to_s == 'token',
                uri: params['redirect_uri']
              )
            else
              response.headers['Location'] = @access_token.to_query(
                state: params['state'],
                error: error_msg,
                error_description: error_description,
                uri: params['redirect_uri'],
                as_fragment: params['response_type'].to_s == 'token'
              )
            end
            return nil
          else
            # User doesn't want a redirect, just give some body.
            response.headers[CONTENT_TYPE] = FORM_MIME
            if task.success?
              response.status = 201
              return @access_token.to_query(state: params['state'])
            else
              response.status = error_status
              return URI.encode_www_form(
                [
                  ['error', error_msg],
                  ['error_description', error_description],
                  ['state', params['state']]
                ]
              )
            end
          end
        end
      end
    end
  end
end
