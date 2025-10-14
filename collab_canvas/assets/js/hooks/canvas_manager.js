import * as PIXI from 'pixi.js';

/**
 * CanvasManager Hook for Phoenix LiveView
 *
 * This hook manages the PixiJS application and canvas rendering,
 * handling object creation, updates, deletion, and user interactions.
 */
export default {
  /**
   * Hook lifecycle - mounted
   */
  mounted() {
    // Store current user ID
    this.currentUserId = this.el.dataset.userId;

    this.setupPixiApp();
    this.setupEventListeners();
    this.loadInitialObjects();
    this.loadInitialPresences();
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
   * Initialize PixiJS Application
   */
  setupPixiApp() {
    // Get canvas container dimensions
    const container = this.el;
    const width = container.clientWidth;
    const height = container.clientHeight;

    // Create PixiJS application (v7 API)
    this.app = new PIXI.Application({
      width: width,
      height: height,
      backgroundColor: 0xffffff,
      antialias: true,
      resolution: window.devicePixelRatio || 1,
      autoDensity: true
    });

    // Add canvas to DOM
    container.appendChild(this.app.view);

    // Create main container for objects
    this.objectContainer = new PIXI.Container();
    this.app.stage.addChild(this.objectContainer);

    // Create cursor overlay container
    this.cursorContainer = new PIXI.Container();
    this.app.stage.addChild(this.cursorContainer);

    // Store object references
    this.objects = new Map();
    this.cursors = new Map();

    // Interaction state
    this.selectedObject = null;
    this.isDragging = false;
    this.dragOffset = { x: 0, y: 0 };
    this.currentTool = 'select';
    this.isCreating = false;
    this.createStart = { x: 0, y: 0 };
    this.tempObject = null;
    this.selectionBox = null;

    // Pan and zoom state
    this.isPanning = false;
    this.panStart = { x: 0, y: 0 };
    this.viewOffset = { x: 0, y: 0 };
    this.zoomLevel = 1;
    this.spacePressed = false;
  },

  /**
   * Setup event listeners for user interactions
   */
  setupEventListeners() {
    const canvas = this.app.view;

    // Mouse events
    canvas.addEventListener('mousedown', this.handleMouseDown.bind(this));
    canvas.addEventListener('mousemove', this.handleMouseMove.bind(this));
    canvas.addEventListener('mouseup', this.handleMouseUp.bind(this));
    canvas.addEventListener('wheel', this.handleWheel.bind(this));

    // Touch events for mobile
    canvas.addEventListener('touchstart', this.handleTouchStart.bind(this));
    canvas.addEventListener('touchmove', this.handleTouchMove.bind(this));
    canvas.addEventListener('touchend', this.handleTouchEnd.bind(this));

    // Keyboard events
    window.addEventListener('keydown', this.handleKeyDown.bind(this));
    window.addEventListener('keyup', this.handleKeyUp.bind(this));

    // Window resize
    window.addEventListener('resize', this.handleResize.bind(this));
  },

  /**
   * Load initial objects from data attributes
   */
  loadInitialObjects() {
    const objectsData = this.el.dataset.objects;
    if (objectsData) {
      try {
        const objects = JSON.parse(objectsData);
        objects.forEach(obj => this.createObject(obj));
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
        this.updatePresences(presences);
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
      this.createObject(data.object);
    });

    // Handle object updated events
    this.handleEvent('object_updated', (data) => {
      this.updateObject(data.object);
    });

    // Handle object deleted events
    this.handleEvent('object_deleted', (data) => {
      this.deleteObject(data.object_id);
    });

    // Handle cursor position updates from other users
    this.handleEvent('cursor_moved', (data) => {
      this.updateCursor(data.user_id, data.position);
    });

    // Handle presence updates
    this.handleEvent('presence_updated', (data) => {
      this.updatePresences(data.presences);
    });

    // Handle tool selection updates from server
    this.handleEvent('tool_selected', (data) => {
      this.currentTool = data.tool;
    });
  },

  /**
   * Create a visual object on the canvas
   */
  createObject(objectData) {
    // Skip if object already exists
    if (this.objects.has(objectData.id)) {
      return;
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

    // Store object reference
    pixiObject.objectId = objectData.id;
    pixiObject.eventMode = 'static'; // Replaces interactive = true
    pixiObject.cursor = 'pointer'; // Replaces buttonMode = true

    // Add event listeners for interaction
    pixiObject.on('pointerdown', this.onObjectPointerDown.bind(this));
    pixiObject.on('pointermove', this.onObjectPointerMove.bind(this));
    pixiObject.on('pointerup', this.onObjectPointerUp.bind(this));

    this.objects.set(objectData.id, pixiObject);
    this.objectContainer.addChild(pixiObject);
  },

  /**
   * Create a rectangle shape
   */
  createRectangle(position, data) {
    const graphics = new PIXI.Graphics();
    const width = data.width || 100;
    const height = data.height || 100;
    const fill = parseInt(data.fill?.replace('#', '0x') || '0x3b82f6');
    const stroke = parseInt(data.stroke?.replace('#', '0x') || '0x1e40af');
    const strokeWidth = data.stroke_width || 2;

    graphics.beginFill(fill);
    graphics.lineStyle(strokeWidth, stroke);
    graphics.drawRect(0, 0, width, height);
    graphics.endFill();

    graphics.x = position.x;
    graphics.y = position.y;

    return graphics;
  },

  /**
   * Create a circle shape
   */
  createCircle(position, data) {
    const graphics = new PIXI.Graphics();
    const radius = (data.width || 100) / 2;
    const fill = parseInt(data.fill?.replace('#', '0x') || '0x3b82f6');
    const stroke = parseInt(data.stroke?.replace('#', '0x') || '0x1e40af');
    const strokeWidth = data.stroke_width || 2;

    graphics.beginFill(fill);
    graphics.lineStyle(strokeWidth, stroke);
    graphics.drawCircle(radius, radius, radius);
    graphics.endFill();

    graphics.x = position.x;
    graphics.y = position.y;

    return graphics;
  },

  /**
   * Create text object
   */
  createText(position, data) {
    const style = new PIXI.TextStyle({
      fontFamily: data.font_family || 'Arial',
      fontSize: data.font_size || 16,
      fill: data.color || '#000000',
      align: data.align || 'left'
    });

    const text = new PIXI.Text(data.text || 'Text', style);
    text.x = position.x;
    text.y = position.y;

    return text;
  },

  /**
   * Update an existing object
   */
  updateObject(objectData) {
    const pixiObject = this.objects.get(objectData.id);
    if (!pixiObject) {
      // Object doesn't exist, create it
      this.createObject(objectData);
      return;
    }

    // Update position if changed
    if (objectData.position) {
      pixiObject.x = objectData.position.x;
      pixiObject.y = objectData.position.y;
    }

    // For more complex updates, recreate the object
    if (objectData.data) {
      this.deleteObject(objectData.id);
      this.createObject(objectData);
    }
  },

  /**
   * Delete an object from the canvas
   */
  deleteObject(objectId) {
    const pixiObject = this.objects.get(objectId);
    if (pixiObject) {
      this.objectContainer.removeChild(pixiObject);
      pixiObject.destroy();
      this.objects.delete(objectId);
    }
  },

  /**
   * Update cursor position for another user
   */
  updateCursor(userId, userData, position) {
    // Don't show cursor if position is invalid or at initial (0, 0)
    if (!position || typeof position.x !== 'number' || typeof position.y !== 'number') {
      return;
    }

    // Don't show cursor at origin (0, 0) - likely user hasn't moved yet
    // Only show it once they've actually moved their cursor
    if (position.x === 0 && position.y === 0) {
      // Remove cursor if it exists (user might have moved away and come back to origin)
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
      cursor.beginFill(cursorColor);
      cursor.moveTo(0, 0);
      cursor.lineTo(0, 20);
      cursor.lineTo(6, 15);
      cursor.lineTo(10, 22);
      cursor.lineTo(14, 19);
      cursor.lineTo(10, 12);
      cursor.lineTo(18, 12);
      cursor.closePath();
      cursor.endFill();

      // User email/name label
      const displayName = userData.email || userData.name || 'User';
      const label = new PIXI.Text(displayName, {
        fontFamily: 'Arial',
        fontSize: 12,
        fill: 0xffffff,
        fontWeight: 'bold'
      });
      label.x = 25;
      label.y = 6;

      // Create label background sized to fit text - use same color as cursor
      const labelBg = new PIXI.Graphics();
      labelBg.beginFill(cursorColor);
      labelBg.drawRoundedRect(0, 0, label.width + 10, 24, 4);
      labelBg.endFill();
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
  },

  /**
   * Update presence list
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
  },

  /**
   * Handle mouse down events
   */
  handleMouseDown(event) {
    const position = this.getMousePosition(event);

    // Start panning with spacebar+click, shift+click, or middle mouse
    if (this.spacePressed || event.shiftKey || event.button === 1) {
      this.isPanning = true;
      this.panStart = { x: event.clientX, y: event.clientY };
      this.app.view.style.cursor = 'grabbing';
      event.preventDefault();
      return;
    }

    // Check if clicking on canvas (not on an object)
    const clickedObject = this.findObjectAt(position);

    if (this.currentTool === 'select') {
      if (clickedObject) {
        // Select and prepare to drag
        this.showSelection(clickedObject);
      } else {
        // Deselect
        this.clearSelection();
      }
    } else if (this.currentTool === 'delete') {
      if (clickedObject) {
        this.safePushEvent('delete_object', {
          object_id: clickedObject.objectId
        });
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
        this.safePushEvent('create_object', {
          type: 'text',
          position: position,
          data: {
            text: text,
            font_size: 16,
            color: '#000000',
            font_family: 'Arial'
          }
        });
      }
      // Switch back to select tool after creating text
      this.setTool('select');
    }
  },

  /**
   * Create temporary object for visual feedback during creation
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
  },

  /**
   * Update temporary object during creation
   */
  updateTempObject(currentPosition) {
    if (!this.tempObject || !this.isCreating) return;

    const width = currentPosition.x - this.createStart.x;
    const height = currentPosition.y - this.createStart.y;

    this.tempObject.clear();
    this.tempObject.lineStyle(2, 0x1e40af);
    this.tempObject.beginFill(0x3b82f6, 0.3);

    if (this.currentTool === 'rectangle') {
      this.tempObject.drawRect(0, 0, width, height);
    } else if (this.currentTool === 'circle') {
      const radius = Math.max(Math.abs(width), Math.abs(height)) / 2;
      this.tempObject.drawCircle(width / 2, height / 2, radius);
    }

    this.tempObject.endFill();
  },

  /**
   * Finalize temporary object creation
   */
  finalizeTempObject(endPosition) {
    if (!this.tempObject || !this.isCreating) return;

    const width = Math.abs(endPosition.x - this.createStart.x);
    const height = Math.abs(endPosition.y - this.createStart.y);

    // Only create if size is reasonable (at least 10px)
    if (width > 10 && height > 10) {
      const position = {
        x: Math.min(this.createStart.x, endPosition.x),
        y: Math.min(this.createStart.y, endPosition.y)
      };

      if (this.currentTool === 'rectangle') {
        this.safePushEvent('create_object', {
          type: 'rectangle',
          position: position,
          data: {
            width: width,
            height: height,
            fill: '#3b82f6',
            stroke: '#1e40af',
            stroke_width: 2
          }
        });
      } else if (this.currentTool === 'circle') {
        const radius = Math.max(width, height) / 2;
        this.safePushEvent('create_object', {
          type: 'circle',
          position: position,
          data: {
            width: radius * 2,
            fill: '#3b82f6',
            stroke: '#1e40af',
            stroke_width: 2
          }
        });
      }
    }

    // Clean up temp object
    this.objectContainer.removeChild(this.tempObject);
    this.tempObject.destroy();
    this.tempObject = null;
    this.isCreating = false;
  },

  /**
   * Find object at given position
   */
  findObjectAt(position) {
    // Check objects in reverse order (top to bottom)
    const objectsArray = Array.from(this.objects.values()).reverse();

    for (const obj of objectsArray) {
      const bounds = obj.getBounds();
      if (
        position.x >= bounds.x &&
        position.x <= bounds.x + bounds.width &&
        position.y >= bounds.y &&
        position.y <= bounds.y + bounds.height
      ) {
        return obj;
      }
    }

    return null;
  },

  /**
   * Handle mouse move events
   */
  handleMouseMove(event) {
    const position = this.getMousePosition(event);

    // Update cursor position for other users (throttled to avoid spam)
    if (!this.isPanning && (!this.lastCursorUpdate || Date.now() - this.lastCursorUpdate > 50)) {
      this.safePushEvent('cursor_move', { position: position });
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
      this.cursorContainer.x = this.viewOffset.x;
      this.cursorContainer.y = this.viewOffset.y;

      this.panStart = { x: event.clientX, y: event.clientY };
    } else if (this.isCreating) {
      // Update temp object while creating
      this.updateTempObject(position);
    } else if (this.isDragging && this.selectedObject) {
      // Move selected object
      const newX = position.x + this.dragOffset.x;
      const newY = position.y + this.dragOffset.y;

      this.selectedObject.x = newX;
      this.selectedObject.y = newY;

      // Update selection box
      if (this.selectionBox) {
        const bounds = this.selectedObject.getBounds();
        this.selectionBox.clear();
        this.selectionBox.lineStyle(2, 0x3b82f6, 1);
        this.selectionBox.drawRect(
          bounds.x - 2,
          bounds.y - 2,
          bounds.width + 4,
          bounds.height + 4
        );
      }
    }
  },

  /**
   * Handle mouse up events
   */
  handleMouseUp(event) {
    const position = this.getMousePosition(event);

    if (this.isCreating) {
      // Finalize object creation
      this.finalizeTempObject(position);
    } else if (this.isDragging && this.selectedObject) {
      // Send update to server after dragging
      this.safePushEvent('update_object', {
        object_id: this.selectedObject.objectId,
        position: {
          x: this.selectedObject.x,
          y: this.selectedObject.y
        }
      });
      this.isDragging = false;
    }

    if (this.isPanning) {
      this.isPanning = false;
      // Restore cursor based on spacebar state
      this.app.view.style.cursor = this.spacePressed ? 'grab' : 'default';
    }
  },

  /**
   * Handle mouse wheel for zoom and pan
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
      this.cursorContainer.scale.set(newZoom, newZoom);
    } else {
      // Pan with trackpad scroll or mouse wheel
      // Use deltaX and deltaY for two-finger trackpad scrolling
      this.viewOffset.x -= event.deltaX;
      this.viewOffset.y -= event.deltaY;
      this.objectContainer.x = this.viewOffset.x;
      this.objectContainer.y = this.viewOffset.y;
      this.cursorContainer.x = this.viewOffset.x;
      this.cursorContainer.y = this.viewOffset.y;
    }
  },

  /**
   * Handle touch events
   */
  handleTouchStart(event) {
    if (event.touches.length === 1) {
      this.handleMouseDown(event.touches[0]);
    }
  },

  handleTouchMove(event) {
    if (event.touches.length === 1) {
      this.handleMouseMove(event.touches[0]);
    }
  },

  handleTouchEnd(event) {
    this.handleMouseUp(event);
  },

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
        this.app.view.style.cursor = 'grab';
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
        if (this.selectedObject) {
          event.preventDefault();
          this.safePushEvent('delete_object', {
            object_id: this.selectedObject.objectId
          });
          this.clearSelection();
        }
        break;
      case 'escape':
        this.clearSelection();
        this.setTool('select');
        break;
      case 'r':
        // Rectangle tool
        this.setTool('rectangle');
        break;
      case 'c':
        // Circle tool
        this.setTool('circle');
        break;
      case 't':
        // Text tool
        this.setTool('text');
        break;
      case 'd':
        // Delete/select tool
        this.setTool('delete');
        break;
      case 's':
        // Select tool
        this.setTool('select');
        break;
    }
  },

  handleKeyUp(event) {
    // Handle spacebar release
    if (event.code === 'Space') {
      this.spacePressed = false;
      if (!this.isPanning) {
        this.app.view.style.cursor = 'default';
      }
    }
  },

  /**
   * Set the current tool
   */
  setTool(tool) {
    this.currentTool = tool;
    // Send tool change to server so UI can update
    this.safePushEvent('select_tool', { tool: tool });
  },

  /**
   * Clear object selection
   */
  clearSelection() {
    if (this.selectedObject && this.selectionBox) {
      this.objectContainer.removeChild(this.selectionBox);
      this.selectionBox.destroy();
      this.selectionBox = null;
    }
    this.selectedObject = null;
  },

  /**
   * Show selection box around object
   */
  showSelection(object) {
    // Remove previous selection
    this.clearSelection();

    // Create selection box
    this.selectionBox = new PIXI.Graphics();
    const bounds = object.getBounds();

    this.selectionBox.lineStyle(2, 0x3b82f6, 1);
    this.selectionBox.drawRect(
      bounds.x - 2,
      bounds.y - 2,
      bounds.width + 4,
      bounds.height + 4
    );

    this.objectContainer.addChild(this.selectionBox);
    this.selectedObject = object;
  },

  /**
   * Handle window resize
   */
  handleResize() {
    const width = this.el.clientWidth;
    const height = this.el.clientHeight;
    this.app.renderer.resize(width, height);
  },

  /**
   * Object interaction handlers (now simplified with global mouse handlers)
   */
  onObjectPointerDown(event) {
    // Prevent event bubbling
    event.stopPropagation();

    const object = event.currentTarget;
    const globalPos = event.data.global;
    const localPos = this.screenToCanvas(globalPos);

    if (this.currentTool === 'select') {
      // Show selection and prepare for drag
      this.showSelection(object);
      this.isDragging = true;
      this.dragOffset = {
        x: object.x - localPos.x,
        y: object.y - localPos.y
      };
    } else if (this.currentTool === 'delete') {
      // Delete object
      this.safePushEvent('delete_object', {
        object_id: object.objectId
      });
    }
  },

  onObjectPointerMove(event) {
    // Handled by global mouse move handler
  },

  onObjectPointerUp(event) {
    // Handled by global mouse up handler
  },

  /**
   * Convert screen position to canvas position
   */
  screenToCanvas(screenPos) {
    return {
      x: (screenPos.x - this.viewOffset.x) / this.zoomLevel,
      y: (screenPos.y - this.viewOffset.y) / this.zoomLevel
    };
  },

  /**
   * Get mouse position relative to canvas
   */
  getMousePosition(event) {
    const rect = this.app.view.getBoundingClientRect();
    return {
      x: (event.clientX - rect.left - this.viewOffset.x) / this.zoomLevel,
      y: (event.clientY - rect.top - this.viewOffset.y) / this.zoomLevel
    };
  },

  /**
   * Hook lifecycle - destroyed
   */
  destroyed() {
    // Clean up PixiJS application
    if (this.app) {
      this.app.destroy(true);
    }

    // Remove event listeners
    window.removeEventListener('keydown', this.handleKeyDown.bind(this));
    window.removeEventListener('keyup', this.handleKeyUp.bind(this));
    window.removeEventListener('resize', this.handleResize.bind(this));
  }
};