module AccessTokens
  class CodeExchange < Mutations::Command

    required do
      string :code
    end

    optional do
      model :user
    end

    def execute
      response = AuthProvider.instance.code_exchange(code)
      unless response
        add_error(:code, :invalid, 'Invalid code or request to auth provider failed')
        return nil
      end

      token = AccessToken.new_from_omniauth(
        response,
        internal: false,
        user: user
      )

      if token.save
        token
      else
        add_error(:token, :invalid, token.errors.inspect)
        nil
      end
    rescue
      ENV["DEBUG"] && puts("Code exchange mutation exception #{$!} #{$!.message}\n#{$!.backtrace}")
      add_error(:request, :failed, 'Request failed')
      return nil
    end
  end
end


