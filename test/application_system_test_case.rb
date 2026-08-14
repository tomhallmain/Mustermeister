require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  # Points Selenium at the Chrome + chromedriver pair downloaded by `bin/rails
  # chrome_for_testing:install` (see lib/tasks/chrome_for_testing.rake) when
  # present, for machines with no system Chrome install, or where Selenium
  # Manager's own chromedriver (this gem version can't auto-match one to a
  # custom Chrome binary) is older than that Chrome build. Falls back to
  # Selenium's own detection of a system-installed Chrome/chromedriver
  # otherwise. The driver path is a Service-level (not driver_option) setting,
  # so it's set up-front rather than inside the driven_by block below.
  downloaded_driver = Dir.glob(Rails.root.join("tmp", "chrome_for_testing", "**", "chromedriver{,.exe}")).first
  Selenium::WebDriver::Chrome::Service.driver_path = downloaded_driver if downloaded_driver

  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ] do |driver_option|
    downloaded_binary = Dir.glob(Rails.root.join("tmp", "chrome_for_testing", "**", "chrome{,.exe}")).first
    driver_option.binary = downloaded_binary if downloaded_binary
  end
end
