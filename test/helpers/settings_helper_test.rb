require "test_helper"

class SettingsHelperTest < ActionView::TestCase
  test "#name_hint_for should mention the name when it is set" do
    assert_equal "People you invite will see Alex", name_hint_for(build(:user, name: "Alex"))
  end

  test "#name_hint_for should explain the fallback when the name is blank" do
    assert_equal 'Not set, so people you invite will just see "Somebody"', name_hint_for(build(:user, name: ""))
  end
end
