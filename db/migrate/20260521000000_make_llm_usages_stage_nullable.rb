class MakeLlmUsagesStageNullable < ActiveRecord::Migration[8.1]
  def up
    change_column_null :llm_usages, :stage, true
  end

  def down
    change_column_null :llm_usages, :stage, false
  end
end
