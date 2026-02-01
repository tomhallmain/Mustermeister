# Silence DEBUG logs for the shared/_priority_badge partial only.
# Rails' ActionView::LogSubscriber logs every partial render at DEBUG level.
ActiveSupport.on_load(:action_view) do
  ActionView::LogSubscriber.prepend(Module.new do
    def render_partial(event)
      return if event.payload[:identifier]&.include?("_priority_badge")
      super
    end
  end)
end
