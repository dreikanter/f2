require "test_helper"

class FeedsControllerSortableTest < ActiveSupport::TestCase
  def controller
    @controller ||= FeedsController.new
  end

  test "sortable_fields configuration is well formed" do
    fields = controller.send(:sortable_fields)

    assert_kind_of Hash, fields
    assert fields.keys.any?, "Expected sortable_fields to contain entries"

    fields.each do |field, config|
      assert field.present?, "sortable field key must be present"
      assert_kind_of Hash, config
      assert config.key?(:title), "sortable field #{field} must define :title"
      assert config.key?(:order_by), "sortable field #{field} must define :order_by"
      assert_includes [:asc, :desc, "asc", "desc"], config.fetch(:direction, :desc), "sortable field #{field} has invalid :direction"
    end
  end
end
