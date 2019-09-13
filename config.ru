require './app'

require 'rack/ssl-enforcer'
use Rack::SslEnforcer

run Sinatra::Application
