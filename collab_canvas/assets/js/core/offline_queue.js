/**
 * OfflineQueue - IndexedDB-backed operation queue for offline support
 * 
 * Queues canvas operations when offline and syncs them when reconnected.
 * Provides visual feedback about connection status.
 */
export class OfflineQueue {
  constructor(canvasId) {
    this.canvasId = canvasId;
    this.dbName = `collab_canvas_offline_${canvasId}`;
    this.storeName = 'operations';
    this.db = null;
    this.isOnline = navigator.onLine;
    this.maxQueueSize = 100; // More than the required 20
    this.syncCallback = null;
    this.statusCallback = null;
    
    // Initialize IndexedDB
    this.initDB();
    
    // Listen for online/offline events
    window.addEventListener('online', () => this.handleOnline());
    window.addEventListener('offline', () => this.handleOffline());
  }

  /**
   * Initialize IndexedDB database
   */
  async initDB() {
    return new Promise((resolve, reject) => {
      const request = indexedDB.open(this.dbName, 1);

      request.onerror = () => {
        console.error('[OfflineQueue] Error opening IndexedDB:', request.error);
        reject(request.error);
      };

      request.onsuccess = () => {
        this.db = request.result;
        console.log('[OfflineQueue] IndexedDB initialized');
        resolve();
      };

      request.onupgradeneeded = (event) => {
        const db = event.target.result;
        
        // Create object store if it doesn't exist
        if (!db.objectStoreNames.contains(this.storeName)) {
          const objectStore = db.createObjectStore(this.storeName, { 
            keyPath: 'id', 
            autoIncrement: true 
          });
          objectStore.createIndex('timestamp', 'timestamp', { unique: false });
          objectStore.createIndex('type', 'type', { unique: false });
        }
      };
    });
  }

  /**
   * Queue an operation for later sync
   * @param {string} type - Operation type: 'create', 'update', 'delete'
   * @param {Object} data - Operation data
   */
  async queueOperation(type, data) {
    if (!this.db) {
      console.warn('[OfflineQueue] DB not ready, waiting...');
      await this.initDB();
    }

    const operation = {
      type,
      data,
      timestamp: Date.now(),
      retries: 0
    };

    return new Promise(async (resolve, reject) => {
      const transaction = this.db.transaction([this.storeName], 'readwrite');
      const store = transaction.objectStore(this.storeName);
      const request = store.add(operation);

      request.onsuccess = async () => {
        console.log('[OfflineQueue] Operation queued:', type, request.result);
        this.updateStatus('offline', await this.getQueueSize());
        resolve(request.result);
      };

      request.onerror = () => {
        console.error('[OfflineQueue] Error queuing operation:', request.error);
        reject(request.error);
      };
    });
  }

  /**
   * Get current queue size
   */
  async getQueueSize() {
    if (!this.db) return 0;

    return new Promise((resolve) => {
      const transaction = this.db.transaction([this.storeName], 'readonly');
      const store = transaction.objectStore(this.storeName);
      const request = store.count();

      request.onsuccess = () => resolve(request.result);
      request.onerror = () => resolve(0);
    });
  }

  /**
   * Get all queued operations
   */
  async getQueuedOperations() {
    if (!this.db) return [];

    return new Promise((resolve, reject) => {
      const transaction = this.db.transaction([this.storeName], 'readonly');
      const store = transaction.objectStore(this.storeName);
      const request = store.getAll();

      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
  }

  /**
   * Clear a specific operation from the queue
   */
  async clearOperation(id) {
    if (!this.db) return;

    return new Promise((resolve, reject) => {
      const transaction = this.db.transaction([this.storeName], 'readwrite');
      const store = transaction.objectStore(this.storeName);
      const request = store.delete(id);

      request.onsuccess = () => resolve();
      request.onerror = () => reject(request.error);
    });
  }

  /**
   * Clear all operations from the queue
   */
  async clearAllOperations() {
    if (!this.db) return;

    return new Promise((resolve, reject) => {
      const transaction = this.db.transaction([this.storeName], 'readwrite');
      const store = transaction.objectStore(this.storeName);
      const request = store.clear();

      request.onsuccess = () => {
        console.log('[OfflineQueue] Queue cleared');
        resolve();
      };
      request.onerror = () => reject(request.error);
    });
  }

  /**
   * Handle online event - sync queued operations
   */
  async handleOnline() {
    console.log('[OfflineQueue] Connection restored, syncing queue...');
    this.isOnline = true;
    this.updateStatus('reconnecting', await this.getQueueSize());
    
    await this.syncQueue();
  }

  /**
   * Handle offline event
   */
  handleOffline() {
    console.log('[OfflineQueue] Connection lost, entering offline mode');
    this.isOnline = false;
    this.updateStatus('offline', 0);
  }

  /**
   * Sync all queued operations
   */
  async syncQueue() {
    const operations = await this.getQueuedOperations();
    
    if (operations.length === 0) {
      console.log('[OfflineQueue] No operations to sync');
      this.updateStatus('online', 0);
      return;
    }

    console.log(`[OfflineQueue] Syncing ${operations.length} operations...`);
    
    const startTime = Date.now();
    let successCount = 0;
    let failCount = 0;

    // Process operations in order
    for (const operation of operations) {
      try {
        // Call the sync callback if provided
        if (this.syncCallback) {
          await this.syncCallback(operation.type, operation.data);
        }
        
        // Remove from queue on success
        await this.clearOperation(operation.id);
        successCount++;
        
        // Update status during sync
        const remaining = operations.length - successCount - failCount;
        this.updateStatus('reconnecting', remaining);
      } catch (error) {
        console.error('[OfflineQueue] Error syncing operation:', error);
        failCount++;
        
        // Retry logic: remove if too many retries
        operation.retries = (operation.retries || 0) + 1;
        if (operation.retries >= 3) {
          console.warn('[OfflineQueue] Operation failed after 3 retries, removing:', operation);
          await this.clearOperation(operation.id);
        }
      }
    }

    const syncDuration = Date.now() - startTime;
    console.log(`[OfflineQueue] Sync complete: ${successCount} succeeded, ${failCount} failed in ${syncDuration}ms`);
    
    this.updateStatus('online', 0);
  }

  /**
   * Register a callback for syncing operations
   */
  onSync(callback) {
    this.syncCallback = callback;
  }

  /**
   * Register a callback for status updates
   */
  onStatusChange(callback) {
    this.statusCallback = callback;
  }

  /**
   * Update connection status
   */
  updateStatus(status, queueSize) {
    if (this.statusCallback) {
      this.statusCallback(status, queueSize);
    }
  }

  /**
   * Check if currently online
   */
  get online() {
    return this.isOnline;
  }

  /**
   * Cleanup resources
   */
  destroy() {
    if (this.db) {
      this.db.close();
      this.db = null;
    }
    
    window.removeEventListener('online', () => this.handleOnline());
    window.removeEventListener('offline', () => this.handleOffline());
  }
}
