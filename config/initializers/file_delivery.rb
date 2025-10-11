require_relative "../../lib/file_delivery"

ActionMailer::Base.add_delivery_method :file, FileDelivery
