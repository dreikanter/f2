Rails.application.configure do
  # Eager load feed processing components
  config.eager_load_paths += %W[
    #{Rails.root}/app/models/loaders
    #{Rails.root}/app/models/processors
    #{Rails.root}/app/models/normalizers
  ]
end
