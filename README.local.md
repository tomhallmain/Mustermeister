# Local Development Guide

## Initial Setup

```bash
# Install dependencies
bundle install
yarn install

# Setup database
rails db:create
rails db:migrate
rails db:seed  # if you have seed data

# Compile assets
yarn build:css
rails assets:precompile RAILS_ENV=development
```

## Database Management

Ensure postgres service is started and running

```bash
# Create database
rails db:create

# Run migrations
rails db:migrate

# Rollback last migration
rails db:rollback

# Reset database (drops, creates, migrates)
rails db:reset

# Check migration status
rails db:migrate:status

# Seed database
rails db:seed
```

### Test-Specific Database Management:

```bash
# This will run all pending migrations only on the test database
rails db:migrate RAILS_ENV=test

# Drop the test database, create a fresh test database, run all migrations on it
rails db:test:prepare
```


## Rails Console Commands

```bash
# Start Rails console
rails console  # or rails c

# Reload console
reload!

# Common console commands
User.all                     # List all users
User.first                   # Get first user
User.find(1)                # Find user by ID
User.where(admin: true)     # Find users by condition
User.create!(email: "test@example.com", password: "password123")  # Create user

# Exit console
exit
```

## Running the Application

```bash
# Start the Rails server
rails server  # or rails s

# Start with specific port
rails server -p 3001

# Start in development
bin/dev  # This runs Procfile.dev processes
```

## Asset Management

```bash
# Build CSS
yarn build:css

# Watch CSS changes
yarn build:css --watch

# Precompile assets
rails assets:precompile RAILS_ENV=development

# Clean assets
rails assets:clean
```

## Rails Admin

```bash
# Access Rails Admin interface
# Visit http://localhost:3000/admin in your browser
# Make sure you're logged in as an admin user

# Make a user admin via console
rails console
user = User.find_by(email: "your@email.com")
user.update(admin: true)
```

## Debugging

```bash
# View logs
tail -f log/development.log

# Clear logs
rails log:clear

# Show routes
rails routes

# Show specific routes
rails routes | grep users
```

## Environment Variables

```bash
# Set environment variables in .env file
# Example .env contents:
DATABASE_URL=postgresql://localhost/myapp_development
RAILS_ENV=development
```

## Testing

```bash
# Run all tests
rails test

# Run specific test file
rails test test/models/user_test.rb

# Run specific test
rails test test/models/user_test.rb:10  # Line number
```

## Internationalization (i18n) Management

```bash
# Check translation health (missing, unused, inconsistent keys)
bundle exec rake "i18n:tasks[health]"

# Find missing translations
bundle exec rake "i18n:tasks[missing]"

# Find unused translation keys
bundle exec rake "i18n-tasks[unused]"

# Add missing translations automatically
bundle exec rake "i18n:tasks[add-missing]"

# Normalize locale files (fix formatting, sort keys)
bundle exec rake "i18n:tasks[normalize]"

# Find hardcoded strings that should be translated
bundle exec rake "i18n:tasks[find]"

# Remove unused translation keys
bundle exec rake "i18n:tasks[remove-unused]"

# Check for inconsistent interpolations
bundle exec rake "i18n:tasks[check-consistent-interpolations]"
```

## Useful Development Commands

```bash
# Generate scaffold
rails generate scaffold Post title:string body:text

# Generate model
rails generate model Comment body:text post:references

# Generate controller
rails generate controller Comments index show

# Remove generated files
rails destroy scaffold Post
rails destroy model Comment
rails destroy controller Comments
```

## Common Issues & Solutions

1. If assets aren't loading:
   ```bash
   rm -rf tmp/cache
   rails assets:precompile RAILS_ENV=development
   ```

2. If database issues occur:
   ```bash
   rails db:reset
   ```

3. If Webpacker/CSS issues:
   ```bash
   yarn install
   yarn build:css
   ```

4. If you see syslog deprecation warnings:
   ```
   warning: syslog was loaded from the standard library, but will no longer be part of the default gems starting from Ruby 3.4.0.
   ```
   This is a known issue with the `logging` gem on Windows. The warning is harmless and will be resolved when the gem updates its gemspec.

## Windows-Specific Rails Asset Pipeline Configuration Notes

**Problem**: Windows file locking behavior causes `Errno::EACCES` during asset precompilation, especially with `rails_admin` CSS.

---

### 1. Environment Variables
```cmd
setx RAILS_TMPDIR "C:\rails_temp"
set TMP="%RAILS_TMPDIR%"
set TEMP="%RAILS_TMPDIR%"```

### 2. Directory Setup (run as Administrator)
```cmd
mkdir C:\rails_temp
icacls "C:\rails_temp" /grant Everyone:(OI)(CI)F /T```

### 3. Precompilation Sequence
```cmd
rails assets:clobber && rails tmp:clear && yarn build:css && rails assets:precompile
```

## Development Tips

- Use `rails routes` to see all available routes
- Use `rails dbconsole` to access database console
- Use `rails stats` to see code statistics
- Use `rails notes` to see TODO/FIXME comments in code 
