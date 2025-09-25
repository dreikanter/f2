class MakeCronExpressionNullable < ActiveRecord::Migration[8.1]
  def change
    change_column_null :feeds, :cron_expression, true
  end
end
