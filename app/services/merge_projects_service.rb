class MergeProjectsService
  class Error < StandardError; end

  # Single source of truth for which Project fields are user-choosable during
  # a merge - shared with the controller's strong-params allowlist and the
  # merge view's fieldset loop.
  MERGEABLE_FIELDS = %w[title description default_priority color category default_category_id due_date].freeze

  def self.call(source:, target:, field_choices:, current_user:)
    new(source, target, field_choices, current_user).call
  end

  def initialize(source, target, field_choices, current_user)
    @source = source
    @target = target
    @field_choices = field_choices || {}
    @current_user = current_user
  end

  def call
    raise Error, "Cannot merge a project into itself" if @source.id == @target.id
    raise Error, "Both projects must belong to the current user" if @source.user_id != @current_user.id || @target.user_id != @current_user.id

    ApplicationRecord.transaction do
      reconcile_custom_statuses!
      move_tasks!
      move_project_comments!
      move_recurring_task_templates!
      apply_field_choices!
      cleanup_task_insights_exclusion!

      # @source may have been loaded with an eager-loaded (e.g. controller's
      # `includes(:tasks)`) association cache from before the moves above -
      # destroy's `dependent: :destroy`/`:nullify` callbacks use whatever's
      # already cached rather than re-querying, which would otherwise destroy
      # already-moved records that still happen to be sitting in a stale
      # in-memory association array. Reloading forces every association to
      # be re-fetched fresh, correctly reflecting that they're all empty now.
      @source.reload
      @source.destroy!
    end

    @target
  rescue ActiveRecord::RecordInvalid => e
    raise Error, "Failed to merge projects: #{e.message}"
  end

  private

  # Task#remap_status_to_new_project only remaps a task's status onto a
  # same-named status that already exists in the new project; a custom
  # status with no matching name in target is left alone and then fails
  # Task#status_belongs_to_project. Pre-creating a same-named target status
  # for each of source's custom ones (skipping any target already has) avoids
  # that - default statuses never need this since every project already has
  # all 7 (StatusesController forbids ever renaming/deleting a default one,
  # so their names never diverge between projects).
  def reconcile_custom_statuses!
    @source.custom_statuses.each do |status|
      next if @target.statuses.exists?(name: status.name)
      @target.statuses.create!(name: status.name)
    end
  end

  def move_tasks!
    @source.tasks.find_each do |task|
      task.paper_trail_event = 'project_merge'
      task.update!(project: @target)
    end
  end

  # @source.comments is project-level only - task-level comments have
  # project_id nil and already move automatically via their task's own FK.
  def move_project_comments!
    @source.comments.find_each do |comment|
      comment.paper_trail_event = 'project_merge'
      comment.update!(project: @target)
    end
  end

  def move_recurring_task_templates!
    @source.recurring_task_templates.find_each { |template| template.update!(project: @target) }
  end

  # confirm_duplicate bypasses Project#warn_if_similar_title_exists: @source
  # is still a live record at this point (destroyed only at the very end), so
  # without this, choosing "keep source's title" would make target look like
  # a duplicate of the still-existing source and fail validation.
  def apply_field_choices!
    attrs = MERGEABLE_FIELDS.each_with_object({}) do |field, memo|
      memo[field] = @field_choices[field] == 'source' ? @source.public_send(field) : @target.public_send(field)
    end
    attrs['confirm_duplicate'] = true
    @target.update!(attrs)
  end

  # users.task_insights_excluded_project_ids is a plain integer[] column (not
  # an FK) of project ids opted out of AI Task Insights - clean up the
  # now-gone source id so it doesn't linger as a stale, meaningless entry.
  def cleanup_task_insights_exclusion!
    ids = @current_user.task_insights_excluded_project_ids
    return unless ids.include?(@source.id)
    @current_user.update!(task_insights_excluded_project_ids: ids - [@source.id])
  end
end
