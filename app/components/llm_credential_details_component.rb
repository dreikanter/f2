class LlmCredentialDetailsComponent < ViewComponent::Base
  def initialize(llm_credential:)
    @llm_credential = llm_credential
  end

  def call
    render(ListComponent.new) do |list|
      items.each { list.with_item(ListComponent::StatItemComponent.new(**_1)) }
    end
  end

  private

  def items
    result = [
      {
        label: "Provider",
        value: LlmProvider.find(@llm_credential.provider).display_name,
        key: "llm_credential.provider"
      },
      {
        label: "Created",
        value: helpers.datetime_with_duration_tag(@llm_credential.created_at),
        key: "llm_credential.created"
      }
    ]

    if @llm_credential.last_validated_at
      result << {
        label: "Last Used",
        value: helpers.datetime_with_duration_tag(@llm_credential.last_validated_at),
        key: "llm_credential.last_used"
      }
    end

    result
  end
end
