import * as PIXI from '../../vendor/pixi.min.mjs';
import { PerformanceMonitor } from './performance_monitor.js';
import { OfflineQueue } from './offline_queue.js';
import { HistoryManager } from './history_manager.js';

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
    this.selectionContainer = null; // Container for selected objects (enables group transforms)

    // Object and cursor storage
    this.objects = new Map();
    this.cursors = new Map();
    this.objectLabels = new Map(); // Map of objectId -> label Text object
    this.labelsVisible = false; // Track if labels are currently visible
    this.lockIndicators = new Map(); // Map of objectId -> lock indicator container

    // Offline support
    this.offlineQueue = null;
    this.connectionStatusIndicator = null;

    // History management (undo/redo)
    this.historyManager = new HistoryManager(50);

    // Interaction state
    this.currentUserId = null;
    this.selectedObjects = new Set(); // Changed from selectedObject to support multi-selection
    this.selectionBoxes = new Map(); // Map of objectId -> selectionBox graphics
    this.selectionData = new Map(); // Map of objectId -> {originalParent, originalX, originalY, originalRotation, originalIndex}
    this.isDragging = false;
    this.dragOffsets = new Map(); // Map of objectId -> {x, y} drag offset (deprecated with selection container)
    this.dragOffset = null; // Single drag offset for selection container {x, y}
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

    // Lasso selection state
    this.isLassoSelecting = false;
    this.lassoStart = { x: 0, y: 0 };
    this.lassoRect = null; // Graphics object for lasso visualization

    // Clipboard state for copy/paste
    this.clipboard = [];

    // Throttle tracking
    this.lastCursorUpdate = 0;
    this.lastDragUpdate = 0;
    this.lastRotateUpdate = 0;
    this.lastResizeUpdate = 0;
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

    // Remote transform tracking for smooth updates and visual feedback
    this.remoteTransforms = new Map(); // Map of objectId -> {userId, type: 'drag'|'rotate'|'resize'}
    this.remoteTransformGlows = new Map(); // Map of objectId -> PIXI.Graphics glow
    this.interpolationTargets = new Map(); // Map of objectId -> {x, y, width, height, rotation, startTime}
    this.presences = {}; // Store presence data for user colors
  }

  /**
   * Initialize the PixiJS application
   * @param {HTMLElement} container - DOM element to attach canvas to
   * @param {string} userId - Current user ID
   * @param {string} canvasId - Canvas ID for offline queue
   */
  async initialize(container, userId, canvasId) {
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

    // Create selection container for group transforms (child of objectContainer)
    this.selectionContainer = new PIXI.Container();
    this.objectContainer.addChild(this.selectionContainer);

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

    // Start interpolation ticker for smooth remote transforms
    this.app.ticker.add(this.updateInterpolations.bind(this));

    // Initialize offline queue
    if (canvasId) {
      this.offlineQueue = new OfflineQueue(canvasId);
      
      // Register sync callback
      this.offlineQueue.onSync(async (type, data) => {
        this.emit(type + '_object', data);
      });

      // Register status change callback
      this.offlineQueue.onStatusChange((status, queueSize) => {
        this.updateConnectionStatus(status, queueSize);
      });

      // Create connection status indicator
      this.createConnectionStatusIndicator();
    }

    // Setup history manager callbacks
    this.historyManager.onUndo(async (operation) => {
      console.log('[CanvasManager] Undoing operation:', operation);
      
      switch (operation.type) {
        case 'create':
          // Delete the created object
          this.emit('delete_object', { object_id: operation.data.id });
          break;
        case 'update':
          // Restore previous state
          if (operation.previousState) {
            this.emit('update_object', operation.previousState);
          }
          break;
        case 'delete':
          // Recreate the deleted object
          if (operation.previousState) {
            this.emit('create_object', operation.previousState);
          }
          break;
      }
    });

    this.historyManager.onRedo(async (operation) => {
      console.log('[CanvasManager] Redoing operation:', operation);
      
      switch (operation.type) {
        case 'create':
          // Recreate the object
          this.emit('create_object', operation.data);
          break;
        case 'update':
          // Reapply the update
          this.emit('update_object', operation.data);
          break;
        case 'delete':
          // Delete again
          this.emit('delete_object', { object_id: operation.data.id });
          break;
      }
    });

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
   * Queues events when offline for later sync
   * @param {string} event - Event name
   * @param {*} data - Event data
   */
  emit(event, data) {
    // Check if this is a canvas operation that should be queued when offline
    const queueableEvents = ['create_object', 'update_object', 'delete_object'];

    if (queueableEvents.includes(event) && this.offlineQueue && !this.offlineQueue.online) {
      // Queue the operation for later sync
      this.offlineQueue.queueOperation(event.replace('_object', ''), data);
      // Don't return early - still emit the event so local UI updates
    }

    // Normal event emission (happens both online and offline)
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
    // Handle both parsed objects and JSON strings
    const data = (typeof objectData.data === 'string')
      ? JSON.parse(objectData.data)
      : (objectData.data || {});
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
      case 'star':
        pixiObject = this.createStar(position, data);
        break;
      case 'triangle':
        pixiObject = this.createTriangle(position, data);
        break;
      case 'polygon':
        pixiObject = this.createPolygon(position, data);
        break;
      default:
        console.warn('Unknown object type:', objectData.type);
        return;
    }

    // Store object reference and lock information
    pixiObject.objectId = objectData.id;
    pixiObject.lockedBy = objectData.locked_by;
    pixiObject.objectType = objectData.type; // Store type for resize redrawing
    pixiObject.objectData = data; // Store original data for resize redrawing
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
    // Validate that the color is a valid string before using it
    const fillColor = this.validateColor(data.fill || data.color) || '#3b82f6';
    const fill = parseInt(fillColor.replace('#', '0x'));
    const strokeColor = this.validateColor(data.stroke || data.color) || '#1e40af';
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
    // Validate that the color is a valid string before using it
    const fillColor = this.validateColor(data.fill || data.color) || '#3b82f6';
    const fill = parseInt(fillColor.replace('#', '0x'));
    const strokeColor = this.validateColor(data.stroke || data.color) || '#1e40af';
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
   * Redraw a Graphics object with new dimensions
   * Used during resize to show smooth visual updates
   * @param {PIXI.Graphics} graphics - The graphics object to redraw
   * @param {number} width - New width
   * @param {number} height - New height
   */
  redrawGraphicsWithSize(graphics, width, height) {
    if (!(graphics instanceof PIXI.Graphics)) {
      return; // Only works for Graphics objects
    }

    const data = graphics.objectData || {};
    const type = graphics.objectType;

    // Get fill and stroke from stored data
    const fillColor = data.fill || data.color || '#3b82f6';
    const fill = parseInt(fillColor.replace('#', '0x'));
    const strokeColor = data.stroke || data.color || '#1e40af';
    const stroke = parseInt(strokeColor.replace('#', '0x'));
    const strokeWidth = data.stroke_width || 2;

    // Clear and redraw
    graphics.clear();

    if (type === 'circle') {
      const radius = width / 2;
      graphics.circle(radius, radius, radius)
        .fill(fill)
        .stroke({ width: strokeWidth, color: stroke });
      graphics.pivot.set(radius, radius);
    } else {
      // Rectangle (default)
      graphics.rect(0, 0, width, height)
        .fill(fill)
        .stroke({ width: strokeWidth, color: stroke });
      graphics.pivot.set(width / 2, height / 2);
    }

    // Restore opacity if it was set
    // Preserve alpha, default to 1.0 (fully opaque) if not specified
    graphics.alpha = data.opacity !== undefined ? data.opacity : 1.0;
  }

  /**
   * Create text object
   * @param {Object} position - {x, y} position
   * @param {Object} data - Text data
   * @returns {PIXI.Text}
   */
  createText(position, data) {
    // Validate color before using
    const textColor = this.validateColor(data.color) || '#000000';

    const style = new PIXI.TextStyle({
      fontFamily: data.font_family || 'Arial',
      fontSize: data.font_size || 16,
      fill: textColor,
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
   * Create a star shape
   * @param {Object} position - {x, y} position
   * @param {Object} data - Shape data
   * @returns {PIXI.Graphics}
   */
  createStar(position, data) {
    const graphics = new PIXI.Graphics();
    const points = data.points || 5; // Number of star points
    const outerRadius = (data.width || 100) / 2;
    const innerRadius = outerRadius * (data.innerRatio || 0.5);

    // Validate colors
    const fillColor = this.validateColor(data.fill || data.color) || '#3b82f6';
    const fill = parseInt(fillColor.replace('#', '0x'));
    const strokeColor = this.validateColor(data.stroke) || fillColor;
    const stroke = parseInt(strokeColor.replace('#', '0x'));
    const strokeWidth = data.stroke_width || 2;

    // Calculate star points
    const starPoints = [];
    for (let i = 0; i < points * 2; i++) {
      const angle = (i * Math.PI) / points - Math.PI / 2;
      const radius = i % 2 === 0 ? outerRadius : innerRadius;
      starPoints.push(
        Math.cos(angle) * radius,
        Math.sin(angle) * radius
      );
    }

    // Draw star using poly
    graphics.poly(starPoints)
      .fill({ color: fill, alpha: data.opacity || 1 })
      .stroke({ width: strokeWidth, color: stroke });

    graphics.x = position.x;
    graphics.y = position.y;

    // Apply rotation if specified
    if (data.rotation !== undefined && data.rotation !== 0) {
      this.applyRotation(graphics, data.rotation, data.pivot_point, outerRadius * 2, outerRadius * 2);
    } else {
      graphics.pivot.set(0, 0);
    }

    return graphics;
  }

  /**
   * Create a triangle shape
   * @param {Object} position - {x, y} position
   * @param {Object} data - Shape data
   * @returns {PIXI.Graphics}
   */
  createTriangle(position, data) {
    const graphics = new PIXI.Graphics();
    const width = data.width || 100;
    const height = data.height || 100;

    // Validate colors
    const fillColor = this.validateColor(data.fill || data.color) || '#3b82f6';
    const fill = parseInt(fillColor.replace('#', '0x'));
    const strokeColor = this.validateColor(data.stroke) || fillColor;
    const stroke = parseInt(strokeColor.replace('#', '0x'));
    const strokeWidth = data.stroke_width || 2;

    // Draw equilateral triangle pointing up
    const trianglePoints = [
      0, -height / 2,           // Top
      -width / 2, height / 2,   // Bottom left
      width / 2, height / 2     // Bottom right
    ];

    graphics.poly(trianglePoints)
      .fill({ color: fill, alpha: data.opacity || 1 })
      .stroke({ width: strokeWidth, color: stroke });

    graphics.x = position.x;
    graphics.y = position.y;

    // Apply rotation if specified
    if (data.rotation !== undefined && data.rotation !== 0) {
      this.applyRotation(graphics, data.rotation, data.pivot_point, width, height);
    } else {
      graphics.pivot.set(0, 0);
    }

    return graphics;
  }

  /**
   * Create a polygon shape
   * @param {Object} position - {x, y} position
   * @param {Object} data - Shape data
   * @returns {PIXI.Graphics}
   */
  createPolygon(position, data) {
    const graphics = new PIXI.Graphics();
    const sides = data.sides || 6; // Default to hexagon
    const radius = (data.width || 100) / 2;

    // Validate colors
    const fillColor = this.validateColor(data.fill || data.color) || '#3b82f6';
    const fill = parseInt(fillColor.replace('#', '0x'));
    const strokeColor = this.validateColor(data.stroke) || fillColor;
    const stroke = parseInt(strokeColor.replace('#', '0x'));
    const strokeWidth = data.stroke_width || 2;

    // Calculate polygon points
    const polygonPoints = [];
    for (let i = 0; i < sides; i++) {
      const angle = (i * 2 * Math.PI) / sides - Math.PI / 2;
      polygonPoints.push(
        Math.cos(angle) * radius,
        Math.sin(angle) * radius
      );
    }

    // Draw polygon
    graphics.poly(polygonPoints)
      .fill({ color: fill, alpha: data.opacity || 1 })
      .stroke({ width: strokeWidth, color: stroke });

    graphics.x = position.x;
    graphics.y = position.y;

    // Apply rotation if specified
    if (data.rotation !== undefined && data.rotation !== 0) {
      this.applyRotation(graphics, data.rotation, data.pivot_point, radius * 2, radius * 2);
    } else {
      graphics.pivot.set(0, 0);
    }

    return graphics;
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

    // Determine if this is a remote transform (not from current user)
    const isRemoteTransform = pixiObject.lockedBy && pixiObject.lockedBy !== this.currentUserId;

    if (isRemoteTransform) {
      console.log('[CanvasManager] Remote transform detected for object', objectData.id, 'locked by', pixiObject.lockedBy, 'current user', this.currentUserId);
    }

    // Update position if changed
    if (objectData.position) {
      // Skip position updates for objects in selection container (being dragged/selected)
      const isInSelectionContainer = pixiObject.parent === this.selectionContainer;

      if (isInSelectionContainer) {
        console.log('[CanvasManager] Skipping position update for object', objectData.id, 'in selectionContainer');
      } else if (isRemoteTransform) {
        // Remote user is transforming - use smooth interpolation
        // ONLY set position, not size or rotation
        this.setInterpolationTarget(objectData.id, {
          x: objectData.position.x,
          y: objectData.position.y,
          onlyPosition: true  // Flag to prevent size/rotation interpolation
        });
      } else {
        // Local update or unlocked object - immediate update
        pixiObject.x = objectData.position.x;
        pixiObject.y = objectData.position.y;
      }

      // Update label position for this object if labels are visible
      if (this.labelsVisible && !isRemoteTransform) {
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
      const wasRemoteLocked = pixiObject.lockedBy && pixiObject.lockedBy !== this.currentUserId;
      const isNowRemoteLocked = objectData.locked_by && objectData.locked_by !== this.currentUserId;
      const isNowUnlocked = objectData.locked_by === null;

      console.log('[CanvasManager] Updating lock status for object', objectData.id, 'locked_by:', objectData.locked_by, 'current user:', this.currentUserId);
      pixiObject.lockedBy = objectData.locked_by;
      this.updateObjectAppearance(pixiObject);

      // If object is NOW locked by another user, immediately hide selection box
      if (isNowRemoteLocked) {
        console.log('[CanvasManager] Object locked by remote user, removing selection box', objectData.id);
        const box = this.selectionBoxes.get(objectData.id);
        if (box) {
          box.visible = false;
        }
        const rotationHandle = this.rotationHandles.get(objectData.id);
        if (rotationHandle) {
          rotationHandle.visible = false;
        }
        const resizeHandle = this.resizeHandles.get(objectData.id);
        if (resizeHandle) {
          resizeHandle.visible = false;
        }
      }

      // Clean up remote transform state if object was unlocked
      if (wasRemoteLocked && isNowUnlocked) {
        console.log('[CanvasManager] Object unlocked, cleaning up interpolation state', objectData.id);
        this.interpolationTargets.delete(objectData.id);

        // Make selection box visible again if it exists
        const box = this.selectionBoxes.get(objectData.id);
        if (box) {
          box.visible = true;
        }
        const rotationHandle = this.rotationHandles.get(objectData.id);
        if (rotationHandle) {
          rotationHandle.visible = true;
        }
        const resizeHandle = this.resizeHandles.get(objectData.id);
        if (resizeHandle) {
          resizeHandle.visible = true;
        }
      }
    }

    // Handle data changes - check if this is a partial update (like rotation only) or full object replacement
    if (objectData.data) {
      try {
        const newData = JSON.parse(objectData.data);

        // If this is ONLY a rotation update (single key), apply it without recreating
        const keys = Object.keys(newData);
        if (keys.length === 1 && keys[0] === 'rotation') {
          if (isRemoteTransform) {
            // Remote user is rotating - use smooth interpolation
            // ONLY set rotation, not position or size
            this.setInterpolationTarget(objectData.id, {
              rotation: newData.rotation,
              onlyRotation: true  // Flag to prevent size interpolation
            });
          } else {
            // Local update - immediate rotation
            pixiObject.angle = newData.rotation;

            // Update selection box to match rotation
            const selectionBox = this.selectionBoxes.get(objectData.id);
            if (selectionBox) {
              selectionBox.angle = newData.rotation;
            }
          }

          return;
        }

        // If this is ONLY a size update (width/height), try to update without recreating
        if (keys.length <= 2 && keys.every(k => k === 'width' || k === 'height')) {
          // Only handle size updates for Graphics objects (not Text)
          if (pixiObject instanceof PIXI.Graphics) {
            if (isRemoteTransform) {
              // Remote user is resizing - use smooth interpolation
              // ONLY set width/height, not rotation
              this.setInterpolationTarget(objectData.id, {
                width: newData.width,
                height: newData.height,
                onlyResize: true  // Flag to prevent rotation interpolation
              });
            } else {
              // Local update - immediate resize
              const bounds = pixiObject.getLocalBounds();
              const width = newData.width !== undefined ? newData.width : bounds.width;
              const height = newData.height !== undefined ? newData.height : bounds.height;

              // Redraw using our helper method (preserves colors/styles)
              this.redrawGraphicsWithSize(pixiObject, width, height);

              // Update selection boxes
              this.updateSelectionBoxes();
            }
            return;
          }
        }

        // For complex updates or full data replacement, recreate the object
        // Note: This path is now less frequent due to partial update optimizations
        // for rotation-only (line 738) and size-only updates (line 761)

        // IMPORTANT: Preserve selection state before recreating
        const wasSelected = this.selectedObjects.has(pixiObject);
        const wasInSelectionContainer = pixiObject.parent === this.selectionContainer;
        const savedSelectionData = this.selectionData.get(objectData.id);

        this.deleteObject(objectData.id);
        this.createObject(objectData);

        // Restore selection state after recreation
        if (wasSelected && wasInSelectionContainer) {
          const recreatedObject = this.objects.get(objectData.id);
          if (recreatedObject) {
            console.log('[CanvasManager] Restoring selection for recreated object', objectData.id);

            // Restore selectionData if it existed
            if (savedSelectionData) {
              this.selectionData.set(objectData.id, savedSelectionData);
            }

            this.addToSelection(recreatedObject);
            this.selectedObjects.add(recreatedObject);
            // Don't create selection box - it should already exist
          }
        }

        // Update label for recreated object if labels are visible
        this.updateObjectLabels();
      } catch (error) {
        console.error('[CanvasManager] Error handling object data update:', error);
      }
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
   * Show a lock indicator (avatar/name tag) next to a locked object
   * @param {number} objectId - ID of the locked object
   * @param {Object} userInfo - User info with name, color, avatar
   */
  showLockIndicator(objectId, userInfo) {
    // Remove existing indicator if any
    this.hideLockIndicator(objectId);

    const pixiObject = this.objects.get(objectId);
    if (!pixiObject) return;

    // Only show indicator if locked by another user
    if (pixiObject.lockedBy === this.currentUserId) return;

    // Create container for the lock indicator
    const container = new PIXI.Container();

    // Create background pill
    const bg = new PIXI.Graphics();
    const bgColor = parseInt(userInfo.color.replace('#', '0x'));
    const textColor = this.getContrastColor(userInfo.color);
    
    // Create text
    const text = new PIXI.Text({
      text: `🔒 ${userInfo.name}`,
      style: new PIXI.TextStyle({
        fontFamily: 'Arial',
        fontSize: 12,
        fill: textColor,
        fontWeight: 'bold'
      })
    });

    // Draw rounded rectangle background
    const padding = 6;
    const radius = 6;
    bg.roundRect(
      0,
      0,
      text.width + padding * 2,
      text.height + padding * 2,
      radius
    )
    .fill(bgColor)
    .stroke({ width: 2, color: 0xffffff });

    // Position text inside background
    text.x = padding;
    text.y = padding;

    container.addChild(bg);
    container.addChild(text);

    // Position indicator above the object
    const bounds = pixiObject.getBounds();
    container.x = bounds.x;
    container.y = bounds.y - container.height - 10;

    // Add to label container (renders above objects)
    this.labelContainer.addChild(container);
    this.lockIndicators.set(objectId, container);
  }

  /**
   * Hide the lock indicator for an object
   * @param {number} objectId - ID of the object
   */
  hideLockIndicator(objectId) {
    const indicator = this.lockIndicators.get(objectId);
    if (indicator) {
      this.labelContainer.removeChild(indicator);
      indicator.destroy();
      this.lockIndicators.delete(objectId);
    }
  }

  /**
   * Get contrast color (black or white) for a given background color
   * @param {string} hexColor - Hex color string like "#3b82f6"
   * @returns {string} - Hex color string for text
   */
  getContrastColor(hexColor) {
    // Remove # if present
    const hex = hexColor.replace('#', '');
    
    // Convert to RGB
    const r = parseInt(hex.substr(0, 2), 16);
    const g = parseInt(hex.substr(2, 2), 16);
    const b = parseInt(hex.substr(4, 2), 16);
    
    // Calculate perceived brightness
    const brightness = (r * 299 + g * 587 + b * 114) / 1000;
    
    // Return black for light backgrounds, white for dark
    return brightness > 128 ? 0x000000 : 0xffffff;
  }

  /**
   * Update positions of all lock indicators to follow their objects
   */
  updateLockIndicators() {
    this.lockIndicators.forEach((indicator, objectId) => {
      const pixiObject = this.objects.get(objectId);
      if (pixiObject) {
        const bounds = pixiObject.getBounds();
        indicator.x = bounds.x;
        indicator.y = bounds.y - indicator.height - 10;
      }
    });
  }

  /**
   * Create connection status indicator
   */
  createConnectionStatusIndicator() {
    const container = new PIXI.Container();
    
    // Create background
    const bg = new PIXI.Graphics();
    bg.roundRect(0, 0, 200, 40, 6)
      .fill(0x10b981)
      .stroke({ width: 2, color: 0xffffff });
    
    // Create status text
    const text = new PIXI.Text({
      text: 'Online',
      style: new PIXI.TextStyle({
        fontFamily: 'Arial',
        fontSize: 14,
        fill: 0xffffff,
        fontWeight: 'bold'
      })
    });
    text.x = 10;
    text.y = 10;
    
    container.addChild(bg);
    container.addChild(text);
    
    // Position in top-right corner
    container.x = this.canvasWidth - 220;
    container.y = 20;
    container.visible = false; // Hidden by default (only show when offline)
    
    this.app.stage.addChild(container);
    this.connectionStatusIndicator = { container, bg, text };
  }

  /**
   * Update connection status indicator
   * @param {string} status - 'online', 'offline', or 'reconnecting'
   * @param {number} queueSize - Number of queued operations
   */
  updateConnectionStatus(status, queueSize) {
    if (!this.connectionStatusIndicator) return;
    
    const { container, bg, text } = this.connectionStatusIndicator;
    
    switch (status) {
      case 'online':
        container.visible = false;
        break;
        
      case 'offline':
        container.visible = true;
        bg.clear();
        bg.roundRect(0, 0, 200, 40, 6)
          .fill(0xef4444)
          .stroke({ width: 2, color: 0xffffff });
        text.text = `Offline (${queueSize} queued)`;
        break;
        
      case 'reconnecting':
        container.visible = true;
        bg.clear();
        bg.roundRect(0, 0, 200, 40, 6)
          .fill(0xf59e0b)
          .stroke({ width: 2, color: 0xffffff });
        text.text = `Syncing... (${queueSize} left)`;
        break;
    }
  }

  /**
   * Perform undo operation
   */
  async performUndo() {
    const success = await this.historyManager.undo();
    if (success) {
      console.log('[CanvasManager] Undo performed');
    }
  }

  /**
   * Perform redo operation
   */
  async performRedo() {
    const success = await this.historyManager.redo();
    if (success) {
      console.log('[CanvasManager] Redo performed');
    }
  }

  /**
   * Add operation to history for undo/redo
   * @param {string} type - Operation type: 'create', 'update', 'delete'
   * @param {Object} data - Operation data
   * @param {Object} previousState - Previous state for undo
   */
  addToHistory(type, data, previousState = null) {
    this.historyManager.addOperation(type, data, previousState);
  }

  /**
   * Start batching operations (for multi-object or AI operations)
   */
  startHistoryBatch() {
    this.historyManager.startBatch();
  }

  /**
   * End batching operations
   */
  endHistoryBatch() {
    this.historyManager.endBatch();
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

    // Also remove the lock indicator if it exists
    this.hideLockIndicator(objectId);
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
    // Store presence data for user colors and info
    this.presences = presences;

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
        console.log('[CanvasManager] Object clicked via DOM event (fallback), objectId:', clickedObject.objectId);
        // Shift+click = toggle selection, regular click = replace selection
        if (event.shiftKey) {
          this.toggleSelection(clickedObject);
        } else {
          // Check if object is in selection container (not the Set - reference equality bug)
          const isInSelection = clickedObject.parent === this.selectionContainer;
          console.log('[CanvasManager] DOM fallback: isInSelection:', isInSelection, 'selectionContainer children:', this.selectionContainer.children.length);

          if (!isInSelection) {
            console.log('[CanvasManager] DOM fallback: calling setSelection');
            this.setSelection(clickedObject);
          } else {
            console.log('[CanvasManager] DOM fallback: object already in selection, preserving multi-selection');
          }
        }
      } else {
        // Clicking on empty space = start lasso selection or clear selection
        console.log('[CanvasManager] Empty space clicked');
        if (!event.shiftKey) {
          this.clearSelection();
        }
        // Start lasso selection
        this.isLassoSelecting = true;
        this.lassoStart = position;
        this.createLassoRect(position);
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

      // Broadcast rotation changes during rotate (throttled to avoid spam)
      if (!this.lastRotateUpdate || Date.now() - this.lastRotateUpdate > 50) {
        const objectData = Array.from(this.objects.entries()).find(([id, pixiObj]) => pixiObj === obj);
        if (objectData) {
          const [objectId] = objectData;
          this.emit('update_object', {
            object_id: objectId,
            data: {
              rotation: Math.round(angle)
            }
          });
        }
        this.lastRotateUpdate = Date.now();
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

      // Redraw object with new size for smooth visual feedback
      this.redrawGraphicsWithSize(obj, newWidth, newHeight);

      // Update selection box to match new size
      this.updateSelectionBoxes();

      // Broadcast size changes during resize (throttled to avoid spam)
      if (!this.lastResizeUpdate || Date.now() - this.lastResizeUpdate > 50) {
        const objectData = Array.from(this.objects.entries()).find(([id, pixiObj]) => pixiObj === obj);
        if (objectData) {
          const [objectId] = objectData;
          this.emit('update_object', {
            object_id: objectId,
            data: {
              width: Math.round(newWidth),
              height: Math.round(newHeight)
            }
          });
        }
        this.lastResizeUpdate = Date.now();
      }
    } else if (this.isLassoSelecting) {
      // Update lasso selection rectangle
      this.updateLassoRect(position);
    } else if (this.isCreating) {
      // Update temp object while creating
      this.updateTempObject(position);
    } else if (this.isDragging && this.selectedObjects.size > 0) {
      // Check if actual movement occurred (more than 3 pixels threshold)
      if (this.dragStartPos) {
        const dx = Math.abs(position.x - this.dragStartPos.x);
        const dy = Math.abs(position.y - this.dragStartPos.y);
        if (dx > 3 || dy > 3) {
          this.hasDragged = true;
        }
      }

      // Move the entire selection container (all children move together automatically)
      if (this.dragOffset) {
        const newX = position.x + this.dragOffset.x;
        const newY = position.y + this.dragOffset.y;

        this.selectionContainer.x = newX;
        this.selectionContainer.y = newY;

        // Log drag movement (throttled)
        if (!this.lastDragLog || Date.now() - this.lastDragLog > 200) {
          console.log('[CanvasManager] Dragging selectionContainer to', { x: newX, y: newY }, 'children:', this.selectionContainer.children.length);
          this.lastDragLog = Date.now();
        }
      } else {
        console.error('[CanvasManager] isDragging but no dragOffset!');
      }

      // Update all selection boxes
      this.updateSelectionBoxes();

      // Update all object labels to follow dragged objects
      this.updateObjectLabels();

      // Update all lock indicators to follow dragged objects
      this.updateLockIndicators();

      // Broadcast positions for all selected objects during drag (throttled to avoid spam)
      if (!this.lastDragUpdate || Date.now() - this.lastDragUpdate > 50) {
        this.selectedObjects.forEach(obj => {
          // Skip if object has been destroyed (no parent means it's not in scene graph)
          if (!obj || !obj.parent) {
            console.warn('[CanvasManager] Skipping destroyed object in selectedObjects during drag');
            this.selectedObjects.delete(obj);
            return;
          }

          // Get world position of object for server update
          const worldPos = obj.getGlobalPosition();
          this.emit('update_object', {
            object_id: obj.objectId,
            position: { x: worldPos.x, y: worldPos.y }
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

    if (this.isLassoSelecting) {
      // Finalize lasso selection
      this.finalizeLassoSelection(event);
    } else if (this.isCreating) {
      // Finalize object creation
      this.finalizeTempObject(position);
    } else if (this.isDragging && this.selectedObjects.size > 0) {
      // Check if actual dragging occurred
      if (this.hasDragged) {
        console.log('[CanvasManager] Committing drag - actual movement detected');
        // Commit drag: get world positions, reset container, update local positions
        const updates = [];
        this.selectedObjects.forEach(obj => {
          // Skip if object has been destroyed
          if (!obj || !obj.parent) {
            console.warn('[CanvasManager] Skipping destroyed object in selectedObjects during drag commit');
            this.selectedObjects.delete(obj);
            return;
          }

          // Capture world position before resetting container
          const worldPos = obj.getGlobalPosition();
          updates.push({ obj, worldPos });
        });

        // Reset selection container to origin
        this.selectionContainer.x = 0;
        this.selectionContainer.y = 0;

        // Update each object's local position to maintain world position
        updates.forEach(({ obj, worldPos }) => {
          // Convert world position to selectionContainer's local space (now at 0,0)
          const localPos = this.selectionContainer.toLocal(worldPos);
          obj.x = localPos.x;
          obj.y = localPos.y;

          // Send final position to server
          this.emit('update_object', {
            object_id: obj.objectId,
            position: {
              x: worldPos.x,
              y: worldPos.y
            }
          });
        });

        // Update selection boxes to match new positions
        this.updateSelectionBoxes();
      } else {
        console.log('[CanvasManager] No movement detected - treating as click, not drag');
        // No actual movement - just a click, not a drag
        // Don't commit anything, just clear the drag state
      }

      this.isDragging = false;
      this.hasDragged = false;
      this.dragOffset = null;
      this.dragStartPos = null;
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
    // Don't handle keyboard shortcuts if user is typing
    const isTyping = event.target.tagName === 'INPUT' || event.target.tagName === 'TEXTAREA';

    // Handle Cmd/Ctrl+Z for Undo
    if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 'z' && !event.shiftKey) {
      if (!isTyping) {
        event.preventDefault();
        this.performUndo();
      }
      return;
    }

    // Handle Cmd/Ctrl+Shift+Z for Redo
    if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 'z' && event.shiftKey) {
      if (!isTyping) {
        event.preventDefault();
        this.performRedo();
      }
      return;
    }

    // Handle spacebar for panning
    if (event.code === 'Space' && !this.spacePressed) {
      if (isTyping) return;
      event.preventDefault();
      this.spacePressed = true;
      if (!this.isPanning) {
        this.app.canvas.style.cursor = 'grab';
      }
      return;
    }

    // Don't handle keyboard shortcuts if user is typing in an input
    if (isTyping) return;

    // Check for modifier keys
    const isMac = navigator.platform.toUpperCase().indexOf('MAC') >= 0;
    const cmdOrCtrl = isMac ? event.metaKey : event.ctrlKey;

    // Handle keyboard shortcuts with Cmd/Ctrl
    if (cmdOrCtrl) {
      switch (event.key.toLowerCase()) {
        case 'g':
          event.preventDefault();
          if (event.shiftKey) {
            this.ungroupSelected();
          } else {
            this.groupSelected();
          }
          return;
        case 'd':
          event.preventDefault();
          this.duplicateSelected();
          return;
        case 'c':
          event.preventDefault();
          this.copySelected();
          return;
        case 'v':
          event.preventDefault();
          this.pasteFromClipboard();
          return;
        case 'a':
          event.preventDefault();
          this.selectAll();
          return;
        case ']':
          event.preventDefault();
          if (event.shiftKey) {
            this.bringToFront();
          }
          return;
        case '[':
          event.preventDefault();
          if (event.shiftKey) {
            this.sendToBack();
          }
          return;
      }
    }

    // Handle arrow keys for nudging
    if (['ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight'].includes(event.key)) {
      if (this.selectedObjects.size > 0) {
        event.preventDefault();
        const nudgeAmount = event.shiftKey ? 10 : 1;
        this.nudgeSelected(event.key, nudgeAmount);
        return;
      }
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
        if (!cmdOrCtrl) {
          this.setTool('circle');
        }
        break;
      case 't':
        this.setTool('text');
        break;
      case 'd':
        if (!cmdOrCtrl) {
          this.setTool('delete');
        }
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
   * Create lasso selection rectangle for visual feedback
   * @param {Object} position - {x, y} starting position
   */
  createLassoRect(position) {
    if (this.lassoRect) {
      this.objectContainer.removeChild(this.lassoRect);
      this.lassoRect.destroy();
    }

    this.lassoRect = new PIXI.Graphics();
    this.lassoRect.x = position.x;
    this.lassoRect.y = position.y;
    this.lassoRect.alpha = 0.3;
    this.objectContainer.addChild(this.lassoRect);
  }

  /**
   * Update lasso selection rectangle during drag
   * @param {Object} currentPosition - {x, y} current position
   */
  updateLassoRect(currentPosition) {
    if (!this.lassoRect || !this.isLassoSelecting) return;

    const width = currentPosition.x - this.lassoStart.x;
    const height = currentPosition.y - this.lassoStart.y;

    this.lassoRect.clear();
    
    // Draw selection rectangle with dashed border effect
    this.lassoRect.rect(0, 0, width, height)
      .fill({ color: 0x3b82f6, alpha: 0.1 })
      .stroke({ width: 1, color: 0x1e40af });
  }

  /**
   * Finalize lasso selection and select objects within rectangle
   * @param {MouseEvent} event - Mouse event for shift key detection
   */
  finalizeLassoSelection(event) {
    if (!this.lassoRect || !this.isLassoSelecting) return;

    const endPos = this.getMousePosition(event);
    
    // Calculate selection rectangle bounds
    const minX = Math.min(this.lassoStart.x, endPos.x);
    const maxX = Math.max(this.lassoStart.x, endPos.x);
    const minY = Math.min(this.lassoStart.y, endPos.y);
    const maxY = Math.max(this.lassoStart.y, endPos.y);

    // Find objects within the lasso rectangle
    const width = maxX - minX;
    const height = maxY - minY;
    
    // Only process if lasso has reasonable size (at least 5px)
    if (width > 5 && height > 5) {
      // Clear previous selection unless shift is held
      if (!event.shiftKey) {
        this.clearSelection();
      }

      // Select all objects that intersect with the lasso rectangle
      this.objects.forEach((obj, objectId) => {
        const bounds = obj.getBounds();

        // Check if object intersects with lasso rectangle
        if (this.rectanglesIntersect(
          minX, minY, maxX, maxY,
          bounds.x, bounds.y, bounds.x + bounds.width, bounds.y + bounds.height
        )) {
          if (!this.selectedObjects.has(obj)) {
            // Reparent object to selection container
            this.addToSelection(obj);
            // Add to selection tracking
            this.selectedObjects.add(obj);
            this.emit('lock_object', { object_id: obj.objectId });
            this.createSelectionBox(obj);
          }
        }
      });
    }

    console.log('[CanvasManager] AFTER lasso loop, selectionContainer children:', this.selectionContainer.children.length, 'children IDs:', this.selectionContainer.children.map(c => c.objectId));

    // Remove lasso rect
    this.objectContainer.removeChild(this.lassoRect);
    this.lassoRect.destroy();
    this.lassoRect = null;
    this.isLassoSelecting = false;

    console.log('[CanvasManager] Lasso selection complete, selected', this.selectedObjects.size, 'objects');
    console.log('[CanvasManager] Selected object IDs:', Array.from(this.selectedObjects).map(o => o.objectId));
    console.log('[CanvasManager] FINAL check - selectionContainer children:', this.selectionContainer.children.length);
  }

  /**
   * Check if two rectangles intersect
   * @param {number} x1min - First rectangle min x
   * @param {number} y1min - First rectangle min y
   * @param {number} x1max - First rectangle max x
   * @param {number} y1max - First rectangle max y
   * @param {number} x2min - Second rectangle min x
   * @param {number} y2min - Second rectangle min y
   * @param {number} x2max - Second rectangle max x
   * @param {number} y2max - Second rectangle max y
   * @returns {boolean} True if rectangles intersect
   */
  rectanglesIntersect(x1min, y1min, x1max, y1max, x2min, y2min, x2max, y2max) {
    return !(x1max < x2min || x2max < x1min || y1max < y2min || y2max < y1min);
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

    // Reparent all objects back to their original parents
    this.selectedObjects.forEach(obj => {
      this.removeFromSelection(obj);
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

    // Reset selection container position to origin
    this.selectionContainer.x = 0;
    this.selectionContainer.y = 0;
  }

  /**
   * Add object to selection container (reparents to selectionContainer)
   * Preserves world position by converting coordinates between containers
   * @param {PIXI.DisplayObject} object - Object to add to selection
   */
  addToSelection(object) {
    if (!object || !object.objectId) {
      console.error('[CanvasManager] addToSelection: Invalid object', object);
      return;
    }

    console.log('[CanvasManager] addToSelection: object', object.objectId, 'current parent:', object.parent?.constructor?.name, 'selectionContainer children before:', this.selectionContainer.children.length);

    // Get world position before reparenting
    const worldPos = object.getGlobalPosition();

    // Store original parent and local state
    this.selectionData.set(object.objectId, {
      originalParent: object.parent,
      originalX: object.x,
      originalY: object.y,
      originalRotation: object.rotation,
      originalIndex: object.parent.getChildIndex(object)
    });

    // Remove from current parent and add to selection container
    object.parent.removeChild(object);
    this.selectionContainer.addChild(object);

    console.log('[CanvasManager] addToSelection: object', object.objectId, 'reparented, new parent:', object.parent?.constructor?.name, 'selectionContainer children after:', this.selectionContainer.children.length);

    // Convert world position to selection container's local space
    const localPos = this.selectionContainer.toLocal(worldPos);
    object.x = localPos.x;
    object.y = localPos.y;
  }

  /**
   * Remove object from selection container (reparents back to original parent)
   * Preserves world position by converting coordinates between containers
   * @param {PIXI.DisplayObject} object - Object to remove from selection
   */
  removeFromSelection(object) {
    if (!object || !object.objectId) {
      console.error('[CanvasManager] removeFromSelection: Invalid object', object);
      return;
    }

    console.log('[CanvasManager] removeFromSelection called for object', object.objectId, 'parent:', object.parent?.constructor?.name, 'selectionContainer children before:', this.selectionContainer.children.length);

    // If object is not in selection container, nothing to do
    if (object.parent !== this.selectionContainer) {
      console.log('[CanvasManager] removeFromSelection: object not in selectionContainer, skipping');
      this.selectionData.delete(object.objectId);
      return;
    }

    const savedData = this.selectionData.get(object.objectId);

    // If no saved data, fall back to moving to objectContainer at current world position
    if (!savedData) {
      console.warn('[CanvasManager] removeFromSelection: No saved data for object', object.objectId, '- moving to objectContainer');

      // Get world position before reparenting
      const worldPos = object.getGlobalPosition();

      // Remove from selection container and add to objectContainer
      this.selectionContainer.removeChild(object);
      this.objectContainer.addChild(object);

      // Convert world position to objectContainer's local space
      const localPos = this.objectContainer.toLocal(worldPos);
      object.x = localPos.x;
      object.y = localPos.y;
      return;
    }

    // Get world position before reparenting
    const worldPos = object.getGlobalPosition();

    // Remove from selection container
    this.selectionContainer.removeChild(object);

    // Add back to original parent at original index
    savedData.originalParent.addChildAt(object, savedData.originalIndex);

    // Convert world position to original parent's local space
    const localPos = savedData.originalParent.toLocal(worldPos);
    object.x = localPos.x;
    object.y = localPos.y;

    // Clean up saved data
    this.selectionData.delete(object.objectId);
  }

  /**
   * Set selection to a single object (clears previous selection)
   * @param {PIXI.DisplayObject} object - Object to select
   */
  setSelection(object) {
    // Clear previous selection
    console.log('[CanvasManager] setSelection: BEFORE clearSelection, selectionContainer children:', this.selectionContainer.children.length, 'children:', this.selectionContainer.children.map(c => ({ id: c.objectId, parent: c.parent?.constructor?.name })));
    this.clearSelection();

    // Reparent object to selection container
    this.addToSelection(object);

    // Add to selection tracking
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
      // Deselect - reparent back to original container
      this.removeFromSelection(object);
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
      // Add to selection - reparent to selection container
      this.addToSelection(object);
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
        // Skip if object is locked by another user (remote transform in progress)
        // Remote users should see glow, not selection boxes
        if (obj.lockedBy && obj.lockedBy !== this.currentUserId) {
          console.log('[CanvasManager] Hiding selection box for remote locked object', objectId, 'locked by', obj.lockedBy);
          box.visible = false;

          // Also hide rotation and resize handles
          const rotationHandle = this.rotationHandles.get(objectId);
          if (rotationHandle) rotationHandle.visible = false;

          const resizeHandle = this.resizeHandles.get(objectId);
          if (resizeHandle) resizeHandle.visible = false;

          return; // Skip updating positions
        }

        // Ensure visible for local objects or unlocked objects
        box.visible = true;

        // Use local bounds (container-relative)
        const bounds = obj.getLocalBounds();
        box.clear();
        box.rect(
          -2,
          -2,
          bounds.width + 4,
          bounds.height + 4
        ).stroke({ width: 2, color: 0x3b82f6 });

        // Update position to match object (convert to objectContainer space)
        const worldPos = obj.getGlobalPosition();
        const boxLocalPos = this.objectContainer.toLocal(worldPos);
        box.x = boxLocalPos.x;
        box.y = boxLocalPos.y;

        // Update rotation and pivot to match object (for rotated objects)
        box.angle = obj.angle;
        box.pivot.set(obj.pivot.x, obj.pivot.y);

        // Update rotation handle position (top-right corner)
        const rotationHandle = this.rotationHandles.get(objectId);
        if (rotationHandle) {
          rotationHandle.visible = true; // Ensure visible for local objects
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

          // Position handle at rotated corner position (convert to objectContainer space)
          const handleWorldX = worldPos.x + rotatedX;
          const handleWorldY = worldPos.y + rotatedY;
          const handleLocalPos = this.objectContainer.toLocal(new PIXI.Point(handleWorldX, handleWorldY));
          rotationHandle.x = handleLocalPos.x;
          rotationHandle.y = handleLocalPos.y;
        }

        // Update resize handle position (bottom-right corner)
        const resizeHandle = this.resizeHandles.get(objectId);
        if (resizeHandle) {
          resizeHandle.visible = true; // Ensure visible for local objects

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

          // Position handle at rotated corner position (convert to objectContainer space)
          const resizeWorldX = worldPos.x + rotatedX;
          const resizeWorldY = worldPos.y + rotatedY;
          const resizeLocalPos = this.objectContainer.toLocal(new PIXI.Point(resizeWorldX, resizeWorldY));
          resizeHandle.x = resizeLocalPos.x;
          resizeHandle.y = resizeLocalPos.y;

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

    console.log('[CanvasManager] PixiJS Object pointer down, objectId:', object.objectId, 'selectedObjects.size:', this.selectedObjects.size, 'has object:', this.selectedObjects.has(object));

    // Check if object is locked by another user
    const pixiObject = this.objects.get(object.objectId);
    if (pixiObject && pixiObject.lockedBy && pixiObject.lockedBy !== this.currentUserId) {
      // Object is locked by another user, prevent interaction
      console.log('[CanvasManager] Object is locked by another user');
      return;
    }

    if (this.currentTool === 'select') {
      // Check if clicked object is a child of selectionContainer
      // (This handles lasso selections properly since all selected objects are reparented there)
      const isInSelection = object.parent === this.selectionContainer;

      console.log('[CanvasManager] onObjectPointerDown: object', object.objectId, 'parent:', object.parent?.constructor?.name, 'isInSelection:', isInSelection, 'selectionContainer children:', this.selectionContainer.children.length, 'selectedObjects size:', this.selectedObjects.size);

      if (!isInSelection) {
        // Object is not in selection container, select it
        console.log('[CanvasManager] onObjectPointerDown: calling setSelection for object', object.objectId);
        this.setSelection(object);
      } else {
        console.log('[CanvasManager] onObjectPointerDown: object already in selection, preserving multi-selection');
      }

      // Prepare for dragging the selection container (all children move together)
      this.isDragging = true;
      this.hasDragged = false; // Track if actual movement occurs

      // Calculate single drag offset for selection container
      this.dragOffset = {
        x: this.selectionContainer.x - localPos.x,
        y: this.selectionContainer.y - localPos.y
      };

      // Store initial mouse position to detect clicks vs drags
      this.dragStartPos = { x: localPos.x, y: localPos.y };

      console.log('[CanvasManager] onObjectPointerDown: set dragOffset', this.dragOffset, 'selectionContainer pos:', { x: this.selectionContainer.x, y: this.selectionContainer.y });
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
   * Validate and sanitize color values to prevent NaN errors
   * @param {any} color - Color value to validate (can be string, number, null, undefined, NaN, etc.)
   * @returns {string|null} Valid hex color string or null if invalid
   */
  validateColor(color) {
    // Return null if color is not a valid string
    if (typeof color !== 'string' || !color || color === 'null' || color === 'undefined' || color === 'NaN') {
      console.warn('[CanvasManager] Invalid color value:', color, '- using default');
      return null;
    }

    // Check if it's a valid hex color format
    if (!/^#[0-9A-Fa-f]{6}$/.test(color)) {
      console.warn('[CanvasManager] Invalid hex color format:', color, '- using default');
      return null;
    }

    return color;
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
   * Group selected objects together
   */
  groupSelected() {
    if (this.selectedObjects.size < 2) {
      console.log('[CanvasManager] Need at least 2 objects to create a group');
      return;
    }

    const objectIds = this.getSelectedObjectIds();
    this.emit('create_group', { object_ids: objectIds });
    console.log('[CanvasManager] Creating group with objects:', objectIds);
  }

  /**
   * Ungroup selected objects
   */
  ungroupSelected() {
    if (this.selectedObjects.size === 0) {
      console.log('[CanvasManager] No objects selected to ungroup');
      return;
    }

    const objectIds = this.getSelectedObjectIds();
    this.emit('ungroup', { object_ids: objectIds });
    console.log('[CanvasManager] Ungrouping objects:', objectIds);
  }

  /**
   * Duplicate selected objects
   */
  duplicateSelected() {
    if (this.selectedObjects.size === 0) {
      console.log('[CanvasManager] No objects selected to duplicate');
      return;
    }

    this.selectedObjects.forEach(obj => {
      // Get the object's data
      const objectEntry = Array.from(this.objects.entries()).find(([id, pixiObj]) => pixiObj === obj);
      if (objectEntry) {
        const [objectId, pixiObj] = objectEntry;
        
        // Create duplicate with offset position
        this.emit('duplicate_object', {
          object_id: objectId,
          offset: { x: 20, y: 20 }
        });
      }
    });

    console.log('[CanvasManager] Duplicating selected objects');
  }

  /**
   * Copy selected objects to clipboard
   */
  copySelected() {
    if (this.selectedObjects.size === 0) {
      console.log('[CanvasManager] No objects selected to copy');
      return;
    }

    this.clipboard = [];
    this.selectedObjects.forEach(obj => {
      const objectEntry = Array.from(this.objects.entries()).find(([id, pixiObj]) => pixiObj === obj);
      if (objectEntry) {
        const [objectId, pixiObj] = objectEntry;
        
        // Store object data for pasting
        this.clipboard.push({
          id: objectId,
          x: pixiObj.x,
          y: pixiObj.y,
          angle: pixiObj.angle || 0
        });
      }
    });

    console.log('[CanvasManager] Copied', this.clipboard.length, 'objects to clipboard');
  }

  /**
   * Paste objects from clipboard
   */
  pasteFromClipboard() {
    if (this.clipboard.length === 0) {
      console.log('[CanvasManager] Clipboard is empty');
      return;
    }

    this.clipboard.forEach(clipboardItem => {
      this.emit('duplicate_object', {
        object_id: clipboardItem.id,
        offset: { x: 20, y: 20 }
      });
    });

    console.log('[CanvasManager] Pasting', this.clipboard.length, 'objects from clipboard');
  }

  /**
   * Nudge selected objects in a direction
   * @param {string} direction - Arrow key direction
   * @param {number} amount - Amount to nudge in pixels
   */
  nudgeSelected(direction, amount) {
    if (this.selectedObjects.size === 0) {
      return;
    }

    const delta = { x: 0, y: 0 };
    switch (direction) {
      case 'ArrowUp':
        delta.y = -amount;
        break;
      case 'ArrowDown':
        delta.y = amount;
        break;
      case 'ArrowLeft':
        delta.x = -amount;
        break;
      case 'ArrowRight':
        delta.x = amount;
        break;
    }

    // Update all selected objects
    this.selectedObjects.forEach(obj => {
      obj.x += delta.x;
      obj.y += delta.y;

      // Emit update to server
      this.emit('update_object', {
        object_id: obj.objectId,
        position: { x: obj.x, y: obj.y }
      });
    });

    // Update selection boxes
    this.updateSelectionBoxes();
  }

  /**
   * Select all objects on the canvas
   */
  selectAll() {
    this.clearSelection();

    this.objects.forEach((pixiObj, objectId) => {
      // Reparent to selection container
      this.addToSelection(pixiObj);
      // Add to selection tracking
      this.selectedObjects.add(pixiObj);
      this.emit('lock_object', { object_id: pixiObj.objectId });
      this.createSelectionBox(pixiObj);
    });

    console.log('[CanvasManager] Selected all', this.selectedObjects.size, 'objects');
  }

  /**
   * Bring selected objects to front
   */
  bringToFront() {
    if (this.selectedObjects.size === 0) {
      console.log('[CanvasManager] No objects selected');
      return;
    }

    this.selectedObjects.forEach(obj => {
      this.emit('bring_to_front', { object_id: obj.objectId });
    });

    console.log('[CanvasManager] Bringing', this.selectedObjects.size, 'objects to front');
  }

  /**
   * Send selected objects to back
   */
  sendToBack() {
    if (this.selectedObjects.size === 0) {
      console.log('[CanvasManager] No objects selected');
      return;
    }

    this.selectedObjects.forEach(obj => {
      this.emit('send_to_back', { object_id: obj.objectId });
    });

    console.log('[CanvasManager] Sending', this.selectedObjects.size, 'objects to back');
  }

  /**
   * Align selected objects
   * @param {string} alignment - 'left', 'right', 'center', 'top', 'bottom', 'middle'
   */
  alignObjects(alignment) {
    if (this.selectedObjects.size < 2) {
      console.log('[CanvasManager] Need at least 2 objects to align');
      return;
    }

    const selectedIds = this.getSelectedObjectIds();
    this.emit('align_objects', {
      object_ids: selectedIds,
      alignment: alignment
    });

    console.log('[CanvasManager] Aligning', selectedIds.length, 'objects:', alignment);
  }

  /**
   * Distribute selected objects horizontally
   */
  distributeHorizontally() {
    if (this.selectedObjects.size < 3) {
      console.log('[CanvasManager] Need at least 3 objects to distribute');
      return;
    }

    const selectedIds = this.getSelectedObjectIds();
    this.emit('distribute_objects', {
      object_ids: selectedIds,
      direction: 'horizontal'
    });

    console.log('[CanvasManager] Distributing', selectedIds.length, 'objects horizontally');
  }

  /**
   * Distribute selected objects vertically
   */
  distributeVertically() {
    if (this.selectedObjects.size < 3) {
      console.log('[CanvasManager] Need at least 3 objects to distribute');
      return;
    }

    const selectedIds = this.getSelectedObjectIds();
    this.emit('distribute_objects', {
      object_ids: selectedIds,
      direction: 'vertical'
    });

    console.log('[CanvasManager] Distributing', selectedIds.length, 'objects vertically');
  }

  /**
   * Show context menu for selected objects
   * @param {Object} position - {x, y} position for menu
   */
  showContextMenu(position) {
    if (this.selectedObjects.size === 0) {
      return;
    }

    this.emit('show_context_menu', {
      position: position,
      selected_count: this.selectedObjects.size
    });
  }

  /**
   * Export canvas to PNG
   * @param {boolean} selectionOnly - Export only selected objects
   */
  async exportToPNG(selectionOnly = false) {
    try {
      let renderTarget;
      
      if (selectionOnly && this.selectedObjects.size > 0) {
        // Calculate bounds of selected objects
        let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
        
        this.selectedObjects.forEach(obj => {
          const bounds = obj.getBounds();
          minX = Math.min(minX, bounds.x);
          minY = Math.min(minY, bounds.y);
          maxX = Math.max(maxX, bounds.x + bounds.width);
          maxY = Math.max(maxY, bounds.y + bounds.height);
        });
        
        const width = maxX - minX;
        const height = maxY - minY;
        
        // Create temporary container for selected objects
        const tempContainer = new PIXI.Container();
        tempContainer.x = -minX;
        tempContainer.y = -minY;
        
        this.selectedObjects.forEach(obj => {
          tempContainer.addChild(obj);
        });
        
        // Create render texture
        const renderTexture = PIXI.RenderTexture.create({
          width: Math.ceil(width),
          height: Math.ceil(height),
          resolution: window.devicePixelRatio || 1
        });
        
        this.app.renderer.render(tempContainer, { renderTexture });
        
        // Extract canvas and trigger download
        const canvas = this.app.renderer.extract.canvas(renderTexture);
        this.triggerDownload(canvas.toDataURL('image/png'), 'canvas-selection.png');
        
        // Restore objects to original container
        this.selectedObjects.forEach(obj => {
          this.objectContainer.addChild(obj);
        });
        
        tempContainer.destroy();
        renderTexture.destroy();
      } else {
        // Export entire canvas
        // Calculate bounds of all objects
        let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
        
        this.objects.forEach(obj => {
          const bounds = obj.getBounds();
          minX = Math.min(minX, bounds.x);
          minY = Math.min(minY, bounds.y);
          maxX = Math.max(maxX, bounds.x + bounds.width);
          maxY = Math.max(maxY, bounds.y + bounds.height);
        });
        
        const width = maxX - minX;
        const height = maxY - minY;
        
        // Create render texture
        const renderTexture = PIXI.RenderTexture.create({
          width: Math.ceil(width) || 800,
          height: Math.ceil(height) || 600,
          resolution: window.devicePixelRatio || 1
        });
        
        // Temporarily offset container
        const originalX = this.objectContainer.x;
        const originalY = this.objectContainer.y;
        this.objectContainer.x = -minX;
        this.objectContainer.y = -minY;
        
        this.app.renderer.render(this.objectContainer, { renderTexture });
        
        // Restore original position
        this.objectContainer.x = originalX;
        this.objectContainer.y = originalY;
        
        // Extract canvas and trigger download
        const canvas = this.app.renderer.extract.canvas(renderTexture);
        this.triggerDownload(canvas.toDataURL('image/png'), 'canvas-export.png');
        
        renderTexture.destroy();
      }
      
      console.log('[CanvasManager] PNG export complete');
    } catch (error) {
      console.error('[CanvasManager] PNG export failed:', error);
    }
  }

  /**
   * Export canvas to SVG
   * @param {boolean} selectionOnly - Export only selected objects
   */
  exportToSVG(selectionOnly = false) {
    try {
      const objectsToExport = selectionOnly && this.selectedObjects.size > 0
        ? Array.from(this.selectedObjects)
        : Array.from(this.objects.values());
      
      if (objectsToExport.length === 0) {
        console.warn('[CanvasManager] No objects to export');
        return;
      }
      
      // Calculate bounds
      let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
      
      objectsToExport.forEach(obj => {
        const bounds = obj.getBounds();
        minX = Math.min(minX, bounds.x);
        minY = Math.min(minY, bounds.y);
        maxX = Math.max(maxX, bounds.x + bounds.width);
        maxY = Math.max(maxY, bounds.y + bounds.height);
      });
      
      const width = maxX - minX;
      const height = maxY - minY;
      
      // Create SVG
      let svg = `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="${minX} ${minY} ${width} ${height}">
`;
      
      // Convert each object to SVG
      objectsToExport.forEach(obj => {
        svg += this.objectToSVG(obj);
      });
      
      svg += '</svg>';
      
      // Trigger download
      const blob = new Blob([svg], { type: 'image/svg+xml' });
      const url = URL.createObjectURL(blob);
      this.triggerDownload(url, 'canvas-export.svg');
      URL.revokeObjectURL(url);
      
      console.log('[CanvasManager] SVG export complete');
    } catch (error) {
      console.error('[CanvasManager] SVG export failed:', error);
    }
  }

  /**
   * Convert a PixiJS object to SVG string
   * @param {PIXI.DisplayObject} obj - Object to convert
   * @returns {string} SVG string
   */
  objectToSVG(obj) {
    let svg = '';
    
    if (obj instanceof PIXI.Graphics) {
      // Extract bounds and color info from the graphics object
      const bounds = obj.getBounds();
      const fill = obj.fill?.color !== undefined 
        ? `#${obj.fill.color.toString(16).padStart(6, '0')}`
        : '#3b82f6';
      const stroke = obj.stroke?.color !== undefined
        ? `#${obj.stroke.color.toString(16).padStart(6, '0')}`
        : fill;
      const strokeWidth = obj.stroke?.width || 2;
      
      // Simple rectangle approximation for graphics objects
      svg = `  <rect x="${bounds.x}" y="${bounds.y}" width="${bounds.width}" height="${bounds.height}" 
        fill="${fill}" stroke="${stroke}" stroke-width="${strokeWidth}" 
        opacity="${obj.alpha}" transform="rotate(${obj.angle} ${bounds.x + bounds.width/2} ${bounds.y + bounds.height/2})" />\n`;
    } else if (obj instanceof PIXI.Text) {
      const bounds = obj.getBounds();
      const fill = obj.style.fill || '#000000';
      const fontSize = obj.style.fontSize || 16;
      const fontFamily = obj.style.fontFamily || 'Arial';
      
      svg = `  <text x="${bounds.x}" y="${bounds.y + fontSize}" 
        fill="${fill}" font-size="${fontSize}" font-family="${fontFamily}" 
        opacity="${obj.alpha}">${obj.text}</text>\n`;
    }
    
    return svg;
  }

  /**
   * Trigger file download
   * @param {string} dataUrl - Data URL or blob URL
   * @param {string} filename - Filename for download
   */
  triggerDownload(dataUrl, filename) {
    const link = document.createElement('a');
    link.download = filename;
    link.href = dataUrl;
    link.click();
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
   * Show a subtle glow effect for remote transforms
   * @param {number} objectId - Object ID
   * @param {string} userId - User ID performing the transform
   */
  showRemoteTransformGlow(objectId, userId) {
    // Remove existing glow if any
    this.hideRemoteTransformGlow(objectId);

    const pixiObject = this.objects.get(objectId);
    if (!pixiObject) {
      console.log('[CanvasManager] showRemoteTransformGlow: pixiObject not found for', objectId);
      return;
    }

    // Get user's color from presence data
    const userData = this.presences[userId];
    const userColor = userData?.metas?.[0]?.color || '#3b82f6';
    const glowColor = parseInt(userColor.replace('#', '0x'));

    console.log('[CanvasManager] Creating glow for object', objectId, 'user', userId, 'color', userColor);

    // Create glow graphics
    const glow = new PIXI.Graphics();
    const bounds = pixiObject.getLocalBounds();

    // Draw subtle glow outline (larger than object, with transparency)
    const glowPadding = 8;
    glow.rect(
      -glowPadding,
      -glowPadding,
      bounds.width + glowPadding * 2,
      bounds.height + glowPadding * 2
    ).stroke({ width: 3, color: glowColor, alpha: 0.6 });

    // Position glow at object's position
    glow.x = pixiObject.x;
    glow.y = pixiObject.y;

    // Match rotation and pivot of the object
    glow.angle = pixiObject.angle;
    glow.pivot.set(pixiObject.pivot.x, pixiObject.pivot.y);

    // Store the color for later use during updates
    glow.strokeColor = glowColor;
    glow.userId = userId;

    this.objectContainer.addChild(glow);
    this.remoteTransformGlows.set(objectId, glow);
  }

  /**
   * Hide the remote transform glow for an object
   * @param {number} objectId - Object ID
   */
  hideRemoteTransformGlow(objectId) {
    const glow = this.remoteTransformGlows.get(objectId);
    if (glow) {
      if (glow.parent) {
        glow.parent.removeChild(glow);
      }
      glow.destroy();
      this.remoteTransformGlows.delete(objectId);
    }
  }

  /**
   * Set interpolation target for smooth animation
   * @param {number} objectId - Object ID
   * @param {Object} target - Target values {x, y, width, height, rotation}
   */
  setInterpolationTarget(objectId, target) {
    const pixiObject = this.objects.get(objectId);
    if (!pixiObject) return;

    const interpolationData = {
      startTime: Date.now(),
      duration: 150 // Animate over 150ms
    };

    // Only set position if it's being updated
    if (target.x !== undefined || target.y !== undefined) {
      interpolationData.startX = pixiObject.x;
      interpolationData.startY = pixiObject.y;
      interpolationData.targetX = target.x !== undefined ? target.x : pixiObject.x;
      interpolationData.targetY = target.y !== undefined ? target.y : pixiObject.y;
    }

    // Only set size if it's being updated (and NOT during rotation-only updates)
    if ((target.width !== undefined || target.height !== undefined) && !target.onlyRotation && !target.onlyPosition) {
      const bounds = pixiObject.getLocalBounds();
      interpolationData.startWidth = bounds.width;
      interpolationData.startHeight = bounds.height;
      interpolationData.targetWidth = target.width !== undefined ? target.width : bounds.width;
      interpolationData.targetHeight = target.height !== undefined ? target.height : bounds.height;
    }

    // Only set rotation if it's being updated (and NOT during resize-only updates)
    if (target.rotation !== undefined && !target.onlyResize && !target.onlyPosition) {
      interpolationData.startRotation = pixiObject.angle || 0;
      interpolationData.targetRotation = target.rotation;
    }

    this.interpolationTargets.set(objectId, interpolationData);
  }

  /**
   * Update interpolations for smooth remote transforms (called each frame)
   */
  updateInterpolations() {
    const now = Date.now();
    const completedInterpolations = [];

    this.interpolationTargets.forEach((target, objectId) => {
      const pixiObject = this.objects.get(objectId);
      if (!pixiObject) {
        completedInterpolations.push(objectId);
        return;
      }

      const elapsed = now - target.startTime;
      const progress = Math.min(elapsed / target.duration, 1.0);

      // Use easeOutCubic for smooth deceleration
      const eased = 1 - Math.pow(1 - progress, 3);

      // Interpolate position
      if (target.targetX !== undefined && target.startX !== undefined) {
        pixiObject.x = target.startX + (target.targetX - target.startX) * eased;
      }
      if (target.targetY !== undefined && target.startY !== undefined) {
        pixiObject.y = target.startY + (target.targetY - target.startY) * eased;
      }

      // Interpolate rotation
      if (target.targetRotation !== undefined && target.startRotation !== undefined) {
        let rotationDelta = target.targetRotation - target.startRotation;
        // Handle angle wrapping (shortest path)
        if (rotationDelta > 180) rotationDelta -= 360;
        if (rotationDelta < -180) rotationDelta += 360;
        pixiObject.angle = target.startRotation + rotationDelta * eased;
      }

      // Interpolate size
      if ((target.targetWidth !== undefined || target.targetHeight !== undefined) &&
          pixiObject instanceof PIXI.Graphics) {
        const width = target.startWidth + (target.targetWidth - target.startWidth) * eased;
        const height = target.startHeight + (target.targetHeight - target.startHeight) * eased;
        this.redrawGraphicsWithSize(pixiObject, width, height);
      }

      // Mark as complete if finished
      if (progress >= 1.0) {
        completedInterpolations.push(objectId);
      }
    });

    // Clean up completed interpolations
    completedInterpolations.forEach(objectId => {
      this.interpolationTargets.delete(objectId);
    });
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
