# frozen_string_literal: true

# Write-back tools for the external scheduling integration: the narrow set of
# fields a scheduler sets after deciding when work happens. Creation and
# deletion are absent on purpose - widening this surface later is safe,
# withdrawing it once another app depends on it is not.
#
# Separate from TaskToolsService because that class feeds the Task Insights
# LLM loop with task titles and descriptions, content a user can be talked
# into pasting. A write tool reachable from there would turn prompt injection
# into unauthorized data modification, so only Api::ToolsController#create
# dispatches here.
class TaskWriteToolsService
  TOOL_DEFINITIONS = [
    {
      name: "set_scheduled_at",
      description: "Record when a scheduler has slotted a task in. Independent of the due date, which is a deadline rather than a plan.",
      args: {
        task_id: "required integer",
        scheduled_at: "required ISO8601 datetime; pass an empty string to clear the slot"
      }
    },
    {
      name: "set_status",
      description: "Move a task to another status by name, within its own project.",
      args: {
        task_id: "required integer",
        status_name: "required name of a status that exists in the task's project"
      }
    }
  ].freeze
  TOOL_NAMES = TOOL_DEFINITIONS.map { |tool| tool[:name] }.freeze

  def initialize(user:, excluded_project_ids: [])
    @user = user
    @excluded_project_ids = normalized_excluded_project_ids(excluded_project_ids)
  end

  def run(tool_name, args = {})
    case tool_name.to_s
    when "set_scheduled_at" then set_scheduled_at(args)
    when "set_status" then set_status(args)
    else
      { error: "Unknown tool: #{tool_name}" }
    end
  end

  private

  # The per-user project exclusion applies to writes exactly as it does to
  # reads: a project held back from the integration must not be modifiable
  # through it either.
  def writable_tasks
    scope = @user.accessible_tasks.not_archived
    return scope if @excluded_project_ids.blank?

    scope.where.not(project_id: @excluded_project_ids)
  end

  def normalized_excluded_project_ids(project_ids)
    ids = Array(project_ids).map(&:to_i).uniq
    return [] if ids.empty?

    @user.accessible_projects.where(id: ids).pluck(:id).map(&:to_i)
  end

  # A task outside the caller's scope is reported as simply not found, so the
  # API never confirms that some other user's task id exists.
  def find_task(task_id)
    id = task_id.to_i
    return nil if id.zero?

    writable_tasks.find_by(id: id)
  end

  def set_scheduled_at(args)
    task = find_task(args["task_id"])
    return { error: "Task not found" } unless task
    return { error: "scheduled_at is required (pass an empty string to clear it)" } unless args.key?("scheduled_at")

    raw = args["scheduled_at"].to_s.strip
    if raw.empty?
      task.scheduled_at = nil
    else
      parsed = parse_time(raw)
      return { error: "scheduled_at must be an ISO8601 datetime or an empty string" } if parsed.nil?

      task.scheduled_at = parsed
    end

    persist(task)
  end

  def set_status(args)
    task = find_task(args["task_id"])
    return { error: "Task not found" } unless task

    name = args["status_name"].to_s.strip
    return { error: "status_name is required" } if name.empty?

    # Task#status_name= resolves the name within the task's own project and
    # leaves status nil when nothing matches, which is how an unknown name is
    # detected here rather than by listing the project's statuses first.
    task.status_name = name
    return { error: "No status named #{name.inspect} in this task's project" } if task.status.nil?

    persist(task)
  end

  # Tagged so external scheduling writes are distinguishable from a person's
  # own edits in the task's version history, matching the existing 'merged'
  # and 'transfer_ownership' convention.
  def persist(task)
    task.paper_trail_event = 'api_write_back'
    task.save!
    { task: TaskToolsService.format_task(task) }
  rescue ActiveRecord::RecordInvalid => e
    { error: "Could not update task: #{e.record.errors.full_messages.to_sentence}" }
  end

  # Strict ISO8601 rather than Time.zone.parse: that parser is lenient enough
  # to pull a weekday out of prose like "next tuesday-ish" and return a real
  # timestamp for it, which would store a slot the caller never asked for. A
  # string carrying no offset is read as being in the application's zone.
  # KeyError covers an ISO8601 fragment carrying no date at all, such as a
  # bare "09:00:00", which reaches the point of building a Time without a year.
  def parse_time(value)
    Time.zone.iso8601(value)
  rescue ArgumentError, KeyError
    nil
  end
end
