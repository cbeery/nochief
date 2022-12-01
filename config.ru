require './app'

require 'rack/ssl-enforcer'
use Rack::SslEnforcer unless development?

require 'sass/plugin/rack'
Sass::Plugin.options[:style] = :compressed
use Sass::Plugin::Rack

run Sinatra::Application
