class PruneSessionsJob < ApplicationJob
  queue_as :default

  def perform
    Session.expired.in_batches(of: 500).delete_all
  end
end
