require "test_helper"

# The scaffolded database.yml gave production and staging their own `cache` and
# `queue` databases pointing at migrations paths that were never created, so
# db:prepare created them empty. Solid Cache connected to that empty database
# and every rate-limited request — sign-in among them — died on a missing
# solid_cache_entries table. The solid_* tables live in the primary schema.
class DatabaseConfigTest < ActiveSupport::TestCase
  DEPLOYED_ENVIRONMENTS = %w[production staging].freeze

  test "every deployed database has a schema the deploy can load" do
    DEPLOYED_ENVIRONMENTS.each do |env|
      configs_for(env).each do |config|
        assert schema_source?(config),
          "#{env}/#{config.name} has no schema dump and no migrations, so db:prepare would create it empty"
      end
    end
  end

  test "solid cache uses a database whose schema defines solid_cache_entries" do
    DEPLOYED_ENVIRONMENTS.each do |env|
      name = Rails.application.config_for(:cache, env: env)[:database].presence || "primary"
      config = configs_for(env).find { |candidate| candidate.name == name.to_s }

      assert config, "#{env} points Solid Cache at a #{name} database that database.yml doesn't declare"
      assert_includes schema_tables(config), "solid_cache_entries",
        "#{env} points Solid Cache at the #{name} database, whose schema has no solid_cache_entries table"
    end
  end

  private

  def configs_for(env)
    ActiveRecord::Base.configurations.configs_for(env_name: env)
  end

  def schema_source?(config)
    return true if schema_dump(config)

    Array(config.migrations_paths).any? { |path| Dir.glob(Rails.root.join(path, "*.rb")).any? }
  end

  def schema_dump(config)
    path = ActiveRecord::Tasks::DatabaseTasks.schema_dump_path(config)
    path if path && File.exist?(path)
  end

  def schema_tables(config)
    dump = schema_dump(config)
    return [] unless dump

    File.read(dump).scan(/create_table "([^"]+)"/).flatten
  end
end
