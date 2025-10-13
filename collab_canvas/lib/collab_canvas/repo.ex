defmodule CollabCanvas.Repo do
  use Ecto.Repo,
    otp_app: :collab_canvas,
    adapter: Ecto.Adapters.SQLite3
end
