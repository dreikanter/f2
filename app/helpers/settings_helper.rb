module SettingsHelper
  def name_hint_for(user)
    if user.name.present?
      "People you invite will see #{user.name}"
    else
      'Not set, so people you invite will just see "Somebody"'
    end
  end
end
