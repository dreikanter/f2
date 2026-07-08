class AiCredentialDetailsComponent < ViewComponent::Base
  def initialize(ai_credential:)
    @ai_credential = ai_credential
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
        value: @ai_credential.llm_provider.display_name,
        key: "ai_credential.provider"
      },
      {
        label: "Created",
        value: helpers.datetime_with_duration_tag(@ai_credential.created_at),
        key: "ai_credential.created"
      }
    ]

    if @ai_credential.last_validated_at
      result << {
        label: "Last Used",
        value: helpers.datetime_with_duration_tag(@ai_credential.last_validated_at),
        key: "ai_credential.last_used"
      }
    end

    result
  end
end
