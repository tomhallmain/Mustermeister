class ExpandRecurringTaskTemplateFrequencyOptions < ActiveRecord::Migration[8.0]
  def up
    safety_assured do
      rename_column :recurring_task_templates, :frequency, :base_unit
    end

    add_column :recurring_task_templates, :interval, :integer, default: 1, null: false
    add_column :recurring_task_templates, :semimonthly_first_day, :integer
    add_column :recurring_task_templates, :semimonthly_second_day, :integer

    safety_assured do
      execute <<~SQL.squish
        UPDATE recurring_task_templates
        SET base_unit = CASE base_unit
          WHEN 'daily' THEN 'day'
          WHEN 'weekly' THEN 'week'
          WHEN 'monthly' THEN 'month'
          WHEN 'yearly' THEN 'year'
          ELSE base_unit
        END
      SQL
    end
  end

  def down
    safety_assured do
      execute <<~SQL.squish
        UPDATE recurring_task_templates
        SET base_unit = CASE base_unit
          WHEN 'day' THEN 'daily'
          WHEN 'week' THEN 'weekly'
          WHEN 'month' THEN 'monthly'
          WHEN 'year' THEN 'yearly'
          ELSE base_unit
        END
      SQL
    end

    remove_column :recurring_task_templates, :semimonthly_second_day
    remove_column :recurring_task_templates, :semimonthly_first_day
    remove_column :recurring_task_templates, :interval

    safety_assured do
      rename_column :recurring_task_templates, :base_unit, :frequency
    end
  end
end
