# Pixel Canvas Hook - Integration Guide

## Overview

The `PixelCanvas` hook is a high-performance JavaScript hook for rendering pixelated images on an HTML canvas in Phoenix LiveView applications. It's optimized for grid sizes from 16x16 up to 256x256, with specific performance targets for common use cases.

## Performance Characteristics

- **64x64 grid (4,096 pixels)**: < 100ms render time (synchronous rendering)
- **128x128 grid (16,384 pixels)**: < 500ms render time (asynchronous rendering with chunking)
- **256x256 grid (65,536 pixels)**: ~1-2 seconds (asynchronous rendering)

## Architecture

### Rendering Strategies

The hook uses two rendering strategies optimized for different grid sizes:

1. **Synchronous Rendering** (≤ 64x64):
   - Renders all pixels in a single batch
   - Fastest for small grids
   - Uses browser's hardware-accelerated fillRect
   - No frame blocking concerns

2. **Asynchronous Rendering** (> 64x64):
   - Chunks pixels into batches of 1,024
   - Uses requestAnimationFrame to prevent UI blocking
   - Maintains 60fps during rendering
   - Progress appears smoothly

### Canvas Optimizations

1. **Context Configuration**:
   ```javascript
   context2d('2d', {
     alpha: false,              // No transparency = faster
     willReadFrequently: false  // Write-only optimization
   })
   ```

2. **Batch Operations**: All fillRect calls are batched before browser paint

3. **Pre-calculated Dimensions**: Square sizes computed once before rendering loop

4. **Single Clear Operation**: Canvas cleared once with `clearRect` (faster than fillRect)

## Integration Steps

### 1. Template Setup (LiveView)

Add a canvas element with the `phx-hook` attribute in your LiveView template:

```heex
<!-- In your .heex template -->
<div id="pixel-canvas-container"
     phx-hook="PixelCanvas"
     data-perf-monitoring="true">
  <canvas id="pixel-canvas"
          width="512"
          height="512"
          class="border border-gray-300">
  </canvas>
</div>
```

**Important attributes**:
- `phx-hook="PixelCanvas"` - Attaches the hook
- `data-perf-monitoring="true"` - (Optional) Enables console performance logging
- Canvas `width` and `height` should match your desired pixel dimensions

### 2. LiveView Module Setup

In your LiveView module, send pixel data using `push_event`:

```elixir
defmodule MyAppWeb.ImagePixelatorLive do
  use MyAppWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def handle_event("process_image", params, socket) do
    # Your image processing logic here
    # This would call the process_image function from Task 5
    pixels = process_image(params["image"], params["grid_size"])

    # Send pixel data to the client
    {:noreply,
     socket
     |> push_event("render_pixels", %{
       pixels: pixels,
       width: params["grid_size"],
       height: params["grid_size"]
     })}
  end

  # Example pixel data structure
  defp example_pixels do
    [
      %{x: 0, y: 0, hex_color: "#FF0000"},
      %{x: 1, y: 0, hex_color: "#00FF00"},
      %{x: 0, y: 1, hex_color: "#0000FF"},
      # ... more pixels
    ]
  end
end
```

### 3. Event Payload Format

The `render_pixels` event expects this payload structure:

```elixir
%{
  pixels: [
    %{x: 0, y: 0, hex_color: "#FF0000"},  # Top-left pixel
    %{x: 1, y: 0, hex_color: "#00FF00"},  # Second pixel in first row
    # ... all pixels in row-major order
  ],
  width: 64,   # Grid width (number of columns)
  height: 64   # Grid height (number of rows)
}
```

**Pixel coordinate system**:
- `x`: Column index (0 to width-1)
- `y`: Row index (0 to height-1)
- `hex_color`: CSS hex color string (e.g., "#RRGGBB")

### 4. Canvas Size Configuration

The hook automatically scales pixels to fit the canvas:

```
square_width = canvas.width / grid_width
square_height = canvas.height / grid_height
```

**Examples**:
- 512x512 canvas with 64x64 grid → 8x8 pixel squares
- 512x512 canvas with 128x128 grid → 4x4 pixel squares
- 1024x1024 canvas with 64x64 grid → 16x16 pixel squares

### 5. Multiple Canvas Instances

You can have multiple pixel canvases on the same page:

```heex
<!-- Canvas 1 -->
<div id="pixel-canvas-1" phx-hook="PixelCanvas">
  <canvas width="512" height="512"></canvas>
</div>

<!-- Canvas 2 -->
<div id="pixel-canvas-2" phx-hook="PixelCanvas">
  <canvas width="256" height="256"></canvas>
</div>
```

Send events to specific canvases using targeted push_event:

```elixir
# Send to specific canvas by targeting its container ID
push_event(socket, "render_pixels", %{
  # Event payload
  target: "pixel-canvas-1"  # Optional: target specific hook instance
})
```

## Performance Monitoring

Enable performance monitoring by adding the data attribute:

```heex
<div phx-hook="PixelCanvas" data-perf-monitoring="true">
  <canvas></canvas>
</div>
```

This will log render times to the browser console:

```
[PixelCanvas] Rendered 4096 pixels in 87.23ms (sync)
[PixelCanvas] Rendered 16384 pixels in 412.56ms (async, 16 chunks)
```

Performance warnings are automatically logged if targets are exceeded:

```
[PixelCanvas] Performance warning: 64x64 grid took 142.34ms (target: <100ms)
```

## Error Handling

The hook includes validation and error handling:

1. **Missing Canvas**: Logs error if canvas element not found
2. **Invalid Context**: Logs error if 2D context unavailable
3. **Invalid Pixel Data**: Validates payload structure
4. **Invalid Dimensions**: Checks for positive width/height

All errors are logged to the browser console with `[PixelCanvas]` prefix.

## Browser Compatibility

- **Chrome/Edge**: Fully supported
- **Firefox**: Fully supported
- **Safari**: Fully supported
- **IE11**: Not supported (uses modern canvas APIs)

## Advanced Customization

### Adjusting Chunk Size

For different performance characteristics, modify the CHUNK_SIZE constant in `pixel_canvas.js`:

```javascript
// Render 2048 pixels per frame instead of 1024
const CHUNK_SIZE = 2048;
```

**Trade-offs**:
- Larger chunks → Faster total render time, but potential frame drops
- Smaller chunks → Smoother rendering, but longer total time

### Custom Canvas Context Options

Modify the context creation in the `mounted()` hook:

```javascript
this.ctx = this.canvas.getContext('2d', {
  alpha: true,               // Enable transparency
  desynchronized: true,      // Reduce latency (experimental)
  willReadFrequently: false
});
```

## Testing

### Unit Test Example (Vitest)

```javascript
import { describe, it, expect, vi } from 'vitest';
import PixelCanvas from './pixel_canvas';

describe('PixelCanvas', () => {
  it('renders pixels synchronously for small grids', () => {
    const canvas = document.createElement('canvas');
    canvas.width = 512;
    canvas.height = 512;

    const hook = {
      el: canvas,
      handleEvent: vi.fn((event, callback) => {
        if (event === 'render_pixels') {
          callback({
            pixels: [
              { x: 0, y: 0, hex_color: '#FF0000' }
            ],
            width: 16,
            height: 16
          });
        }
      })
    };

    PixelCanvas.mounted.call(hook);

    // Verify canvas was cleared and pixel rendered
    // (Add actual assertions based on your testing needs)
  });
});
```

### Browser Test Example

```javascript
// In your E2E tests (Playwright, Cypress, etc.)
await page.goto('/pixelator');

// Upload image and wait for render
await page.setInputFiles('input[type="file"]', 'test-image.png');
await page.selectOption('select[name="grid_size"]', '64');
await page.click('button[type="submit"]');

// Wait for canvas to render
await page.waitForFunction(() => {
  const canvas = document.querySelector('#pixel-canvas');
  const ctx = canvas.getContext('2d');
  const imageData = ctx.getImageData(0, 0, 1, 1);
  // Check if any pixels have been drawn
  return imageData.data[3] !== 0; // Alpha channel
});
```

## Troubleshooting

### Canvas not rendering

1. **Check hook registration**: Verify `PixelCanvas` is in the hooks object in `app.js`
2. **Check phx-hook attribute**: Ensure `phx-hook="PixelCanvas"` is on a parent div, not the canvas itself
3. **Check console**: Look for `[PixelCanvas]` error messages
4. **Check payload**: Verify pixel data format matches expected structure

### Poor performance

1. **Enable monitoring**: Add `data-perf-monitoring="true"` to see actual render times
2. **Check grid size**: Grids > 256x256 may be too large
3. **Check browser**: Ensure using a modern browser with hardware acceleration
4. **Reduce chunk size**: For smoother (but slower) rendering, decrease CHUNK_SIZE

### Pixels appear stretched or distorted

1. **Check canvas size**: Ensure width/height attributes match your requirements
2. **Check CSS**: CSS sizing different from canvas attributes will stretch the image
3. **Check grid dimensions**: Verify width/height in payload match actual pixel count

## Example: Complete Integration

Here's a complete minimal example:

**LiveView Template** (`image_pixelator_live.html.heex`):
```heex
<div class="container mx-auto p-4">
  <h1 class="text-2xl font-bold mb-4">Image Pixelator</h1>

  <form phx-submit="process_image">
    <input type="file" name="image" accept="image/png,image/jpeg" required />

    <select name="grid_size">
      <option value="16">16x16</option>
      <option value="32">32x32</option>
      <option value="64" selected>64x64</option>
      <option value="128">128x128</option>
    </select>

    <button type="submit">Pixelate</button>
  </form>

  <div id="pixel-canvas-wrapper"
       phx-hook="PixelCanvas"
       data-perf-monitoring="true"
       class="mt-4">
    <canvas id="pixel-canvas"
            width="512"
            height="512"
            class="border border-gray-300">
    </canvas>
  </div>
</div>
```

**LiveView Module** (`image_pixelator_live.ex`):
```elixir
defmodule MyAppWeb.ImagePixelatorLive do
  use MyAppWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def handle_event("process_image", %{"image" => image, "grid_size" => grid_size}, socket) do
    grid_size = String.to_integer(grid_size)

    # Process image (implement this based on Task 5)
    pixels = process_image(image, grid_size)

    {:noreply,
     socket
     |> push_event("render_pixels", %{
       pixels: pixels,
       width: grid_size,
       height: grid_size
     })}
  end

  defp process_image(_image, _grid_size) do
    # TODO: Implement image processing logic
    # This will be done in Task 5
    []
  end
end
```

## Files Modified/Created

1. **Created**: `/assets/js/hooks/pixel_canvas.js` - Main hook implementation
2. **Modified**: `/assets/js/app.js` - Added hook registration

## Next Steps

After integrating the hook, you'll need to:

1. **Task 5**: Implement server-side `process_image/2` function
2. **Task 7**: Create the LiveView template with upload form
3. **Task 8**: Add grid size selection UI
4. **Task 9**: Implement error handling
5. **Task 10**: Add performance testing and monitoring

## Support

For issues or questions:
- Check browser console for `[PixelCanvas]` logs
- Verify Phoenix LiveView version compatibility (tested with 0.20.0+)
- Ensure canvas element is properly sized and visible
