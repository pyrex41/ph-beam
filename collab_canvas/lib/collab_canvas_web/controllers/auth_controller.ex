defmodule CollabCanvasWeb.AuthController do
  @moduledoc """
  Handles authentication and authorization using Auth0 via Ueberauth.

  This controller manages the complete OAuth 2.0 authentication flow with Auth0:

  ## Authentication Flow

  1. User clicks login and is redirected to `/auth/auth0` (handled by `request/2`)
  2. Ueberauth redirects the user to Auth0's login page
  3. User authenticates with Auth0 (email/password, social login, etc.)
  4. Auth0 redirects back to `/auth/auth0/callback` with authorization code
  5. Ueberauth exchanges the code for user information
  6. `callback/2` processes the auth response:
     - On success: Creates or retrieves user from database
     - Stores user information in session
     - Redirects to home page
     - On failure: Shows error message and redirects to home page

  ## User Management

  The controller interacts with the `CollabCanvas.Accounts` context to:
  - Find existing users by provider and provider_uid
  - Create new user records for first-time logins
  - Store user profile information (email, name, avatar)

  ## Session Management

  User sessions are managed via Phoenix sessions:
  - `user_id`: Primary key of the authenticated user
  - `user_email`: User's email address for quick access
  - `user_name`: User's display name for quick access
  - Sessions are renewed on successful authentication for security
  - Sessions are completely dropped on logout

  ## Configuration

  Requires Ueberauth and Ueberauth Auth0 strategy to be configured in `config.exs`:
  - Auth0 domain
  - Auth0 client ID
  - Auth0 client secret
  - Callback URL
  """
  use CollabCanvasWeb, :controller
  plug Ueberauth

  alias CollabCanvas.Accounts

  @doc """
  Initiates the OAuth 2.0 authentication flow with Auth0.

  This function is called when a user visits `/auth/auth0`. The Ueberauth plug
  intercepts this request and automatically redirects the user to Auth0's
  authorization page where they can log in.

  ## Parameters

    - `conn` - The Phoenix connection struct
    - `_params` - Request parameters (unused, handled by Ueberauth)

  ## Returns

  The connection struct. The actual redirect is handled by the Ueberauth plug.

  ## Example Route

      get "/auth/:provider", AuthController, :request
  """
  def request(conn, _params) do
    # Ueberauth handles the redirect
    conn
  end

  @doc """
  Handles the OAuth callback from Auth0 after authentication attempt.

  This function has two clauses to handle success and failure cases:

  ## Failure Case

  When authentication fails (wrong credentials, user cancels, etc.), Ueberauth
  assigns `ueberauth_failure` to the connection. This clause catches that and
  displays an error message to the user.

  ## Success Case

  When authentication succeeds, Ueberauth assigns `ueberauth_auth` to the connection
  containing the user's profile information from Auth0. This clause:

  1. Extracts user information (email, name, avatar, provider details)
  2. Calls `Accounts.find_or_create_user/1` to get or create the user record
  3. On success: Stores user info in session and redirects to home page
  4. On error: Shows error message and redirects to home page

  ## Parameters

    - `conn` - The Phoenix connection struct with Ueberauth assigns
    - `_params` - Request parameters (unused)

  ## Returns

  A connection struct with flash message and redirect.

  ## Example Route

      get "/auth/:provider/callback", AuthController, :callback

  ## Session Data Stored

    - `user_id` - Database ID of the authenticated user
    - `user_email` - User's email address
    - `user_name` - User's display name
  """
  def callback(%{assigns: %{ueberauth_failure: _fails}} = conn, _params) do
    conn
    |> put_flash(:error, "Failed to authenticate.")
    |> redirect(to: "/")
  end

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    # Extract user information from Auth0
    user_params = %{
      email: auth.info.email,
      name: auth.info.name,
      avatar: auth.info.image,
      provider: "auth0",
      provider_uid: auth.uid
    }

    case Accounts.find_or_create_user(user_params) do
      {:ok, user} ->
        conn
        |> put_flash(:info, "Successfully authenticated!")
        |> put_session(:user_id, user.id)
        |> put_session(:user_email, user.email)
        |> put_session(:user_name, user.name)
        |> configure_session(renew: true)
        |> redirect(to: "/")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Failed to create user account.")
        |> redirect(to: "/")
    end
  end

  @doc """
  Logs out the currently authenticated user.

  This function terminates the user's session by completely dropping all session
  data. This includes user_id, user_email, and user_name. The user is then
  redirected to the home page with a confirmation message.

  Note: This only clears the application session. If using Auth0's Single Sign-On
  (SSO), the user may still be logged into Auth0 and could be automatically
  re-authenticated if they visit the login page again. For complete logout,
  consider redirecting to Auth0's logout endpoint.

  ## Parameters

    - `conn` - The Phoenix connection struct
    - `_params` - Request parameters (unused)

  ## Returns

  A connection struct with the session dropped, a flash message, and redirect to home.

  ## Example Route

      get "/auth/logout", AuthController, :logout
      delete "/auth/logout", AuthController, :logout
  """
  def logout(conn, _params) do
    conn
    |> configure_session(drop: true)
    |> put_flash(:info, "You have been logged out.")
    |> redirect(to: "/")
  end
end
