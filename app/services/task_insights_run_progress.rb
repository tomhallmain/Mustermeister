# frozen_string_literal: true

# Pushes TaskInsightsChatService state to TaskInsightsRunStore for live polling.
class TaskInsightsRunProgress
  def initialize(run_id)
    @run_id = run_id
  end

  def sync(state_events:, tool_calls:)
    TaskInsightsRunStore.sync_running(@run_id, state_events: state_events, tool_calls: tool_calls)
  end
end
