# One page of the task index: unarchived tasks from the given scope,
# optionally without completed ones, searched and sorted.
class TaskIndexQuery
  PER_PAGE = 15

  DEFAULT_SORT = 'updated_desc'
  # Active (not completed) tasks oldest-first, then completed tasks newest-first -
  # deliberately the reverse of the kanban board's "most recently active first" logic,
  # surfacing neglected active tasks while keeping a normal recency log of completed ones.
  ACTIVE_OLDEST_SORT = 'active_oldest_completed_newest'
  SORT_OPTIONS = [DEFAULT_SORT, ACTIVE_OLDEST_SORT].freeze

  DEFAULT_SORT_SQL = 'COALESCE(updated_at, created_at) DESC, created_at DESC'
  ACTIVE_OLDEST_COMPLETED_NEWEST_SQL = <<~SQL.squish
    CASE WHEN tasks.completed THEN 1 ELSE 0 END ASC,
    CASE WHEN tasks.completed
      THEN -EXTRACT(EPOCH FROM COALESCE(tasks.updated_at, tasks.created_at))
      ELSE EXTRACT(EPOCH FROM COALESCE(tasks.updated_at, tasks.created_at))
    END ASC
  SQL

  def self.valid_sort(sort_by)
    SORT_OPTIONS.include?(sort_by) ? sort_by : DEFAULT_SORT
  end

  def initialize(scope:, show_completed:, search:, sort_by:, page:)
    @scope = scope
    @show_completed = show_completed
    @search = search
    @sort_by = sort_by
    @page = page
  end

  def call
    tasks = @scope.not_archived.includes(:project, :tags, :task_category, :comments)
    tasks = tasks.not_completed unless @show_completed
    tasks = if @search.present?
      tasks.search_ranked(@search, then_order: sort_sql)
    else
      tasks.order(Arel.sql(sort_sql))
    end
    tasks.page(@page).per(PER_PAGE)
  end

  private

  def sort_sql
    @sort_by == ACTIVE_OLDEST_SORT ? ACTIVE_OLDEST_COMPLETED_NEWEST_SQL : DEFAULT_SORT_SQL
  end
end
