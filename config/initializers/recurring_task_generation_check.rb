# Runs a catch-up recurring-task-generation check once the app has fully
# booted (after all initializers, before the first request). Generation can
# only ever happen while the app is running, so this - together with the
# Solid Queue recurring job in config/recurring.yml and the opportunistic
# check on page loads (see RecurringTaskGenerationCheck) - makes sure a
# schedule catches up promptly after a restart even before anyone visits a
# page or the hourly job next fires.

Rails.application.config.after_initialize do
  require_relative '../../lib/rails_context_detector'

  if RailsContextDetector.should_run_startup_checks?
    Rails.logger.info "Running recurring task generation check (context: #{RailsContextDetector.current_context})"

    begin
      RecurringTaskTemplate.generate_all_due!
    rescue => e
      Rails.logger.error "Recurring task generation startup check failed: #{e.message}"
    end
  end
end
