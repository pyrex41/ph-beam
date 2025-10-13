#!/usr/bin/env elixir

# Test script for Accounts context
# Run with: cd collab_canvas && mix run test_accounts.exs

alias CollabCanvas.{Accounts, Repo}

IO.puts("\n=== Testing Accounts Context ===\n")

# Clean up any existing test data
IO.puts("Cleaning up existing test data...")
Repo.delete_all(CollabCanvas.Accounts.User)

# Test 1: Create User
IO.puts("\n1. Testing create_user/1...")
{:ok, user1} = Accounts.create_user(%{
  email: "test1@example.com",
  name: "Test User 1",
  avatar: "https://example.com/avatar1.jpg"
})
IO.puts("✓ Created user: #{user1.email} (ID: #{user1.id})")

# Test 2: Create another user
{:ok, user2} = Accounts.create_user(%{
  email: "test2@example.com",
  name: "Test User 2",
  provider: "google",
  provider_uid: "google-123456"
})
IO.puts("✓ Created user: #{user2.email} (ID: #{user2.id})")

# Test 3: Get user by ID
IO.puts("\n2. Testing get_user/1 by ID...")
fetched_user = Accounts.get_user(user1.id)
if fetched_user && fetched_user.id == user1.id do
  IO.puts("✓ Retrieved user by ID: #{fetched_user.email}")
else
  IO.puts("✗ Failed to retrieve user by ID")
end

# Test 4: Get user by email
IO.puts("\n3. Testing get_user/1 by email...")
fetched_by_email = Accounts.get_user("test2@example.com")
if fetched_by_email && fetched_by_email.email == "test2@example.com" do
  IO.puts("✓ Retrieved user by email: #{fetched_by_email.email}")
else
  IO.puts("✗ Failed to retrieve user by email")
end

# Test 5: List users
IO.puts("\n4. Testing list_users/0...")
users = Accounts.list_users()
IO.puts("✓ Found #{length(users)} users")
Enum.each(users, fn user ->
  IO.puts("  - #{user.email} (#{user.name})")
end)

# Test 6: Update last login
IO.puts("\n5. Testing update_last_login/1...")
{:ok, updated_user} = Accounts.update_last_login(user1)
if updated_user.last_login do
  IO.puts("✓ Updated last_login for #{updated_user.email}")
  IO.puts("  Last login: #{updated_user.last_login}")
else
  IO.puts("✗ Failed to update last_login")
end

# Test 7: Find or create user (existing)
IO.puts("\n6. Testing find_or_create_user/1 with existing user...")
{:ok, existing_user} = Accounts.find_or_create_user(%{
  email: "test2@example.com",
  name: "Test User 2 Updated",
  provider: "google",
  provider_uid: "google-123456"
})
if existing_user.id == user2.id do
  IO.puts("✓ Found existing user: #{existing_user.email}")
  IO.puts("  Last login updated: #{existing_user.last_login}")
else
  IO.puts("✗ Expected to find existing user but got new one")
end

# Test 8: Find or create user (new)
IO.puts("\n7. Testing find_or_create_user/1 with new user (Auth0 format)...")
{:ok, new_user} = Accounts.find_or_create_user(%{
  email: "auth0user@example.com",
  name: "Auth0 User",
  picture: "https://example.com/auth0-avatar.jpg",
  sub: "auth0|abc123def456",
  provider: "auth0"
})
IO.puts("✓ Created new user via find_or_create: #{new_user.email}")
IO.puts("  Provider: #{new_user.provider}")
IO.puts("  Provider UID: #{new_user.provider_uid}")
IO.puts("  Last login: #{new_user.last_login}")

# Test 9: Verify unique constraints
IO.puts("\n8. Testing unique email constraint...")
case Accounts.create_user(%{email: "test1@example.com", name: "Duplicate"}) do
  {:error, changeset} ->
    if changeset.errors[:email] do
      IO.puts("✓ Email uniqueness constraint working")
    else
      IO.puts("✗ Expected email error but got: #{inspect(changeset.errors)}")
    end
  {:ok, _} ->
    IO.puts("✗ Should have failed on duplicate email")
end

# Test 10: Test invalid email
IO.puts("\n9. Testing email validation...")
case Accounts.create_user(%{email: "invalid-email", name: "Invalid"}) do
  {:error, changeset} ->
    if changeset.errors[:email] do
      IO.puts("✓ Email format validation working")
    else
      IO.puts("✗ Expected email validation error")
    end
  {:ok, _} ->
    IO.puts("✗ Should have failed on invalid email")
end

# Final summary
IO.puts("\n=== Summary ===")
final_users = Accounts.list_users()
IO.puts("Total users in database: #{length(final_users)}")

IO.puts("\nAll tests completed! ✓")
