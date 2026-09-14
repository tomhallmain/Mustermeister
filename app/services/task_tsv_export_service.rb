# frozen_string_literal: true

# Renders a list of tasks as TSV (tab-separated values) for download from a
# project's report page. Uses the stdlib CSV library with a tab separator
# rather than naive string joining, so titles/descriptions that happen to
# contain a literal tab, quote, or newline are still quoted/escaped correctly.
require "csv"

class TaskTsvExportService
  # Ordered identity, then classification, then dates, with the one long free
  # text field last so it never pushes the rest off the edge of a spreadsheet.
  # Header names stay untranslated: UserDataService::TSV_IMPORT_COLUMNS matches
  # incoming columns against these literal names, so a localized header would
  # stop resolving. Import matches by name rather than position, so this order
  # is a presentation choice and nothing depends on it.
  HEADERS = ["Title", "Status", "Priority", "Category",
             "Due Date", "Created", "Updated", "Description"].freeze

  def self.call(tasks)
    CSV.generate(col_sep: "\t") do |tsv|
      tsv << HEADERS
      tasks.each do |task|
        tsv << [
          task.title,
          task.status&.name,
          task.priority,
          task.task_category&.name,
          task.due_date&.to_date&.iso8601,
          task.created_at&.to_date&.iso8601,
          task.updated_at&.to_date&.iso8601,
          task.description
        ]
      end
    end
  end
end
