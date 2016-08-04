module V1
  class TokenApi < Roda
    include RequestHelpers

    route do |r|
      r.get do
        validate_access_token
        @auth_provider = AuthProvider.first_or_create
        unless @auth_provider
          halt_request(404, 'Not found') and return
        end
        render('auth_provider/show')
      end

      r.post do
        @auth_provider = AuthProvider.first

        if @auth_provider
          validate_access_token
        end

        ap_params = {
          provider:       request.params['provider'],
          client_id:      request.params['client_id'],
          client_secret:  request.params['client_secret']
        }

        @auth_provider = AuthProvider.first_or_create
        @auth_provider.assign_attributes(ap_params)

        if @auth_provider.save
          response.status = 201
          render('auth_provider/show')
        else
          response.status = 400
          {'error': @auth_provider.errors}
        end
      end
    end
  end
end

