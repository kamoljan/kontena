require 'omniauth'
require 'omniauth-github'

class AuthProvider
  module Github
    GITHUB_ACCEPT = { 'Accept' => 'application/vnd.github.v3' }.freeze

    def strategy
      @strategy ||= OmniAuth::Strategies::GitHub.new(nil, client_id, client_secret)
    end

    def provider_scope
      'user:email,read:org'
    end

    def user_info(token)
      basic = user_basic_info(token)
      return nil unless basic
      {
        external_id: basic['id'],
        email:       basic['email'],
        name:        basic['name'],
        member_of:   user_orgs(token)
      }
    rescue
      nil
    end

    def user_basic_info(token)
      token.get('user', headers: GITHUB_ACCEPT).parsed
    rescue
      nil
    end

    def user_orgs(token)
      token.get('user/orgs', headers: GITHUB_ACCEPT).parsed.map { |org| org['login'] }
    rescue
      []
    end
  end
end
