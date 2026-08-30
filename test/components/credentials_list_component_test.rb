require "test_helper"
require "view_component/test_case"

class CredentialsListComponentTest < ViewComponent::TestCase
  def user
    @user ||= create(:user)
  end

  test "#render should use the shared row for every credential type" do
    credentials = [
      create(:access_token, :active, user: user),
      create(:ai_credential, :active, user: user),
      create(:search_credential, :active, user: user)
    ]

    result = render_inline(CredentialsListComponent.new(credentials: credentials))

    credentials.each do |credential|
      assert_not_nil result.at_css("[data-key='#{credential.model_name.param_key}.#{credential.id}']")
      assert_not_nil result.at_css("##{CredentialDeleteModalComponent.modal_id(credential)}")
    end
  end

  test "#render should render nothing for an empty collection" do
    result = render_inline(CredentialsListComponent.new(credentials: []))

    assert_empty result.css("div")
  end
end
