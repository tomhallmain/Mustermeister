# frozen_string_literal: true

# Aggregates task statistics across a set of projects for reporting and analysis.
# All counts exclude archived tasks.
class ReportStatsService
  Result = Struct.new(
    :summary,
    :projects_summary,
    :projects_breakdown,
    :project_ids,
    keyword_init: true
  )

  ProjectsSummary = Struct.new(
    :total_projects,
    :complete_projects_count,
    :incomplete_projects_count,
    :project_completion_ratio,
    keyword_init: true
  )

  Summary = Struct.new(
    :total_tasks,
    :completed_count,
    :incomplete_count,
    :completion_ratio,
    :status_breakdown,
    keyword_init: true
  )

  ProjectBreakdown = Struct.new(
    :project,
    :total_tasks,
    :completed_count,
    :incomplete_count,
    :completion_ratio,
    :status_breakdown,
    keyword_init: true
  )

  # Canonical status order for reports (matches Status.default_statuses / kanban).
  # Returns array of [status_name, count] with known statuses first, then custom alphabetically.
  def self.sorted_status_breakdown(status_breakdown_hash)
    return [] if status_breakdown_hash.blank?
    order = Status.default_statuses.values
    status_breakdown_hash.sort_by do |name, _count|
      idx = order.index(name)
      [idx ? idx : Float::INFINITY, name.to_s]
    end
  end

  def self.call(projects_scope, project_ids: nil)
    new(projects_scope, project_ids: project_ids).call
  end

  def initialize(projects_scope, project_ids: nil)
    @projects_scope = projects_scope
    @project_ids = project_ids
  end

  def call
    projects = resolve_projects
    project_ids = projects.pluck(:id)

    tasks_scope = Task.not_archived.where(project_id: project_ids)
    summary = build_summary(tasks_scope)
    projects_breakdown = projects.map { |p| build_project_breakdown(p) }
    projects_summary = build_projects_summary(projects_breakdown)

    Result.new(
      summary: summary,
      projects_summary: projects_summary,
      projects_breakdown: projects_breakdown,
      project_ids: project_ids
    )
  end

  private

  def resolve_projects
    if @project_ids.present?
      @projects_scope.where(id: @project_ids)
    else
      @projects_scope
    end
  end

  def build_projects_summary(projects_breakdown)
    total = projects_breakdown.size
    complete = projects_breakdown.count { |pb| pb.completion_ratio == 100.0 && pb.total_tasks.positive? }
    incomplete = total - complete
    ratio = total.positive? ? (complete.to_f / total * 100).round(1) : 0
    ProjectsSummary.new(
      total_projects: total,
      complete_projects_count: complete,
      incomplete_projects_count: incomplete,
      project_completion_ratio: ratio
    )
  end

  def build_summary(tasks_scope)
    total = tasks_scope.count
    completed = tasks_scope.completed.count
    incomplete = total - completed
    ratio = total.positive? ? (completed.to_f / total * 100).round(1) : 0
    status_breakdown = tasks_scope.joins(:status).group("statuses.name").count

    Summary.new(
      total_tasks: total,
      completed_count: completed,
      incomplete_count: incomplete,
      completion_ratio: ratio,
      status_breakdown: status_breakdown
    )
  end

  def build_project_breakdown(project)
    tasks = project.tasks.not_archived
    total = tasks.count
    completed = tasks.completed.count
    incomplete = total - completed
    ratio = total.positive? ? (completed.to_f / total * 100).round(1) : 0
    status_breakdown = tasks.joins(:status).group("statuses.name").count

    ProjectBreakdown.new(
      project: project,
      total_tasks: total,
      completed_count: completed,
      incomplete_count: incomplete,
      completion_ratio: ratio,
      status_breakdown: status_breakdown
    )
  end
end
