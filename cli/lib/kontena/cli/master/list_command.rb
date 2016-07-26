module Kontena::Cli::Master
  class ListCommand < Clamp::Command
    include Kontena::Cli::Common

    def execute
      puts '%-24s %-30s' % ['Name', 'Url']
      current_server = config.current_server
      config.servers.each do |server|
        if server['name'] == current_server
          name = "* #{server['name']}"
        else
          name = server['name']
        end
        puts '%-24s %-30s' % [name, server['url']]
      end
    end
  end
end
