require './app'

require 'rack/ssl-enforcer'
use Rack::SslEnforcer unless development?

run Sinatra::Application
