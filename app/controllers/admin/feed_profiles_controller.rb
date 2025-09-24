class Admin::FeedProfilesController < ApplicationController
  before_action :require_admin
  before_action :load_feed_profile, only: [:show, :edit, :update, :destroy]

  def index
    @feed_profiles = FeedProfile.includes(:user).order(:name)
  end

  def show
    @feed_profile = FeedProfile.find(params[:id])
    authorize @feed_profile
  end

  def new
    @feed_profile = FeedProfile.new
  end

  def edit
    @feed_profile = FeedProfile.find(params[:id])
    authorize @feed_profile
  end

  def create
    @feed_profile = FeedProfile.new(feed_profile_params)

    if @feed_profile.save
      redirect_to admin_feed_profile_path(@feed_profile), notice: "Feed profile was successfully created."
    else
      render :new, status: :unprocessable_content
    end
  end

  def update
    if @feed_profile.update(feed_profile_params)
      redirect_to admin_feed_profile_path(@feed_profile), notice: "Feed profile was successfully updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @feed_profile.destroy!
    redirect_to admin_feed_profiles_path, notice: "Feed profile was successfully deleted."
  end

  private

  def require_admin
    redirect_to root_path, alert: "Access denied." unless Current.user.permission?("admin")
  end

  def load_feed_profile
    @feed_profile = FeedProfile.find(params[:id])
  end

  def feed_profile_params
    params.require(:feed_profile).permit(:name, :loader, :processor, :normalizer, :user_id)
  end
end
