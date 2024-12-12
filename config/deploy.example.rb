### lib
require_relative 'secret_provider_local'

### replace deploy with docker:deploy
Rake::Task['deploy'].clear_actions

task :deploy do
  invoke 'docker:deploy'
end


### config

set :log_level, :debug

set :application, 'myapp'

set :repo_url, 'git@github.com:/me/myapp.git'

# docker
set :base_dir, File.expand_path(File.dirname(File.dirname(__FILE__)))
set :local_temp_dir, File.expand_path(File.dirname(File.dirname(__FILE__)), "temp")

secret_provider = SecretProviderLocal.new({dir: '/path/to/secrets'})
set :secret_provider, secret_provider

set :docker_env_vars, {
  'RAILS_MASTER_KEY' => secret_provider.secret_file_contents('production/production.key')
}

# Default value for keep_releases is 5
set :keep_releases, 3


# Add necessary files and directories which can be changed on server.
append :linked_dirs, 'log'

