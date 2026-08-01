class TaskMergeService
  class Error < StandardError; end

  def self.call(target:, source:, current_user:)
    new(target, source, current_user).call
  end

  def initialize(target, source, current_user)
    @target = target
    @source = source
    @current_user = current_user
  end

  def call
    raise Error, "Cannot merge a task into itself" if @target.id == @source.id
    raise Error, "Both tasks must belong to you" if @target.user_id != @current_user.id || @source.user_id != @current_user.id
    raise Error, "Both tasks must be in the same project" if @target.project_id != @source.project_id

    ApplicationRecord.transaction do
      merge_title!
      merge_description!
      merge_priority!
      merge_due_date!
      merge_task_category!
      merge_tags!
      move_comments!
      move_attachments!
      merge_task_result!
      merge_recurring_task_template!

      @target.confirm_duplicate = true
      @target.paper_trail_event = 'merged'
      @target.save!

      # @source may have been loaded with an eager-loaded association cache
      # from before the moves above - destroy's dependent: :destroy callbacks
      # use whatever's already cached rather than re-querying, which would
      # otherwise destroy already-moved records still sitting in a stale
      # in-memory association array. Reloading forces every association to
      # be re-fetched fresh, correctly reflecting that they're all empty now.
      @source.reload
      @source.destroy!
    end

    @target
  rescue ActiveRecord::RecordInvalid => e
    raise Error, "Failed to merge tasks: #{e.message}"
  end

  private

  def merge_title!
    @target.title = [@target.title, @source.title].max_by { |t| t.to_s.length }
  end

  # Only adds the source's content if it actually has any - concatenating
  # onto a blank target description doesn't need a leading blank line.
  def merge_description!
    return if @source.description.blank?

    separator = I18n.t('views.tasks.merge.description_separator', title: @source.title)
    addition = "#{separator}\n#{@source.description}"
    @target.description = [@target.description.presence, addition].compact.join("\n\n")
  end

  def merge_priority!
    @target.priority = [@target.priority, @source.priority].max_by { |p| Task::PRIORITY_WEIGHTS[p] || 0 }
  end

  # Earlier (more urgent) of the two non-blank due dates wins, rather than
  # silently dropping whichever task's deadline was sooner.
  def merge_due_date!
    dates = [@target.due_date, @source.due_date].compact
    @target.due_date = dates.min if dates.any?
  end

  def merge_task_category!
    @target.task_category_id ||= @source.task_category_id
  end

  def merge_tags!
    @target.tag_ids = (@target.tag_ids + @source.tag_ids).uniq
  end

  def move_comments!
    @source.comments.find_each do |comment|
      comment.paper_trail_event = 'task_merge'
      comment.update!(task: @target)
    end
  end

  # Attachment isn't paper-trailed (see its own model comment), so no
  # paper_trail_event here.
  def move_attachments!
    @source.attachments.find_each { |attachment| attachment.update!(task: @target) }
  end

  # Task#sync_task_result_with_completion (an after_save callback) destroys
  # a task's task_result whenever the task isn't completed - transferring
  # source's result onto a target that isn't completed would just get wiped
  # out again by that callback on the @target.save! below, so there's no
  # point attempting it. Source's result, if any, is still preserved in its
  # own PaperTrail history even when this doesn't apply.
  def merge_task_result!
    return unless @target.completed?
    return if @target.task_result || @source.task_result.nil?
    @source.task_result.update!(task: @target)
  end

  # Same-project restriction (enforced in #call) means the inherited
  # template can never mismatch the target's own project.
  def merge_recurring_task_template!
    return if @target.recurring_task_template_id.present?
    @target.recurring_task_template_id = @source.recurring_task_template_id if @source.recurring_task_template_id.present?
  end
end
