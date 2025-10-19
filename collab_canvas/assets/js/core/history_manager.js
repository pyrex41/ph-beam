/**
 * HistoryManager - Undo/Redo System for Canvas Operations
 * 
 * Maintains a history stack of canvas operations with support for:
 * - Undo (Cmd/Ctrl+Z)
 * - Redo (Cmd/Ctrl+Shift+Z)
 * - Multi-object operations (treated as atomic actions)
 * - AI-generated operations (grouped as single undoable action)
 */
export class HistoryManager {
  constructor(maxHistorySize = 50) {
    this.undoStack = [];
    this.redoStack = [];
    this.maxHistorySize = maxHistorySize;
    this.currentBatch = null; // For batching multi-object operations
    this.undoCallback = null;
    this.redoCallback = null;
  }

  /**
   * Start a batch of operations (for multi-object or AI operations)
   * All operations added during a batch will be treated as a single undoable action
   */
  startBatch() {
    this.currentBatch = [];
  }

  /**
   * End the current batch and add it to the undo stack
   */
  endBatch() {
    if (this.currentBatch && this.currentBatch.length > 0) {
      this.undoStack.push({
        type: 'batch',
        operations: this.currentBatch,
        timestamp: Date.now()
      });
      
      // Enforce max size
      if (this.undoStack.length > this.maxHistorySize) {
        this.undoStack.shift();
      }
      
      // Clear redo stack when new action is added
      this.redoStack = [];
    }
    this.currentBatch = null;
  }

  /**
   * Add an operation to the history
   * @param {string} type - Operation type: 'create', 'update', 'delete'
   * @param {Object} data - Operation data
   * @param {Object} previousState - Previous state for undo (optional for creates)
   */
  addOperation(type, data, previousState = null) {
    const operation = {
      type,
      data,
      previousState,
      timestamp: Date.now()
    };

    // If batching, add to batch instead of undo stack
    if (this.currentBatch) {
      this.currentBatch.push(operation);
      return;
    }

    // Otherwise add directly to undo stack
    this.undoStack.push(operation);
    
    // Enforce max size
    if (this.undoStack.length > this.maxHistorySize) {
      this.undoStack.shift();
    }
    
    // Clear redo stack when new action is added
    this.redoStack = [];
  }

  /**
   * Undo the last operation or batch
   */
  async undo() {
    if (this.undoStack.length === 0) {
      console.log('[HistoryManager] Nothing to undo');
      return false;
    }

    const action = this.undoStack.pop();
    
    try {
      if (action.type === 'batch') {
        // Undo batch operations in reverse order
        for (let i = action.operations.length - 1; i >= 0; i--) {
          await this.undoOperation(action.operations[i]);
        }
      } else {
        await this.undoOperation(action);
      }
      
      // Add to redo stack
      this.redoStack.push(action);
      
      return true;
    } catch (error) {
      console.error('[HistoryManager] Error during undo:', error);
      // Put it back on the undo stack if it failed
      this.undoStack.push(action);
      return false;
    }
  }

  /**
   * Redo the last undone operation or batch
   */
  async redo() {
    if (this.redoStack.length === 0) {
      console.log('[HistoryManager] Nothing to redo');
      return false;
    }

    const action = this.redoStack.pop();
    
    try {
      if (action.type === 'batch') {
        // Redo batch operations in forward order
        for (const operation of action.operations) {
          await this.redoOperation(operation);
        }
      } else {
        await this.redoOperation(action);
      }
      
      // Add back to undo stack
      this.undoStack.push(action);
      
      return true;
    } catch (error) {
      console.error('[HistoryManager] Error during redo:', error);
      // Put it back on the redo stack if it failed
      this.redoStack.push(action);
      return false;
    }
  }

  /**
   * Undo a single operation
   */
  async undoOperation(operation) {
    if (this.undoCallback) {
      await this.undoCallback(operation);
    } else {
      console.warn('[HistoryManager] No undo callback registered');
    }
  }

  /**
   * Redo a single operation
   */
  async redoOperation(operation) {
    if (this.redoCallback) {
      await this.redoCallback(operation);
    } else {
      console.warn('[HistoryManager] No redo callback registered');
    }
  }

  /**
   * Register callback for undoing operations
   * @param {Function} callback - Function to call with operation to undo
   */
  onUndo(callback) {
    this.undoCallback = callback;
  }

  /**
   * Register callback for redoing operations
   * @param {Function} callback - Function to call with operation to redo
   */
  onRedo(callback) {
    this.redoCallback = callback;
  }

  /**
   * Check if undo is available
   */
  canUndo() {
    return this.undoStack.length > 0;
  }

  /**
   * Check if redo is available
   */
  canRedo() {
    return this.redoStack.length > 0;
  }

  /**
   * Get undo stack size
   */
  getUndoStackSize() {
    return this.undoStack.length;
  }

  /**
   * Get redo stack size
   */
  getRedoStackSize() {
    return this.redoStack.length;
  }

  /**
   * Clear all history
   */
  clear() {
    this.undoStack = [];
    this.redoStack = [];
    this.currentBatch = null;
  }
}
