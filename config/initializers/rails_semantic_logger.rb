# Edge Rails compatibility shim for rails_semantic_logger 4.20.0.
#
# The gem patches Action Cable's TaggedLoggerProxy at its pre-Rails-8 location,
# ActionCable::Connection::TaggedLoggerProxy. Edge Rails relocated that class to
# ActionCable::Server::TaggedLoggerProxy, so the gem's
# `require "action_cable/connection/tagged_logger_proxy"` — run from an
# after_initialize hook — raises LoadError and aborts production boot under
# eager_load. The gem only loads on the deployed environments (see Gemfile), so
# this shim is scoped to them too.
#
# Alias the old constant to the relocated class so the gem's patch lands on the
# real proxy, and mark the stale path as already loaded so the require becomes a
# no-op. Remove once rails_semantic_logger targets ActionCable::Server.
if defined?(RailsSemanticLogger) && defined?(ActionCable)
  require "action_cable/server/tagged_logger_proxy"

  module ActionCable
    module Connection
      TaggedLoggerProxy = ActionCable::Server::TaggedLoggerProxy unless defined?(TaggedLoggerProxy)
    end
  end

  $LOADED_FEATURES << "action_cable/connection/tagged_logger_proxy.rb"
end
