class Kontena::Cli::LogoutCommand < Clamp::Command
  include Kontena::Cli::Common

  def execute
    config.servers.each { |s| s.token = nil }
    config.accounts.each { |a| a.token = nil }
    config.current_server = nil
    config.current_account = nil
    config.write
  end
end
