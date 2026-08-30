class CredentialsListComponent < ViewComponent::Base
  def initialize(credentials:)
    @credentials = credentials
  end

  def call
    safe_join([list, modals])
  end

  private

  attr_reader :credentials

  def list
    render(ListComponent.new) do |list|
      credentials.each { |credential| list.with_item(CredentialListItemComponent.new(credential: credential)) }
    end
  end

  def modals
    safe_join(credentials.map { |credential| render(CredentialDeleteModalComponent.new(credential: credential)) })
  end
end
