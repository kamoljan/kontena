require 'bcrypt'

# Table for storing temporary random state strings
#
# A matching state must be found when receiving authorization
# callbacks to prevent fake authentication.
#
# The user relation is optional.
#
# You can store extra redirect_uri if you need to redirect back to for
# example CLI after receiving the callback.
#
# The original scope from auth request can also be
# stored here.
class AuthorizationRequest
  include Mongoid::Document
  include Mongoid::Timestamps

  belongs_to :user

  field :state, type: String
  field :redirect_uri, type: String
  field :scope, type: String
  field :deleted_at, type: Time, default: nil

  index({ state: 1 })
  index({ created_at: 1 })
  index({ deleted_at: 1 }, { sparse: true })

  def state=(state)
    unless state.start_with?('$2a')
      super(AuthorizationRequest.hash_state(state))
    else
      super(state)
    end
  end

  set_callback :save, :after do |doc|
    AuthorizationRequest.clean_up
  end

  class << self
    def find_and_invalidate(state)
      ar = AuthorizationRequest.where(state: hash_state(state)).find_and_modify(
        { '$set' => { deleted_at: Time.now.utc } }
      )
      if ar
        ar.destroy
        ar
      else
        nil
      end
    end

    # Clean up auth requests older than 1 hour.
    def clean_up
      AuthorizationRequest.where(:created_at.lte => Time.now.utc - 3600).delete
    end

    def hash_state(state)
      AuthProvider.encrypt(state)
    end
  end
end
