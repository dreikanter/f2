require_relative "../../lib/file_delivery"

ActiveSupport.on_load(:action_mailer) do
  ActionMailer::Base.add_delivery_method :file, FileDelivery
end
