require "securerandom"

module AccessTokens
  class Refresh < Mutations::Command

    required do
      string :refresh_token
    end

    def validate
      @old_token = AccessToken.find_by_refresh_token_and_mark_used(self.refresh_token)
      if @old_token.nil?
        add_error('Refresh token not found or already used')
      end
    end

    def execute
      AccessTokens::Create.run(
        user: @old_token.user,
        scopes: @old_token.scopes
      ).result
    end
  end
end

