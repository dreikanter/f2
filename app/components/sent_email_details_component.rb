class SentEmailDetailsComponent < ViewComponent::Base
  def initialize(email:)
    @email = email
  end

  def call
    render(ListComponent.new) do |list|
      list.with_item(ListComponent::StatItemComponent.new(
        label: "Message ID",
        value: helpers.content_tag(:code, email[:message_id], class: "break-all")
      ))

      list.with_item(ListComponent::StatItemComponent.new(
        label: "From",
        value: helpers.content_tag(:code, email[:from], class: "break-words")
      ))

      list.with_item(ListComponent::StatItemComponent.new(
        label: "To",
        value: helpers.content_tag(:code, email[:to], class: "break-words")
      ))

      list.with_item(ListComponent::StatItemComponent.new(
        label: "Date",
        value: helpers.datetime_with_duration_tag(email[:date])
      ))
    end
  end

  private

  attr_reader :email
end
