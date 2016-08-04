module Users
  # Tries to update an existing user or an invited user if invite_code is 
  # supplied
  #
  # TODO if org membership auto accept is implemented, remove user if
  # that org has disappeared
  class FromUserInfo < Mutations::Command
    optional do
      string :external_id
      string :email
      string :name
      array  :member_of, class: String
      string :invite_code
    end

    def validate
      unless self.external_id || self.email
        add_error(:id, :missing, 'Either external_id or email required')
      end
    end

    def execute
      user = User.or(
       { external_id: self.external_id },
       { email: self.email }
      ).first

      unless user
        if self.invite_code
          user = User.where(invite_code: self.invite_code).first
          if user
            user.invite_code = nil
          else
            add_error(:invite, :invalid, 'Invitation not found')
            return nil
          end
        else
          add_error(:error, :server_error, 'Unable to associate user')
          return nil
        end
      end

      new_roles = user.roles if user

      user.external_id = self.external_id if self.external_id
      user.email       = self.email       if self.email
      user.member_of   = self.member_of || []
      user.roles       = new_roles

      if user.save
        user.roles = new_roles
        user
      else
        add_error(:user, :invalid, 'User validation failed')
        nil
      end
    end
  end
end
