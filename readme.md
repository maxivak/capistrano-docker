Deploy Rails application with Docker using capistrano

# Install

copy files to your Rails project
* `tasks/deploy.rake`
* `files/docker/Dockerfile`


* replace default `deploy` task with `docker:deploy`

```
# config/deploy.rb

Rake::Task['deploy'].clear_actions

task :deploy do
  invoke 'docker:deploy'
end

```


# Deploy


deploy

```
cap production deploy
# or
cap production docker:deploy
```

This will
* download project source from Git repository
* build a Docker image on the local machine
* upload Docker image to the server
* restore Docker image on server
* stop and remove old Docker containers
* run Docker container on server
* remove old Docker images



Notes
* It doesn't use Docker registry. Docker image is built locally and uploaded to server.



# Configure


options

```

# docker
set :base_dir, File.expand_path(File.dirname(File.dirname(__FILE__)))
set :local_temp_dir, File.expand_path(File.dirname(File.dirname(__FILE__)), "temp")

set :docker_env_vars, {
  #'RAILS_MASTER_KEY' => secret_provider.secret_file_contents('production/production.key')
}

```

## Secrets

use secrets from local storage

* save `config/secret_provider_local.rb`

* `config/deploy.rb`
```
require_relative 'secret_provider_local'

secret_provider = SecretProviderLocal.new({dir: '/path/to/secrets'})
set :secret_provider, secret_provider 

..

# use secret
set :docker_env_vars, {
  'RAILS_MASTER_KEY' => secret_provider.secret_file_contents('production/production.key')
}

```


## Docker container

* use docker network

```
set :docker_container_ip, "10.0.1.2"
set :docker_network, "my_network_name"
```


# TODO

TODO:
* create a systemd service to manage Docker container
* build Docker image to run sidekiq
* install sidekiq in Docker container on worker servers