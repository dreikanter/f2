require "test_helper"
require_relative "../../db/migrate/20260913220000_simplify_provider_credential_state"

class SimplifyProviderCredentialStateTest < ActiveSupport::TestCase
  test "#up and #down should convert all credential states and retire only unfinished credential work" do
    connection = ActiveRecord::Base.connection
    original_path = connection.schema_search_path
    schema = "credential_migration_#{SecureRandom.hex(8)}"
    connection.execute("CREATE SCHEMA #{schema}")
    connection.schema_search_path = schema

    [:ai_credentials, :search_credentials].each do |table|
      connection.create_table(table) do |t|
        t.integer :user_id
        t.integer :state, null: false, default: 0
      end
      connection.add_index table, [:user_id, :state]
      connection.execute("INSERT INTO #{table} (state) VALUES (0), (1), (2), (3)")
    end
    connection.create_table(:operation_runs) do |t|
      t.string :subject_type
      t.integer :kind
      t.integer :status
      t.datetime :finished_at
      t.timestamps null: true
    end
    connection.execute <<~SQL
      INSERT INTO operation_runs (subject_type, kind, status) VALUES
        ('AiCredential', 0, 0), ('AiCredential', 2, 1),
        ('SearchCredential', 0, 1), ('SearchCredential', 2, 0),
        ('AiCredential', 0, 2), ('SearchCredential', 0, 3),
        ('AiCredential', 0, 4), ('SearchCredential', 0, 5),
        ('AccessToken', 0, 1), ('AiCredential', 1, 1)
    SQL

    migrate(:up)

    [:ai_credentials, :search_credentials].each do |table|
      assert_equal [false, false, true, false], connection.select_values("SELECT active FROM #{table} ORDER BY id")
      assert_not connection.column_exists?(table, :state)
      column = connection.columns(table).find { _1.name == "active" }
      assert_not column.null
      assert_equal "false", column.default
      assert connection.index_exists?(table, [:user_id, :active])
    end
    assert_equal [5, 5, 5, 5, 2, 3, 4, 5, 1, 1], connection.select_values("SELECT status FROM operation_runs ORDER BY id")
    assert_equal 4, connection.select_value("SELECT COUNT(*) FROM operation_runs WHERE finished_at IS NOT NULL")

    migrate(:down)

    [:ai_credentials, :search_credentials].each do |table|
      assert_equal [3, 3, 2, 3], connection.select_values("SELECT state FROM #{table} ORDER BY id")
      assert_not connection.column_exists?(table, :active)
      assert connection.index_exists?(table, [:user_id, :state])
    end

    migrate(:up)
    assert_equal [false, false, true, false], connection.select_values("SELECT active FROM search_credentials ORDER BY id")
  ensure
    connection.schema_search_path = original_path
    connection.execute("DROP SCHEMA IF EXISTS #{schema} CASCADE")
  end

  private

  def migrate(direction)
    ActiveRecord::Migration.suppress_messages do
      SimplifyProviderCredentialState.new.migrate(direction)
    end
  end
end
