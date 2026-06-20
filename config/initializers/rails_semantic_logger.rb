# Edge Rails compatibility shim for rails_semantic_logger 4.20.0.
#
# Edge Rails moved Action Cable's TaggedLoggerProxy from ActionCable::Connection
# to ActionCable::Server, but the gem still does
# `require "action_cable/connection/tagged_logger_proxy"` from an after_initialize
# hook — a LoadError that aborts eager-load boot. Alias the old constant onto the
# new class so the gem's patch still lands, and seed the stale path into
# $LOADED_FEATURES so the require is a no-op. The gem loads only on the deployed
# environments (see Gemfile); remove once it targets ActionCable::Server.
if defined?(RailsSemanticLogger) && defined?(ActionCable)
  require "action_cable/server/tagged_logger_proxy"

  module ActionCable
    module Connection
      TaggedLoggerProxy = ActionCable::Server::TaggedLoggerProxy unless defined?(TaggedLoggerProxy)
    end
  end

  $LOADED_FEATURES << "action_cable/connection/tagged_logger_proxy.rb"
end
