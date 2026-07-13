class SearchCredentialDetailsComponent < ViewComponent::Base
  def initialize(search_credential:)
    @search_credential = search_credential
  end

  def call
    render(ListComponent.new) do |list|
      items.each { list.with_item(StatListItemComponent.new(**_1)) }
    end
  end

  private

  def items
    result = [
      {
        label: "Provider",
        value: WebSearchProvider::REGISTRY.fetch(@search_credential.provider),
        key: "search_credential.provider"
      },
      {
        label: "Created",
        value: helpers.datetime_with_duration_tag(@search_credential.created_at),
        key: "search_credential.created"
      }
    ]

    if @search_credential.last_validated_at
      result << {
        label: "Last checked",
        value: helpers.datetime_with_duration_tag(@search_credential.last_validated_at),
        key: "search_credential.last_checked"
      }
    end

    result
  end
end
