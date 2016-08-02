require_relative 'registry/create_command'
require_relative 'registry/remove_command'

class Kontena::Cli::RegistryCommand < Clamp::Command

  subcommand "create", "Create Docker image registry service", Kontena::Cli::Registry::CreateCommand
  subcommand ["remove","rm"], "Remove Docker image registry service", Kontena::Cli::Registry::RemoveCommand

  def execute
  end
end
