# Disable HTTP Basic authentication for Mission Control Jobs
# TBD: Enable custom authentication when implementing permission-based access control
MissionControl::Jobs.base_controller_class = "ActionController::Base"
