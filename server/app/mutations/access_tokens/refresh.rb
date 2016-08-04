require "securerandom"

module AccessTokens
  class Refresh < Mutations::Command

    required do
      string :refresh_token
    end

    optional do
      string :scope
    end

    def validate
      @old_token = AccessToken.find_by_refresh_token_and_mark_used(self.refresh_token)
      if @old_token.nil?
        add_error(:http_400, :invalid_request, 'Invalid request')
      end
    end

    def execute
      # RFC allows setting a tighter scope when refreshing
      unless self.scope.nil? || self.scope == ''
        new_scopes = @old_token.scopes & scope.split(',')
      end
      AccessTokens::Create.run(
        user: @old_token.user,
        scopes: new_scopes
      ).result
    end
  end
end

