class RecurringTaskGenerationJob < ApplicationJob
  queue_as :default

  def perform
    RecurringTaskTemplate.generate_all_due!
  end
end
