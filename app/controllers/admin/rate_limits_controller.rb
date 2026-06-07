class Admin::RateLimitsController < ApplicationController
  def show
    authorize :access, :dev?
    @groups = RateLimit.snapshot.group_by(&:policy).transform_values { |rows| rows.group_by(&:subject) }
  end
end
