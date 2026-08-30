require "test_helper"
require "view_component/test_case"

class CredentialDeleteModalComponentTest < ViewComponent::TestCase
  def user
    @user ||= create(:user)
  end

  test "#render should provide the same confirmation UI for every credential type" do
    credentials = [
      create(:access_token, :active, user: user),
      create(:ai_credential, :active, user: user),
      create(:search_credential, :active, user: user)
    ]

    credentials.each do |credential|
      result = render_inline(CredentialDeleteModalComponent.new(credential: credential))

      assert_not_nil result.at_css("##{CredentialDeleteModalComponent.modal_id(credential)}")
      expected_path = Rails.application.routes.url_helpers.public_send(
        "#{credential.model_name.singular}_path",
        credential
      )
      assert_equal expected_path, result.at_css("form")["action"]
      assert_not_nil result.at_css("input[name='_method'][value='delete']")
      assert_includes result.text, credential.display_name
      assert_includes result.text, "Any feeds using it will be automatically disabled."
    end
  end
end
