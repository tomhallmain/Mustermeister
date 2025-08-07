# Load all locale files from the config/locales directory
I18n.load_path += Dir[Rails.root.join('config', 'locales', '**', '*.{rb,yml}')]

# Ensure locales are available
I18n.available_locales = [:en, :es, :fr, :de]
I18n.default_locale = :en

# Set up fallbacks
I18n.fallbacks.map(
  es: :en,
  fr: :en,
  de: :en
)

# Configure time formats
Time::DATE_FORMATS[:default] = "%B %d, %Y at %I:%M %p"
Date::DATE_FORMATS[:default] = "%B %d, %Y"

# Configure number formats
ActiveSupport::NumberHelper.number_to_currency(1000, locale: :en) # => "$1,000.00"
