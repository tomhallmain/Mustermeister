# Opportunistic trigger for recurring task generation: called from a
# before_action on pages users are likely to visit regularly (tasks index,
# recurring schedules index). Throttled process-wide via Rails.cache so it
# costs nothing beyond a cache read on most requests, since generation can
# only ever happen while the app is actually running - this backstops the
# Solid Queue recurring job and the startup check for low-traffic deploys
# where a worker process might not always be up.
module RecurringTaskGenerationCheck
  CACHE_KEY = "recurring_task_generation_last_check"
  THROTTLE = 15.minutes

  def self.run_if_due!
    Rails.cache.fetch(CACHE_KEY, expires_in: THROTTLE) do
      RecurringTaskTemplate.generate_all_due!
      true
    end
  end
end
