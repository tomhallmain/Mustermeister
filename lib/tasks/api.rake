namespace :api do
  desc "Generate (or regenerate) a user's API token for the token-authenticated /api endpoints"
  task :generate_token, [:email] => :environment do |_t, args|
    user = User.find_by(email: args[:email].to_s)
    if user.nil?
      puts "No user found with email #{args[:email].inspect}"
      next
    end

    user.update!(api_token: SecureRandom.hex(32))
    puts "API token for #{user.email}: #{user.api_token}"
  end
end
