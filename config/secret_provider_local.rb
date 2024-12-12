class SecretProviderLocal
  ###
  # - options: {
  # :dir - base dir
  # }
  def initialize(options)
    @options = options

  end

  def secret_file_contents(filename)
    File.read(File.join(base_dir, filename))
  end


  private
  def base_dir
    @options.fetch(:dir)
  end
end
