defmodule CollabCanvasWeb.PixiTestLive do
  use CollabCanvasWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-8">
      <h1 class="text-3xl font-bold mb-4">PixiJS Test</h1>
      <p class="mb-4 text-gray-600">
        This page tests the PixiJS rendering setup.
        You should see a spinning red square below.
      </p>

      <div
        id="pixi-test-container"
        phx-hook="PixiTest"
        phx-update="ignore"
        class="border-2 border-gray-300 rounded-lg"
      >
      </div>

      <div class="mt-4 p-4 bg-blue-50 rounded">
        <p class="text-sm">
          <strong>Note:</strong> If you see a red rotating square above, PixiJS is working correctly!
        </p>
      </div>
    </div>
    """
  end
end
