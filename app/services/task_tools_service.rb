# frozen_string_literal: true

# Requester-agnostic set of read-only task query "tools", shared by
# TaskInsightsChatService's internal LLM tool-calling loop and the external
# Api::ToolsController - both dispatch through the same tool bodies here
# rather than duplicating scoping/formatting logic.
class TaskToolsService
  # Upper bound for how many tasks a single list-style tool may return
  # (default 1000). Set TASK_INSIGHTS_MAX_LIST_ITEMS to a lower value in
  # constrained environments.
  MAX_LIST_ITEMS_CAP = 1000
  MAX_LIST_ITEMS = [[ENV.fetch("TASK_INSIGHTS_MAX_LIST_ITEMS", MAX_LIST_ITEMS_CAP.to_s).to_i, 10].max, MAX_LIST_ITEMS_CAP].min

  # Task descriptions can be arbitrarily long (e.g. a pasted log or stack
  # trace) - truncated so a handful of such tasks can't inflate a list
  # response by orders of magnitude. Set TASK_DESCRIPTION_TRUNCATE_LENGTH to
  # adjust.
  DESCRIPTION_TRUNCATE_LENGTH = ENV.fetch("TASK_DESCRIPTION_TRUNCATE_LENGTH", "500").to_i

  TOOL_DEFINITIONS = [
    {
      name: "project_summary",
      description: "Summarize projects and task totals.",
      args: { project_ids: "optional array of project ids" }
    },
    {
      name: "status_breakdown",
      description: "Get task counts by status.",
      args: { project_ids: "optional array of project ids" }
    },
    {
      name: "overdue_tasks",
      description: "List overdue open tasks.",
      args: { project_ids: "optional array of project ids", limit: "optional integer <= #{MAX_LIST_ITEMS}" }
    },
    {
      name: "high_priority_open_tasks",
      description: "List high-priority open tasks.",
      args: { project_ids: "optional array of project ids", limit: "optional integer <= #{MAX_LIST_ITEMS}" }
    },
    {
      name: "open_tasks_by_priorities",
      description: "List open tasks filtered by one or more priorities (e.g. medium and high).",
      args: {
        priorities: "required array of strings from leisure|low|medium|high",
        project_ids: "optional array of project ids",
        limit: "optional integer <= #{MAX_LIST_ITEMS}"
      }
    },
    {
      name: "recent_tasks",
      description: "List recently updated tasks.",
      args: { project_ids: "optional array of project ids", days: "optional integer", limit: "optional integer <= #{MAX_LIST_ITEMS}" }
    },
    {
      name: "search_tasks",
      description: "Search task titles/descriptions via local substring matching.",
      args: { keyword: "required plain substring string (not a natural-language query)", project_ids: "optional array of project ids", limit: "optional integer <= #{MAX_LIST_ITEMS}" }
    }
  ].freeze
  TOOL_NAMES = TOOL_DEFINITIONS.map { |tool| tool[:name] }.freeze

  def initialize(user:, excluded_project_ids: [])
    @user = user
    @excluded_project_ids = normalized_excluded_project_ids(excluded_project_ids)
  end

  def run(tool_name, args = {})
    case tool_name.to_s
    when "project_summary" then project_summary(args)
    when "status_breakdown" then status_breakdown(args)
    when "overdue_tasks" then overdue_tasks(args)
    when "high_priority_open_tasks" then high_priority_open_tasks(args)
    when "open_tasks_by_priorities" then open_tasks_by_priorities(args)
    when "recent_tasks" then recent_tasks(args)
    when "search_tasks" then search_tasks(args)
    else
      { error: "Unknown tool: #{tool_name}" }
    end
  end

  private

  def scoped_tasks(project_ids = nil)
    scope = @user.tasks.not_archived.includes(:project, :status)
    scope = scope.where.not(project_id: @excluded_project_ids) if @excluded_project_ids.present?
    return scope if project_ids.blank?

    scope.where(project_id: normalized_project_ids(project_ids))
  end

  def normalized_project_ids(project_ids)
    ids = Array(project_ids).map(&:to_i).uniq
    allowed = @user.projects.where(id: ids).pluck(:id)
    @excluded_project_ids.present? ? allowed - @excluded_project_ids : allowed
  end

  def normalized_excluded_project_ids(project_ids)
    ids = Array(project_ids).map(&:to_i).uniq
    return [] if ids.empty?

    @user.projects.where(id: ids).pluck(:id).map(&:to_i)
  end

  def normalized_limit(limit)
    [[limit.to_i, 1].max, MAX_LIST_ITEMS].min
  end

  def format_task(task)
    data = {
      id: task.id,
      title: task.title,
      description: task.description&.truncate(DESCRIPTION_TRUNCATE_LENGTH),
      completed: task.completed,
      project: task.project&.title,
      status: task.status&.name,
      priority: task.priority,
      updated_date: task.updated_at&.to_date&.iso8601
    }
    due = task.due_date&.to_date&.iso8601
    data[:due_date] = due if due.present?
    data
  end

  def project_summary(args)
    tasks = scoped_tasks(args["project_ids"])
    grouped = tasks.group(:project_id).count
    projects = @user.projects.where(id: grouped.keys).index_by(&:id)
    grouped.map do |project_id, total|
      open = tasks.where(project_id: project_id, completed: false).count
      {
        project: projects[project_id]&.title,
        total_tasks: total,
        open_tasks: open,
        completion_ratio: total.positive? ? (((total - open).to_f / total) * 100).round(1) : 0.0
      }
    end.sort_by { |row| -row[:total_tasks] }
  end

  def status_breakdown(args)
    scoped_tasks(args["project_ids"]).joins(:status).group("statuses.name").count
  end

  def overdue_tasks(args)
    limit = normalized_limit(args["limit"] || MAX_LIST_ITEMS)
    scope = scoped_tasks(args["project_ids"])
      .where(completed: false)
      .where("due_date < ?", Time.current)
      .order(due_date: :asc)
    list_result(scope, limit: limit)
  end

  def high_priority_open_tasks(args)
    limit = normalized_limit(args["limit"] || MAX_LIST_ITEMS)
    scope = scoped_tasks(args["project_ids"])
      .where(completed: false, priority: "high")
      .order(updated_at: :asc)
    list_result(scope, limit: limit)
  end

  def open_tasks_by_priorities(args)
    allowed = %w[leisure low medium high]
    priorities = Array(args["priorities"]).map(&:to_s).uniq & allowed
    if priorities.blank?
      return {
        error: "priorities must include at least one of #{allowed.join(', ')}",
        items: [],
        returned_count: 0,
        total_matching_count: 0,
        limit: 0
      }
    end

    limit = normalized_limit(args["limit"] || MAX_LIST_ITEMS)
    scope = scoped_tasks(args["project_ids"])
      .where(completed: false, priority: priorities)
      .order(updated_at: :asc)
    grouped_list_result(scope, limit: limit)
  end

  def recent_tasks(args)
    limit = normalized_limit(args["limit"] || MAX_LIST_ITEMS)
    days = [args["days"].to_i, 1].max
    scope = scoped_tasks(args["project_ids"])
      .where("tasks.updated_at >= ?", days.days.ago)
      .order(updated_at: :desc)
    list_result(scope, limit: limit)
  end

  def search_tasks(args)
    keyword = args["keyword"].to_s.strip
    if keyword.blank?
      return {
        error: "keyword is required",
        items: [],
        returned_count: 0,
        total_matching_count: 0,
        limit: 0
      }
    end

    limit = normalized_limit(args["limit"] || MAX_LIST_ITEMS)
    pattern = "%#{keyword.downcase}%"
    scope = scoped_tasks(args["project_ids"])
      .where("LOWER(tasks.title) LIKE :q OR LOWER(tasks.description) LIKE :q", q: pattern)
      .order(updated_at: :desc)
    list_result(scope, limit: limit)
  end

  def list_result(scope, limit:)
    total_matching_count = scope.except(:limit, :offset).count
    items = scope.limit(limit).map { |task| format_task(task) }
    {
      items: items,
      returned_count: items.size,
      total_matching_count: total_matching_count,
      limit: limit
    }
  end

  def grouped_list_result(scope, limit:)
    limited_items = scope.limit(limit).map { |task| format_task(task) }
    grouped = {}
    limited_items.each do |task|
      priority = task[:priority].presence || "unknown"
      status = task[:status].presence || "unknown"
      project = task[:project].presence || "unknown"
      grouped[priority] ||= { statuses: {} }
      grouped[priority][:statuses][status] ||= { projects: {} }
      grouped[priority][:statuses][status][:projects][project] ||= []
      grouped[priority][:statuses][status][:projects][project] << task.except(:priority, :status, :project)
    end

    {
      priorities: grouped,
      returned_count: limited_items.size,
      total_matching_count: scope.except(:limit, :offset).count,
      limit: limit
    }
  end
end
