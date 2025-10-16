/**
 * ComponentDraggable Hook
 *
 * Handles drag-and-drop functionality for component instantiation from the components panel.
 * Enables users to drag components from the panel and drop them onto the canvas at a specific position.
 *
 * ## Features
 * - Native HTML5 drag-and-drop API
 * - Visual feedback during drag (ghost image, cursor changes)
 * - Coordinate transformation from screen to canvas space
 * - Communication with LiveView via phx-target
 * - Integration with CanvasRenderer for drop target detection
 *
 * ## Event Flow
 * 1. User starts dragging: dragstart event → push "drag_start" to LiveView
 * 2. User drags over canvas: dragover event → prevent default to allow drop
 * 3. User drops on canvas: drop event → calculate position → push "instantiate_component" to LiveView
 * 4. Drag ends: dragend event → push "drag_end" to LiveView
 *
 * ## Data Attributes
 * - data-component-id: Component ID being dragged
 *
 * @module ComponentDraggable
 */

const ComponentDraggable = {
  /**
   * Hook mounted callback.
   * Sets up drag event listeners and configures drag behavior.
   */
  mounted() {
    const componentId = this.el.dataset.componentId;
    let dragStartPosition = null;

    // Configure drag behavior
    this.el.style.cursor = "move";

    /**
     * Handle drag start event.
     * Records starting position and notifies LiveView.
     */
    this.el.addEventListener("dragstart", (e) => {
      // Store component ID in dataTransfer for access during drop
      e.dataTransfer.effectAllowed = "copy";
      e.dataTransfer.setData("text/plain", componentId);
      e.dataTransfer.setData("application/component-id", componentId);

      // Add visual feedback
      this.el.classList.add("opacity-50");

      // Record starting position
      dragStartPosition = {
        x: e.clientX,
        y: e.clientY,
      };

      // Notify LiveView that drag started
      this.pushEvent("drag_start", { component_id: componentId });

      console.log("Component drag started:", componentId);
    });

    /**
     * Handle drag end event.
     * Cleans up visual feedback and notifies LiveView.
     */
    this.el.addEventListener("dragend", (e) => {
      // Remove visual feedback
      this.el.classList.remove("opacity-50");

      // Notify LiveView that drag ended
      this.pushEvent("drag_end", {});

      dragStartPosition = null;

      console.log("Component drag ended");
    });

    /**
     * Handle drop event (if component is dropped back on the panel).
     * This prevents the browser from trying to navigate or load the component.
     */
    this.el.addEventListener("drop", (e) => {
      e.preventDefault();
      e.stopPropagation();
    });

    // Store hook instance for cleanup
    this._boundDragStart = this.el.addEventListener.bind(this.el);
  },

  /**
   * Hook destroyed callback.
   * Cleanup event listeners to prevent memory leaks.
   */
  destroyed() {
    // Event listeners are automatically cleaned up when element is removed
    // This is just for explicit cleanup if needed
    console.log("ComponentDraggable hook destroyed");
  },
};

export default ComponentDraggable;
