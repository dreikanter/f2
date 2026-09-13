require "test_helper"
require_relative "../../db/migrate/20260913220000_simplify_provider_credential_state"

class SimplifyProviderCredentialStateTest < ActiveSupport::TestCase
  test "#change should roll back and reapply the credential columns and indexes" do
    migration = SimplifyProviderCredentialState.new
    connection = ActiveRecord::Base.connection

    migration.migrate(:down)
    [AiCredential, SearchCredential].each do |model|
      assert connection.column_exists?(model.table_name, :state, :integer, default: 0, null: false)
      assert connection.index_exists?(model.table_name, [:user_id, :state])
      assert_not connection.column_exists?(model.table_name, :active)
    end

    migration.migrate(:up)
    [AiCredential, SearchCredential].each do |model|
      model.reset_column_information
      assert_not model.new.active?
      assert connection.column_exists?(model.table_name, :active, :boolean, default: false, null: false)
      assert connection.index_exists?(model.table_name, [:user_id, :active])
      assert_not connection.column_exists?(model.table_name, :state)
    end
  ensure
    AiCredential.reset_column_information
    SearchCredential.reset_column_information
  end
end
