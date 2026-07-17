# Silence DEBUG logs for the shared badge partials only (priority/category/status).
# Rails' ActionView::LogSubscriber logs every partial render at DEBUG level,
# and these partials render once per row on list pages (tasks index, project
# show), so left unchecked they'd flood the log the moment log_level is ever
# turned down to :debug.
ActiveSupport.on_load(:action_view) do
  ActionView::LogSubscriber.prepend(Module.new do
    def render_partial(event)
      identifier = event.payload[:identifier]
      badge_names = %w[_priority_badge _category_badge _status_badge]
      return if identifier && badge_names.any? { |name| identifier.include?(name) }
      super
    end
  end)
end
