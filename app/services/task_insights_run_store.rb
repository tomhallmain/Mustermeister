# frozen_string_literal: true

# Persists in-flight task insight runs for polling. Uses Rails.cache when it is
# not NullStore; otherwise a dedicated memory store so tests work with config.cache_store = :null_store.
class TaskInsightsRunStore
  CACHE_PREFIX = "task_insights_run/v1"
  TTL = 30.minutes

  class << self
    def cache_backend
      @cache_backend ||= if Rails.cache.is_a?(ActiveSupport::Cache::NullStore)
        ActiveSupport::Cache::MemoryStore.new(expires_in: TTL)
      else
        Rails.cache
      end
    end

    def key(run_id)
      "#{CACHE_PREFIX}/#{run_id}"
    end

    def init(run_id, user_id:)
      write(run_id, {
        "user_id" => user_id,
        "status" => "running",
        "state_events" => [],
        "tool_calls" => [],
        "answer" => nil,
        "error" => nil
      })
    end

    def read(run_id)
      cache_backend.read(key(run_id)) || {}
    end

    def sync_running(run_id, state_events:, tool_calls:)
      current = read(run_id)
      return if current.blank?

      write(run_id, current.merge(
        "status" => "running",
        "state_events" => deep_stringify(state_events),
        "tool_calls" => deep_stringify(tool_calls)
      ))
    end

    def complete!(run_id, result)
      sync_running(
        run_id,
        state_events: result.state_events || [],
        tool_calls: result.tool_calls || []
      )
      current = read(run_id)
      write(run_id, current.merge(
        "status" => "complete",
        "answer" => result.answer.to_s
      ))
    end

    def fail!(run_id, error:)
      current = read(run_id)
      events = Array(current["state_events"])
      events << {
        "state" => "job_exception",
        "message" => error.to_s,
        "at" => Time.current.iso8601
      }
      write(run_id, current.merge(
        "status" => "failed",
        "state_events" => events,
        "error" => error.to_s
      ))
    end

    private

    def write(run_id, payload)
      cache_backend.write(key(run_id), payload, expires_in: TTL)
    end

    def deep_stringify(value)
      case value
      when Hash
        value.each_with_object({}) { |(k, v), h| h[k.to_s] = deep_stringify(v) }
      when Array
        value.map { |v| deep_stringify(v) }
      else
        value
      end
    end
  end
end
