/**
 * SpatialHashGrid - Efficient 2D spatial partitioning for overlap detection
 *
 * Divides the canvas into a grid of cells and tracks which objects are in which cells.
 * This reduces overlap detection from O(n²) to O(9k) where k is the average number
 * of objects per cell (only need to check same cell + 8 adjacent cells).
 *
 * @example
 * const grid = new SpatialHashGrid(100); // 100x100 pixel cells
 * grid.insert(object, bounds);
 * const nearby = grid.getNearbyObjects(bounds);
 * grid.remove(object, bounds);
 */
export class SpatialHashGrid {
  /**
   * Create a spatial hash grid
   * @param {number} cellSize - Size of each grid cell in pixels (default: 100)
   */
  constructor(cellSize = 100) {
    this.cellSize = cellSize;
    // Map of "x,y" cell coordinates to Set of objects in that cell
    this.grid = new Map();
    // Map of object ID to Set of cell keys it occupies
    this.objectToCells = new Map();
  }

  /**
   * Convert world coordinates to cell coordinates
   * @param {number} x - World X coordinate
   * @param {number} y - World Y coordinate
   * @returns {{cellX: number, cellY: number}} Cell coordinates
   */
  worldToCell(x, y) {
    return {
      cellX: Math.floor(x / this.cellSize),
      cellY: Math.floor(y / this.cellSize)
    };
  }

  /**
   * Create a cell key from cell coordinates
   * @param {number} cellX - Cell X coordinate
   * @param {number} cellY - Cell Y coordinate
   * @returns {string} Cell key for Map lookup
   */
  cellKey(cellX, cellY) {
    return `${cellX},${cellY}`;
  }

  /**
   * Get all cells that a bounding box overlaps
   * @param {Object} bounds - Bounding box {x, y, width, height}
   * @returns {Array<string>} Array of cell keys
   */
  getCellsForBounds(bounds) {
    const minCell = this.worldToCell(bounds.x, bounds.y);
    const maxCell = this.worldToCell(bounds.x + bounds.width, bounds.y + bounds.height);

    const cells = [];
    for (let x = minCell.cellX; x <= maxCell.cellX; x++) {
      for (let y = minCell.cellY; y <= maxCell.cellY; y++) {
        cells.push(this.cellKey(x, y));
      }
    }
    return cells;
  }

  /**
   * Insert an object into the spatial grid
   * @param {Object} object - Object with an id property
   * @param {Object} bounds - Bounding box {x, y, width, height}
   */
  insert(object, bounds) {
    const objectId = object.id || object.objectId;

    // Remove from old cells if already tracked
    this.remove(object);

    const cells = this.getCellsForBounds(bounds);
    this.objectToCells.set(objectId, new Set(cells));

    // Add object to each cell it overlaps
    cells.forEach(cellKey => {
      if (!this.grid.has(cellKey)) {
        this.grid.set(cellKey, new Set());
      }
      this.grid.get(cellKey).add(object);
    });
  }

  /**
   * Remove an object from the spatial grid
   * @param {Object} object - Object with an id property
   */
  remove(object) {
    const objectId = object.id || object.objectId;
    const cells = this.objectToCells.get(objectId);

    if (!cells) return;

    // Remove object from all cells it was in
    cells.forEach(cellKey => {
      const cellObjects = this.grid.get(cellKey);
      if (cellObjects) {
        cellObjects.delete(object);
        // Clean up empty cells
        if (cellObjects.size === 0) {
          this.grid.delete(cellKey);
        }
      }
    });

    this.objectToCells.delete(objectId);
  }

  /**
   * Update an object's position in the grid
   * @param {Object} object - Object with an id property
   * @param {Object} bounds - New bounding box {x, y, width, height}
   */
  update(object, bounds) {
    this.insert(object, bounds); // insert() already handles removal
  }

  /**
   * Get all objects in cells overlapping the given bounds
   * (includes the object's own cell + 8 adjacent cells)
   * @param {Object} bounds - Bounding box {x, y, width, height}
   * @param {Object} [excludeObject] - Optional object to exclude from results
   * @returns {Set<Object>} Set of nearby objects
   */
  getNearbyObjects(bounds, excludeObject = null) {
    const cells = this.getCellsForBounds(bounds);
    const nearby = new Set();

    cells.forEach(cellKey => {
      const cellObjects = this.grid.get(cellKey);
      if (cellObjects) {
        cellObjects.forEach(obj => {
          if (obj !== excludeObject) {
            nearby.add(obj);
          }
        });
      }
    });

    return nearby;
  }

  /**
   * Check if two bounding boxes overlap
   * @param {Object} a - First bounding box {x, y, width, height}
   * @param {Object} b - Second bounding box {x, y, width, height}
   * @returns {boolean} True if boxes overlap
   */
  static boundsOverlap(a, b) {
    return !(
      a.x + a.width < b.x ||
      b.x + b.width < a.x ||
      a.y + a.height < b.y ||
      b.y + b.height < a.y
    );
  }

  /**
   * Find all objects that actually overlap with the given object
   * (uses spatial grid for coarse check, then precise bounds check)
   * @param {Object} object - Object to check overlaps for
   * @param {Object} bounds - Object's bounding box {x, y, width, height}
   * @returns {Set<Object>} Set of overlapping objects
   */
  getOverlappingObjects(object, bounds) {
    const nearby = this.getNearbyObjects(bounds, object);
    const overlapping = new Set();

    // Precise overlap check for nearby objects
    nearby.forEach(other => {
      // Get other object's bounds (assuming it has a getBounds or similar method)
      const otherBounds = other.pixiBounds || {
        x: other.x,
        y: other.y,
        width: other.width || 0,
        height: other.height || 0
      };

      if (SpatialHashGrid.boundsOverlap(bounds, otherBounds)) {
        overlapping.add(other);
      }
    });

    return overlapping;
  }

  /**
   * Clear all objects from the grid
   */
  clear() {
    this.grid.clear();
    this.objectToCells.clear();
  }

  /**
   * Get statistics about the grid (for debugging/optimization)
   * @returns {Object} Grid statistics
   */
  getStats() {
    const totalCells = this.grid.size;
    const totalObjects = this.objectToCells.size;
    let maxObjectsPerCell = 0;
    let totalObjectsInCells = 0;

    this.grid.forEach(cellObjects => {
      const count = cellObjects.size;
      totalObjectsInCells += count;
      if (count > maxObjectsPerCell) {
        maxObjectsPerCell = count;
      }
    });

    return {
      totalCells,
      totalObjects,
      maxObjectsPerCell,
      avgObjectsPerCell: totalCells > 0 ? (totalObjectsInCells / totalCells).toFixed(2) : 0,
      cellSize: this.cellSize
    };
  }
}
