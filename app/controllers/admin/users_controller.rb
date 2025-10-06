class Admin::UsersController < ApplicationController
  include Pagination

  def index
    authorize User
    @users = paginate_scope
  end

  def show
    @user = User.find(params[:id])
    authorize @user
  end

  private

  def pagination_scope
    policy_scope(User).order(created_at: :desc)
  end
end
