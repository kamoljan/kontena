class CreateInitialAdmin < Mongodb::Migration
  def self.up
    User.create_indexes
    if User.count == 0
      admin = User.create(
        email: 'admin',
        name: 'Local administrator'
      )
      admin.roles << Role.master_admin
    end
  end
end
