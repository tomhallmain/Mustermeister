# frozen_string_literal: true

# Renders a list of tasks as TSV (tab-separated values) for download from a
# project's report page. Uses the stdlib CSV library with a tab separator
# rather than naive string joining, so titles/descriptions that happen to
# contain a literal tab, quote, or newline are still quoted/escaped correctly.
require "csv"

class TaskTsvExportService
  HEADERS = ["Title", "Priority", "Status", "Due Date", "Category", "Description"].freeze

  def self.call(tasks)
    CSV.generate(col_sep: "\t") do |tsv|
      tsv << HEADERS
      tasks.each do |task|
        tsv << [
          task.title,
          task.priority,
          task.status&.name,
          task.due_date&.to_date&.iso8601,
          task.task_category&.name,
          task.description
        ]
      end
    end
  end
end
