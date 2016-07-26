require_relative '../../services/auth_service/client'

module V1
  class TokenApi < Roda
    include RequestHelpers
    include OAuth2TokenVerifier

    route do |r|
      r.get do
        validate_access_token
        @access_token = current_access_token
        render('auth/show')
      end

      r.post do
        params = request.params
        puts params.inspect
        if params['grant_type'] == 'refresh_token' && params['refresh_token']
          task = AccessTokens::Refresh.run(params['refresh_token'])
          if task.success?
            @access_token = task.result
            response.status = 201
            render('auth/show')
          else
            halt_request(403, 'Access denied') and return
          end
        elsif params['grant_type'] == 'code' && params['code']
          task = AccessTokens::ExchangeCode.run(params)
          if task.success?
            @access_token = AccessTokens::Create.run(task.result)
            response.status = 201
            render('auth/show')
          else
            halt_request(403, 'Access denied') and return
          end
        else
          halt_request(400, 'Bad request') and return
        end
      end
    end
  end
end
