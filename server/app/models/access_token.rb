class AccessToken
  include Mongoid::Document
  include Mongoid::Timestamps

  belongs_to :user
  validates_presence_of :scopes, :user

  field :token_type, type: String
  field :token, type: String
  field :refresh_token, type: String
  field :expires_at, type: Time
  field :scopes, type: Array
  field :deleted_at, type: Time, default: nil

  index({ user_id: 1 })
  index({ token: 1 }, { unique: true })
  index({ refresh_token: 1 }, { unique: true, sparse: true })
  index({ expires_at: 1 }, { sparse: true })
  index({ deleted_at: 1 }, { sparse: true })

  class << self
    # Finds an access_token by refresh_token and updates it in place to
    # mark it as used. Otherwise two threads could issue an access token
    # using the same refresh_token at the same time.
    #
    # Returns the marked access token or nil
    #
    # TODO find_and_modify is deprecated in mongoid 5
    #
    # @param [String] refresh_token
    # @return [AccessToken] access_token
    def find_by_refresh_token_and_mark_used(refresh_token)
      AccessToken.where(refresh_token: refresh_token, deleted_at: nil).
                  find_and_modify({ '$set' => { deleted_at: Time.now.utc } })
    end
  end

  def used?
    !deleted_at.nil?
  end

  def expired?
    expires_at && expires_at < Time.now.utc || used?
  end
end
