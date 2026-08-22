require "test_helper"

class DatabaseSchemaSourcesTest < ActiveSupport::TestCase
  # db:prepare creates every configured database and loads that config's own
  # schema dump — db/<name>_schema.rb for anything but the primary. A config
  # with neither a dump nor migrations of its own is created empty and stays
  # that way, so the breakage only surfaces at the first query against it.
  # Production used to route Solid Cache to a separate `cache` database this
  # way, which made a fresh install answer every rate-limited request (sign-in
  # included) with a 500.
  test "every configured database has a schema source" do
    database_configs.each do |db_config|
      assert schema_dump?(db_config) || migrations?(db_config),
        "#{db_config.env_name} database #{db_config.name.inspect} has no schema dump " \
        "(#{schema_dump_path(db_config)}) and no migrations of its own " \
        "(#{migrations_directories(db_config).join(", ")}), so db:prepare would create it empty"
    end
  end

  private

  def database_configs
    ActiveRecord::DatabaseConfigurations.new(Rails.application.config.database_configuration).configs_for
  end

  def schema_dump_path(db_config)
    ActiveRecord::Tasks::DatabaseTasks.schema_dump_path(db_config)
  end

  def schema_dump?(db_config)
    path = schema_dump_path(db_config)
    path.present? && File.exist?(path)
  end

  def migrations_directories(db_config)
    paths = db_config.migrations_paths || ActiveRecord::Migrator.migrations_paths
    Array(paths).map { |path| Rails.root.join(path) }
  end

  def migrations?(db_config)
    migrations_directories(db_config).any? { |dir| Dir.exist?(dir) && Dir.children(dir).any? }
  end
end
