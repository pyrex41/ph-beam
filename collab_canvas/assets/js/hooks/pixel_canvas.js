/**
 * PixelCanvas Hook for Phoenix LiveView
 *
 * High-performance canvas renderer for pixelated images.
 * Optimized for grids from 16x16 up to 256x256.
 *
 * Performance targets:
 * - 64x64 grid (4,096 pixels): < 100ms render time
 * - 128x128 grid (16,384 pixels): < 500ms render time
 *
 * Optimization strategies:
 * 1. Batch canvas operations to minimize reflow/repaint
 * 2. Use fillRect (hardware accelerated) for pixel squares
 * 3. Pre-calculate square dimensions to avoid redundant math
 * 4. Use requestAnimationFrame for grids > 64x64 to prevent blocking
 * 5. Clear canvas once before rendering to minimize state changes
 */
export default {
  /**
   * Hook lifecycle - mounted
   * Called when the hook is first attached to the DOM
   */
  mounted() {
    // Get canvas element from the hook's DOM element
    this.canvas = this.el.querySelector('canvas') || this.el;

    if (!this.canvas || this.canvas.tagName !== 'CANVAS') {
      console.error('[PixelCanvas] Canvas element not found in hook element');
      return;
    }

    // Get 2D rendering context
    // willReadFrequently: false because we only write, never read pixels
    this.ctx = this.canvas.getContext('2d', {
      alpha: false,           // No transparency needed, slight perf boost
      willReadFrequently: false  // Optimization hint for write-only canvas
    });

    if (!this.ctx) {
      console.error('[PixelCanvas] Failed to get 2D context');
      return;
    }

    // Cache canvas dimensions for performance
    this.canvasWidth = this.canvas.width;
    this.canvasHeight = this.canvas.height;

    // Performance monitoring (optional, can be removed in production)
    this.enablePerformanceMonitoring = this.el.dataset.perfMonitoring === 'true';

    // Track requestAnimationFrame ID for cleanup
    this.rafId = null;

    // Listen for render_pixels events from LiveView
    this.handleEvent('render_pixels', (payload) => {
      this.renderPixels(payload);
    });

    console.log('[PixelCanvas] Hook mounted, canvas size:', this.canvasWidth, 'x', this.canvasHeight);
  },

  /**
   * Render pixel data on canvas
   *
   * @param {Object} payload - Event payload from LiveView
   * @param {Array} payload.pixels - Array of {x, y, hex_color} objects
   * @param {Number} payload.width - Grid width (e.g., 64)
   * @param {Number} payload.height - Grid height (e.g., 64)
   */
  renderPixels(payload) {
    const { pixels, width, height } = payload;

    // Validation
    if (!pixels || !Array.isArray(pixels)) {
      console.error('[PixelCanvas] Invalid pixels data:', pixels);
      return;
    }

    if (!width || !height || width <= 0 || height <= 0) {
      console.error('[PixelCanvas] Invalid grid dimensions:', width, 'x', height);
      return;
    }

    // Performance mark (start)
    const startTime = this.enablePerformanceMonitoring ? performance.now() : null;

    // Calculate square size based on canvas and grid dimensions
    // For a 512x512 canvas with 64x64 grid: square_size = 512 / 64 = 8px
    const squareWidth = this.canvasWidth / width;
    const squareHeight = this.canvasHeight / height;

    // Clear entire canvas before rendering
    // Using clearRect is faster than fillRect for clearing
    this.ctx.clearRect(0, 0, this.canvasWidth, this.canvasHeight);

    // For grids larger than 64x64, use requestAnimationFrame to prevent blocking
    // This keeps the UI responsive even with large pixel counts
    const pixelCount = pixels.length;
    const useAsyncRendering = pixelCount > 4096; // 64x64 threshold

    if (useAsyncRendering) {
      this.renderPixelsAsync(pixels, squareWidth, squareHeight, startTime);
    } else {
      this.renderPixelsSync(pixels, squareWidth, squareHeight, startTime);
    }
  },

  /**
   * Synchronous rendering for small grids (<= 64x64)
   * Fastest approach for small pixel counts
   *
   * @param {Array} pixels - Pixel data
   * @param {Number} squareWidth - Width of each pixel square
   * @param {Number} squareHeight - Height of each pixel square
   * @param {Number|null} startTime - Performance monitoring start time
   */
  renderPixelsSync(pixels, squareWidth, squareHeight, startTime) {
    // Batch all fillRect operations together
    // The browser will optimize this into a single paint operation
    for (let i = 0; i < pixels.length; i++) {
      const pixel = pixels[i];

      // Set fill color (support both 'color' and 'hex_color' keys)
      this.ctx.fillStyle = pixel.color || pixel.hex_color;

      // Draw pixel square
      // x and y are grid coordinates (0-based), multiply by square size for canvas coordinates
      this.ctx.fillRect(
        pixel.x * squareWidth,
        pixel.y * squareHeight,
        squareWidth,
        squareHeight
      );
    }

    // Performance monitoring
    if (startTime !== null) {
      const renderTime = performance.now() - startTime;
      console.log(`[PixelCanvas] Rendered ${pixels.length} pixels in ${renderTime.toFixed(2)}ms (sync)`);

      // Warn if exceeding performance target
      if (pixels.length <= 4096 && renderTime > 100) {
        console.warn(`[PixelCanvas] Performance warning: 64x64 grid took ${renderTime.toFixed(2)}ms (target: <100ms)`);
      }
    }
  },

  /**
   * Asynchronous rendering for large grids (> 64x64)
   * Uses requestAnimationFrame to keep UI responsive
   * Renders in chunks to prevent blocking
   *
   * @param {Array} pixels - Pixel data
   * @param {Number} squareWidth - Width of each pixel square
   * @param {Number} squareHeight - Height of each pixel square
   * @param {Number|null} startTime - Performance monitoring start time
   */
  renderPixelsAsync(pixels, squareWidth, squareHeight, startTime) {
    // Cancel any existing animation frame to prevent conflicts
    if (this.rafId) {
      cancelAnimationFrame(this.rafId);
      this.rafId = null;
    }

    // Chunk size: render this many pixels per frame
    // 1024 pixels per frame keeps frame time under 16ms for 60fps
    const CHUNK_SIZE = 1024;
    let currentIndex = 0;

    const renderChunk = () => {
      const endIndex = Math.min(currentIndex + CHUNK_SIZE, pixels.length);

      // Render chunk
      for (let i = currentIndex; i < endIndex; i++) {
        const pixel = pixels[i];
        this.ctx.fillStyle = pixel.color || pixel.hex_color;
        this.ctx.fillRect(
          pixel.x * squareWidth,
          pixel.y * squareHeight,
          squareWidth,
          squareHeight
        );
      }

      currentIndex = endIndex;

      // Continue with next chunk or finish
      if (currentIndex < pixels.length) {
        this.rafId = requestAnimationFrame(renderChunk);
      } else {
        // All done, clear RAF ID
        this.rafId = null;

        if (startTime !== null) {
          // Log performance
          const renderTime = performance.now() - startTime;
          console.log(`[PixelCanvas] Rendered ${pixels.length} pixels in ${renderTime.toFixed(2)}ms (async, ${Math.ceil(pixels.length / CHUNK_SIZE)} chunks)`);

          // Warn if exceeding performance target
          if (pixels.length <= 16384 && renderTime > 500) {
            console.warn(`[PixelCanvas] Performance warning: 128x128 grid took ${renderTime.toFixed(2)}ms (target: <500ms)`);
          }
        }
      }
    };

    // Start async rendering
    this.rafId = requestAnimationFrame(renderChunk);
  },

  /**
   * Hook lifecycle - destroyed
   * Clean up resources when hook is removed from DOM
   */
  destroyed() {
    // Cancel any pending animation frames to prevent memory leaks
    if (this.rafId) {
      cancelAnimationFrame(this.rafId);
      this.rafId = null;
    }

    console.log('[PixelCanvas] Hook destroyed, resources cleaned up');
  }
};
