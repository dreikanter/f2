class ChangelogsController < ApplicationController
  def show
    @sections = Changelog.load.sections
  end
end
