class Admin::FeedProfilesController < ApplicationController
  before_action :load_feed_profile, only: [:show, :edit, :update, :destroy]

  def index
    authorize FeedProfile
    @feed_profiles = policy_scope(FeedProfile).includes(:user).order(:name)
  end

  def show
    authorize @feed_profile
  end

  def new
    @feed_profile = FeedProfile.new
    authorize @feed_profile
  end

  def edit
    authorize @feed_profile
  end

  def create
    @feed_profile = FeedProfile.new(feed_profile_params)
    @feed_profile.user = Current.user
    authorize @feed_profile

    if @feed_profile.save
      redirect_to admin_feed_profile_path(@feed_profile), notice: "Feed profile was successfully created."
    else
      render :new, status: :unprocessable_content
    end
  end

  def update
    authorize @feed_profile
    @feed_profile.assign_attributes(feed_profile_params)
    @feed_profile.user = Current.user

    if @feed_profile.save
      redirect_to admin_feed_profile_path(@feed_profile), notice: "Feed profile was successfully updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    authorize @feed_profile
    @feed_profile.destroy!
    redirect_to admin_feed_profiles_path, notice: "Feed profile was successfully deleted."
  end

  private

  def load_feed_profile
    @feed_profile = FeedProfile.find(params[:id])
  end

  def feed_profile_params
    params.require(:feed_profile).permit(:name, :loader, :processor, :normalizer)
  end
end
