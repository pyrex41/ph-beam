import * as PIXI from '../../vendor/pixi.min.mjs';
import { PerformanceMonitor } from './performance_monitor.js';

/**
 * CanvasManager - Standalone PixiJS Canvas Management
 *
 * Manages the PixiJS application, object rendering, and user interactions.
 * Uses an event emitter pattern to communicate with the host application.
 */
export class CanvasManager {
  constructor() {
    // PixiJS application and containers
    this.app = null;
    this.objectContainer = null;
    this.labelContainer = null; // Separate container for labels (renders on top)
    this.cursorContainer = null;

    // Object and cursor storage
    this.objects = new Map();
    this.cursors = new Map();
    this.objectLabels = new Map(); // Map of objectId -> label Text object
    this.labelsVisible = false; // Track if labels are currently visible

    // Interaction state
    this.currentUserId = null;
    this.selectedObjects = new Set(); // Changed from selectedObject to support multi-selection
    this.selectionBoxes = new Map(); // Map of objectId -> selectionBox graphics
    this.isDragging = false;
    this.dragOffsets = new Map(); // Map of objectId -> {x, y} drag offset
    this.currentTool = 'select';
    this.isCreating = false;
    this.createStart = { x: 0, y: 0 };
    this.tempObject = null;
    this.currentColor = '#000000'; // Current color from color picker

    // Rotation handle state
    this.rotationHandles = new Map(); // Map of objectId -> rotation handle graphics
    this.isRotating = false;
    this.rotatingObject = null;
    this.rotationStartAngle = 0; // Object's angle when rotation started
    this.rotationGrabAngle = 0; // Angle from object center to mouse when grab started

    // Resize handle state
    this.resizeHandles = new Map(); // Map of objectId -> resize handle graphics
    this.isResizing = false;
    this.resizingObject = null;
    this.resizeStartSize = { width: 0, height: 0 };
    this.resizeStartMousePos = { x: 0, y: 0 }; // Mouse position when resize started

    // Pan and zoom state
    this.isPanning = false;
    this.panStart = { x: 0, y: 0 };
    this.viewOffset = { x: 0, y: 0 };
    this.zoomLevel = 1;
    this.spacePressed = false;

    // Throttle tracking
    this.lastCursorUpdate = 0;
    this.lastDragUpdate = 0;
    this.lastCullUpdate = 0;

    // Viewport dimensions
    this.canvasWidth = 0;
    this.canvasHeight = 0;

    // Event listeners
    this.eventListeners = new Map();

    // Bound function references for cleanup
    this.boundHandlers = {};

    // Performance monitoring
    this.performanceMonitor = null;

    // Shared resources for cursor label optimization
    this.sharedCursorLabelStyle = null;
    this.sharedLabelBgContext = null;
  }

  /**
   * Initialize the PixiJS application
   * @param {HTMLElement} container - DOM element to attach canvas to
   * @param {string} userId - Current user ID
   */
  async initialize(container, userId) {
    this.currentUserId = userId;
    const width = container.clientWidth;
    const height = container.clientHeight;

    // Create PixiJS application (v8 API - async initialization)
    this.app = new PIXI.Application();
    await this.app.init({
      width: width,
      height: height,
      background: 0xffffff,
      antialias: true,
      resolution: window.devicePixelRatio || 1,
      autoDensity: true
    });

    // Add canvas to DOM (v8 uses app.canvas instead of app.view)
    container.appendChild(this.app.canvas);

    // Set canvas display and max-size to prevent overflow
    this.app.canvas.style.display = 'block';
    this.app.canvas.style.maxWidth = '100%';
    this.app.canvas.style.maxHeight = '100%';

    // Create main container for objects
    this.objectContainer = new PIXI.Container();
    // Disable culling for now - it was causing objects to disappear during interactions
    // this.objectContainer.cullable = true;
    this.objectContainer.isRenderGroup = true; // v8 render groups for batching
    this.app.stage.addChild(this.objectContainer);

    // Create label container (renders above objects, below cursors)
    this.labelContainer = new PIXI.Container();
    this.labelContainer.isRenderGroup = true; // v8 render groups for label batching
    this.app.stage.addChild(this.labelContainer);

    // Create cursor overlay container with render group for batching
    this.cursorContainer = new PIXI.Container();
    this.cursorContainer.isRenderGroup = true; // v8 render groups for cursor batching
    this.app.stage.addChild(this.cursorContainer);

    // Create shared TextStyle for cursor labels (performance optimization)
    this.sharedCursorLabelStyle = new PIXI.TextStyle({
      fontFamily: 'Arial',
      fontSize: 12,
      fill: 0xffffff,
      fontWeight: 'bold'
    });

    // Create shared GraphicsContext for label backgrounds (performance optimization)
    this.sharedLabelBgContext = new PIXI.GraphicsContext();

    // Store canvas dimensions for viewport culling
    this.canvasWidth = width;
    this.canvasHeight = height;

    // Setup event listeners
    this.setupEventListeners(container);

    // Initialize and start performance monitoring
    this.performanceMonitor = new PerformanceMonitor({ sampleSize: 60 });
    this.performanceMonitor.start();

    // Initial viewport culling (disabled for now)
    // this.updateVisibleObjects();
  }

  /**
   * Setup event listeners for user interactions
   * @param {HTMLElement} container - Parent container element
   */
  setupEventListeners(container) {
    const canvas = this.app.canvas;

    // Create and store bound function references for proper cleanup
    this.boundHandlers = {
      handleMouseDown: this.handleMouseDown.bind(this),
      handleMouseMove: this.handleMouseMove.bind(this),
      handleMouseUp: this.handleMouseUp.bind(this),
      handleWheel: this.handleWheel.bind(this),
      handleTouchStart: this.handleTouchStart.bind(this),
      handleTouchMove: this.handleTouchMove.bind(this),
      handleTouchEnd: this.handleTouchEnd.bind(this),
      handleKeyDown: this.handleKeyDown.bind(this),
      handleKeyUp: this.handleKeyUp.bind(this),
      handleResize: this.handleResize.bind(this)
    };

    // Mouse events
    canvas.addEventListener('mousedown', this.boundHandlers.handleMouseDown);
    // Attach move and up to window so they work even when mouse leaves canvas
    window.addEventListener('mousemove', this.boundHandlers.handleMouseMove);
    window.addEventListener('mouseup', this.boundHandlers.handleMouseUp);
    canvas.addEventListener('wheel', this.boundHandlers.handleWheel);

    // Touch events for mobile
    canvas.addEventListener('touchstart', this.boundHandlers.handleTouchStart);
    canvas.addEventListener('touchmove', this.boundHandlers.handleTouchMove);
    canvas.addEventListener('touchend', this.boundHandlers.handleTouchEnd);

    // Keyboard events
    window.addEventListener('keydown', this.boundHandlers.handleKeyDown);
    window.addEventListener('keyup', this.boundHandlers.handleKeyUp);

    // Window resize
    window.addEventListener('resize', this.boundHandlers.handleResize);

    // ResizeObserver for container size changes (more reliable than window resize)
    this.resizeObserver = new ResizeObserver(() => {
      this.handleResize();
    });
    this.resizeObserver.observe(container);
  }

  /**
   * Event emitter pattern - register event listener
   * @param {string} event - Event name
   * @param {Function} callback - Callback function
   */
  on(event, callback) {
    if (!this.eventListeners.has(event)) {
      this.eventListeners.set(event, []);
    }
    this.eventListeners.get(event).push(callback);
  }

  /**
   * Emit an event to all registered listeners
   * @param {string} event - Event name
   * @param {*} data - Event data
   */
  emit(event, data) {
    const listeners = this.eventListeners.get(event);
    if (listeners) {
      listeners.forEach(callback => callback(data));
    }
  }

  /**
   * Create a visual object on the canvas
   * @param {Object} objectData - Object data from server
   */
  createObject(objectData) {
    // Skip if object already exists
    if (this.objects.has(objectData.id)) {
      return;
    }

    // Clear temp object if present (optimistic UI - replace temp with real object)
    if (this.tempObject) {
      this.objectContainer.removeChild(this.tempObject);
      this.tempObject.destroy();
      this.tempObject = null;
    }

    let pixiObject;
    const data = objectData.data ? JSON.parse(objectData.data) : {};
    const position = objectData.position || { x: 0, y: 0 };

    switch (objectData.type) {
      case 'rectangle':
        pixiObject = this.createRectangle(position, data);
        break;
      case 'circle':
        pixiObject = this.createCircle(position, data);
        break;
      case 'text':
        pixiObject = this.createText(position, data);
        break;
      default:
        console.warn('Unknown object type:', objectData.type);
        return;
    }

    // Store object reference and lock information
    pixiObject.objectId = objectData.id;
    pixiObject.lockedBy = objectData.locked_by;
    pixiObject.eventMode = 'static'; // Replaces interactive = true

    // Set cursor and visual appearance based on lock status
    this.updateObjectAppearance(pixiObject);

    // Add event listeners for interaction
    pixiObject.on('pointerdown', this.onObjectPointerDown.bind(this));
    pixiObject.on('pointermove', this.onObjectPointerMove.bind(this));
    pixiObject.on('pointerup', this.onObjectPointerUp.bind(this));

    this.objects.set(objectData.id, pixiObject);
    this.objectContainer.addChild(pixiObject);

    // Create label for this object if labels are currently visible
    if (this.labelsVisible) {
      this.createLabelForObject(objectData.id, pixiObject);
    }
  }

  /**
   * Create a rectangle shape
   * @param {Object} position - {x, y} position
   * @param {Object} data - Shape data
   * @returns {PIXI.Graphics}
   */
  createRectangle(position, data) {
    const graphics = new PIXI.Graphics();
    const width = data.width || 100;
    const height = data.height || 100;
    // Check for both 'fill' and 'color' fields for backwards compatibility
    const fillColor = data.fill || data.color || '#3b82f6';
    const fill = parseInt(fillColor.replace('#', '0x'));
    const strokeColor = data.stroke || data.color || '#1e40af';
    const stroke = parseInt(strokeColor.replace('#', '0x'));
    const strokeWidth = data.stroke_width || 2;

    // v8 Graphics API: shape → fill → stroke
    graphics.rect(0, 0, width, height)
      .fill(fill)
      .stroke({ width: strokeWidth, color: stroke });

    graphics.x = position.x;
    graphics.y = position.y;

    // Apply rotation if specified (Task 8: rotate_object support)
    if (data.rotation !== undefined && data.rotation !== 0) {
      this.applyRotation(graphics, data.rotation, data.pivot_point, width, height);
    } else {
      // Initialize pivot to center even if not rotated (prevents null pivot errors)
      graphics.pivot.set(width / 2, height / 2);
    }

    // Apply opacity if specified (Task 8: change_style support)
    if (data.opacity !== undefined) {
      graphics.alpha = data.opacity;
    }

    return graphics;
  }

  /**
   * Create a circle shape
   * @param {Object} position - {x, y} position
   * @param {Object} data - Shape data
   * @returns {PIXI.Graphics}
   */
  createCircle(position, data) {
    const graphics = new PIXI.Graphics();
    const radius = (data.width || 100) / 2;
    // Check for both 'fill' and 'color' fields for backwards compatibility
    const fillColor = data.fill || data.color || '#3b82f6';
    const fill = parseInt(fillColor.replace('#', '0x'));
    const strokeColor = data.stroke || data.color || '#1e40af';
    const stroke = parseInt(strokeColor.replace('#', '0x'));
    const strokeWidth = data.stroke_width || 2;

    // v8 Graphics API: shape → fill → stroke
    graphics.circle(radius, radius, radius)
      .fill(fill)
      .stroke({ width: strokeWidth, color: stroke });

    graphics.x = position.x;
    graphics.y = position.y;

    // Apply rotation if specified (Task 8: rotate_object support)
    if (data.rotation !== undefined && data.rotation !== 0) {
      this.applyRotation(graphics, data.rotation, data.pivot_point, radius * 2, radius * 2);
    } else {
      // Initialize pivot to center even if not rotated (prevents null pivot errors)
      graphics.pivot.set(radius, radius);
    }

    // Apply opacity if specified (Task 8: change_style support)
    if (data.opacity !== undefined) {
      graphics.alpha = data.opacity;
    }

    return graphics;
  }

  /**
   * Create text object
   * @param {Object} position - {x, y} position
   * @param {Object} data - Text data
   * @returns {PIXI.Text}
   */
  createText(position, data) {
    const style = new PIXI.TextStyle({
      fontFamily: data.font_family || 'Arial',
      fontSize: data.font_size || 16,
      fill: data.color || '#000000',
      align: data.align || 'left',
      // Task 8: Support bold and italic from update_text command
      fontWeight: data.bold ? 'bold' : 'normal',
      fontStyle: data.italic ? 'italic' : 'normal'
    });

    const text = new PIXI.Text(data.text || 'Text', style);
    text.x = position.x;
    text.y = position.y;

    // Apply rotation if specified (Task 8: rotate_object support)
    const bounds = text.getBounds();
    if (data.rotation !== undefined && data.rotation !== 0) {
      this.applyRotation(text, data.rotation, data.pivot_point, bounds.width, bounds.height);
    } else {
      // Initialize pivot to center even if not rotated (prevents null pivot errors)
      text.pivot.set(bounds.width / 2, bounds.height / 2);
    }

    // Apply opacity if specified (Task 8: change_style support)
    if (data.opacity !== undefined) {
      text.alpha = data.opacity;
    }

    return text;
  }

  /**
   * Apply rotation to a PixiJS object based on pivot point
   * @param {PIXI.DisplayObject} object - Object to rotate
   * @param {number} angle - Rotation angle in degrees
   * @param {string} pivotPoint - Pivot point (center, top-left, top-right, bottom-left, bottom-right)
   * @param {number} width - Object width
   * @param {number} height - Object height
   */
  applyRotation(object, angle, pivotPoint = 'center', width, height) {
    // Set rotation angle
    object.angle = angle;

    // Set pivot based on pivot_point
    // Note: We don't adjust position here - PixiJS handles rotation around pivot correctly
    // The object's x,y position represents where the pivot point is in world coordinates
    switch (pivotPoint) {
      case 'top-left':
        object.pivot.set(0, 0);
        break;
      case 'top-right':
        object.pivot.set(width, 0);
        break;
      case 'bottom-left':
        object.pivot.set(0, height);
        break;
      case 'bottom-right':
        object.pivot.set(width, height);
        break;
      case 'center':
      default:
        object.pivot.set(width / 2, height / 2);
        break;
    }
  }

  /**
   * Show visual feedback animation for AI-modified objects (Task 8)
   * @param {number} objectId - ID of the modified object
   */
  showAIFeedback(objectId) {
    const pixiObject = this.objects.get(objectId);
    if (!pixiObject) return;

    // Use local bounds (container-relative) instead of global bounds
    const bounds = pixiObject.getLocalBounds();
    const highlight = new PIXI.Graphics();

    // Draw a glowing border around the object
    highlight.rect(
      -4,
      -4,
      bounds.width + 8,
      bounds.height + 8
    ).stroke({ width: 3, color: 0x10b981 }); // Green highlight

    // Position highlight at object's position
    highlight.x = pixiObject.x;
    highlight.y = pixiObject.y;

    // Match rotation and pivot of the object so highlight rotates with it
    highlight.angle = pixiObject.angle;
    highlight.pivot.set(pixiObject.pivot.x, pixiObject.pivot.y);

    this.objectContainer.addChild(highlight);

    // Animate the highlight (fade out and remove)
    let alpha = 1.0;
    const fadeInterval = setInterval(() => {
      alpha -= 0.05;
      highlight.alpha = alpha;

      if (alpha <= 0) {
        clearInterval(fadeInterval);
        if (highlight.parent) {
          highlight.parent.removeChild(highlight);
        }
        highlight.destroy();
      }
    }, 50);
  }

  /**
   * Update an existing object
   * @param {Object} objectData - Object data from server
   */
  updateObject(objectData) {
    const pixiObject = this.objects.get(objectData.id);
    if (!pixiObject) {
      // Object doesn't exist, create it
      this.createObject(objectData);
      return;
    }

    // Skip updates for objects currently being dragged by this user
    if (this.isDragging && this.selectedObjects.has(pixiObject)) {
      return;
    }

    // Skip updates for objects currently being rotated by this user
    if (this.isRotating && this.rotatingObject === pixiObject) {
      return;
    }

    // Skip updates for objects currently being resized by this user
    if (this.isResizing && this.resizingObject === pixiObject) {
      return;
    }

    // Update position if changed
    if (objectData.position) {
      pixiObject.x = objectData.position.x;
      pixiObject.y = objectData.position.y;

      // Update label position for this object if labels are visible
      if (this.labelsVisible) {
        const label = this.objectLabels.get(objectData.id);
        if (label) {
          // Use local bounds and object position (same as selection boxes)
          const bounds = pixiObject.getLocalBounds();
          label.container.x = pixiObject.x + bounds.width / 2 - label.container.width / 2;
          label.container.y = pixiObject.y - label.container.height - 5;
        }
      }
    }

    // Update lock status
    if (objectData.locked_by !== undefined) {
      pixiObject.lockedBy = objectData.locked_by;
      this.updateObjectAppearance(pixiObject);
    }

    // For more complex updates, recreate the object
    if (objectData.data) {
      this.deleteObject(objectData.id);
      this.createObject(objectData);

      // Show AI feedback for data changes (Task 8)
      this.showAIFeedback(objectData.id);

      // Update label for recreated object if labels are visible
      this.updateObjectLabels();
    }
  }

  /**
   * Update the visual appearance of an object based on its lock status
   * @param {PIXI.DisplayObject} pixiObject - The object to update
   */
  updateObjectAppearance(pixiObject) {
    if (pixiObject.lockedBy && pixiObject.lockedBy !== this.currentUserId) {
      // Object is locked by another user - gray it out and change cursor
      pixiObject.alpha = 0.5;
      pixiObject.cursor = 'not-allowed';
    } else {
      // Object is unlocked or locked by current user - normal appearance
      pixiObject.alpha = 1.0;
      pixiObject.cursor = 'pointer';
    }
  }

  /**
   * Delete an object from the canvas
   * @param {string} objectId - Object ID
   */
  deleteObject(objectId) {
    const pixiObject = this.objects.get(objectId);
    if (pixiObject) {
      this.objectContainer.removeChild(pixiObject);
      pixiObject.destroy();
      this.objects.delete(objectId);
    }

    // Also remove the label if it exists
    const label = this.objectLabels.get(objectId);
    if (label) {
      this.labelContainer.removeChild(label.container);
      label.container.destroy();
      this.objectLabels.delete(objectId);
    }
  }

  /**
   * Update cursor position for another user
   * @param {string} userId - User ID
   * @param {Object} userData - User metadata
   * @param {Object} position - {x, y} cursor position
   */
  updateCursor(userId, userData, position) {
    // Don't show cursor if position is invalid or at initial (0, 0)
    if (!position || typeof position.x !== 'number' || typeof position.y !== 'number') {
      return;
    }

    // Don't show cursor at origin (0, 0) - likely user hasn't moved yet
    if (position.x === 0 && position.y === 0) {
      const existingCursor = this.cursors.get(userId);
      if (existingCursor && (existingCursor.x !== 0 || existingCursor.y !== 0)) {
        // User actually moved to origin, allow it
      } else {
        return;
      }
    }

    let cursorGroup = this.cursors.get(userId);

    if (!cursorGroup) {
      // Create new cursor with label
      cursorGroup = new PIXI.Container();

      // Cursor pointer (arrow shape)
      const cursor = new PIXI.Graphics();
      const cursorColor = parseInt(userData.color?.replace('#', '0x') || '0x3b82f6');
      // v8 Graphics API: use poly() for custom shapes
      cursor.poly([
        0, 0,
        0, 20,
        6, 15,
        10, 22,
        14, 19,
        10, 12,
        18, 12
      ]).fill(cursorColor);

      // User email/name label using shared TextStyle
      const displayName = userData.email || userData.name || 'User';
      const label = new PIXI.Text({
        text: displayName,
        style: this.sharedCursorLabelStyle // Reuse shared style for performance
      });
      label.x = 25;
      label.y = 6;

      // Create label background using shared GraphicsContext
      const labelBg = new PIXI.Graphics(this.sharedLabelBgContext);
      // v8 Graphics API: shape → fill
      labelBg.roundRect(0, 0, label.width + 10, 24, 4)
        .fill(cursorColor);
      labelBg.x = 20;
      labelBg.y = 0;

      cursorGroup.addChild(cursor);
      cursorGroup.addChild(labelBg);
      cursorGroup.addChild(label);

      this.cursors.set(userId, cursorGroup);
      this.cursorContainer.addChild(cursorGroup);
    }

    // Update position
    cursorGroup.x = position.x;
    cursorGroup.y = position.y;
  }

  /**
   * Update presence list
   * @param {Object} presences - Presence data from server
   */
  updatePresences(presences) {
    // Remove cursors for users who left
    this.cursors.forEach((cursor, userId) => {
      if (!presences[userId]) {
        this.cursorContainer.removeChild(cursor);
        cursor.destroy();
        this.cursors.delete(userId);
      }
    });

    // Update or create cursors for all users except self
    Object.entries(presences).forEach(([userId, data]) => {
      // Skip current user
      if (userId === this.currentUserId) return;

      const metas = data.metas[0]; // Get first meta (most recent)
      if (metas && metas.cursor) {
        this.updateCursor(userId, metas, metas.cursor);
      }
    });
  }

  /**
   * Set the current tool
   * @param {string} tool - Tool name
   * @param {boolean} fromServer - Whether this change came from the server (default: false)
   */
  setTool(tool, fromServer = false) {
    // Prevent feedback loop: don't emit if tool hasn't changed or if update is from server
    if (this.currentTool === tool || fromServer) {
      this.currentTool = tool;
      return;
    }

    this.currentTool = tool;
    this.emit('tool_changed', { tool });
  }

  /**
   * Handle mouse down events
   * @param {MouseEvent} event
   */
  handleMouseDown(event) {
    console.log('[CanvasManager] handleMouseDown, isDragging:', this.isDragging);

    // If we're already dragging (object was clicked via PixiJS event), don't process this event
    if (this.isDragging) {
      console.log('[CanvasManager] Already dragging, skipping handleMouseDown');
      return;
    }

    const position = this.getMousePosition(event);

    // Start panning with spacebar+click or middle mouse (NOT shift anymore - used for multi-select)
    if (this.spacePressed || event.button === 1) {
      console.log('[CanvasManager] Starting pan, setting isPanning=true');
      this.isPanning = true;
      this.panStart = { x: event.clientX, y: event.clientY };
      this.app.canvas.style.cursor = 'grabbing';
      event.preventDefault();
      return;
    }

    // Check if clicking on canvas (not on an object)
    const clickedObject = this.findObjectAt(position);
    console.log('[CanvasManager] Clicked object:', clickedObject?.objectId || 'none');

    if (this.currentTool === 'select') {
      if (clickedObject) {
        // This shouldn't happen if PixiJS events work, but keep as fallback
        console.log('[CanvasManager] Object clicked via DOM event (fallback)');
        // Shift+click = toggle selection, regular click = replace selection
        if (event.shiftKey) {
          this.toggleSelection(clickedObject);
        } else {
          this.setSelection(clickedObject);
        }
      } else {
        // Clicking on empty space = clear selection (unless shift-clicking)
        console.log('[CanvasManager] Empty space clicked, clearing selection');
        if (!event.shiftKey) {
          this.clearSelection();
        }
      }
    } else if (this.currentTool === 'delete') {
      if (clickedObject) {
        this.emit('delete_object', { object_id: clickedObject.objectId });
      }
    } else if (this.currentTool === 'rectangle' || this.currentTool === 'circle') {
      // Start creating shape with drag
      this.isCreating = true;
      this.createStart = position;
      this.createTempObject(this.currentTool, position);
    } else if (this.currentTool === 'text') {
      // Create text at click position
      const text = prompt('Enter text:', 'Text');
      if (text) {
        this.emit('create_object', {
          type: 'text',
          position: position,
          data: {
            text: text,
            font_size: 16,
            color: this.currentColor,
            font_family: 'Arial'
          }
        });
      }
      // Switch back to select tool after creating text
      this.setTool('select');
    }
  }

  /**
   * Handle mouse move events
   * @param {MouseEvent} event
   */
  handleMouseMove(event) {
    // Safety check for null/undefined events or events with null/undefined coordinates
    // Wrap in try-catch since event.clientX/clientY might be getters that throw
    try {
      if (!event) {
        console.warn('[CanvasManager] handleMouseMove called with null/undefined event');
        return;
      }

      // Test accessing clientX/clientY - these might be getters that throw
      const testX = event.clientX;
      const testY = event.clientY;

      if (typeof testX !== 'number' || typeof testY !== 'number') {
        console.warn('[CanvasManager] handleMouseMove called with invalid coordinates:', { clientX: testX, clientY: testY, event });
        return;
      }
    } catch (error) {
      console.warn('[CanvasManager] handleMouseMove caught error accessing event properties:', error, event);
      return;
    }

    const position = this.getMousePosition(event);

    // Update cursor position for other users (throttled to avoid spam)
    if (!this.isPanning && !this.isRotating && !this.isResizing && (!this.lastCursorUpdate || Date.now() - this.lastCursorUpdate > 50)) {
      this.emit('cursor_move', { position });
      this.lastCursorUpdate = Date.now();
    }

    if (this.isPanning) {
      // Pan the view using screen coordinates for smooth panning
      const dx = event.clientX - this.panStart.x;
      const dy = event.clientY - this.panStart.y;

      this.viewOffset.x += dx;
      this.viewOffset.y += dy;
      this.objectContainer.x = this.viewOffset.x;
      this.objectContainer.y = this.viewOffset.y;
      this.labelContainer.x = this.viewOffset.x;
      this.labelContainer.y = this.viewOffset.y;
      this.cursorContainer.x = this.viewOffset.x;
      this.cursorContainer.y = this.viewOffset.y;

      this.panStart = { x: event.clientX, y: event.clientY };

      // Emit viewport changed event for saving
      this.emit('viewport_changed');

      // Debounced culling during pan (disabled for now)
      // this.debouncedCullUpdate();
    } else if (this.isRotating && this.rotatingObject) {
      // Calculate rotation angle using relative rotation from grab point
      const obj = this.rotatingObject;

      // Calculate current angle from object center to mouse
      const dx = position.x - obj.x;
      const dy = position.y - obj.y;
      const currentAngle = Math.atan2(dy, dx) * (180 / Math.PI) + 90;

      // Calculate the delta from the initial grab angle
      let angleDelta = currentAngle - this.rotationGrabAngle;

      // Handle angle wrapping (if delta crosses 0/360 boundary)
      if (angleDelta > 180) angleDelta -= 360;
      if (angleDelta < -180) angleDelta += 360;

      // Apply delta to the object's starting rotation
      let angle = this.rotationStartAngle + angleDelta;

      // Snap to 15-degree increments if Shift key is held
      if (event.shiftKey) {
        angle = Math.round(angle / 15) * 15;
      }

      // Normalize angle to 0-360 range
      if (angle < 0) angle += 360;
      if (angle >= 360) angle -= 360;

      // Update object rotation
      obj.angle = angle;

      // Update selection box to match rotation
      const selectionBox = this.selectionBoxes.get(obj.objectId);
      if (selectionBox) {
        selectionBox.angle = angle;
      }
    } else if (this.isResizing && this.resizingObject) {
      // Calculate new size using relative mouse movement
      const obj = this.resizingObject;

      // Calculate how much the mouse has moved from initial grab position
      const mouseDx = position.x - this.resizeStartMousePos.x;
      const mouseDy = position.y - this.resizeStartMousePos.y;

      // For rotated objects, transform mouse delta into object's local space
      const angleRad = -(obj.angle * Math.PI / 180); // Negative to reverse rotation
      const localDx = mouseDx * Math.cos(angleRad) - mouseDy * Math.sin(angleRad);
      const localDy = mouseDx * Math.sin(angleRad) + mouseDy * Math.cos(angleRad);

      // Apply delta * 2 to starting size (movement affects both sides from center)
      const newWidth = Math.max(20, this.resizeStartSize.width + localDx * 2);
      const newHeight = Math.max(20, this.resizeStartSize.height + localDy * 2);

      // Store the new size temporarily (will be saved to server on mouseup)
      obj.tempWidth = newWidth;
      obj.tempHeight = newHeight;

      // Update selection box to match new size
      this.updateSelectionBoxes();
    } else if (this.isCreating) {
      // Update temp object while creating
      this.updateTempObject(position);
    } else if (this.isDragging && this.selectedObjects.size > 0) {
      // Move all selected objects together (Task 19: multi-object dragging)
      this.selectedObjects.forEach(obj => {
        const offset = this.dragOffsets.get(obj.objectId);
        if (offset) {
          const newX = position.x + offset.x;
          const newY = position.y + offset.y;

          obj.x = newX;
          obj.y = newY;
        }
      });

      // Update all selection boxes
      this.updateSelectionBoxes();

      // Update all object labels to follow dragged objects
      this.updateObjectLabels();

      // Broadcast positions for all selected objects during drag (throttled to avoid spam)
      if (!this.lastDragUpdate || Date.now() - this.lastDragUpdate > 50) {
        this.selectedObjects.forEach(obj => {
          this.emit('update_object', {
            object_id: obj.objectId,
            position: { x: obj.x, y: obj.y }
          });
        });
        this.lastDragUpdate = Date.now();
      }
    }
  }

  /**
   * Handle mouse up events
   * @param {MouseEvent} event
   */
  handleMouseUp(event) {
    // Handle panning state first (doesn't need mouse position)
    if (this.isPanning) {
      console.log('[CanvasManager] Panning ended, resetting isPanning flag');
      this.isPanning = false;
      // Restore cursor based on spacebar state
      this.app.canvas.style.cursor = this.spacePressed ? 'grab' : 'default';
      return; // Early return after handling pan
    }

    // Handle rotation finish
    if (this.isRotating && this.rotatingObject) {
      const obj = this.rotatingObject;

      // Get the object's current rotation in the data
      const objectData = Array.from(this.objects.entries()).find(([id, pixiObj]) => pixiObj === obj);
      if (objectData) {
        const [objectId, pixiObj] = objectData;

        // Emit update with new rotation angle
        this.emit('update_object', {
          object_id: objectId,
          data: {
            rotation: Math.round(obj.angle) // Round to nearest degree
          }
        });
      }

      // Reset rotation handle cursor
      const handle = this.rotationHandles.get(obj.objectId);
      if (handle) {
        handle.cursor = 'grab';
      }

      this.isRotating = false;
      this.rotatingObject = null;
      return;
    }

    // Handle resize finish
    if (this.isResizing && this.resizingObject) {
      const obj = this.resizingObject;

      // Get the object's ID and current data
      const objectData = Array.from(this.objects.entries()).find(([id, pixiObj]) => pixiObj === obj);
      if (objectData) {
        const [objectId, pixiObj] = objectData;

        // Emit update with new size
        this.emit('update_object', {
          object_id: objectId,
          data: {
            width: Math.round(obj.tempWidth || this.resizeStartSize.width),
            height: Math.round(obj.tempHeight || this.resizeStartSize.height)
          }
        });
      }

      // Reset resize handle cursor
      const handle = this.resizeHandles.get(obj.objectId);
      if (handle) {
        handle.cursor = 'nwse-resize';
      }

      this.isResizing = false;
      this.resizingObject = null;
      return;
    }

    // Only get mouse position if we need it
    const position = this.getMousePosition(event);

    if (this.isCreating) {
      // Finalize object creation
      this.finalizeTempObject(position);
    } else if (this.isDragging && this.selectedObjects.size > 0) {
      // Send final update to server after dragging all selected objects
      this.selectedObjects.forEach(obj => {
        this.emit('update_object', {
          object_id: obj.objectId,
          position: {
            x: obj.x,
            y: obj.y
          }
        });
      });
      this.isDragging = false;
    }
  }

  /**
   * Handle mouse wheel for zoom and pan
   * @param {WheelEvent} event
   */
  handleWheel(event) {
    event.preventDefault();

    // Ctrl/Cmd+wheel = zoom, otherwise pan
    if (event.ctrlKey || event.metaKey) {
      // Zoom
      const delta = event.deltaY > 0 ? 0.9 : 1.1;
      const newZoom = Math.min(Math.max(this.zoomLevel * delta, 0.1), 5);

      this.zoomLevel = newZoom;
      this.objectContainer.scale.set(newZoom, newZoom);
      this.labelContainer.scale.set(newZoom, newZoom);
      this.cursorContainer.scale.set(newZoom, newZoom);

      // Emit viewport changed event for saving
      this.emit('viewport_changed');

      // Debounced culling during zoom (disabled for now)
      // this.debouncedCullUpdate();
    } else {
      // Pan with trackpad scroll or mouse wheel
      this.viewOffset.x -= event.deltaX;
      this.viewOffset.y -= event.deltaY;
      this.objectContainer.x = this.viewOffset.x;
      this.objectContainer.y = this.viewOffset.y;
      this.labelContainer.x = this.viewOffset.x;
      this.labelContainer.y = this.viewOffset.y;
      this.cursorContainer.x = this.viewOffset.x;
      this.cursorContainer.y = this.viewOffset.y;

      // Emit viewport changed event for saving
      this.emit('viewport_changed');

      // Debounced culling during pan (disabled for now)
      // this.debouncedCullUpdate();
    }
  }

  /**
   * Handle touch events
   */
  handleTouchStart(event) {
    if (event.touches.length === 1) {
      this.handleMouseDown(event.touches[0]);
    }
  }

  handleTouchMove(event) {
    if (event.touches.length === 1) {
      this.handleMouseMove(event.touches[0]);
    }
  }

  handleTouchEnd(event) {
    this.handleMouseUp(event);
  }

  /**
   * Handle keyboard events
   */
  handleKeyDown(event) {
    // Handle spacebar for panning
    if (event.code === 'Space' && !this.spacePressed) {
      // Don't handle spacebar if user is typing in an input
      if (event.target.tagName === 'INPUT' || event.target.tagName === 'TEXTAREA') {
        return;
      }
      event.preventDefault();
      this.spacePressed = true;
      if (!this.isPanning) {
        this.app.canvas.style.cursor = 'grab';
      }
      return;
    }

    // Don't handle keyboard shortcuts if user is typing in an input
    if (event.target.tagName === 'INPUT' || event.target.tagName === 'TEXTAREA') {
      return;
    }

    switch (event.key.toLowerCase()) {
      case 'delete':
      case 'backspace':
        if (this.selectedObjects.size > 0) {
          event.preventDefault();
          // Delete all selected objects
          this.selectedObjects.forEach(obj => {
            this.emit('delete_object', { object_id: obj.objectId });
          });
          this.clearSelection();
        }
        break;
      case 'escape':
        this.clearSelection();
        this.setTool('select');
        break;
      case 'r':
        this.setTool('rectangle');
        break;
      case 'c':
        this.setTool('circle');
        break;
      case 't':
        this.setTool('text');
        break;
      case 'd':
        this.setTool('delete');
        break;
      case 's':
        this.setTool('select');
        break;
    }
  }

  handleKeyUp(event) {
    // Handle spacebar release
    if (event.code === 'Space') {
      this.spacePressed = false;
      if (!this.isPanning) {
        this.app.canvas.style.cursor = 'default';
      }
    }
  }

  /**
   * Create temporary object for visual feedback during creation
   * @param {string} type - Object type
   * @param {Object} position - {x, y} position
   */
  createTempObject(type, position) {
    if (this.tempObject) {
      this.objectContainer.removeChild(this.tempObject);
      this.tempObject.destroy();
    }

    this.tempObject = new PIXI.Graphics();
    this.tempObject.x = position.x;
    this.tempObject.y = position.y;
    this.objectContainer.addChild(this.tempObject);
  }

  /**
   * Update temporary object during creation
   * @param {Object} currentPosition - {x, y} current position
   */
  updateTempObject(currentPosition) {
    if (!this.tempObject || !this.isCreating) return;

    const width = currentPosition.x - this.createStart.x;
    const height = currentPosition.y - this.createStart.y;

    this.tempObject.clear();

    // v8 Graphics API: shape → fill → stroke
    if (this.currentTool === 'rectangle') {
      this.tempObject.rect(0, 0, width, height)
        .fill({ color: 0x3b82f6, alpha: 0.3 })
        .stroke({ width: 2, color: 0x1e40af });
    } else if (this.currentTool === 'circle') {
      const radius = Math.max(Math.abs(width), Math.abs(height)) / 2;
      this.tempObject.circle(width / 2, height / 2, radius)
        .fill({ color: 0x3b82f6, alpha: 0.3 })
        .stroke({ width: 2, color: 0x1e40af });
    }
  }

  /**
   * Finalize temporary object creation
   * @param {Object} endPosition - {x, y} end position
   */
  finalizeTempObject(endPosition) {
    if (!this.tempObject || !this.isCreating) return;

    const width = Math.abs(endPosition.x - this.createStart.x);
    const height = Math.abs(endPosition.y - this.createStart.y);

    // Only create if size is reasonable (at least 10px)
    if (width > 10 && height > 10) {
      // Calculate top-left corner
      const topLeft = {
        x: Math.min(this.createStart.x, endPosition.x),
        y: Math.min(this.createStart.y, endPosition.y)
      };

      if (this.currentTool === 'rectangle') {
        // Objects have center pivot, so position represents center point
        const position = {
          x: topLeft.x + width / 2,
          y: topLeft.y + height / 2
        };

        this.emit('create_object', {
          type: 'rectangle',
          position: position,
          data: {
            width: width,
            height: height,
            fill: this.currentColor,
            stroke: this.currentColor,
            stroke_width: 2
          }
        });
      } else if (this.currentTool === 'circle') {
        const radius = Math.max(width, height) / 2;

        // Objects have center pivot, so position represents center point
        // Use width/2 and height/2 to match temp object positioning during drag
        const position = {
          x: topLeft.x + width / 2,
          y: topLeft.y + height / 2
        };

        this.emit('create_object', {
          type: 'circle',
          position: position,
          data: {
            width: radius * 2,
            fill: this.currentColor,
            stroke: this.currentColor,
            stroke_width: 2
          }
        });
      }

      // Keep temp object visible (optimistic UI)
      // It will be removed when the real object is created by the backend
      // Make it slightly more opaque to show it's "pending"
      this.tempObject.alpha = 0.7;
    } else {
      // Size too small, remove temp object immediately
      this.objectContainer.removeChild(this.tempObject);
      this.tempObject.destroy();
      this.tempObject = null;
    }

    // Reset creating flag
    this.isCreating = false;
  }

  /**
   * Find object at given position
   * @param {Object} position - {x, y} position
   * @returns {PIXI.DisplayObject|null}
   */
  findObjectAt(position) {
    // Check objects in reverse order (top to bottom)
    const objectsArray = Array.from(this.objects.values()).reverse();

    for (const obj of objectsArray) {
      const rect = obj.getBounds();
      if (
        position.x >= rect.x &&
        position.x <= rect.x + rect.width &&
        position.y >= rect.y &&
        position.y <= rect.y + rect.height
      ) {
        return obj;
      }
    }

    return null;
  }

  /**
   * Clear all object selections
   */
  clearSelection() {
    // Unlock all selected objects
    this.selectedObjects.forEach(obj => {
      this.emit('unlock_object', { object_id: obj.objectId });
    });

    // Remove all selection boxes
    this.selectionBoxes.forEach((box, objectId) => {
      if (box.parent) {
        box.parent.removeChild(box);
      }
      box.destroy({ children: true });
    });

    // Remove all rotation handles
    this.rotationHandles.forEach((handle, objectId) => {
      if (handle.parent) {
        handle.parent.removeChild(handle);
      }
      handle.destroy({ children: true });
    });

    // Remove all resize handles
    this.resizeHandles.forEach((handle, objectId) => {
      if (handle.parent) {
        handle.parent.removeChild(handle);
      }
      handle.destroy({ children: true });
    });

    this.selectedObjects.clear();
    this.selectionBoxes.clear();
    this.rotationHandles.clear();
    this.resizeHandles.clear();
  }

  /**
   * Set selection to a single object (clears previous selection)
   * @param {PIXI.DisplayObject} object - Object to select
   */
  setSelection(object) {
    // Clear previous selection
    this.clearSelection();

    // Add to selection
    this.selectedObjects.add(object);

    // Lock the object for editing
    this.emit('lock_object', { object_id: object.objectId });

    // Create selection box
    this.createSelectionBox(object);
  }

  /**
   * Toggle selection of an object (for Shift+click multi-selection)
   * @param {PIXI.DisplayObject} object - Object to toggle
   */
  toggleSelection(object) {
    if (this.selectedObjects.has(object)) {
      // Deselect
      this.selectedObjects.delete(object);
      this.emit('unlock_object', { object_id: object.objectId });

      // Remove selection box
      const box = this.selectionBoxes.get(object.objectId);
      if (box) {
        if (box.parent) {
          box.parent.removeChild(box);
        }
        box.destroy({ children: true });
        this.selectionBoxes.delete(object.objectId);
      }

      // Remove rotation handle
      const rotationHandle = this.rotationHandles.get(object.objectId);
      if (rotationHandle) {
        if (rotationHandle.parent) {
          rotationHandle.parent.removeChild(rotationHandle);
        }
        rotationHandle.destroy({ children: true });
        this.rotationHandles.delete(object.objectId);
      }

      // Remove resize handle
      const resizeHandle = this.resizeHandles.get(object.objectId);
      if (resizeHandle) {
        if (resizeHandle.parent) {
          resizeHandle.parent.removeChild(resizeHandle);
        }
        resizeHandle.destroy({ children: true });
        this.resizeHandles.delete(object.objectId);
      }
    } else {
      // Add to selection
      this.selectedObjects.add(object);
      this.emit('lock_object', { object_id: object.objectId });
      this.createSelectionBox(object);
    }
  }

  /**
   * Create a selection box for an object
   * @param {PIXI.DisplayObject} object - Object to create selection box for
   */
  createSelectionBox(object) {
    // Remove any existing selection box for this object first
    const existingBox = this.selectionBoxes.get(object.objectId);
    if (existingBox) {
      this.objectContainer.removeChild(existingBox);
      existingBox.destroy();
      this.selectionBoxes.delete(object.objectId);
    }

    // Remove existing rotation handle
    const existingRotationHandle = this.rotationHandles.get(object.objectId);
    if (existingRotationHandle) {
      this.objectContainer.removeChild(existingRotationHandle);
      existingRotationHandle.destroy();
      this.rotationHandles.delete(object.objectId);
    }

    // Remove existing resize handle
    const existingResizeHandle = this.resizeHandles.get(object.objectId);
    if (existingResizeHandle) {
      this.objectContainer.removeChild(existingResizeHandle);
      existingResizeHandle.destroy();
      this.resizeHandles.delete(object.objectId);
    }

    const selectionBox = new PIXI.Graphics();

    // Use local bounds (container-relative) instead of global bounds
    const bounds = object.getLocalBounds();

    // v8 Graphics API: shape → stroke (no fill for selection box)
    selectionBox.rect(
      -2,
      -2,
      bounds.width + 4,
      bounds.height + 4
    ).stroke({ width: 2, color: 0x3b82f6 });

    // Position selection box at object's position
    selectionBox.x = object.x;
    selectionBox.y = object.y;

    // Match rotation and pivot of the object so selection box rotates with it
    selectionBox.angle = object.angle;
    selectionBox.pivot.set(object.pivot.x, object.pivot.y);

    this.objectContainer.addChild(selectionBox);
    this.selectionBoxes.set(object.objectId, selectionBox);

    // Create rotation handle at top-right corner
    const rotationHandle = new PIXI.Graphics();

    // Draw circle with white fill and blue border
    rotationHandle.circle(0, 0, 10)
      .fill({ color: 0xffffff })
      .stroke({ width: 2, color: 0x3b82f6 });

    // Draw rotation arrow icon (curved arrow)
    const arrowRadius = 4;
    rotationHandle.arc(0, 0, arrowRadius, -Math.PI * 0.75, Math.PI * 0.25)
      .stroke({ width: 1.5, color: 0x3b82f6 });

    // Arrow head
    rotationHandle.moveTo(arrowRadius * Math.cos(Math.PI * 0.25), arrowRadius * Math.sin(Math.PI * 0.25))
      .lineTo(arrowRadius * Math.cos(Math.PI * 0.25) + 2, arrowRadius * Math.sin(Math.PI * 0.25) - 2)
      .moveTo(arrowRadius * Math.cos(Math.PI * 0.25), arrowRadius * Math.sin(Math.PI * 0.25))
      .lineTo(arrowRadius * Math.cos(Math.PI * 0.25) + 2, arrowRadius * Math.sin(Math.PI * 0.25) + 1)
      .stroke({ width: 1.5, color: 0x3b82f6 });

    // Position at top-right corner, accounting for object rotation
    const rotLocalX = bounds.width / 2 + 2;
    const rotLocalY = -bounds.height / 2 - 2;
    const rotAngleRad = object.angle * Math.PI / 180;
    const rotRotatedX = rotLocalX * Math.cos(rotAngleRad) - rotLocalY * Math.sin(rotAngleRad);
    const rotRotatedY = rotLocalX * Math.sin(rotAngleRad) + rotLocalY * Math.cos(rotAngleRad);
    rotationHandle.x = object.x + rotRotatedX;
    rotationHandle.y = object.y + rotRotatedY;

    // Make handle interactive
    rotationHandle.eventMode = 'static';
    rotationHandle.cursor = 'grab';
    rotationHandle.objectId = object.objectId;

    // Add rotation handle event listeners
    rotationHandle.on('pointerdown', this.onRotationHandleDown.bind(this));
    rotationHandle.on('pointerup', this.onRotationHandleUp.bind(this));
    rotationHandle.on('pointerupoutside', this.onRotationHandleUp.bind(this));

    this.objectContainer.addChild(rotationHandle);
    this.rotationHandles.set(object.objectId, rotationHandle);

    // Create resize handle at bottom-right corner
    const resizeHandle = new PIXI.Graphics();

    // Draw circle with white fill and blue border
    resizeHandle.circle(0, 0, 10)
      .fill({ color: 0xffffff })
      .stroke({ width: 2, color: 0x3b82f6 });

    // Draw resize arrows pointing towards center (diagonal inward)
    // Arrow pointing up-left (towards center from bottom-right corner)
    resizeHandle.moveTo(0, 0)
      .lineTo(-4, -4)
      .moveTo(-4, -4)
      .lineTo(-2, -4)
      .moveTo(-4, -4)
      .lineTo(-4, -2)
      .stroke({ width: 1.5, color: 0x3b82f6 });

    // Position at bottom-right corner, accounting for object rotation
    const resLocalX = bounds.width / 2 + 2;
    const resLocalY = bounds.height / 2 + 2;
    const resAngleRad = object.angle * Math.PI / 180;
    const resRotatedX = resLocalX * Math.cos(resAngleRad) - resLocalY * Math.sin(resAngleRad);
    const resRotatedY = resLocalX * Math.sin(resAngleRad) + resLocalY * Math.cos(resAngleRad);
    resizeHandle.x = object.x + resRotatedX;
    resizeHandle.y = object.y + resRotatedY;

    // Rotate handle to point towards center (object angle + 180° to point inward)
    resizeHandle.angle = object.angle + 180;

    // Make handle interactive
    resizeHandle.eventMode = 'static';
    resizeHandle.cursor = 'nwse-resize';
    resizeHandle.objectId = object.objectId;

    // Add resize handle event listeners
    resizeHandle.on('pointerdown', this.onResizeHandleDown.bind(this));
    resizeHandle.on('pointerup', this.onResizeHandleUp.bind(this));
    resizeHandle.on('pointerupoutside', this.onResizeHandleUp.bind(this));

    this.objectContainer.addChild(resizeHandle);
    this.resizeHandles.set(object.objectId, resizeHandle);
  }

  /**
   * Update all selection boxes and rotation handles to match object positions
   */
  updateSelectionBoxes() {
    this.selectionBoxes.forEach((box, objectId) => {
      const obj = this.objects.get(objectId);
      if (obj) {
        // Use local bounds (container-relative)
        const bounds = obj.getLocalBounds();
        box.clear();
        box.rect(
          -2,
          -2,
          bounds.width + 4,
          bounds.height + 4
        ).stroke({ width: 2, color: 0x3b82f6 });

        // Update position to match object
        box.x = obj.x;
        box.y = obj.y;

        // Update rotation and pivot to match object (for rotated objects)
        box.angle = obj.angle;
        box.pivot.set(obj.pivot.x, obj.pivot.y);

        // Update rotation handle position (top-right corner)
        const rotationHandle = this.rotationHandles.get(objectId);
        if (rotationHandle) {
          // Use temp size if resizing, otherwise use actual bounds
          const width = obj.tempWidth || bounds.width;
          const height = obj.tempHeight || bounds.height;

          // Calculate corner position in local space (relative to object center)
          const localX = width / 2 + 2;
          const localY = -height / 2 - 2;

          // Rotate the local position by the object's angle
          const angleRad = obj.angle * Math.PI / 180;
          const rotatedX = localX * Math.cos(angleRad) - localY * Math.sin(angleRad);
          const rotatedY = localX * Math.sin(angleRad) + localY * Math.cos(angleRad);

          // Position handle at rotated corner position
          rotationHandle.x = obj.x + rotatedX;
          rotationHandle.y = obj.y + rotatedY;
        }

        // Update resize handle position (bottom-right corner)
        const resizeHandle = this.resizeHandles.get(objectId);
        if (resizeHandle) {
          // Use temp size if resizing, otherwise use actual bounds
          const width = obj.tempWidth || bounds.width;
          const height = obj.tempHeight || bounds.height;

          // Calculate corner position in local space (relative to object center)
          const localX = width / 2 + 2;
          const localY = height / 2 + 2;

          // Rotate the local position by the object's angle
          const angleRad = obj.angle * Math.PI / 180;
          const rotatedX = localX * Math.cos(angleRad) - localY * Math.sin(angleRad);
          const rotatedY = localX * Math.sin(angleRad) + localY * Math.cos(angleRad);

          // Position handle at rotated corner position
          resizeHandle.x = obj.x + rotatedX;
          resizeHandle.y = obj.y + rotatedY;

          // Rotate handle to point towards center (object angle + 180° to point inward)
          resizeHandle.angle = obj.angle + 180;
        }
      }
    });
  }

  /**
   * Update all object labels to match object positions
   */
  updateObjectLabels() {
    if (!this.labelsVisible) return;

    this.objectLabels.forEach((label, objectId) => {
      const obj = this.objects.get(objectId);
      if (obj) {
        // Use local bounds and object position (same as selection boxes)
        const bounds = obj.getLocalBounds();
        label.container.x = obj.x + bounds.width / 2 - label.container.width / 2;
        label.container.y = obj.y - label.container.height - 5; // 5px above object
      }
    });
  }

  /**
   * Handle window resize
   */
  handleResize() {
    // Use requestAnimationFrame to ensure we get accurate dimensions
    requestAnimationFrame(() => {
      if (!this.app || !this.app.renderer) return;

      const container = this.app.canvas.parentElement;
      if (!container) return;

      const width = container.clientWidth;
      const height = container.clientHeight;

      // Only resize if we have valid dimensions
      if (width > 0 && height > 0) {
        this.app.renderer.resize(width, height);
        this.canvasWidth = width;
        this.canvasHeight = height;

        // Update culling after resize (disabled for now)
        // this.updateVisibleObjects();
      }
    });
  }

  /**
   * Update viewport culling (debounced during pan/zoom)
   */
  debouncedCullUpdate() {
    const now = Date.now();
    if (now - this.lastCullUpdate > 100) {
      this.updateVisibleObjects();
      this.lastCullUpdate = now;
    }
  }

  /**
   * Update visible objects using v8 Culler for viewport culling
   * Culls objects outside the visible viewport for better performance
   */
  updateVisibleObjects() {
    if (!this.objectContainer || !this.app) return;

    // Calculate visible viewport bounds with generous padding to prevent disappearing objects during pan
    const padding = 500; // Extra padding to keep objects visible during pan/zoom (increased from 100)
    const viewportBounds = new PIXI.Rectangle(
      -this.viewOffset.x / this.zoomLevel - padding,
      -this.viewOffset.y / this.zoomLevel - padding,
      this.canvasWidth / this.zoomLevel + padding * 2,
      this.canvasHeight / this.zoomLevel + padding * 2
    );

    // Use v8 Culler.shared to cull invisible objects
    PIXI.Culler.shared.cull(this.objectContainer, viewportBounds);
  }

  /**
   * Object interaction handlers
   */
  onObjectPointerDown(event) {
    // Prevent event bubbling
    event.stopPropagation();

    const object = event.currentTarget;
    const globalPos = event.data.global;
    const localPos = this.screenToCanvas(globalPos);

    console.log('[CanvasManager] Object pointer down, isPanning:', this.isPanning, 'objectId:', object.objectId);

    // Check if object is locked by another user
    const pixiObject = this.objects.get(object.objectId);
    if (pixiObject && pixiObject.lockedBy && pixiObject.lockedBy !== this.currentUserId) {
      // Object is locked by another user, prevent interaction
      console.log('[CanvasManager] Object is locked by another user');
      return;
    }

    if (this.currentTool === 'select') {
      // If object is not selected, select it (but don't deselect others if shift was held during initial click)
      if (!this.selectedObjects.has(object)) {
        this.setSelection(object);
      }

      // Prepare for dragging all selected objects
      console.log('[CanvasManager] Setting isDragging=true');
      this.isDragging = true;

      // Calculate drag offset for each selected object
      this.dragOffsets.clear();
      this.selectedObjects.forEach(obj => {
        this.dragOffsets.set(obj.objectId, {
          x: obj.x - localPos.x,
          y: obj.y - localPos.y
        });
      });
    } else if (this.currentTool === 'delete') {
      // Delete object
      this.emit('delete_object', { object_id: object.objectId });
    }
  }

  onObjectPointerMove(event) {
    // Handled by global mouse move handler
  }

  onObjectPointerUp(event) {
    // Handled by global mouse up handler
  }

  /**
   * Handle rotation handle pointer down
   * @param {PIXI.FederatedPointerEvent} event - PixiJS pointer event
   */
  onRotationHandleDown(event) {
    event.stopPropagation();

    const handle = event.currentTarget;
    const objectId = handle.objectId;
    const object = this.objects.get(objectId);

    if (!object) {
      console.error('[CanvasManager] No object found for objectId:', objectId);
      return;
    }

    // Get mouse position at grab time
    const globalPos = event.data.global;
    const mousePos = this.screenToCanvas(globalPos);

    // Calculate initial angle from object center to mouse position
    const dx = mousePos.x - object.x;
    const dy = mousePos.y - object.y;
    this.rotationGrabAngle = Math.atan2(dy, dx) * (180 / Math.PI) + 90;

    // Start rotating
    this.isRotating = true;
    this.rotatingObject = object;
    this.rotationStartAngle = object.angle || 0;

    // Change cursor to grabbing
    handle.cursor = 'grabbing';

    // Prevent object dragging while rotating
    this.isDragging = false;
  }

  /**
   * Handle rotation handle pointer up
   * @param {PIXI.FederatedPointerEvent} event - PixiJS pointer event
   */
  onRotationHandleUp(event) {
    if (!this.isRotating || !this.rotatingObject) return;

    event.stopPropagation();

    const obj = this.rotatingObject;

    // Get the object's ID
    const objectData = Array.from(this.objects.entries()).find(([id, pixiObj]) => pixiObj === obj);
    if (objectData) {
      const [objectId, pixiObj] = objectData;

      // Emit update with new rotation angle (stored in data field, just like AI rotation)
      this.emit('update_object', {
        object_id: objectId,
        data: {
          rotation: Math.round(obj.angle) // Round to nearest degree
        }
      });
    }

    // Reset rotation handle cursor
    const handle = event.currentTarget;
    if (handle) {
      handle.cursor = 'grab';
    }

    this.isRotating = false;
    this.rotatingObject = null;
  }

  /**
   * Handle resize handle pointer down
   * @param {PIXI.FederatedPointerEvent} event - PixiJS pointer event
   */
  onResizeHandleDown(event) {
    event.stopPropagation();

    const handle = event.currentTarget;
    const objectId = handle.objectId;
    const object = this.objects.get(objectId);

    if (!object) {
      console.error('[CanvasManager] No object found for objectId:', objectId);
      return;
    }

    // Get mouse position at grab time
    const globalPos = event.data.global;
    const mousePos = this.screenToCanvas(globalPos);

    // Store initial mouse position and object size
    this.resizeStartMousePos = { x: mousePos.x, y: mousePos.y };
    const bounds = object.getLocalBounds();
    this.resizeStartSize = { width: bounds.width, height: bounds.height };

    // Start resizing
    this.isResizing = true;
    this.resizingObject = object;

    // Change cursor to grabbing
    handle.cursor = 'nwse-resize';

    // Prevent object dragging while resizing
    this.isDragging = false;
  }

  /**
   * Handle resize handle pointer up
   * @param {PIXI.FederatedPointerEvent} event - PixiJS pointer event
   */
  onResizeHandleUp(event) {
    if (!this.isResizing || !this.resizingObject) return;

    event.stopPropagation();

    const obj = this.resizingObject;

    // Get the object's ID
    const objectData = Array.from(this.objects.entries()).find(([id, pixiObj]) => pixiObj === obj);
    if (objectData) {
      const [objectId, pixiObj] = objectData;

      // Emit update with new size
      this.emit('update_object', {
        object_id: objectId,
        data: {
          width: Math.round(obj.tempWidth || this.resizeStartSize.width),
          height: Math.round(obj.tempHeight || this.resizeStartSize.height)
        }
      });
    }

    // Reset resize handle cursor
    const handle = event.currentTarget;
    if (handle) {
      handle.cursor = 'nwse-resize';
    }

    this.isResizing = false;
    this.resizingObject = null;
  }

  /**
   * Convert screen position to canvas position
   * @param {Object} screenPos - {x, y} screen position
   * @returns {Object} {x, y} canvas position
   */
  screenToCanvas(screenPos) {
    return {
      x: (screenPos.x - this.viewOffset.x) / this.zoomLevel,
      y: (screenPos.y - this.viewOffset.y) / this.zoomLevel
    };
  }

  /**
   * Get mouse position relative to canvas
   * @param {MouseEvent} event
   * @returns {Object} {x, y} position
   */
  getMousePosition(event) {
    // Safety check for null/undefined events or events with null/undefined coordinates
    // Wrap in try-catch since event.clientX/clientY might be getters that throw
    try {
      if (!event) {
        console.warn('[CanvasManager] getMousePosition called with null/undefined event');
        return { x: 0, y: 0 };
      }

      // Test accessing clientX/clientY - these might be getters that throw
      const clientX = event.clientX;
      const clientY = event.clientY;

      if (typeof clientX !== 'number' || typeof clientY !== 'number') {
        console.warn('[CanvasManager] getMousePosition called with invalid coordinates:', { clientX, clientY, event });
        return { x: 0, y: 0 };
      }

      const rect = this.app.canvas.getBoundingClientRect();
      return {
        x: (clientX - rect.left - this.viewOffset.x) / this.zoomLevel,
        y: (clientY - rect.top - this.viewOffset.y) / this.zoomLevel
      };
    } catch (error) {
      console.warn('[CanvasManager] getMousePosition caught error accessing event properties:', error, event);
      return { x: 0, y: 0 };
    }
  }

  /**
   * Get current performance metrics
   * @returns {Object} Performance metrics (fps, avgFrameTime, minFps, maxFps)
   */
  getPerformanceMetrics() {
    if (!this.performanceMonitor) {
      return {
        fps: 0,
        avgFrameTime: 0,
        minFps: 0,
        maxFps: 0
      };
    }
    return this.performanceMonitor.getMetrics();
  }

  /**
   * Get IDs of currently selected objects
   * @returns {Array<string>} Array of selected object IDs
   */
  getSelectedObjectIds() {
    return Array.from(this.selectedObjects).map(obj => obj.objectId);
  }

  /**
   * Restore viewport to a saved position
   * @param {number} x - Viewport X position
   * @param {number} y - Viewport Y position
   * @param {number} zoom - Zoom level
   */
  restoreViewport(x, y, zoom) {
    // Set zoom level
    this.zoomLevel = zoom;
    this.objectContainer.scale.set(zoom, zoom);
    this.labelContainer.scale.set(zoom, zoom);
    this.cursorContainer.scale.set(zoom, zoom);

    // Set viewport offset
    this.viewOffset = { x, y };
    this.objectContainer.x = x;
    this.objectContainer.y = y;
    this.labelContainer.x = x;
    this.labelContainer.y = y;
    this.cursorContainer.x = x;
    this.cursorContainer.y = y;
  }

  /**
   * Get current viewport state
   * @returns {Object} {x, y, zoom}
   */
  getViewportState() {
    return {
      x: this.viewOffset.x,
      y: this.viewOffset.y,
      zoom: this.zoomLevel
    };
  }

  /**
   * Set the current color for object creation
   * @param {string} color - Hex color string (e.g., "#FF0000")
   */
  setCurrentColor(color) {
    this.currentColor = color || '#000000';
  }

  /**
   * Create a label for a single object
   * @param {number} objectId - Object ID
   * @param {PIXI.DisplayObject} pixiObject - The PixiJS object
   * @param {string} labelText - Optional label text (if not provided, retrieves from stored label or generates default)
   */
  createLabelForObject(objectId, pixiObject, labelText = null) {
    // If no labelText provided, try to get it from existing label or use default
    if (!labelText) {
      const existingLabel = this.objectLabels.get(objectId);
      labelText = existingLabel?.labelText || `Object ${objectId}`;
    }

    // Remove existing label if present
    const existingLabel = this.objectLabels.get(objectId);
    if (existingLabel) {
      this.labelContainer.removeChild(existingLabel.container);
      existingLabel.container.destroy();
    }

    // Create label container
    const labelContainer = new PIXI.Container();

    // Create text label
    const text = new PIXI.Text({
      text: labelText,
      style: new PIXI.TextStyle({
        fontFamily: 'Arial',
        fontSize: 14,
        fill: 0xffffff,
        fontWeight: 'bold'
      })
    });

    // Create background for label
    const padding = 4;
    const bg = new PIXI.Graphics();
    bg.roundRect(0, 0, text.width + padding * 2, text.height + padding * 2, 4)
      .fill({ color: 0x3b82f6, alpha: 0.9 });

    // Position text on top of background
    text.x = padding;
    text.y = padding;

    labelContainer.addChild(bg);
    labelContainer.addChild(text);

    // Position label above the object using local bounds and object position
    // (similar to how selection boxes are positioned)
    const bounds = pixiObject.getLocalBounds();
    labelContainer.x = pixiObject.x + bounds.width / 2 - labelContainer.width / 2;
    labelContainer.y = pixiObject.y - labelContainer.height - 5; // 5px above object

    // Store label reference with text for persistence
    this.objectLabels.set(objectId, { container: labelContainer, text, bg, labelText });

    // Add to label container (renders on top of objects)
    this.labelContainer.addChild(labelContainer);
  }

  /**
   * Toggle visual labels on canvas objects
   * @param {boolean} show - Whether to show or hide labels
   * @param {Object} labels - Map of object_id => display_name (e.g., "Rectangle 1")
   */
  toggleObjectLabels(show, labels) {
    console.log('[CanvasManager] toggleObjectLabels called - show:', show, 'labels:', labels, 'labelsVisible:', this.labelsVisible);
    if (show) {
      // Show labels
      this.labelsVisible = true;

      // Create label for each object
      this.objects.forEach((pixiObject, objectId) => {
        const labelText = labels[objectId] || `Object ${objectId}`;
        this.createLabelForObject(objectId, pixiObject, labelText);
      });
    } else {
      // Hide labels
      this.labelsVisible = false;

      // Remove all labels
      this.objectLabels.forEach((label, objectId) => {
        this.labelContainer.removeChild(label.container);
        label.container.destroy();
      });

      this.objectLabels.clear();
    }
  }

  /**
   * Destroy the CanvasManager and clean up resources
   */
  destroy() {
    // Remove event listeners using stored bound references
    const canvas = this.app?.canvas;
    if (canvas) {
      canvas.removeEventListener('mousedown', this.boundHandlers.handleMouseDown);
      canvas.removeEventListener('wheel', this.boundHandlers.handleWheel);
      canvas.removeEventListener('touchstart', this.boundHandlers.handleTouchStart);
      canvas.removeEventListener('touchmove', this.boundHandlers.handleTouchMove);
      canvas.removeEventListener('touchend', this.boundHandlers.handleTouchEnd);
    }

    // Remove window event listeners (mousemove and mouseup are on window, not canvas)
    window.removeEventListener('mousemove', this.boundHandlers.handleMouseMove);
    window.removeEventListener('mouseup', this.boundHandlers.handleMouseUp);
    window.removeEventListener('keydown', this.boundHandlers.handleKeyDown);
    window.removeEventListener('keyup', this.boundHandlers.handleKeyUp);
    window.removeEventListener('resize', this.boundHandlers.handleResize);

    // Disconnect ResizeObserver
    if (this.resizeObserver) {
      this.resizeObserver.disconnect();
      this.resizeObserver = null;
    }

    // Stop performance monitoring
    if (this.performanceMonitor) {
      this.performanceMonitor.stop();
      this.performanceMonitor = null;
    }

    // Clean up PixiJS application
    if (this.app) {
      this.app.destroy(true);
      this.app = null;
    }

    // Clear all event listeners
    this.eventListeners.clear();
  }
}
