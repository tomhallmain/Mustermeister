class ConvertRecurringTaskTemplateIntervalToDecimal < ActiveRecord::Migration[8.0]
  def up
    safety_assured do
      change_column :recurring_task_templates, :interval, :decimal, precision: 5, scale: 1, default: "1.0", null: false

      # Old "semimonthly" schedules become the closest equivalent under the new
      # model: twice a month, via base_unit "month" + interval 0.5, computed
      # from the midpoint of each month rather than two independently
      # configured days.
      execute <<~SQL.squish
        UPDATE recurring_task_templates
        SET base_unit = 'month', interval = 0.5
        WHERE base_unit = 'semimonthly'
      SQL

      remove_column :recurring_task_templates, :semimonthly_first_day
      remove_column :recurring_task_templates, :semimonthly_second_day
    end
  end

  def down
    safety_assured do
      add_column :recurring_task_templates, :semimonthly_first_day, :integer
      add_column :recurring_task_templates, :semimonthly_second_day, :integer
      change_column :recurring_task_templates, :interval, :integer, default: 1, null: false
    end
  end
end
