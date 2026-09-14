namespace :api do
  desc "Generate (or regenerate) a user's API token for the token-authenticated /api endpoints"
  task :generate_token, [:email] => :environment do |_t, args|
    user = User.find_by(email: args[:email].to_s)
    if user.nil?
      puts "No user found with email #{args[:email].inspect}"
      next
    end

    raw_token = user.regenerate_api_token!
    puts "API token for #{user.email}: #{raw_token}"
    puts "Only the digest is stored, so this token cannot be shown again."
    puts "Scope: #{user.api_token_scope} (write-back needs 'read_write', set on the profile page)"
  end
end
