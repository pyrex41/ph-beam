import { CanvasManager } from '../core/canvas_manager.js';

/**
 * CanvasManager Hook for Phoenix LiveView
 *
 * Thin adapter that integrates the standalone CanvasManager class
 * with Phoenix LiveView. Handles data flow between server and canvas.
 */
export default {
  /**
   * Hook lifecycle - mounted
   */
  async mounted() {
    // Store current user ID and canvas ID
    this.currentUserId = this.el.dataset.userId;
    this.canvasId = this.el.dataset.canvasId;

    // Create CanvasManager instance
    this.canvasManager = new CanvasManager();
    await this.canvasManager.initialize(this.el, this.currentUserId, this.canvasId);

    // Set initial current color from data attribute
    const currentColor = this.el.dataset.currentColor || '#000000';
    this.canvasManager.setCurrentColor(currentColor);

    // Setup event listeners to bridge CanvasManager events to LiveView
    this.setupCanvasEventListeners();

    // Load initial data
    this.loadInitialObjects();
    this.loadInitialPresences();

    // Auto-fit all objects on page load
    this.canvasManager.resetView();

    // Setup server event handlers
    this.setupServerEventHandlers();
  },

  /**
   * Safely push event to server (ignores if not connected)
   */
  safePushEvent(eventName, payload) {
    try {
      this.pushEvent(eventName, payload);
    } catch (error) {
      // Silently ignore if LiveView not connected
      // Connection will be established shortly
    }
  },

  /**
   * Setup event listeners from CanvasManager
   */
  setupCanvasEventListeners() {
    // Forward canvas events to server
    this.canvasManager.on('create_object', (data) => {
      this.safePushEvent('create_object', data);
    });

    this.canvasManager.on('update_object', (data) => {
      this.safePushEvent('update_object', data);
    });

    this.canvasManager.on('update_objects_batch', (data) => {
      this.safePushEvent('update_objects_batch', data);
    });

    this.canvasManager.on('delete_object', (data) => {
      this.safePushEvent('delete_object', data);
    });

    this.canvasManager.on('lock_object', (data) => {
      this.safePushEvent('lock_object', data);
    });

    this.canvasManager.on('unlock_object', (data) => {
      this.safePushEvent('unlock_object', data);
    });

    this.canvasManager.on('cursor_move', (data) => {
      this.safePushEvent('cursor_move', data);
    });

    this.canvasManager.on('tool_changed', (data) => {
      this.safePushEvent('select_tool', data);
    });

    this.canvasManager.on('bring_to_front', (data) => {
      this.safePushEvent('bring_to_front', data);
    });

    this.canvasManager.on('send_to_back', (data) => {
      this.safePushEvent('send_to_back', data);
    });

    this.canvasManager.on('move_forward', (data) => {
      this.safePushEvent('move_forward', data);
    });

    this.canvasManager.on('move_backward', (data) => {
      this.safePushEvent('move_backward', data);
    });

    // Undo/Redo events
    this.canvasManager.on('undo', (data) => {
      this.safePushEvent('undo', data);
    });

    this.canvasManager.on('redo', (data) => {
      this.safePushEvent('redo', data);
    });

    // Operation batching events
    this.canvasManager.on('start_operation', (data) => {
      this.safePushEvent('start_operation', data);
    });

    this.canvasManager.on('end_operation', (data) => {
      this.safePushEvent('end_operation', data);
    });

    // Setup drag-and-drop for component instantiation
    this.setupComponentDragAndDrop();

    // Setup AI command button to inject selected object IDs
    this.setupAICommandButton();
  },

  /**
   * Setup drag-and-drop event listeners for component instantiation
   */
  setupComponentDragAndDrop() {
    const canvasElement = this.el;

    // Allow dropping on canvas
    canvasElement.addEventListener('dragover', (e) => {
      e.preventDefault();
      e.dataTransfer.dropEffect = 'copy';
    });

    // Handle component drop
    canvasElement.addEventListener('drop', (e) => {
      e.preventDefault();
      e.stopPropagation();

      // Get component ID from dataTransfer
      const componentId = e.dataTransfer.getData('application/component-id') ||
                          e.dataTransfer.getData('text/plain');

      if (componentId) {
        // Get canvas coordinates from drop position
        const rect = canvasElement.getBoundingClientRect();
        const screenX = e.clientX - rect.left;
        const screenY = e.clientY - rect.top;

        // Transform screen coordinates to canvas world space
        const canvasPosition = this.canvasManager.screenToCanvas(screenX, screenY);

        console.log('Component dropped:', {
          componentId,
          screenPosition: { x: screenX, y: screenY },
          canvasPosition
        });

        // Notify server to instantiate the component
        this.safePushEvent('instantiate_component', {
          component_id: componentId,
          position: canvasPosition
        });
      }
    });

    // Prevent dragenter from interfering
    canvasElement.addEventListener('dragenter', (e) => {
      e.preventDefault();
    });
  },

  /**
   * Setup AI command button to inject selected object IDs
   */
  setupAICommandButton() {
    // Find the AI execute button in the DOM
    const aiButton = document.getElementById('ai-execute-button');

    if (aiButton) {
      // Intercept click events to handle AI command with selected objects
      aiButton.addEventListener('click', (e) => {
        // Only intercept if button is not disabled
        if (aiButton.disabled) {
          return;
        }

        // Prevent default Phoenix click handler
        e.preventDefault();
        e.stopPropagation();

        // Get the command from the textarea
        const command = aiButton.getAttribute('phx-value-command');

        // Get selected object IDs from canvas manager
        const selectedIds = this.canvasManager.getSelectedObjectIds();

        // Get current viewport state for semantic positioning
        const viewport = this.canvasManager.getViewportState();
        const canvasWidth = this.el.clientWidth;
        const canvasHeight = this.el.clientHeight;

        // Push event to server with command, selected IDs, and viewport
        this.safePushEvent('execute_ai_command', {
          command: command,
          selected_ids: selectedIds,
          viewport: {
            x: viewport.x,
            y: viewport.y,
            zoom: viewport.zoom,
            canvas_width: canvasWidth,
            canvas_height: canvasHeight
          }
        });
      }, true); // Use capture phase to run before any other handlers
    }
  },

  /**
   * Load initial objects from data attributes
   */
  loadInitialObjects() {
    const objectsData = this.el.dataset.objects;
    if (objectsData) {
      try {
        const objects = JSON.parse(objectsData);
        objects.forEach(obj => this.canvasManager.createObject(obj));
      } catch (error) {
        console.error('Failed to parse initial objects:', error);
      }
    }
  },

  /**
   * Load initial presences from data attributes
   */
  loadInitialPresences() {
    const presencesData = this.el.dataset.presences;
    if (presencesData) {
      try {
        const presences = JSON.parse(presencesData);
        this.canvasManager.updatePresences(presences);
      } catch (error) {
        console.error('Failed to parse initial presences:', error);
      }
    }
  },

  /**
   * Setup handlers for server events via Phoenix hooks
   */
  setupServerEventHandlers() {
    // Handle object created events
    this.handleEvent('object_created', (data) => {
      this.canvasManager.createObject(data.object);
    });

    // Handle object updated events
    this.handleEvent('object_updated', (data) => {
      this.canvasManager.updateObject(data.object, { animate: data.animate });
    });

    // Handle batch object updates (for layout operations and AI)
    this.handleEvent('objects_updated_batch', (data) => {
      console.log('Batch update received:', data.objects.length, 'objects');
      // Start history batch for undo/redo
      this.canvasManager.startHistoryBatch();
      // Skip animation if this client is currently dragging (they already see objects in final position)
      // Use animation for remote clients watching the drag or for AI/layout operations
      const shouldAnimate = !this.canvasManager.isDragging;
      data.objects.forEach(obj => this.canvasManager.updateObject(obj, { animate: shouldAnimate }));
      // End history batch
      this.canvasManager.endHistoryBatch();
    });

    // Handle object deleted events
    this.handleEvent('object_deleted', (data) => {
      this.canvasManager.deleteObject(data.object_id);
    });

    // Handle cursor position updates from other users
    this.handleEvent('cursor_moved', (data) => {
      this.canvasManager.updateCursor(data.user_id, data, data.position);
    });

    // Handle presence updates
    this.handleEvent('presence_updated', (data) => {
      this.canvasManager.updatePresences(data.presences);
    });

    // Handle tool selection updates from server
    this.handleEvent('tool_selected', (data) => {
      this.canvasManager.setTool(data.tool, true); // Pass true to indicate this is from server
    });

    // Handle object lock updates from server
    this.handleEvent('object_locked', (data) => {
      this.canvasManager.updateObject(data.object);
      // Show lock indicator with user info
      if (data.user_info) {
        this.canvasManager.showLockIndicator(data.object.id, data.user_info);
      }
    });

    // Handle object unlock updates from server
    this.handleEvent('object_unlocked', (data) => {
      this.canvasManager.updateObject(data.object);
      // Remove lock indicator
      this.canvasManager.hideLockIndicator(data.object.id);
    });

    // Handle object label toggle
    this.handleEvent('toggle_object_labels', (data) => {
      console.log('[Hook] toggle_object_labels event received:', data);
      this.canvasManager.toggleObjectLabels(data.show, data.labels);
    });

    // Handle viewport restoration
    this.handleEvent('restore_viewport', (data) => {
      this.canvasManager.restoreViewport(data.x, data.y, data.zoom);
    });

    // Handle color changes from color picker
    this.handleEvent('color_changed', (data) => {
      this.canvasManager.setCurrentColor(data.color);

      // If objects are selected, update their colors
      const selectedIds = this.canvasManager.getSelectedObjectIds();
      if (selectedIds.length > 0) {
        console.log(`[Hook] Updating color of ${selectedIds.length} selected objects to ${data.color}`);

        // Update each selected object's color
        selectedIds.forEach(id => {
          this.safePushEvent('update_object_color', {
            object_id: id,
            color: data.color
          });
        });
      }
    });

    // Handle reset view command (fit all objects on screen)
    this.handleEvent('reset_view', () => {
      console.log('[Hook] reset_view event received from server');
      this.canvasManager.resetView();
    });

    // Handle layer reordering (bring to front, send to back, etc.)
    this.handleEvent('objects_reordered', (data) => {
      console.log('[Hook] objects_reordered event received:', data.objects.length, 'objects');
      this.canvasManager.reorderObjects(data.objects);
    });

    // Handle object selection from layers panel
    this.handleEvent('select_object_from_layer', (data) => {
      console.log('[Hook] select_object_from_layer event received:', data.object_id);
      this.canvasManager.selectObjectById(data.object_id);
    });

    // Handle multi-object selection (e.g., from semantic AI selection)
    this.handleEvent('select_objects', (data) => {
      console.log('[Hook] select_objects event received:', data.object_ids);
      this.canvasManager.selectObjectsByIds(data.object_ids);
    });

    // Handle error sound playback with volume boost
    this.handleEvent('play_error_sound', () => {
      console.log('[Hook] play_error_sound event received');

      // Create audio context for volume control
      const audioContext = new (window.AudioContext || window.webkitAudioContext)();
      const audio = new Audio('/sounds/sorrydave.mp3');

      // Create audio source from the audio element
      const source = audioContext.createMediaElementSource(audio);

      // Create gain node to boost volume (1.5x louder)
      const gainNode = audioContext.createGain();
      gainNode.gain.value = 1.5; // Boost volume by 50%

      // Connect: source -> gain -> destination (speakers)
      source.connect(gainNode);
      gainNode.connect(audioContext.destination);

      // Play the audio
      audio.play().catch(err => {
        console.warn('[Hook] Failed to play error sound:', err);
      });
    });

    // Setup debounced viewport saving
    this.setupViewportSaving();
  },

  /**
   * Setup debounced viewport saving after pan/zoom operations
   */
  setupViewportSaving() {
    // Debounce timeout
    let saveTimeout = null;

    // Listen to viewport changes from the canvas manager
    const saveViewport = () => {
      // Clear any pending save
      if (saveTimeout) {
        clearTimeout(saveTimeout);
      }

      // Debounce for 1 second after last pan/zoom
      saveTimeout = setTimeout(() => {
        const viewport = this.canvasManager.getViewportState();
        this.safePushEvent('save_viewport', {
          x: viewport.x,
          y: viewport.y,
          zoom: viewport.zoom
        });
      }, 1000);
    };

    // Hook into viewport changes
    this.canvasManager.on('viewport_changed', saveViewport);
  },

  /**
   * Hook lifecycle - destroyed
   */
  destroyed() {
    // Clean up CanvasManager
    if (this.canvasManager) {
      this.canvasManager.destroy();
      this.canvasManager = null;
    }
  }
};