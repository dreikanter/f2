ActiveSupport.on_load(:action_mailer) do
  require_dependency Rails.root.join("app/services/transactional_email_event_recorder").to_s
  register_observer(TransactionalEmailEventRecorder::Observer.new)
end
