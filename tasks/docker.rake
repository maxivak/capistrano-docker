namespace :docker do
  task :init_new_release do
    # release_id
    now = Time.now
    release_id = now.strftime("%Y%m%d%H%M%S")

    set :release_id, release_id
  end

  task :prepare do
    release_id = fetch(:release_id)

    set :docker_image_name, "apps/#{fetch(:application)}"
    set :docker_image_fullname, "#{fetch(:docker_image_name)}:#{release_id}"

    set :docker_container_name, "app-#{fetch(:application)}"
    set :docker_container_fullname, "#{fetch(:docker_container_name)}-#{release_id}"

    set :local_release_path, File.join(fetch(:local_temp_dir), "releases/#{release_id}").to_s

    # init server
    on roles(:app), in: :sequence do
      execute "mkdir -p /data/apps/#{fetch(:application)}"
      execute "mkdir -p /data/apps/#{fetch(:application)}/shared"
      execute "mkdir -p /data/apps/#{fetch(:application)}/repo"
      execute "mkdir -p /data/apps/#{fetch(:application)}/temp"
    end
  end

  task :deploy do
    invoke 'docker:init_new_release'
    invoke 'docker:prepare'

    invoke "docker:release:print_revision"

    # git repo
    invoke "docker:git:update_repo_locally"

    # build image
    invoke "docker:build:build_locally"

    # deliver docker image to server
    invoke "docker:build:deliver"

    # stop current container
    invoke "docker:container:stop_old"

    # run docker container
    invoke "docker:container:create_systemd_service"
    invoke "docker:container:run"

    # clean up
    # remove old containers
    invoke "docker:container:remove_old"
    # remove old docker images
    invoke "docker:image:clean"
    # remove old releases locally /temp/releases
    invoke "docker:release:remove_old"
  end

  task :deploy_code do
    # TODO: not finished. 2024-dec
    raise 'TODO'

    invoke 'docker:init_new_release'
    invoke 'docker:prepare'

    invoke "docker:release:print_revision"

    # git repo
    invoke "docker:git:update_repo_locally"

    # upload code
    invoke "docker:code:upload"
    invoke "docker:code:update"

    #
    invoke "docker:code:assets:precompile"

    # restart docker container
    invoke "docker:container:restart"
  end

  namespace :release do
    task :print_revision do
      # revision
      #revision_id = `git rev-parse HEAD`.strip
      revision_id = `git rev-list --max-count=1 #{fetch(:branch)}`.strip

      puts "revision: #{revision_id}"
    end

    task :remove_old do
      sh "cd #{fetch(:local_temp_dir)}/releases && rm -rf *"
    end

  end

  namespace :git do
    task :update_repo_locally do
      git_repo_url = fetch(:repo_url)
      local_release_path = fetch(:local_release_path)

      # git clone locally
      # temp/repo
      temp_repo_path = File.join(fetch(:local_temp_dir), "repo")
      sh "mkdir -p #{temp_repo_path}"

      repo_mirror_exists = ` [ -f #{temp_repo_path.to_s}/HEAD ] && echo "1"`.strip == '1'
      if !repo_mirror_exists
        sh "git clone --mirror #{git_repo_url} #{temp_repo_path.to_s}"
        sh "cd #{temp_repo_path.to_s} && git remote set-url origin #{git_repo_url}"
      end

      sh "cd #{temp_repo_path.to_s} && git remote update --prune"
      sh "cd #{temp_repo_path.to_s} && git fetch origin #{fetch(:branch)}"

      sh "mkdir -p #{local_release_path}"

      sh "cd #{temp_repo_path.to_s} && git archive #{fetch(:branch)} | /usr/bin/env tar -x -f - -C #{local_release_path.to_s}"
    end

  end

  namespace :build do

    task :build_locally do
      local_release_path = fetch(:local_release_path)

      files_dir_path = File.join(fetch(:base_dir), "files")

      sh "cp #{files_dir_path}/docker/Dockerfile #{local_release_path.to_s}/. "

      cmd = ["docker build"]
      cmd << %Q(--label service="#{fetch(:docker_image_name)}")
      cmd << "-t #{fetch(:docker_image_fullname)}"
      cmd << " . "

      cmd_build = cmd.join(" ")

      sh "cd #{local_release_path.to_s} && #{cmd_build}"

    end

    task :deliver do
      release_id = fetch(:release_id)
      local_image_tgz_filename = File.join(fetch(:local_temp_dir), "image-#{release_id}.tar.gz").to_s

      cmd = %Q(docker save #{fetch(:docker_image_fullname)} | gzip -c > #{local_image_tgz_filename})
      sh(cmd)

      image_tgz_filename = "/data/apps/#{fetch(:application)}/image-#{release_id}.tar.gz"

      # upload
      on roles(:app), in: :sequence do
        upload! local_image_tgz_filename, image_tgz_filename
      end

      # load docker image
      cmd = %Q(docker load < #{image_tgz_filename})
      on roles(:app), in: :sequence do
        execute cmd
      end
    end
  end

  namespace :image do
    task :clean do
      retain = fetch(:keep_releases)

      service_filter = "--filter label=service=#{fetch(:docker_image_name)}"

      pipe = [
        %Q(docker images --format "{{.Tag}}" #{service_filter}),
        'sort -r',
        "tail -n +#{retain + 1}",
        "while read tag; do docker rmi #{fetch(:docker_image_name)}:$tag; done"
      ]

      cmd = pipe.join(" | ")

      on roles(:app), in: :sequence do
        execute :sh, cmd
      end

      # on roles(:app) do
      #     execute 'docker rmi -f $(docker images -f "dangling=true" -q)'
      #   end
    end

  end

  namespace :container do
    task :create_systemd_service do
      # TODO: finish

      # Run Docker container as a service with systemd

      container_name = "#{fetch(:docker_container_name)}"
      service_name = "docker.#{container_name}.service"
      systemd_service_filename = %Q(/etc/systemd/system/#{service_name})

      content = <<S
                                                                                                       ```
[Unit]
Description=My container
After=docker.service
Requires=docker.service

[Service]
TimeoutStartSec=0
Restart=always
ExecStartPre=-/usr/bin/docker exec %n stop 
ExecStartPre=-/usr/bin/docker rm %n
#ExecStartPre=/usr/bin/docker pull #{fetch(:docker_image_fullname)}
ExecStart=/usr/bin/docker run --rm --name %n #{fetch(:docker_image_fullname)}

[Install]
WantedBy=default.target
S



      on roles(:web) do

        #sudo systemctl enable docker.myservice
      end

      on roles(:worker) do

      end
    end

    task :run do
      # create docker container
      # label docker container with service=xx
      # network, volumes, env vars, master key

      # env vars
      env_vars = fetch(:docker_env_vars) || {}
      env_vars['RAILS_ENV'] = fetch(:rails_env)
      s_env_vars = env_vars.keys.map{|k| "--env #{k}=#{env_vars[k]}"}.join(" ")

      # volumes. follow :linked_dirs
      linked_dirs = fetch(:linked_dirs)

      on roles(:app), in: :sequence do
        linked_dirs.each do |dir|
          execute "mkdir -p /data/apps/#{fetch(:application)}/shared/#{dir.to_s}"
        end
      end

      volumes_data = linked_dirs.map do |dir|
        dir_path = "/data/apps/#{fetch(:application)}/shared/#{dir.to_s}"
        app_dir_path = "/rails/#{dir.to_s}"
        [dir_path, app_dir_path]
      end
      s_volumes = volumes_data.map{|item| "--volume #{item[0]}:#{item[1]}"}.join(" ")

      on roles(:app), in: :sequence do
        execute %Q(docker rm -f #{fetch(:docker_container_fullname)})

        cmd = %Q(docker run -d --name=#{fetch(:docker_container_fullname)} --label="#{fetch(:docker_image_name)}" --net=#{fetch(:docker_network)} --ip #{fetch(:docker_container_ip)} #{s_volumes} #{s_env_vars} #{fetch(:docker_image_fullname)})

        puts cmd
        execute cmd
      end
    end

    task :stop_old do
      service_filter = "--filter label=service=#{fetch(:docker_image_name)}"

      pipe = [
        %Q(docker ps -q -a #{service_filter}),
        "while read container_id; do docker stop $container_id; done"
      ]

      cmd = pipe.join(" | ")

      on roles(:app), in: :sequence do
        execute cmd
      end
    end

    task :remove_old do
      retain = fetch(:keep_releases)

      service_filter = "--filter label=service=#{fetch(:docker_image_name)}"

      pipe = [
        %Q(docker ps -a --format '{{.Names}}' #{service_filter}),
        'sort -r',
        "tail -n +#{retain + 1}",
        "while read container_id; do docker rm $container_id; done"
      ]

      cmd = pipe.join(" | ")

      on roles(:app), in: :sequence do
        execute cmd
      end
    end

  end

end
