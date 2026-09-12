# add_delivery_method keeps the class object, and FileDelivery is reloadable,
# so register it on every reload. Pinning the one from boot would leave a code
# change in lib/file_delivery.rb without effect until a restart.
Rails.application.config.to_prepare do
  ActionMailer::Base.add_delivery_method :file, FileDelivery
end
