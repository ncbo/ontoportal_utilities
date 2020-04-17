require 'global'

Global.configure do |config|
  config.backend :filesystem, environment: :default, path: 'config'
end
