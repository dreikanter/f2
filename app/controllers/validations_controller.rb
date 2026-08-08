# Polling endpoint behind the validation spinner on an access token's or
# credential's show page. Each poll re-reads the record and answers with its
# re-rendered show content once the asynchronous check has settled.
#
# Subclasses declare their model; the nested param, partial, locals, and target
# element all follow from it.
class ValidationsController < ApplicationController
  class_attribute :validated_class, instance_writer: false

  def show
    record = policy_scope(validated_class).find(params[:"#{param_key}_id"])
    authorize record

    # Stay silent while validation is still in flight so the poller leaves the
    # spinner running instead of redrawing (and restarting) it every cycle.
    return head :no_content if record.pending? || record.validating?

    render turbo_stream: turbo_stream.update(
      "#{param_key.dasherize}-show",
      partial: "#{validated_class.model_name.plural}/show_content",
      locals: { param_key.to_sym => record, feed_id: params[:feed_id] }
    )
  end

  private

  # Doubles as the target element id (dasherized) and the partial's local name.
  def param_key
    validated_class.model_name.param_key
  end
end
