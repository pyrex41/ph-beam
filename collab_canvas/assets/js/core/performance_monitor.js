/**
 * PerformanceMonitor - FPS and rendering metrics tracking
 *
 * Tracks frame timing and calculates performance metrics with minimal overhead.
 * Uses requestAnimationFrame for accurate frame timing.
 */
export class PerformanceMonitor {
  /**
   * Create a PerformanceMonitor instance
   * @param {Object} config - Configuration options
   * @param {number} config.sampleSize - Number of frames to track for rolling average (default: 60)
   */
  constructor(config = {}) {
    this.sampleSize = config.sampleSize || 60;

    // Performance tracking state
    this.isRunning = false;
    this.frameCount = 0;
    this.frameTimes = [];
    this.lastFrameTime = 0;
    this.animationFrameId = null;

    // Session metrics
    this.minFps = Infinity;
    this.maxFps = 0;

    // Bind the update method for use with requestAnimationFrame
    this.update = this.update.bind(this);
  }

  /**
   * Start monitoring performance
   */
  start() {
    if (this.isRunning) {
      return;
    }

    this.isRunning = true;
    this.lastFrameTime = performance.now();
    this.animationFrameId = requestAnimationFrame(this.update);
  }

  /**
   * Stop monitoring performance
   */
  stop() {
    if (!this.isRunning) {
      return;
    }

    this.isRunning = false;

    if (this.animationFrameId !== null) {
      cancelAnimationFrame(this.animationFrameId);
      this.animationFrameId = null;
    }
  }

  /**
   * Reset all metrics
   */
  reset() {
    this.frameCount = 0;
    this.frameTimes = [];
    this.minFps = Infinity;
    this.maxFps = 0;
    this.lastFrameTime = 0;
  }

  /**
   * Get current performance metrics
   * @returns {Object} Metrics object with fps, avgFrameTime, minFps, maxFps
   */
  getMetrics() {
    if (this.frameTimes.length === 0) {
      return {
        fps: 0,
        avgFrameTime: 0,
        minFps: 0,
        maxFps: 0
      };
    }

    // Calculate average frame time from recent samples
    const sum = this.frameTimes.reduce((a, b) => a + b, 0);
    const avgFrameTime = sum / this.frameTimes.length;

    // Calculate current FPS from average frame time
    const fps = avgFrameTime > 0 ? 1000 / avgFrameTime : 0;

    return {
      fps: Math.round(fps * 100) / 100, // Round to 2 decimal places
      avgFrameTime: Math.round(avgFrameTime * 100) / 100,
      minFps: this.minFps === Infinity ? 0 : Math.round(this.minFps * 100) / 100,
      maxFps: Math.round(this.maxFps * 100) / 100
    };
  }

  /**
   * Internal update method called by requestAnimationFrame
   * @param {DOMHighResTimeStamp} currentTime - Current timestamp from rAF
   */
  update(currentTime) {
    if (!this.isRunning) {
      return;
    }

    // Calculate frame time (time since last frame)
    const frameTime = currentTime - this.lastFrameTime;
    this.lastFrameTime = currentTime;

    // Skip the first frame (it will have an artificially high frame time)
    if (this.frameCount > 0) {
      // Add to frame times array
      this.frameTimes.push(frameTime);

      // Keep only the most recent samples
      if (this.frameTimes.length > this.sampleSize) {
        this.frameTimes.shift();
      }

      // Update min/max FPS
      const currentFps = frameTime > 0 ? 1000 / frameTime : 0;
      if (currentFps > 0) {
        this.minFps = Math.min(this.minFps, currentFps);
        this.maxFps = Math.max(this.maxFps, currentFps);
      }
    }

    this.frameCount++;

    // Continue monitoring
    this.animationFrameId = requestAnimationFrame(this.update);
  }
}
