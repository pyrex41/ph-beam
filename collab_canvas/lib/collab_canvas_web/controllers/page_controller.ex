defmodule CollabCanvasWeb.PageController do
  use CollabCanvasWeb, :controller

  plug CollabCanvasWeb.Plugs.Auth, :load_current_user when action in [:home]

  def home(conn, _params) do
    render(conn, :home)
  end
end
