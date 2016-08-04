require 'omniauth'

if ENV["TEST"] 
  OmniAuth.config.logger = nil
else
  OmniAuth.config.logger = Logger.new(STDOUT)
  OmniAuth.config.logger.progname = 'OMNIAUTH'
  OmniAuth.config.logger.level = ENV["DEBUG"] ? Logger::DEBUG : Logger::INFO
end
