class SentEmailDetailsComponent < ViewComponent::Base
  def initialize(email:)
    @email = email
  end

  def call
    helpers.render list_group
  end

  private

  attr_reader :email

  def list_group
    ListGroupComponent.new.tap do |list|
      list.with_item(ListGroupComponent::StatItemComponent.new(
        label: "Message ID",
        value: helpers.content_tag(:code, email[:message_id], class: "text-xs break-all")
      ))

      list.with_item(ListGroupComponent::StatItemComponent.new(
        label: "From",
        value: helpers.content_tag(:code, email[:from], class: "text-xs break-words")
      ))

      list.with_item(ListGroupComponent::StatItemComponent.new(
        label: "To",
        value: helpers.content_tag(:code, email[:to], class: "text-xs break-words")
      ))

      list.with_item(ListGroupComponent::StatItemComponent.new(
        label: "Date",
        value: helpers.content_tag(:span, email[:date], class: "text-sm text-slate-700")
      ))
    end
  end
end
