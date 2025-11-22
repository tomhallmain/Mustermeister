#!/usr/bin/env ruby
# frozen_string_literal: true

# Password Reset Script for Mustermeister
#
# IMPORTANT: Passwords are hashed (not encrypted), which means they cannot be
# decrypted. This is a security feature - passwords are stored using bcrypt,
# a one-way cryptographic hash function.
#
# This script allows you to reset your password by setting a new one.
#
# Usage:
#   rails runner scripts/reset_user_password.rb
#   OR
#   ruby scripts/reset_user_password.rb (if you set up the Rails environment)

# Load Rails environment
require_relative '../config/environment'

puts "=" * 60
puts "Mustermeister Password Reset Script"
puts "=" * 60
puts
puts "NOTE: Passwords cannot be decrypted because they are hashed using"
puts "bcrypt (a one-way function). This script will help reset a password."
puts

# Get user email
print "Enter your email address: "
email = STDIN.gets.chomp.strip

if email.empty?
  puts "\nError: Email cannot be empty."
  exit 1
end

# Find the user
user = User.find_by(email: email)

unless user
  puts "\nError: User with email '#{email}' not found."
  puts "\nAvailable users in database:"
  User.all.each do |u|
    puts "  - #{u.email} (#{u.name})"
  end
  exit 1
end

puts "\nFound user: #{user.name} (#{user.email})"
puts

# Get new password
print "Enter new password: "
new_password = STDIN.noecho(&:gets).chomp
puts

if new_password.empty?
  puts "\nError: Password cannot be empty."
  exit 1
end

print "Confirm new password: "
password_confirmation = STDIN.noecho(&:gets).chomp
puts

if new_password != password_confirmation
  puts "\nError: Passwords do not match."
  exit 1
end

# Update password using Devise's method (this properly hashes it)
# We set the password first to trigger Devise's hashing, then update directly
# to bypass the email notification callback that's causing issues
user.password = new_password
user.password_confirmation = password_confirmation

# Validate the password first
unless user.valid?
  puts "\n✗ Error: Password validation failed:"
  user.errors.full_messages.each do |error|
    puts "  - #{error}"
  end
  exit 1
end

# Update the encrypted_password directly to bypass email callbacks
# This still uses Devise's proper password hashing (already done above)
begin
  user.update_column(:encrypted_password, user.encrypted_password)
  puts "\n✓ Password successfully reset!"
  puts "  You can now log in with your email and the new password."
  puts "  (Email notification was skipped to avoid mailer configuration issues)"
rescue StandardError => e
  puts "\n✗ Error updating password: #{e.message}"
  exit 1
end

