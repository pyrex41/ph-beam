defmodule CollabCanvasWeb.Presence do
  @moduledoc """
  Provides real-time presence tracking for collaborative features.

  This module tracks online users and their cursor positions using Phoenix Presence,
  which provides CRDT-backed conflict-free replicated data types for distributed
  presence tracking across multiple nodes.

  ## Usage

      # Track a user in a canvas room
      {:ok, _} = Presence.track(self(), "canvas:123", user_id, %{
        online_at: System.system_time(:second),
        cursor: %{x: 0, y: 0},
        color: "#3b82f6",
        name: "User Name"
      })

      # List all present users
      Presence.list("canvas:123")

      # Get presence for a specific user
      Presence.get_by_key("canvas:123", user_id)
  """

  use Phoenix.Presence,
    otp_app: :collab_canvas,
    pubsub_server: CollabCanvas.PubSub
end
