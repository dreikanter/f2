require "test_helper"
require_relative "../../db/migrate/20260909143000_add_configuration_digest_to_feed_identifications"

class FeedIdentificationConfigurationMigrationTest < ActiveSupport::TestCase
  test "#change should preserve legacy results and leave their configuration unknown" do
    identification = create(:feed_identification, :working)
    candidates = identification.candidates
    migration = AddConfigurationDigestToFeedIdentifications.new

    migration.migrate(:down)
    assert_not FeedIdentification.connection.column_exists?(:feed_identifications, :configuration_digest)
    migration.migrate(:up)
    FeedIdentification.reset_column_information

    assert_equal candidates, identification.reload.candidates
    assert_nil identification.configuration_digest
    assert_not identification.current_configuration?
  ensure
    FeedIdentification.reset_column_information
  end
end
