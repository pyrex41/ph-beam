defmodule CollabCanvasWeb.AuthController do
  use CollabCanvasWeb, :controller
  plug Ueberauth

  alias CollabCanvas.Accounts

  @doc """
  Initiates the OAuth flow by redirecting to Auth0.
  This is automatically handled by Ueberauth when accessing /auth/auth0
  """
  def request(conn, _params) do
    # Ueberauth handles the redirect
    conn
  end

  @doc """
  Handles the callback from Auth0 after successful authentication.
  Extracts user information and creates/updates the user in the database.
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
  Logs out the user by clearing the session.
  """
  def logout(conn, _params) do
    conn
    |> configure_session(drop: true)
    |> put_flash(:info, "You have been logged out.")
    |> redirect(to: "/")
  end
end
