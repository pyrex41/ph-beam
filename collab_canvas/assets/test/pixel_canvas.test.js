/**
 * Tests for PixelCanvas Hook
 *
 * These tests verify the rendering logic and performance characteristics
 * of the pixel canvas hook.
 */

import { describe, it, expect, beforeEach, vi } from 'vitest';
import PixelCanvas from '../js/hooks/pixel_canvas';

describe('PixelCanvas Hook', () => {
  let canvas;
  let ctx;
  let hook;

  beforeEach(() => {
    // Create a mock canvas element
    canvas = document.createElement('canvas');
    canvas.width = 512;
    canvas.height = 512;
    canvas.id = 'test-pixel-canvas';

    // Create mock 2D context
    ctx = {
      clearRect: vi.fn(),
      fillRect: vi.fn(),
      fillStyle: null
    };

    // Mock getContext
    canvas.getContext = vi.fn(() => ctx);

    // Create container div (hook should be attached to parent, not canvas)
    const container = document.createElement('div');
    container.appendChild(canvas);

    // Create hook instance with mocked methods
    hook = {
      el: container,
      handleEvent: vi.fn(),
      canvas: null,
      ctx: null,
      canvasWidth: null,
      canvasHeight: null,
      enablePerformanceMonitoring: false
    };
  });

  describe('mounted()', () => {
    it('should find canvas element and get 2D context', () => {
      PixelCanvas.mounted.call(hook);

      expect(hook.canvas).toBe(canvas);
      expect(hook.ctx).toBe(ctx);
      expect(canvas.getContext).toHaveBeenCalledWith('2d', {
        alpha: false,
        willReadFrequently: false
      });
    });

    it('should cache canvas dimensions', () => {
      PixelCanvas.mounted.call(hook);

      expect(hook.canvasWidth).toBe(512);
      expect(hook.canvasHeight).toBe(512);
    });

    it('should register render_pixels event handler', () => {
      PixelCanvas.mounted.call(hook);

      expect(hook.handleEvent).toHaveBeenCalledWith('render_pixels', expect.any(Function));
    });

    it('should handle missing canvas element gracefully', () => {
      const emptyHook = {
        el: document.createElement('div'),
        handleEvent: vi.fn()
      };

      // Should not throw
      expect(() => PixelCanvas.mounted.call(emptyHook)).not.toThrow();
    });
  });

  describe('renderPixels()', () => {
    beforeEach(() => {
      PixelCanvas.mounted.call(hook);
    });

    it('should clear canvas before rendering', () => {
      const payload = {
        pixels: [{ x: 0, y: 0, hex_color: '#FF0000' }],
        width: 16,
        height: 16
      };

      hook.renderPixels(payload);

      expect(ctx.clearRect).toHaveBeenCalledWith(0, 0, 512, 512);
    });

    it('should calculate correct square size for 64x64 grid', () => {
      const payload = {
        pixels: [{ x: 0, y: 0, hex_color: '#FF0000' }],
        width: 64,
        height: 64
      };

      hook.renderPixels(payload);

      // 512 / 64 = 8px per square
      expect(ctx.fillRect).toHaveBeenCalledWith(0, 0, 8, 8);
    });

    it('should render pixel at correct position', () => {
      const payload = {
        pixels: [{ x: 5, y: 3, hex_color: '#00FF00' }],
        width: 32,
        height: 32
      };

      hook.renderPixels(payload);

      // 512 / 32 = 16px per square
      // x: 5 * 16 = 80, y: 3 * 16 = 48
      expect(ctx.fillRect).toHaveBeenCalledWith(80, 48, 16, 16);
    });

    it('should set correct fill color', () => {
      const payload = {
        pixels: [{ x: 0, y: 0, hex_color: '#FF00FF' }],
        width: 16,
        height: 16
      };

      hook.renderPixels(payload);

      expect(ctx.fillStyle).toBe('#FF00FF');
    });

    it('should handle invalid payload gracefully', () => {
      const consoleSpy = vi.spyOn(console, 'error').mockImplementation(() => {});

      // Missing pixels array
      hook.renderPixels({ width: 64, height: 64 });
      expect(consoleSpy).toHaveBeenCalled();

      // Invalid dimensions
      hook.renderPixels({ pixels: [], width: -1, height: 64 });
      expect(consoleSpy).toHaveBeenCalled();

      consoleSpy.mockRestore();
    });
  });

  describe('renderPixelsSync()', () => {
    beforeEach(() => {
      PixelCanvas.mounted.call(hook);
    });

    it('should render all pixels in single batch', () => {
      const pixels = [
        { x: 0, y: 0, hex_color: '#FF0000' },
        { x: 1, y: 0, hex_color: '#00FF00' },
        { x: 0, y: 1, hex_color: '#0000FF' }
      ];

      hook.renderPixelsSync(pixels, 8, 8, null);

      // Should call fillRect for each pixel
      expect(ctx.fillRect).toHaveBeenCalledTimes(3);
      expect(ctx.fillRect).toHaveBeenNthCalledWith(1, 0, 0, 8, 8);
      expect(ctx.fillRect).toHaveBeenNthCalledWith(2, 8, 0, 8, 8);
      expect(ctx.fillRect).toHaveBeenNthCalledWith(3, 0, 8, 8, 8);
    });

    it('should log performance when monitoring enabled', () => {
      const consoleSpy = vi.spyOn(console, 'log').mockImplementation(() => {});
      const startTime = performance.now();

      const pixels = Array.from({ length: 4096 }, (_, i) => ({
        x: i % 64,
        y: Math.floor(i / 64),
        hex_color: '#000000'
      }));

      hook.renderPixelsSync(pixels, 8, 8, startTime);

      expect(consoleSpy).toHaveBeenCalledWith(
        expect.stringMatching(/Rendered 4096 pixels in .* \(sync\)/)
      );

      consoleSpy.mockRestore();
    });
  });

  describe('renderPixelsAsync()', () => {
    beforeEach(() => {
      PixelCanvas.mounted.call(hook);
      // Mock requestAnimationFrame
      global.requestAnimationFrame = vi.fn((cb) => {
        cb();
        return 1;
      });
    });

    it('should render large grids in chunks', () => {
      const pixels = Array.from({ length: 10000 }, (_, i) => ({
        x: i % 100,
        y: Math.floor(i / 100),
        hex_color: '#000000'
      }));

      hook.renderPixelsAsync(pixels, 5, 5, null);

      // Should call fillRect for all pixels
      expect(ctx.fillRect).toHaveBeenCalledTimes(10000);
      // Should use requestAnimationFrame for chunking
      expect(global.requestAnimationFrame).toHaveBeenCalled();
    });

    it('should log performance for async rendering', () => {
      const consoleSpy = vi.spyOn(console, 'log').mockImplementation(() => {});
      const startTime = performance.now();

      const pixels = Array.from({ length: 16384 }, (_, i) => ({
        x: i % 128,
        y: Math.floor(i / 128),
        hex_color: '#000000'
      }));

      hook.renderPixelsAsync(pixels, 4, 4, startTime);

      expect(consoleSpy).toHaveBeenCalledWith(
        expect.stringMatching(/Rendered 16384 pixels in .* \(async, \d+ chunks\)/)
      );

      consoleSpy.mockRestore();
    });
  });

  describe('Performance Targets', () => {
    beforeEach(() => {
      PixelCanvas.mounted.call(hook);
    });

    it('should render 64x64 grid synchronously', () => {
      const pixels = Array.from({ length: 4096 }, (_, i) => ({
        x: i % 64,
        y: Math.floor(i / 64),
        hex_color: '#000000'
      }));

      const payload = { pixels, width: 64, height: 64 };
      hook.renderPixels(payload);

      // Verify synchronous rendering was used (no RAF calls)
      expect(global.requestAnimationFrame).not.toHaveBeenCalled();
    });

    it('should render 128x128 grid asynchronously', () => {
      global.requestAnimationFrame = vi.fn((cb) => {
        cb();
        return 1;
      });

      const pixels = Array.from({ length: 16384 }, (_, i) => ({
        x: i % 128,
        y: Math.floor(i / 128),
        hex_color: '#000000'
      }));

      const payload = { pixels, width: 128, height: 128 };
      hook.renderPixels(payload);

      // Verify async rendering was used
      expect(global.requestAnimationFrame).toHaveBeenCalled();
    });
  });

  describe('destroyed()', () => {
    it('should clean up resources', () => {
      PixelCanvas.mounted.call(hook);

      // Should not throw
      expect(() => PixelCanvas.destroyed.call(hook)).not.toThrow();
    });
  });
});
