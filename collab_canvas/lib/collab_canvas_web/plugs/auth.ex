defmodule CollabCanvasWeb.Plugs.Auth do
  @moduledoc """
  Authentication plug for protecting routes and LiveViews.

  This plug checks if a user is authenticated by verifying the session.
  It can be used in the router pipeline or individual controller/LiveView actions.
  """

  import Plug.Conn
  import Phoenix.Controller

  alias CollabCanvas.Accounts

  @doc """
  Loads the current user from the session.

  ## Usage

  In your router:

      pipeline :authenticated do
        plug CollabCanvasWeb.Plugs.Auth, :load_current_user
      end

  In a LiveView:

      def mount(_params, session, socket) do
        socket = assign_current_user(socket, session)
        ...
      end
  """
  def init(opts), do: opts

  def call(conn, :load_current_user) do
    case get_session(conn, :user_id) do
      nil ->
        conn
        |> assign(:current_user, nil)

      user_id ->
        case Accounts.get_user(user_id) do
          nil ->
            conn
            |> clear_session()
            |> assign(:current_user, nil)

          user ->
            conn
            |> assign(:current_user, user)
        end
    end
  end

  def call(conn, :require_authenticated) do
    case conn.assigns[:current_user] do
      nil ->
        conn
        |> put_flash(:error, "You must be logged in to access this page.")
        |> redirect(to: "/")
        |> halt()

      _user ->
        conn
    end
  end

  @doc """
  Assigns the current user to a LiveView socket from the session.

  ## Example

      def mount(_params, session, socket) do
        socket = assign_current_user(socket, session)

        if socket.assigns.current_user do
          {:ok, socket}
        else
          {:ok, redirect(socket, to: "/")}
        end
      end
  """
  def assign_current_user(socket, session) do
    case session["user_id"] do
      nil ->
        Phoenix.Component.assign(socket, :current_user, nil)

      user_id ->
        case Accounts.get_user(user_id) do
          nil ->
            Phoenix.Component.assign(socket, :current_user, nil)

          user ->
            Phoenix.Component.assign(socket, :current_user, user)
        end
    end
  end

  @doc """
  Checks if a user is authenticated (has a valid session).

  Returns `true` if the user is logged in, `false` otherwise.
  """
  def authenticated?(conn) do
    conn.assigns[:current_user] != nil
  end

  @doc """
  Gets the current user from the connection assigns.

  Returns `nil` if no user is authenticated.
  """
  def current_user(conn) do
    conn.assigns[:current_user]
  end

  @doc """
  LiveView on_mount hook for authentication.

  ## Usage

      defmodule MyAppWeb.MyLive do
        use MyAppWeb, :live_view

        on_mount {CollabCanvasWeb.Plugs.Auth, :require_authenticated_user}

        ...
      end
  """
  def on_mount(:load_current_user, _params, session, socket) do
    {:cont, assign_current_user(socket, session)}
  end

  def on_mount(:require_authenticated_user, _params, session, socket) do
    socket = assign_current_user(socket, session)

    if socket.assigns.current_user do
      {:cont, socket}
    else
      socket =
        socket
        |> Phoenix.LiveView.put_flash(:error, "You must be logged in to access this page.")
        |> Phoenix.LiveView.redirect(to: "/")

      {:halt, socket}
    end
  end
end
