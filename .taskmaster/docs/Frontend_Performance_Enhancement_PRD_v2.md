# Frontend Performance Enhancement PRD
## Porting Advanced Canvas Features from Common Lisp Reference

**Version:** 2.0 (Updated for PixiJS v8)
**Date:** October 2025
**Project:** CollabCanvas - Phoenix LiveView Performance Optimization
**Priority:** High
**Estimated Duration:** 4-7 days (extended for v8 migration)

---

## Executive Summary

This PRD outlines the plan to enhance the CollabCanvas frontend by porting high-performance patterns and advanced interaction features from a proven Common Lisp reference implementation. The current Phoenix LiveView implementation is functional but lacks critical performance optimizations needed for smooth rendering with 1000+ objects and rich multi-user interactions.

**NEW**: This version includes comprehensive guidance for migrating from PixiJS v7 to v8, incorporating v8-specific performance optimizations and architectural changes.

### Current State
- Basic PixiJS v7 canvas with simple object rendering
- Individual event listeners per object (high memory overhead)
- No viewport culling (renders all objects even when off-screen)
- Simple cursor rendering using PIXI.Graphics per user
- Single object selection only
- **Migration Risk**: Legacy v7 patterns that may not leverage v8 optimizations

### Target State
- **PixiJS v8 Architecture**: Async initialization, new package structure, optimized renderer
- Advanced viewport culling for 10x performance improvement
- Centralized drag handler (90% reduction in event listeners)
- Shared texture rendering for remote cursors (70% GPU memory reduction)
- Multi-object selection with Shift+Click
- Modular, maintainable architecture with CanvasManager class
- **v8-Specific Optimizations**: Render groups, container culling, particle system upgrades

### Performance Goals
- **FPS:** Maintain 60 FPS with 1000+ objects on screen (2000+ with v8 optimizations)
- **Memory:** Reduce GPU memory usage by 70% for cursor rendering
- **Latency:** <16ms per frame for all canvas operations
- **Scale:** Support 50+ concurrent users with visible cursors (100+ with v8)
- **Bundle Size:** 20-30% reduction with v8's single-package structure

---

## Technical Context

### Files to Modify
1. **Primary Target:** `collab_canvas/assets/js/hooks/canvas_manager.js`
   - Current: ~1019 lines, basic v7 implementation
   - Post-refactor: ~1500-1800 lines with advanced features + v8 migration

2. **Package Dependencies:**
   - **Update:** `package.json` - Migrate from `@pixi/*` packages to `pixi.js@^8.0.0`
   - **Review:** All PixiJS imports across the codebase
   - **New:** Potential custom build configuration for bundle optimization

### Reference Implementation
- **Source:** Common Lisp project `frontend/src/canvas.js`
- **Location:** `repomix-output-cl.xml` (provided context)
- **Features to Port:**
  - PerformanceMonitor class for FPS tracking
  - Viewport culling with configurable padding
  - Centralized event handling architecture
  - Shared texture pattern for repeated graphics
  - Multi-selection state management

### Technology Stack
- **PixiJS:** v8.x (WebGL 2D rendering, WebGPU-ready)
- **Phoenix LiveView:** Real-time state synchronization
- **Alpine.js:** Lightweight UI state management
- **Build Tools:** Webpack/Vite (for custom PixiJS builds)

---

## PixiJS v8 Migration Strategy

### Phase 0: Pre-Migration Assessment & Setup

**Objective:** Prepare the codebase for v8 migration and assess compatibility requirements.

#### 0.1 Dependency Audit

**Requirements:**
- Audit all PixiJS-dependent libraries (filters, plugins, third-party integrations)
- Identify which libraries have v8-compatible versions
- Document any libraries that block migration

**Known Compatibility:**
- ✅ **Migrated**: pixi-filters, pixi-sound, pixi-gif, pixi-ui
- ⚠️ **Verify**: Any custom/internal PixiJS extensions
- ❌ **Incompatible**: pixi-layers (to be replaced with native v8 features)

**Acceptance Criteria:**
- [ ] Complete dependency compatibility matrix
- [ ] Migration blockers identified and documented
- [ ] Alternative solutions identified for incompatible dependencies

#### 0.2 Package Structure Migration

**Requirements:**
- Update `package.json` to use single `pixi.js` package
- Remove all `@pixi/*` sub-packages
- Update all import statements throughout codebase

**Migration Pattern:**
```javascript
// OLD (v7):
import { Application } from '@pixi/app';
import { Sprite } from '@pixi/sprite';
import { Graphics } from '@pixi/graphics';

// NEW (v8):
import { Application, Sprite, Graphics } from 'pixi.js';
```

**Acceptance Criteria:**
- [ ] Single `pixi.js@^8.0.0` dependency installed
- [ ] All `@pixi/*` packages removed
- [ ] All import statements updated
- [ ] No import errors in build

#### 0.3 Async Initialization Migration

**Critical Change:** PixiJS v8 requires async initialization for WebGPU compatibility.

**Current Code Pattern:**
```javascript
mounted() {
  this.app = new PIXI.Application({
    view: this.el.querySelector('canvas'),
    width: 800,
    height: 600,
    backgroundColor: 0xffffff
  });
  
  // Immediate canvas operations
  this.setupCanvas();
}
```

**New v8 Pattern:**
```javascript
async mounted() {
  this.app = new PIXI.Application();
  
  await this.app.init({
    canvas: this.el.querySelector('canvas'),
    width: 800,
    height: 600,
    background: '#ffffff', // Note: backgroundColor → background
    resolution: window.devicePixelRatio || 1,
    autoDensity: true,
  });
  
  // Canvas operations after initialization
  await this.setupCanvas();
}
```

**Key Changes:**
- `view` parameter → `canvas` parameter
- `backgroundColor` → `background` (accepts hex strings)
- Options moved from constructor to `init()` method
- `mounted()` hook must be async
- All dependent operations must await initialization

**Acceptance Criteria:**
- [ ] Application initialization is async
- [ ] All canvas operations wait for init completion
- [ ] LiveView hook compatibility maintained
- [ ] Error handling for initialization failures

### Phase 0.4: Texture System Migration

**Critical Change:** v8 has completely restructured texture architecture.

#### BaseTexture Removal

**OLD (v7):**
```javascript
const baseTexture = new PIXI.BaseTexture(imageElement, {
  resolution: 2,
  mipmap: PIXI.MIPMAP_MODES.POW2
});
const texture = new PIXI.Texture(baseTexture);
```

**NEW (v8):**
```javascript
// Create ImageSource (replaces BaseTexture)
const source = new ImageSource({
  resource: imageElement,
  resolution: 2,
  autoGenerateMipmaps: true // Note: renamed property
});

// Create Texture
const texture = new Texture({ source });
```

#### Texture Source Types

v8 introduces specialized texture sources:
- `ImageSource` - For images (Image, ImageBitmap)
- `CanvasSource` - For canvas elements
- `VideoSource` - For video elements (auto-updates)
- `BufferSource` - For raw buffer data
- `CompressedSource` - For GPU-compressed formats

**Implementation Pattern:**
```javascript
// Shared cursor texture (our use case)
createSharedCursorTexture() {
  const graphics = new Graphics();
  graphics.rect(0, 0, 16, 24).fill(0xFFFFFF);
  
  // Generate texture from graphics
  const texture = this.app.renderer.generateTexture(graphics);
  graphics.destroy();
  
  return texture; // Returns Texture with built-in source
}
```

#### Automatic Mipmap Management

**Critical for RenderTextures:**
```javascript
const renderTexture = RenderTexture.create({
  width: 1024,
  height: 1024,
  autoGenerateMipmaps: true // Enable mipmaps
});

// Render to texture
this.app.renderer.render({
  target: renderTexture,
  container: scene
});

// MUST manually update mipmaps after rendering
renderTexture.source.updateMipmaps();
```

**Acceptance Criteria:**
- [ ] All BaseTexture references replaced with TextureSource
- [ ] Mipmap generation explicitly managed for RenderTextures
- [ ] Video textures use VideoSource for auto-updates
- [ ] Shared textures properly created and reused

### Phase 0.5: Graphics API Migration

**Major Overhaul:** Graphics API has fundamentally changed in v8.

#### New Draw-Then-Fill Pattern

**OLD (v7) - Begin-End Pattern:**
```javascript
const graphics = new Graphics()
  .beginFill(0xff0000)
  .drawRect(50, 50, 100, 100)
  .endFill()
  .lineStyle(2, 0xffffff)
  .beginFill(0x0000ff)
  .drawCircle(300, 200, 50)
  .endFill();
```

**NEW (v8) - Shape-Then-Style Pattern:**
```javascript
const graphics = new Graphics()
  .rect(50, 50, 100, 100)
  .fill(0xff0000)
  .circle(300, 200, 50)
  .fill(0x0000ff)
  .stroke({ width: 2, color: 0xffffff });
```

#### Graphics Method Renames

| v7 Method | v8 Method |
|-----------|-----------|
| `drawRect()` | `rect()` |
| `drawCircle()` | `circle()` |
| `drawEllipse()` | `ellipse()` |
| `drawRoundedRect()` | `roundRect()` |
| `drawPolygon()` | `poly()` |
| `drawStar()` | `star()` |
| `lineStyle()` | `stroke()` |
| `beginFill()` | `fill()` (after shape) |
| `beginHole()` / `endHole()` | `cut()` (after shape) |

#### Fill and Stroke Options

**v7 Signature:**
```javascript
graphics.beginTextureFill({
  texture: Texture.WHITE,
  alpha: 0.5,
  color: 0xff0000
});
graphics.lineStyle(4, 0x00ff00, 1);
```

**v8 Signature:**
```javascript
// Fill with texture
graphics
  .rect(0, 0, 100, 100)
  .fill({
    texture: Texture.WHITE,
    color: 0xff0000,
    alpha: 0.5
  });

// Stroke with options
graphics
  .rect(0, 0, 100, 100)
  .stroke({
    width: 4,
    color: 0x00ff00,
    alpha: 1
  });
```

#### Holes (Cutouts)

**v7:**
```javascript
graphics
  .beginFill(0x00ff00)
  .drawRect(0, 0, 100, 100)
  .beginHole()
  .drawCircle(50, 50, 20)
  .endHole()
  .endFill();
```

**v8:**
```javascript
graphics
  .rect(0, 0, 100, 100)
  .fill(0x00ff00)
  .circle(50, 50, 20)
  .cut(); // Cut acts on previous shape
```

#### GraphicsContext (formerly GraphicsGeometry)

**Purpose:** Share graphics data across multiple Graphics objects efficiently.

**v7:**
```javascript
const graphics = new Graphics()
  .beginFill(0xff0000)
  .drawRect(0, 0, 50, 50)
  .endFill();

const geometry = graphics.geometry;
const clone = new Graphics(geometry);
```

**v8:**
```javascript
// Create reusable context
const context = new GraphicsContext()
  .rect(0, 0, 50, 50)
  .fill(0xff0000);

// Use context in multiple Graphics objects
const graphics1 = new Graphics(context);
const graphics2 = new Graphics(context);
graphics2.x = 100; // Independent positioning
```

**Acceptance Criteria:**
- [ ] All `beginFill/endFill` replaced with shape + fill pattern
- [ ] Graphics method names updated to v8 conventions
- [ ] Holes implemented using `cut()`
- [ ] Shared graphics use GraphicsContext
- [ ] Selection outlines and visual indicators updated

### Phase 0.6: Container and Display Object Changes

#### Leaf Nodes Cannot Have Children

**Breaking Change:** Only `Container` objects can have children in v8.

**v7 (allowed):**
```javascript
const sprite = new Sprite(texture);
const childSprite = new Sprite(childTexture);
sprite.addChild(childSprite); // Works in v7
```

**v8 (prohibited):**
```javascript
const sprite = new Sprite(texture);
const childSprite = new Sprite(childTexture);
sprite.addChild(childSprite); // ERROR in v8!

// Correct v8 pattern:
const container = new Container();
const sprite = new Sprite(texture);
const childSprite = new Sprite(childTexture);

container.addChild(sprite);
container.addChild(childSprite);
```

**Affected Classes (cannot have children in v8):**
- `Sprite`
- `Graphics`
- `Text`, `BitmapText`, `HTMLText`
- `Mesh`
- `NineSliceSprite` (renamed from NineSlicePlane)
- `TilingSprite`

**Migration Strategy:**
```javascript
// Helper function for migration
function ensureContainer(displayObject) {
  if (displayObject.children && displayObject.children.length > 0) {
    // This object has children but isn't a Container
    const container = new Container();
    container.position.copyFrom(displayObject.position);
    container.rotation = displayObject.rotation;
    container.scale.copyFrom(displayObject.scale);
    
    // Transfer children
    while (displayObject.children.length > 0) {
      container.addChild(displayObject.children[0]);
    }
    
    // Add original object to container
    displayObject.position.set(0, 0);
    displayObject.rotation = 0;
    displayObject.scale.set(1, 1);
    container.addChild(displayObject);
    
    return container;
  }
  return displayObject;
}
```

#### DisplayObject Removed

**v7 inheritance:**
```
DisplayObject (base)
  ├── Container
  │   ├── Sprite
  │   └── Graphics
  └── ...
```

**v8 inheritance:**
```
Container (base)
  ├── Sprite
  ├── Graphics
  └── ...
```

**Impact:** All scene objects now extend `Container`, but leaf nodes have children functionality disabled.

#### updateTransform() Removed

**v7 Pattern (common for custom logic):**
```javascript
class MySprite extends Sprite {
  updateTransform() {
    super.updateTransform();
    // Custom per-frame logic
    this.rotation += 0.01;
  }
}
```

**v8 Pattern:**
```javascript
class MySprite extends Sprite {
  constructor() {
    super();
    this.onRender = this._onRender.bind(this);
  }
  
  _onRender() {
    // Custom per-frame logic
    this.rotation += 0.01;
  }
}
```

**Key Difference:** Use `onRender` callback instead of overriding `updateTransform()`.

#### Container Culling Changes

**v7:** Automatic culling during render loop.

**v8:** Manual culling control for optimization.

**New Properties:**
- `cullable` - Whether container can be culled
- `cullArea` - Custom cull bounds (overrides object bounds)
- `cullableChildren` - Whether children can be culled

**Implementation:**
```javascript
import { Container, Rectangle, Culler } from 'pixi.js';

const container = new Container();
container.cullable = true;
container.cullArea = new Rectangle(0, 0, 800, 600);
container.cullableChildren = false;

// Manual culling (integrate with viewport updates)
const viewport = new Rectangle(0, 0, 800, 600);
Culler.shared.cull(container, viewport);

// Then render
renderer.render(container);
```

**Integration with Viewport Culling:**
```javascript
updateVisibleObjects() {
  const bounds = this.calculateVisibleBounds();
  
  // Use built-in Culler for efficient culling
  Culler.shared.cull(this.objectsContainer, bounds);
  
  // Optional: Custom culling logic for specific objects
  for (const [id, object] of this.objects) {
    if (object.customCullLogic) {
      object.visible = this.customCullCheck(object, bounds);
    }
  }
}
```

**Acceptance Criteria:**
- [ ] Leaf nodes wrapped in Containers where needed
- [ ] No children added to Sprite/Graphics objects
- [ ] Custom `updateTransform()` logic migrated to `onRender`
- [ ] Container culling integrated with viewport system
- [ ] Performance validated: culling reduces draw calls

### Phase 0.7: Event System Updates

#### Default EventMode Change

**v7 Default:** `eventMode = 'auto'`
**v8 Default:** `eventMode = 'passive'`

**Impact:** Objects no longer automatically interactive.

**Required Changes:**
```javascript
// v7 - interactive by default
const sprite = new Sprite(texture);
sprite.on('pointerdown', handler); // Works

// v8 - must explicitly enable
const sprite = new Sprite(texture);
sprite.eventMode = 'static'; // or 'dynamic'
sprite.on('pointerdown', handler);
```

**EventMode Options:**
- `'passive'` - Not interactive (default)
- `'static'` - Interactive, properties rarely change
- `'dynamic'` - Interactive, properties change frequently
- `'none'` - Skip event processing entirely (optimization)

#### interactiveChildren Optimization

**v8 Enhancement:** Better control over event propagation.

```javascript
const container = new Container();
container.interactiveChildren = false; // Skip child hit testing

// Only container receives events, not children
container.eventMode = 'static';
container.on('pointerdown', (event) => {
  // Handle at container level
});
```

**Use Case for CollabCanvas:**
```javascript
// Optimize event handling for object groups
const selectionGroup = new Container();
selectionGroup.interactiveChildren = false; // Don't test individual objects
selectionGroup.eventMode = 'none'; // Group is not interactive itself

// This prevents 100s of event checks for large selections
```

**Acceptance Criteria:**
- [ ] All interactive objects have explicit `eventMode`
- [ ] Event propagation optimized with `interactiveChildren`
- [ ] No broken interaction after migration
- [ ] Event handler performance validated

### Phase 0.8: Miscellaneous API Changes

#### Application.view → Application.canvas

```javascript
// v7
const app = new Application({ view: canvasElement });
document.body.appendChild(app.view);

// v8
const app = new Application();
await app.init({ canvas: canvasElement });
document.body.appendChild(app.canvas);
```

#### Bounds Return Type Change

```javascript
// v7
const bounds = container.getBounds(); // Returns Rectangle
console.log(bounds.x, bounds.y, bounds.width, bounds.height);

// v8
const bounds = container.getBounds(); // Returns Bounds object
const rect = bounds.rectangle; // Get Rectangle from Bounds
console.log(rect.x, rect.y, rect.width, rect.height);
```

#### Ticker Callback Signature

```javascript
// v7
Ticker.shared.add((deltaTime) => {
  sprite.rotation += deltaTime * 0.1;
});

// v8
Ticker.shared.add((ticker) => {
  sprite.rotation += ticker.deltaTime * 0.1;
  // Also available: ticker.elapsedMS, ticker.FPS
});
```

#### PIXI Constants → String Literals

```javascript
// v7
texture.baseTexture.scaleMode = PIXI.SCALE_MODES.NEAREST;
texture.baseTexture.wrapMode = PIXI.WRAP_MODES.REPEAT;

// v8
texture.source.scaleMode = 'nearest'; // 'nearest' or 'linear'
texture.source.wrapMode = 'repeat'; // 'repeat', 'clamp-to-edge', 'mirror-repeat'
```

#### Mesh Topology Constants

```javascript
// v7
const mesh = new Mesh(geometry, shader, null, PIXI.DRAW_MODES.TRIANGLES);

// v8
const mesh = new Mesh({
  geometry,
  shader,
  texture,
  // topology: 'triangle-list' (default), 'point-list', 'line-list', 'line-strip', 'triangle-strip'
});
```

#### Text/BitmapText Constructor Changes

```javascript
// v7
const text = new Text('Hello', style);
const bitmapText = new BitmapText('World', { fontName: 'Arial', fontSize: 24 });

// v8
const text = new Text({
  text: 'Hello',
  style: style
});

const bitmapText = new BitmapText({
  text: 'World',
  style: { fontFamily: 'Arial', fontSize: 24 }
});
```

#### Utils Namespace Removed

```javascript
// v7
import { utils } from 'pixi.js';
utils.isMobile.any();

// v8
import { isMobile } from 'pixi.js';
isMobile.any();
```

**Acceptance Criteria:**
- [ ] All application view references updated to canvas
- [ ] Bounds extraction uses `.rectangle` property
- [ ] Ticker callbacks use ticker object parameter
- [ ] Constants replaced with string literals
- [ ] Constructor signatures updated throughout

---

## PixiJS Performance Best Practices (v8-Optimized)

### General Performance Guidelines

**From PixiJS Performance Tips Documentation:**

1. **Optimize Only When Needed**
   - PixiJS handles significant content out-of-the-box
   - Profile before optimizing (use PerformanceMonitor)
   - Measure impact of each optimization

2. **Scene Complexity Management**
   - More objects = slower performance
   - Object order matters: grouping similar types improves batching
   - Better: `sprite/sprite/graphic/graphic` than `sprite/graphic/sprite/graphic`

3. **Renderer Initialization Options**
   ```javascript
   await app.init({
     useContextAlpha: false, // Disable alpha for performance boost
     antialias: false, // Disable on older devices
     resolution: window.devicePixelRatio,
     autoDensity: true
   });
   ```

4. **Culling Strategy**
   - PixiJS v8 culling is manual (controlled by developer)
   - GPU-bound scenarios: culling improves performance
   - CPU-bound scenarios: culling may degrade performance
   - **Rule:** Profile to determine if culling helps

### Sprite Optimization

1. **Use Spritesheets** (Critical for Performance)
   ```javascript
   // Load spritesheet
   await Assets.load('spritesheet.json');
   
   // Create sprites from sheet
   const sprite1 = Sprite.from('frame1.png');
   const sprite2 = Sprite.from('frame2.png');
   // Both share same texture atlas - batched together!
   ```

2. **Texture Batching**
   - PixiJS can batch up to 16 different textures (hardware dependent)
   - Sprites using same texture atlas batch efficiently
   - Fastest rendering method in PixiJS

3. **Low-Resolution Textures for Mobile**
   ```javascript
   // Use @0.5x suffix for automatic resolution handling
   await Assets.load({
     alias: 'bunny',
     src: [
       { resolution: 2, src: 'bunny@2x.png' },
       { resolution: 1, src: 'bunny.png' },
       { resolution: 0.5, src: 'bunny@0.5x.png' }
     ]
   });
   ```

4. **Draw Order Optimization**
   - Group objects by type and texture
   - Minimize state changes between draws
   - Sort children to optimize batch creation

### Graphics Optimization

1. **Static Graphics** (v8 Feature)
   - Graphics fastest when not constantly modified
   - Transform, alpha, tint are free to change
   - Shape/path changes trigger rebuilds

2. **Graphics Batching**
   - Graphics under 100 points batch automatically
   - Small graphics (rectangles, triangles) as fast as sprites
   - Complex graphics (100s of points) → consider converting to sprite

3. **GraphicsContext for Reuse** (v8)
   ```javascript
   // Create once, use many times
   const sharedContext = new GraphicsContext()
     .rect(0, 0, 50, 50)
     .fill(0xff0000);
   
   // Efficient: Multiple graphics share same context
   for (let i = 0; i < 100; i++) {
     const g = new Graphics(sharedContext);
     g.position.set(i * 60, 0);
     container.addChild(g);
   }
   ```

4. **Convert Complex Graphics to Textures**
   ```javascript
   const graphics = new Graphics()
     .circle(0, 0, 50)
     .fill(0x00ff00);
   
   // Generate texture once
   const texture = app.renderer.generateTexture(graphics);
   graphics.destroy();
   
   // Create sprites from texture (faster for many instances)
   for (let i = 0; i < 1000; i++) {
     const sprite = new Sprite(texture);
     container.addChild(sprite);
   }
   ```

### Texture Management

1. **Automatic Garbage Collection**
   - PixiJS automatically manages texture lifecycle
   - Manual management via `texture.destroy()`

2. **Batch Destruction with Delay**
   ```javascript
   // Avoid frame freezes from simultaneous destroys
   const texturesToDestroy = [...]; // Array of textures
   
   texturesToDestroy.forEach((tex, index) => {
     setTimeout(() => {
       tex.destroy(true);
     }, index * 10); // 10ms stagger
   });
   ```

3. **Mipmap Management (v8)**
   ```javascript
   // Enable mipmaps for scaled textures
   const source = new ImageSource({
     resource: imageElement,
     autoGenerateMipmaps: true
   });
   
   // For RenderTextures, manually update
   renderTexture.source.updateMipmaps();
   ```

### Text Rendering

1. **Minimize Text Changes**
   - Each text change triggers canvas render + GPU upload
   - Use `BitmapText` for frequently changing text
   ```javascript
   // Slow: Updating every frame
   Ticker.shared.add(() => {
     text.text = `Score: ${score}`; // Canvas render each frame!
   });
   
   // Fast: Use BitmapText
   const bitmapText = new BitmapText({
     text: 'Score: 0',
     style: { fontFamily: 'Arial', fontSize: 24 }
   });
   ```

2. **Text Resolution Control**
   ```javascript
   const text = new Text({
     text: 'Hello',
     style: style,
     resolution: 1 // Lower than default for memory savings
   });
   ```

3. **BitmapText for Dynamic Content**
   - Much faster than standard Text
   - Requires bitmap font atlas
   - Best for scores, timers, chat messages

### Mask Optimization

1. **Mask Performance Hierarchy** (Fastest to Slowest)
   - **Fastest:** Axis-aligned rectangle masks (scissor rect)
   - **Fast:** Graphics masks (stencil buffer)
   - **Slow:** Sprite masks (filters) - avoid in excess

2. **Rectangle Mask Example**
   ```javascript
   const mask = new Graphics()
     .rect(0, 0, 400, 400)
     .fill(0xffffff);
   
   container.mask = mask;
   ```

3. **Mask Quantity Limits**
   - Use sparingly (100s of masks will degrade performance)
   - Prefer culling over masking when possible

### Filter Optimization

1. **Memory Management**
   ```javascript
   // Release filter memory when done
   container.filters = null;
   ```

2. **Filter Area Specification**
   ```javascript
   // Specify area to avoid measurement overhead
   container.filterArea = new Rectangle(0, 0, 800, 600);
   ```

3. **Filter Quantity Impact**
   - Filters are expensive (GPU-intensive)
   - Avoid excessive layering
   - Consider alternatives (blend modes, Graphics)

### Blend Mode Optimization

**Critical:** Blend mode changes break batches.

```javascript
// Poor batching (4 draw calls):
sprite1.blendMode = 'screen';  // Batch break
sprite2.blendMode = 'normal';  // Batch break
sprite3.blendMode = 'screen';  // Batch break
sprite4.blendMode = 'normal';  // Batch break

// Good batching (2 draw calls):
sprite1.blendMode = 'screen';  // Batch 1
sprite3.blendMode = 'screen';  // Batch 1
sprite2.blendMode = 'normal';  // Batch 2
sprite4.blendMode = 'normal';  // Batch 2
```

**Optimization:** Group objects by blend mode in scene graph.

### Event/Interaction Optimization

1. **Disable Interactive Children**
   ```javascript
   container.interactiveChildren = false;
   // Prevents event system from crawling children
   ```

2. **Explicit Hit Areas**
   ```javascript
   sprite.hitArea = new Rectangle(0, 0, 100, 100);
   // Stops event system from measuring bounds
   ```

3. **EventMode Optimization** (v8)
   ```javascript
   sprite.eventMode = 'static'; // Properties rarely change
   // Use 'dynamic' only if position/scale/rotation change frequently
   ```

### Particle Container (v8 Rework)

**Major v8 Upgrade:** Can handle 100,000+ particles efficiently.

**v7 → v8 Migration:**
```javascript
// v7 (limited to ~10,000)
const particles = new ParticleContainer();
for (let i = 0; i < 10000; i++) {
  const sprite = new Sprite(texture);
  particles.addChild(sprite); // Uses children array
}

// v8 (handles 100,000+)
const particles = new ParticleContainer({
  boundsArea: new Rectangle(0, 0, 800, 600) // Required for culling
});

for (let i = 0; i < 100000; i++) {
  const particle = new Particle(texture);
  particles.addParticle(particle); // Direct particle management
}
```

**Key v8 Changes:**
- Uses `Particle` class (not Sprite)
- Particles stored in `particleChildren` (not `children`)
- Must provide `boundsArea` (doesn't calculate bounds)
- Direct array manipulation allowed for max performance

**Particle Interface:**
```javascript
const particle = {
  x: 100,
  y: 100,
  scaleX: 1,
  scaleY: 1,
  anchorX: 0.5,
  anchorY: 0.5,
  rotation: 0,
  color: 0xffffff,
  texture: myTexture
};

particles.addParticle(particle);
```

**Use Case for CollabCanvas:**
- Remote cursor particles (if 100+ users)
- Particle effects (selection indicators, animations)
- Thousands of small objects (dots, markers)

### Render Groups (v8 Feature)

**NEW in v8:** Explicit control over batch grouping.

```javascript
import { Container } from 'pixi.js';

const renderGroup = new Container();
renderGroup.isRenderGroup = true; // Mark as render group

// All children batched together optimally
// Reduces state changes and draw calls
```

**When to Use:**
- Objects that always render together
- UI panels with many elements
- Object groups that move together

**CollabCanvas Application:**
```javascript
// Group selection highlights together
const selectionGroup = new Container();
selectionGroup.isRenderGroup = true;
selectionGroup.label = 'selection-indicators';

// All selection outlines batched efficiently
for (const objectId of selectedObjects) {
  const highlight = createSelectionHighlight(objectId);
  selectionGroup.addChild(highlight);
}
```

---

## Phase 1: Architecture Refactoring + v8 Migration

### 1.1 Extract CanvasManager Class

**Objective:** Improve code organization, testability, and complete v8 migration simultaneously.

**Requirements:**
- Create new `CanvasManager` class in separate module
- Move all PixiJS-specific logic from hook to manager
- Apply all v8 API changes during extraction
- Hook becomes thin adapter between LiveView and CanvasManager
- Maintain 100% backward compatibility with LiveView events

**v8-Specific Changes During Extraction:**
- Async initialization pattern
- Updated import statements (`pixi.js` package)
- Graphics API converted to v8 syntax
- Texture handling with new Source pattern
- Event mode explicit setting

**Implementation Notes:**
```javascript
// New structure:
// canvas_manager.js (hook) - 250 lines
// core/canvas_manager_class.js - 1200 lines
// core/performance_monitor.js - 150 lines
// core/v8_compatibility.js - 100 lines (helper utilities)

// Hook structure (canvas_manager.js):
export default {
  async mounted() {
    this.manager = new CanvasManager(this.el, this);
    await this.manager.initialize();
  },
  
  async updated() {
    await this.manager.handleUpdate(this.el);
  },
  
  destroyed() {
    this.manager.destroy();
  },
  
  // LiveView event handlers
  handleEvent(event, payload) {
    this.manager.handleLiveViewEvent(event, payload);
  }
};

// Manager class structure (core/canvas_manager_class.js):
export class CanvasManager {
  constructor(element, liveViewHook) {
    this.element = element;
    this.hook = liveViewHook;
    this.app = null;
    this.objects = new Map();
    this.selectedObjects = new Set();
    // ... other state
  }
  
  async initialize() {
    // v8 async initialization
    this.app = new Application();
    await this.app.init({
      canvas: this.element.querySelector('canvas'),
      width: 800,
      height: 600,
      background: '#ffffff',
      resolution: window.devicePixelRatio,
      autoDensity: true,
      useContextAlpha: false, // Performance
      antialias: false // Mobile performance
    });
    
    await this.setupCanvas();
    this.setupEventHandlers();
  }
  
  // ... rest of implementation
}
```

**Acceptance Criteria:**
- [ ] CanvasManager can be instantiated independently
- [ ] All v8 API changes applied successfully
- [ ] All existing functionality works unchanged
- [ ] Clear separation: Hook = LiveView bridge, Manager = Canvas logic
- [ ] No global state - all state encapsulated in manager instance
- [ ] Async initialization properly handled
- [ ] LiveView event synchronization maintained

### 1.2 Implement PerformanceMonitor

**Objective:** Track FPS and frame times to validate v8 performance improvements.

**Requirements:**
- Port PerformanceMonitor class from reference implementation
- Track average FPS over 1-second windows
- Expose metrics via console and optional on-screen display
- Minimal performance overhead (<0.1ms per frame)
- Compare v7 vs v8 performance metrics

**v8 Integration:**
```javascript
export class PerformanceMonitor {
  constructor(app) {
    this.app = app;
    this.frames = [];
    this.lastTime = performance.now();
    this.fps = 0;
    this.frameTime = 0;
    
    // Use v8 Ticker callback signature
    this.app.ticker.add(this._onTick.bind(this));
  }
  
  _onTick(ticker) {
    const now = performance.now();
    const delta = now - this.lastTime;
    this.lastTime = now;
    
    this.frames.push(delta);
    if (this.frames.length > 60) this.frames.shift();
    
    // Calculate metrics
    this.frameTime = this.frames.reduce((a, b) => a + b) / this.frames.length;
    this.fps = 1000 / this.frameTime;
    
    // Log every second
    if (this.frames.length >= 60) {
      console.log(`[PerformanceMonitor] FPS: ${this.fps.toFixed(1)}, Frame: ${this.frameTime.toFixed(2)}ms`);
    }
  }
  
  getMetrics() {
    return {
      fps: this.fps,
      frameTime: this.frameTime,
      renderer: this.app.renderer.type // 'webgl' or 'webgpu'
    };
  }
}
```

**Acceptance Criteria:**
- [ ] FPS accurately measured and logged
- [ ] Console output: `[PerformanceMonitor] FPS: 60.2, Frame time: 16.6ms`
- [ ] Metrics available for LiveView to display in UI
- [ ] No performance degradation from monitoring itself
- [ ] v7 baseline vs v8 performance comparison documented

---

## Phase 2: High-Performance Viewport Culling (v8-Enhanced)

### 2.1 Implement Visibility Calculation with v8 Culler

**Objective:** Leverage v8's built-in Culler for optimal viewport culling performance.

**Requirements:**
- Calculate visible bounds in world coordinates
- Use `Culler.shared.cull()` for automatic visibility updates
- Add configurable padding (default: 200px) to prevent pop-in
- Integrate with v8's container culling properties
- Trigger on: viewport pan, zoom, initial load

**v8-Optimized Implementation:**
```javascript
import { Culler, Rectangle } from 'pixi.js';

class CanvasManager {
  constructor() {
    // Configure containers for culling
    this.objectsContainer = new Container();
    this.objectsContainer.cullable = true;
    this.objectsContainer.cullableChildren = true;
    
    this.cullingPadding = 200;
    this.cullingEnabled = true;
  }
  
  calculateVisibleBounds(padding = this.cullingPadding) {
    // Get viewport bounds in world coordinates
    const viewport = this.app.screen;
    
    // Apply camera transform if using viewport plugin
    const worldBounds = new Rectangle(
      this.camera.x - padding,
      this.camera.y - padding,
      viewport.width + (padding * 2),
      viewport.height + (padding * 2)
    );
    
    return worldBounds;
  }
  
  updateVisibleObjects() {
    if (!this.cullingEnabled) return;
    
    const bounds = this.calculateVisibleBounds();
    
    // Use v8's built-in Culler (highly optimized)
    Culler.shared.cull(this.objectsContainer, bounds);
    
    // Optional: Custom culling for specific object types
    for (const [id, object] of this.objects) {
      if (object.customCullBehavior) {
        object.visible = this.customCullCheck(object, bounds);
      }
    }
  }
  
  customCullCheck(object, bounds) {
    // Use v8's Bounds API
    const objectBounds = object.getBounds().rectangle;
    
    // Check intersection
    return boundsIntersect(objectBounds, bounds);
  }
}

function boundsIntersect(a, b) {
  return !(
    a.x + a.width < b.x ||
    a.x > b.x + b.width ||
    a.y + a.height < b.y ||
    a.y > b.y + b.height
  );
}
```

**v8 Performance Advantages:**
- Built-in Culler is GPU-optimized
- Container culling properties reduce CPU overhead
- `cullableChildren` prevents unnecessary recursion
- Better cache locality with v8's render groups

**Acceptance Criteria:**
- [ ] Off-screen objects have `visible: false`
- [ ] Objects become visible ~200px before entering viewport
- [ ] Uses v8's `Culler.shared.cull()` for main culling
- [ ] Performance: 60 FPS with 5000 objects (90% off-screen)
- [ ] No visible pop-in during fast panning
- [ ] 20% better performance than custom culling implementation

### 2.2 Integrate with Pan/Zoom + Render Groups

**Objective:** Automatic culling with v8 render groups for optimal batching.

**Requirements:**
- Call `updateVisibleObjects()` after pan operations
- Call `updateVisibleObjects()` after zoom operations
- Debounce during continuous pan/zoom (max 60Hz)
- Initial culling pass on canvas load
- Use render groups to batch visible objects

**v8 Render Group Integration:**
```javascript
setupRenderGroups() {
  // Create render groups for different object types
  this.visibleObjectsGroup = new Container();
  this.visibleObjectsGroup.isRenderGroup = true;
  this.visibleObjectsGroup.label = 'visible-objects';
  
  this.culledObjectsGroup = new Container();
  this.culledObjectsGroup.visible = false;
  
  this.objectsContainer.addChild(this.visibleObjectsGroup);
  this.objectsContainer.addChild(this.culledObjectsGroup);
}

updateVisibleObjects() {
  const bounds = this.calculateVisibleBounds();
  
  // Move objects between render groups based on visibility
  for (const [id, object] of this.objects) {
    const objectBounds = object.getBounds().rectangle;
    const isVisible = boundsIntersect(objectBounds, bounds);
    
    if (isVisible && object.parent !== this.visibleObjectsGroup) {
      this.visibleObjectsGroup.addChild(object);
    } else if (!isVisible && object.parent !== this.culledObjectsGroup) {
      this.culledObjectsGroup.addChild(object);
    }
  }
  
  // v8's render groups automatically batch visible objects
}

// Debounced viewport update
setupViewportHandlers() {
  let updateTimeout;
  
  const debouncedUpdate = () => {
    if (updateTimeout) return; // Already scheduled
    
    updateTimeout = requestAnimationFrame(() => {
      this.updateVisibleObjects();
      updateTimeout = null;
    });
  };
  
  this.viewport.on('moved', debouncedUpdate);
  this.viewport.on('zoomed', debouncedUpdate);
}
```

**Acceptance Criteria:**
- [ ] Smooth panning with culling enabled
- [ ] Zoom in/out correctly updates visibility
- [ ] No jank or stuttering during viewport manipulation
- [ ] Initial load renders only visible objects
- [ ] Render groups reduce draw calls by 40%+
- [ ] Debouncing limits culling to 60Hz

---

## Phase 3: Centralized Drag Handler (v8-Compatible)

### 3.1 Implement Global Event Architecture

**Objective:** Replace per-object event listeners with single global handlers using v8's event system.

**Requirements:**
- Single pointermove listener on `app.stage`
- Single pointerup listener on `app.stage`
- Keep pointerdown on individual objects (for hit detection)
- Explicit `eventMode` settings for v8 compatibility
- State variable: `this.draggedObject` to track current drag target

**v8 Event System Implementation:**
```javascript
class CanvasManager {
  setupEventHandlers() {
    // Enable interactive mode on stage (v8 requirement)
    this.app.stage.eventMode = 'static';
    this.app.stage.hitArea = this.app.screen;
    
    // Global handlers (only 2 event listeners!)
    this.app.stage.on('pointermove', this.onGlobalPointerMove.bind(this));
    this.app.stage.on('pointerup', this.onGlobalPointerUp.bind(this));
    this.app.stage.on('pointerupoutside', this.onGlobalPointerUp.bind(this));
    
    this.draggedObject = null;
    this.dragStartOffset = { x: 0, y: 0 };
  }
  
  createObject(objectData) {
    const object = this.createPixiObject(objectData);
    
    // Enable events on individual objects (v8 requirement)
    object.eventMode = 'static'; // Use 'dynamic' if transforms change often
    object.cursor = 'pointer';
    
    // Only pointerdown on individual objects
    object.on('pointerdown', (event) => this.onObjectPointerDown(event, object));
    
    this.objects.set(objectData.id, object);
    this.objectsContainer.addChild(object);
  }
  
  onObjectPointerDown(event, object) {
    // Prevent pan if object is hit
    event.stopPropagation();
    
    this.draggedObject = object;
    
    // Calculate offset for smooth dragging
    const objectPosition = object.position;
    const pointerPosition = event.data.global;
    this.dragStartOffset = {
      x: objectPosition.x - pointerPosition.x,
      y: objectPosition.y - pointerPosition.y
    };
    
    // Visual feedback
    object.alpha = 0.7;
  }
  
  onGlobalPointerMove(event) {
    if (!this.draggedObject) return;
    
    const pointerPosition = event.data.global;
    
    // Update position with offset
    this.draggedObject.x = pointerPosition.x + this.dragStartOffset.x;
    this.draggedObject.y = pointerPosition.y + this.dragStartOffset.y;
    
    // Throttled LiveView update
    this.throttledUpdatePosition(this.draggedObject);
  }
  
  onGlobalPointerUp(event) {
    if (!this.draggedObject) return;
    
    // Restore visual state
    this.draggedObject.alpha = 1.0;
    
    // Final position update to backend
    this.sendFinalPosition(this.draggedObject);
    
    this.draggedObject = null;
  }
  
  throttledUpdatePosition(object) {
    if (this.updateThrottle) return;
    
    this.updateThrottle = setTimeout(() => {
      this.hook.pushEvent('update_object', {
        object_id: object.userData.id,
        position: { x: object.x, y: object.y }
      });
      this.updateThrottle = null;
    }, 50); // 20 updates per second max
  }
}
```

**v8 EventMode Optimization:**
```javascript
// Static mode for objects that rarely change properties
object.eventMode = 'static';

// Dynamic mode for objects that frequently update
animatedObject.eventMode = 'dynamic';

// Disable events entirely for optimization
nonInteractiveObject.eventMode = 'none';
```

**Acceptance Criteria:**
- [ ] Only 3 global event listeners (move + up + upoutside) on stage
- [ ] All objects have explicit `eventMode` set
- [ ] Drag functionality identical to current implementation
- [ ] Memory usage reduced by ~66% (measured in Chrome DevTools)
- [ ] No performance regression
- [ ] v8 event system working correctly

### 3.2 Maintain LiveView Integration

**Objective:** Ensure drag events still sync to backend correctly with v8 changes.

**Requirements:**
- Send `update_object` event during drag (throttled to 50ms)
- Send final `update_object` event on drag end
- Support optimistic updates
- Handle conflicts gracefully
- Compatible with v8's async nature

**Acceptance Criteria:**
- [ ] Real-time position updates visible to other users
- [ ] Final position persisted to database
- [ ] No race conditions or lost updates
- [ ] Graceful handling of concurrent edits
- [ ] Async operations properly awaited

---

## Phase 4: Optimized Remote Cursor Rendering (v8 TextureSource)

### 4.1 Shared Cursor Texture System with v8 API

**Objective:** Leverage v8's texture generation for 70% GPU memory reduction.

**Requirements:**
- Create single shared cursor texture using v8's `generateTexture()`
- Use `Sprite` instances referencing shared texture
- Apply user color via `sprite.tint` property
- Proper TextureSource management

**v8 Implementation:**
```javascript
class CanvasManager {
  async initialize() {
    await this.app.init(/* options */);
    
    // Create shared cursor texture (v8 style)
    this.sharedCursorTexture = this.createSharedCursorTexture();
    
    // Setup cursors container
    this.cursorsContainer = new Container();
    this.cursorsContainer.isRenderGroup = true; // v8 render group
    this.cursorsContainer.label = 'remote-cursors';
    this.app.stage.addChild(this.cursorsContainer);
  }
  
  createSharedCursorTexture() {
    // Draw cursor shape using v8 Graphics API
    const graphics = new Graphics();
    
    // Draw white cursor arrow (will be tinted per user)
    graphics
      .moveTo(0, 0)
      .lineTo(0, 20)
      .lineTo(6, 15)
      .lineTo(10, 24)
      .lineTo(13, 22)
      .lineTo(9, 13)
      .lineTo(16, 13)
      .lineTo(0, 0)
      .fill(0xFFFFFF); // White base color
    
    // Generate texture from graphics (v8 method)
    const texture = this.app.renderer.generateTexture(graphics);
    
    // Clean up temporary graphics
    graphics.destroy();
    
    return texture; // Contains TextureSource internally
  }
  
  createUserCursor(userId, userName, color) {
    // Create sprite from shared texture
    const sprite = new Sprite(this.sharedCursorTexture);
    
    // Apply user-specific color via tint
    sprite.tint = color;
    
    // Create label container
    const labelContainer = new Container();
    
    // User name label (v8 Text API)
    const label = new Text({
      text: userName,
      style: {
        fontFamily: 'Arial',
        fontSize: 12,
        fill: 0xffffff,
        stroke: { color: 0x000000, width: 2 }
      }
    });
    label.x = 18;
    label.y = 2;
    
    labelContainer.addChild(sprite);
    labelContainer.addChild(label);
    
    // Store reference
    this.cursors.set(userId, labelContainer);
    this.cursorsContainer.addChild(labelContainer);
    
    return labelContainer;
  }
  
  updateCursorPosition(userId, x, y) {
    const cursor = this.cursors.get(userId);
    if (!cursor) return;
    
    // Only update position (not re-render)
    cursor.x = x;
    cursor.y = y;
  }
}
```

**v8 Memory Advantages:**
- Single TextureSource shared by all cursor sprites
- Tint operation is GPU-side (no additional memory)
- Render group batches all cursors in single draw call
- 70% GPU memory reduction compared to separate Graphics objects

**Acceptance Criteria:**
- [ ] Single texture created on canvas initialization
- [ ] All user cursors use sprite instances with tint
- [ ] GPU memory usage reduced by 70% (measurable)
- [ ] Visual appearance identical to current implementation
- [ ] Supports 100+ concurrent user cursors at 60 FPS
- [ ] v8 texture API properly utilized

### 4.2 Cursor Label Optimization with v8 Features

**Objective:** Efficiently render user name labels using v8's Text improvements.

**Requirements:**
- Reuse text style objects where possible
- Cache label backgrounds per user
- Update position only (not regenerate text)
- Use render groups for cursor labels

**v8 Text Optimization:**
```javascript
class CanvasManager {
  setupCursorStyles() {
    // Shared text style (v8 accepts style objects)
    this.cursorLabelStyle = {
      fontFamily: 'Arial',
      fontSize: 12,
      fill: 0xffffff,
      stroke: { color: 0x000000, width: 2 },
      resolution: 1 // Lower resolution for memory savings
    };
    
    // Shared background graphics context (v8 feature)
    this.labelBackgroundContext = new GraphicsContext()
      .roundRect(0, 0, 100, 20, 4)
      .fill({ color: 0x000000, alpha: 0.7 });
  }
  
  createUserCursor(userId, userName, color) {
    const container = new Container();
    
    // Cursor sprite (shared texture)
    const sprite = new Sprite(this.sharedCursorTexture);
    sprite.tint = color;
    
    // Label background (shared context)
    const background = new Graphics(this.labelBackgroundContext);
    background.x = 18;
    background.y = 0;
    
    // Label text (v8 API)
    const label = new Text({
      text: userName,
      style: this.cursorLabelStyle // Reuse style
    });
    label.x = 20;
    label.y = 2;
    
    container.addChild(sprite);
    container.addChild(background);
    container.addChild(label);
    
    // Enable culling for distant cursors
    container.cullable = true;
    
    this.cursors.set(userId, container);
    this.cursorsContainer.addChild(container);
    
    return container;
  }
  
  updateUserName(userId, newName) {
    const cursor = this.cursors.get(userId);
    if (!cursor) return;
    
    // Only update text property (efficient in v8)
    const label = cursor.children[2]; // Text object
    label.text = newName;
  }
}
```

**v8 Performance Benefits:**
- Shared GraphicsContext for backgrounds (single GPU upload)
- Text resolution control reduces memory
- Container culling hides distant cursors automatically
- Render group batches all labels efficiently

**Acceptance Criteria:**
- [ ] Name labels render correctly for all users
- [ ] No text rendering on every frame
- [ ] Label backgrounds share common styling
- [ ] Performance: <1ms per frame for 50 cursors
- [ ] v8 GraphicsContext properly utilized
- [ ] Text style reuse reduces memory

---

## Phase 5: Multi-Object Selection (v8-Enhanced)

### 5.1 Implement Selection State Management

**Objective:** Allow users to select and manipulate multiple objects using v8's Container features.

**Requirements:**
- Maintain `Set<objectId>` for selected objects
- Shift+Click adds/removes from selection
- Regular Click clears selection (unless shift held)
- Visual indication using v8 Graphics API
- Support up to 100 selected objects
- Use render groups for selection highlights

**v8 Implementation:**
```javascript
class CanvasManager {
  constructor() {
    this.selectedObjects = new Set(); // Set<string>
    this.selectionGraphicsContext = null; // Shared context
  }
  
  async initialize() {
    // ... app init
    
    // Create shared selection outline context (v8)
    this.selectionGraphicsContext = new GraphicsContext()
      .rect(-2, -2, 104, 104) // Slightly larger than object
      .stroke({ width: 2, color: 0x00aaff });
    
    // Selection highlights container (v8 render group)
    this.selectionContainer = new Container();
    this.selectionContainer.isRenderGroup = true;
    this.selectionContainer.label = 'selection-highlights';
    this.app.stage.addChild(this.selectionContainer);
  }
  
  createObject(objectData) {
    const object = this.createPixiObject(objectData);
    
    // Enable events (v8 requirement)
    object.eventMode = 'static';
    object.cursor = 'pointer';
    
    // Click handler with shift detection
    object.on('pointerdown', (event) => {
      this.handleObjectClick(object, event);
    });
    
    // Store metadata
    object.userData = { id: objectData.id };
    
    this.objects.set(objectData.id, object);
    this.objectsContainer.addChild(object);
  }
  
  handleObjectClick(object, event) {
    const objectId = object.userData.id;
    
    if (event.shiftKey) {
      // Toggle selection
      if (this.selectedObjects.has(objectId)) {
        this.selectedObjects.delete(objectId);
      } else {
        this.selectedObjects.add(objectId);
      }
    } else {
      // Replace selection
      this.selectedObjects.clear();
      this.selectedObjects.add(objectId);
    }
    
    this.updateSelectionVisuals();
    
    // Don't start drag if shift-selecting
    if (event.shiftKey) {
      event.stopPropagation();
    }
  }
  
  updateSelectionVisuals() {
    // Clear old highlights
    this.selectionContainer.removeChildren();
    
    // Create highlights for selected objects (using shared context)
    for (const objectId of this.selectedObjects) {
      const object = this.objects.get(objectId);
      if (!object) continue;
      
      // Create highlight using shared context (v8)
      const highlight = new Graphics(this.selectionGraphicsContext);
      
      // Position to match object
      highlight.x = object.x;
      highlight.y = object.y;
      highlight.rotation = object.rotation;
      highlight.scale.copyFrom(object.scale);
      
      // Non-interactive (optimization)
      highlight.eventMode = 'none';
      
      this.selectionContainer.addChild(highlight);
    }
    
    // v8 render group automatically batches all highlights
  }
  
  clearSelection() {
    this.selectedObjects.clear();
    this.updateSelectionVisuals();
  }
}

// Keyboard shortcut for clear selection
document.addEventListener('keydown', (event) => {
  if (event.key === 'Escape') {
    this.manager.clearSelection();
  }
});
```

**v8 Performance Advantages:**
- Shared GraphicsContext reduces GPU memory
- Render group batches all selection outlines (single draw call)
- `eventMode: 'none'` prevents unnecessary event processing
- Container transforms efficiently applied to children

**Acceptance Criteria:**
- [ ] Shift+Click adds objects to selection
- [ ] Regular Click clears previous selection
- [ ] Selected objects show blue outline/highlight
- [ ] Selection state survives pan/zoom operations
- [ ] Escape key clears all selections
- [ ] v8 GraphicsContext used for shared outline
- [ ] Render group batches highlights efficiently

### 5.2 Implement Multi-Object Dragging with v8 Render Groups

**Objective:** Move all selected objects together leveraging v8's batching.

**Requirements:**
- When dragging any selected object, move all selected objects
- Calculate and apply same delta to all objects in selection
- Maintain relative positions between objects
- Send single batch update to backend on drag end
- Use render groups for efficient rendering during drag

**v8-Optimized Implementation:**
```javascript
class CanvasManager {
  onObjectPointerDown(event, object) {
    event.stopPropagation();
    
    const objectId = object.userData.id;
    
    // If clicking non-selected object without shift, select it
    if (!event.shiftKey && !this.selectedObjects.has(objectId)) {
      this.selectedObjects.clear();
      this.selectedObjects.add(objectId);
      this.updateSelectionVisuals();
    }
    
    // Start drag for all selected objects
    if (this.selectedObjects.has(objectId)) {
      this.draggedObject = object;
      this.isDraggingSelection = this.selectedObjects.size > 1;
      
      // Store initial positions for all selected objects
      this.dragStartPositions = new Map();
      for (const id of this.selectedObjects) {
        const obj = this.objects.get(id);
        this.dragStartPositions.set(id, {
          x: obj.x,
          y: obj.y
        });
      }
      
      // Store pointer start position
      this.dragStartPointer = {
        x: event.data.global.x,
        y: event.data.global.y
      };
      
      // Visual feedback for all selected
      for (const id of this.selectedObjects) {
        this.objects.get(id).alpha = 0.7;
      }
    }
  }
  
  onGlobalPointerMove(event) {
    if (!this.draggedObject) return;
    
    // Calculate drag delta
    const currentPointer = event.data.global;
    const deltaX = currentPointer.x - this.dragStartPointer.x;
    const deltaY = currentPointer.y - this.dragStartPointer.y;
    
    // Move all selected objects
    for (const objectId of this.selectedObjects) {
      const object = this.objects.get(objectId);
      const startPos = this.dragStartPositions.get(objectId);
      
      object.x = startPos.x + deltaX;
      object.y = startPos.y + deltaY;
    }
    
    // Update selection highlights to match
    this.updateSelectionVisuals();
    
    // Throttled LiveView update
    this.throttledBatchUpdate();
  }
  
  onGlobalPointerUp(event) {
    if (!this.draggedObject) return;
    
    // Restore visual state
    for (const id of this.selectedObjects) {
      this.objects.get(id).alpha = 1.0;
    }
    
    // Send batch update to backend
    if (this.isDraggingSelection) {
      this.sendBatchUpdate();
    } else {
      this.sendSingleUpdate(this.draggedObject);
    }
    
    this.draggedObject = null;
    this.isDraggingSelection = false;
    this.dragStartPositions.clear();
  }
  
  sendBatchUpdate() {
    const updates = Array.from(this.selectedObjects).map(id => {
      const object = this.objects.get(id);
      return {
        object_id: id,
        position: { x: object.x, y: object.y }
      };
    });
    
    this.hook.pushEvent('update_objects_batch', { updates });
  }
  
  throttledBatchUpdate() {
    if (this.batchUpdateThrottle) return;
    
    this.batchUpdateThrottle = setTimeout(() => {
      const updates = Array.from(this.selectedObjects).map(id => {
        const object = this.objects.get(id);
        return {
          object_id: id,
          position: { x: object.x, y: object.y }
        };
      });
      
      this.hook.pushEvent('update_objects_realtime', { updates });
      this.batchUpdateThrottle = null;
    }, 50);
  }
}
```

**v8 Performance Benefits:**
- Render groups batch all selected objects
- Efficient transform updates (GPU-side)
- No re-upload of graphics data during drag
- Container culling automatically applied

**Acceptance Criteria:**
- [ ] All selected objects move together maintaining relative positions
- [ ] Single batch update event sent to backend
- [ ] Optimistic updates render immediately
- [ ] Undo/redo works for multi-object moves
- [ ] Performance: No lag with 50+ selected objects
- [ ] v8 render groups optimize batch rendering

### 5.3 Backend Batch Update Support

**Objective:** Handle batch position updates efficiently on the backend.

**Requirements:**
- New LiveView event handler: `update_objects_batch`
- Single database transaction for all updates
- Single PubSub broadcast with all changes
- Conflict detection for locked objects

**Elixir Implementation:**
```elixir
def handle_event("update_objects_batch", %{"updates" => updates}, socket) do
  canvas_id = socket.assigns.canvas_id
  user_id = socket.assigns.current_user.id

  # Update all objects in single transaction
  result = Repo.transaction(fn ->
    Enum.map(updates, fn update ->
      case Canvases.update_object(
        update["object_id"],
        update["position"],
        user_id
      ) do
        {:ok, object} -> {:ok, object}
        {:error, :locked} -> {:error, :locked, update["object_id"]}
        {:error, reason} -> {:error, reason}
      end
    end)
  end)

  case result do
    {:ok, results} ->
      # Check for any locked objects
      locked = Enum.filter(results, fn
        {:error, :locked, _} -> true
        _ -> false
      end)

      if Enum.empty?(locked) do
        # Single broadcast for all successful updates
        PubSub.broadcast(
          CollabCanvas.PubSub,
          "canvas:#{canvas_id}",
          {:objects_updated_batch, updates, user_id}
        )

        {:noreply, socket}
      else
        # Some objects were locked, inform user
        locked_ids = Enum.map(locked, fn {:error, :locked, id} -> id end)

        {:noreply,
         socket
         |> put_flash(:error, "Some objects are locked: #{inspect(locked_ids)}")}
      end

    {:error, _reason} ->
      # Transaction failed, rollback automatic
      {:noreply,
       socket
       |> put_flash(:error, "Failed to update objects")}
  end
end

# Real-time updates during drag
def handle_event("update_objects_realtime", %{"updates" => updates}, socket) do
  canvas_id = socket.assigns.canvas_id
  user_id = socket.assigns.current_user.id

  # Broadcast without database update (optimistic)
  PubSub.broadcast(
    CollabCanvas.PubSub,
    "canvas:#{canvas_id}",
    {:objects_moved_realtime, updates, user_id}
  )

  {:noreply, socket}
end
```

**Frontend PubSub Handler:**
```javascript
// In LiveView hook
this.handleEvent("objects_updated_batch", ({ updates, userId }) => {
  if (userId === this.currentUserId) return; // Ignore own updates

  updates.forEach(update => {
    const object = this.manager.objects.get(update.object_id);
    if (object) {
      object.x = update.position.x;
      object.y = update.position.y;
    }
  });

  this.manager.updateSelectionVisuals();
});
```

**Acceptance Criteria:**
- [ ] Batch updates processed in single transaction
- [ ] All-or-nothing update semantics
- [ ] Single broadcast to all users
- [ ] Proper error handling and rollback
- [ ] Performance: <50ms for 50 object updates
- [ ] Locked object conflicts handled gracefully

---

## Testing Strategy

### Unit Tests

**CanvasManager Class:**
- [ ] v8 async initialization
- [ ] Viewport culling calculations with v8 Culler
- [ ] Multi-selection state management
- [ ] Drag delta calculations
- [ ] Cursor position transforms
- [ ] GraphicsContext reuse

**PerformanceMonitor:**
- [ ] FPS calculation accuracy with v8 Ticker
- [ ] Frame time tracking
- [ ] Performance overhead measurement
- [ ] v7 vs v8 performance comparison

### Integration Tests

**v8 Compatibility:**
- [ ] Async initialization in LiveView hook
- [ ] Event system with explicit eventMode
- [ ] Graphics API v8 syntax
- [ ] Texture Source management
- [ ] Container culling integration

**LiveView Integration:**
- [ ] Object creation syncs to backend
- [ ] Batch updates persist correctly
- [ ] Real-time cursor updates
- [ ] Concurrent user interactions
- [ ] Async operations properly handled

### Performance Tests

**v8 Benchmarks:**
- [ ] 1000 objects: Maintain 60 FPS
- [ ] 2000 objects (v8 improvement): Maintain 60 FPS
- [ ] 5000 objects (90% culled): Maintain 60 FPS
- [ ] 50 concurrent cursors: <2ms rendering overhead
- [ ] 100 selected objects: Drag at 60 FPS
- [ ] v7 baseline vs v8 performance comparison

**v8-Specific Tests:**
- [ ] Render group batching effectiveness
- [ ] Container culling performance impact
- [ ] GraphicsContext memory savings
- [ ] TextureSource sharing benefits
- [ ] Culler.shared performance

**Load Testing:**
- [ ] 50 simultaneous users
- [ ] 10,000 objects per canvas
- [ ] 1000 updates per second
- [ ] Memory usage under 500MB
- [ ] v8 WebGL vs WebGPU comparison (if available)

### Manual Testing Checklist

**Basic Functionality (v8):**
- [ ] Create rectangle, circle, text (v8 API)
- [ ] Drag single object
- [ ] Drag multiple objects
- [ ] Pan with space+drag
- [ ] Zoom with scroll
- [ ] Delete objects
- [ ] Async operations complete correctly

**Multi-User:**
- [ ] See other users' cursors
- [ ] See other users' edits in real-time
- [ ] Locked object indication
- [ ] Cursor name labels

**Performance:**
- [ ] Smooth pan/zoom with 1000+ objects
- [ ] No lag during multi-object drag
- [ ] Cursors render smoothly for 20+ users
- [ ] v8 performance gains visible

**v8-Specific:**
- [ ] Render groups reduce draw calls
- [ ] Container culling works correctly
- [ ] Shared textures reduce memory
- [ ] GraphicsContext sharing functional

---

## Implementation Plan

### Milestone 0: v8 Migration Preparation (Days 1-2)

**Tasks:**
1. Dependency audit and compatibility check
2. Update package.json to pixi.js@^8.0.0
3. Update all import statements
4. Migrate to async initialization pattern
5. Update Graphics API to v8 syntax
6. Migrate texture handling to TextureSource
7. Test basic canvas functionality

**Deliverables:**
- v8-compatible codebase
- Migration issues documented
- Performance baseline established

### Milestone 1: Architecture Refactoring (Day 3)

**Tasks:**
1. Extract CanvasManager class from hook (with v8 changes)
2. Implement PerformanceMonitor (v8 Ticker)
3. Update hook to use new class structure
4. Verify backward compatibility

**Deliverables:**
- `core/canvas_manager_class.js`
- `core/performance_monitor.js`
- `core/v8_compatibility.js`
- Updated `canvas_manager.js` hook

### Milestone 2: Viewport Culling (Day 4)

**Tasks:**
1. Implement `updateVisibleObjects()` with v8 Culler
2. Integrate with pan/zoom handlers
3. Setup render groups for visible/culled objects
4. Add configurable padding parameter
5. Performance testing with 5000 objects

**Deliverables:**
- v8-optimized viewport culling
- Performance benchmark results (v7 vs v8)

### Milestone 3: Centralized Drag Handler (Day 5)

**Tasks:**
1. Implement global event handlers (v8 event system)
2. Migrate drag logic from per-object to global
3. Set explicit eventMode on all objects
4. Remove old event listeners
5. Verify LiveView integration

**Deliverables:**
- v8-compatible event handling
- Memory usage reduction metrics

### Milestone 4: Cursor Optimization (Day 5-6)

**Tasks:**
1. Create shared cursor texture (v8 generateTexture)
2. Migrate to sprite-based rendering
3. Implement tint-based coloring
4. Use GraphicsContext for label backgrounds
5. Setup render group for cursors
6. Optimize label rendering

**Deliverables:**
- v8 TextureSource-based cursor system
- GPU memory savings metrics
- Render group performance data

### Milestone 5: Multi-Selection (Day 6-7)

**Tasks:**
1. Implement selection state management
2. Create shared GraphicsContext for selection outlines
3. Add Shift+Click handler
4. Implement multi-object dragging with render groups
5. Create backend batch update handler
6. Visual selection indicators (v8 Graphics)

**Deliverables:**
- Multi-selection feature complete
- Backend batch update endpoint
- v8-optimized selection rendering

### Milestone 6: Testing & Polish (Day 7)

**Tasks:**
1. Run full test suite
2. v7 vs v8 performance comparison
3. Fix any bugs discovered
4. Update documentation
5. Create migration guide

**Deliverables:**
- Test results report
- Performance comparison (v7 vs v8)
- Updated README
- v8 migration guide

---

## Success Metrics

### Performance Metrics

**Target Improvements (v7 → v8):**
- **FPS:** 40 → 60 FPS with 1000 objects (+50%)
- **FPS (v8 boost):** 60 → 60 FPS with 2000 objects (2x capacity)
- **Memory:** 300MB → 90MB for 50 cursors (-70%)
- **Render Time:** 25ms → 12ms per frame (-52% with v8)
- **Event Listeners:** 3000 → 100 (-97%)
- **Draw Calls:** 100 → 20 with render groups (-80%)
- **Bundle Size:** -25% with single-package structure

### v8-Specific Metrics

**Render Groups:**
- 40-60% reduction in draw calls
- Improved batch efficiency

**Container Culling:**
- 10-15% CPU usage reduction
- Faster culling than custom implementation

**GraphicsContext Sharing:**
- 60-70% memory reduction for shared graphics
- Faster graphics object creation

**TextureSource Management:**
- Simplified texture lifecycle
- Automatic mipmap handling

### User Experience

**Qualitative Goals:**
- Buttery smooth panning and zooming
- Instant response to drag operations
- No visible lag with 50+ users (100+ with v8)
- Professional desktop-app feel
- Faster initial load time (v8 optimizations)

---

## Risk Mitigation

### v8-Specific Risks

**Risk: v8 migration breaks existing functionality**
- Mitigation: Comprehensive test suite before changes
- Mitigation: Phase 0 dedicated to migration
- Mitigation: v7 baseline performance documented
- Mitigation: Feature flag for v7/v8 toggle during transition

**Risk: Third-party library incompatibility**
- Mitigation: Complete dependency audit in Phase 0
- Mitigation: Alternative libraries identified
- Mitigation: Custom implementations as fallback

**Risk: v8 performance worse on low-end devices**
- Mitigation: WebGL fallback (v8 supports both WebGL and WebGPU)
- Mitigation: Progressive enhancement
- Mitigation: Device capability detection
- Mitigation: Configurable quality settings

**Risk: Async initialization complicates LiveView integration**
- Mitigation: Proper async/await handling in hooks
- Mitigation: Loading states during initialization
- Mitigation: Error handling for initialization failures
- Mitigation: Fallback to v7 if init fails

### General Technical Risks

**Risk: Performance worse on low-end devices**
- Mitigation: Progressive enhancement approach
- Mitigation: Device capability detection
- Mitigation: Configurable culling aggressiveness
- Mitigation: v8's better mobile performance helps

**Risk: LiveView sync issues with batch updates**
- Mitigation: Extensive integration testing
- Mitigation: Conflict resolution strategy
- Mitigation: Optimistic update reconciliation
- Mitigation: Async operation handling

### Project Risks

**Risk: Scope creep beyond 7 days**
- Mitigation: Strict phase gating
- Mitigation: MVP-first approach
- Mitigation: Defer nice-to-haves to Phase 6
- Mitigation: v8 migration is Day 1-2 only

**Risk: Common Lisp reference code doesn't translate well**
- Mitigation: Adapt patterns rather than direct port
- Mitigation: Leverage v8 best practices
- Mitigation: Consult PixiJS v8 documentation
- Mitigation: Use v8-native features where better

---

## Code Quality Standards

### Architecture Principles
- **Separation of Concerns:** Clear boundaries between hook, manager, and PixiJS
- **Single Responsibility:** Each class/module has one clear purpose
- **Testability:** All logic testable without DOM or LiveView
- **Performance First:** Minimize allocations, cache calculations
- **v8-Optimized:** Use v8 features (render groups, Culler, GraphicsContext)

### Code Style
- **ES6+ Features:** Use modern JavaScript (classes, async/await, destructuring)
- **v8 API Compliance:** Follow v8 conventions and best practices
- **TypeScript-Ready:** JSDoc comments for all public methods
- **Error Handling:** Graceful degradation, async error handling
- **Logging:** Structured logging with performance markers

### v8-Specific Guidelines
- Always use async/await for initialization
- Explicit eventMode on all interactive objects
- Prefer GraphicsContext for shared graphics
- Use render groups for batched rendering
- Leverage Culler.shared for culling
- Use v8 Graphics API (shape-then-fill pattern)
- Proper TextureSource lifecycle management

### Documentation Requirements
- **Inline Comments:** Complex algorithms explained
- **Method Documentation:** JSDoc for all public APIs
- **Architecture Diagrams:** Visual representation of class relationships
- **Performance Notes:** Document optimization reasoning
- **v8 Migration Notes:** Document v7 → v8 changes

---

## Rollout Strategy

### Phase 1: Internal Testing (Day 7)
- Deploy to staging environment
- Manual testing with 5-10 internal users
- v7 vs v8 performance profiling
- v8-specific feature validation

### Phase 2: Beta Release (Week 2)
- Feature flag: `enable_pixijs_v8: true`
- Invite 50 beta users
- Monitor performance metrics
- Collect feedback on v8 improvements
- Identify any v8 compatibility issues

### Phase 3: General Availability (Week 3)
- Enable v8 for all users
- Monitor error rates and performance
- Prepare hotfix process
- Document v8 performance improvements

### Rollback Plan
- Feature flag to revert to v7 implementation
- Keep v7 code for 2 weeks post-GA
- Database migrations are backward compatible
- v8-specific features degrade gracefully

---

## Future Enhancements (Out of Scope)

### Potential Phase 6 Features
- **WebGPU Renderer:** Enable WebGPU when available for additional performance
- **Spatial Index:** Quadtree for faster hit detection (complementing v8 culling)
- **Custom Shaders:** Leverage v8's unified shader system
- **Object Grouping:** Hierarchical organization with render groups
- **Smart Snapping:** Align objects with guides
- **Collaborative Cursors:** Show what each user is selecting
- **Undo/Redo Stack:** Full history management
- **Copy/Paste:** Duplicate objects easily
- **Advanced Particles:** Use v8's upgraded ParticleContainer

---

## Appendix A: PixiJS v8 Migration Checklist

### Package Structure
- [ ] Remove all `@pixi/*` packages
- [ ] Install `pixi.js@^8.0.0`
- [ ] Update all import statements
- [ ] Review custom build configuration

### Initialization
- [ ] Make initialization async
- [ ] Move options to `init()` method
- [ ] Update `mounted()` hook to be async
- [ ] Handle initialization errors

### Graphics API
- [ ] Replace `beginFill/endFill` with shape + fill
- [ ] Update method names (drawRect → rect, etc.)
- [ ] Convert holes to `cut()` pattern
- [ ] Migrate to GraphicsContext for shared graphics

### Textures
- [ ] Replace BaseTexture with TextureSource
- [ ] Update mipmap property names
- [ ] Handle RenderTexture mipmaps manually
- [ ] Use appropriate Source types (Image, Canvas, Video)

### Containers & Display Objects
- [ ] Ensure only Containers have children
- [ ] Replace `updateTransform` with `onRender`
- [ ] Implement container culling
- [ ] Setup render groups

### Events
- [ ] Set explicit `eventMode` on all objects
- [ ] Update default from 'auto' to 'passive'
- [ ] Optimize with `interactiveChildren`
- [ ] Update Ticker callback signature

### Miscellaneous APIs
- [ ] Change `app.view` to `app.canvas`
- [ ] Update `getBounds()` to use `.rectangle`
- [ ] Replace constants with string literals
- [ ] Update constructor signatures
- [ ] Remove utils namespace usage

---

## Appendix B: PixiJS Performance Quick Reference

### Render Optimization Hierarchy
1. **Use Spritesheets** - 16 textures batch together
2. **Render Groups** - Explicit batch control (v8)
3. **Container Culling** - Hide off-screen content (v8)
4. **GraphicsContext** - Share graphics data (v8)
5. **Blend Mode Grouping** - Avoid batch breaks
6. **Event Mode Optimization** - Reduce event processing

### Memory Optimization
1. **Shared Textures** - One texture, many sprites
2. **TextureSource Reuse** - v8 automatic management
3. **Destroy Unused** - Manual cleanup when needed
4. **Lower Resolution** - Reduce texture sizes
5. **GraphicsContext Sharing** - Reuse graphics definitions

### CPU Optimization
1. **Culler.shared** - v8's optimized culling
2. **Static EventMode** - For rarely-changing objects
3. **Disable Interactive Children** - Skip event checks
4. **ParticleContainer** - Lightweight particles (v8 upgraded)
5. **Render Groups** - Reduce scene graph traversal

### GPU Optimization
1. **Batch Rendering** - Group by texture/blend mode
2. **Mipmaps** - For scaled textures
3. **Disable Alpha/Antialias** - Mobile performance
4. **Filter Areas** - Specify bounds explicitly
5. **Tint Over Filters** - GPU-side color changes

---

## Appendix C: Reference Implementation Comparison

### Common Lisp Reference Features (Adapted for v8)
```javascript
// Key patterns to port with v8 enhancements:

1. PerformanceMonitor class
   - FPS tracking with moving average
   - Frame time analysis
   - Memory usage monitoring
   - v8 Ticker integration

2. Viewport culling algorithm
   - calculateVisibleBounds(padding)
   - boundsIntersect(a, b)
   - updateVisibleObjects()
   - v8 Culler.shared integration

3. Centralized event handling
   - Single stage-level listeners
   - State machine for drag/pan/zoom
   - Event delegation pattern
   - v8 eventMode optimization

4. Shared texture optimization
   - generateTexture() for reusable assets
   - Sprite pooling for cursors
   - Tint-based color variations
   - v8 TextureSource management

5. Multi-selection architecture
   - Set-based selection tracking
   - Batch update queue
   - Selection visual container
   - v8 GraphicsContext for highlights
   - Render groups for batch rendering
```

### v8-Specific Enhancements Beyond Reference
```javascript
// New v8 features not in reference:

1. Render Groups
   - Explicit batch control
   - Reduced scene graph traversal
   - Better cache locality

2. Container Culling
   - Built-in culling properties
   - cullable, cullArea, cullableChildren
   - Automatic visibility management

3. GraphicsContext
   - Share graphics definitions
   - Reduce GPU memory
   - Faster object creation

4. Unified Shader System
   - WebGL and WebGPU support
   - Simplified shader creation
   - Resource-based architecture

5. Upgraded ParticleContainer
   - 10x more particles
   - Particle interface
   - Direct array manipulation
```

---

## Appendix D: Performance Comparison Table

| Metric | v7 Baseline | v8 Target | Improvement |
|--------|-------------|-----------|-------------|
| Max Objects @ 60 FPS | 1,000 | 2,000 | +100% |
| Culled Objects @ 60 FPS | 3,000 | 5,000 | +67% |
| Cursor GPU Memory (50 users) | 300 MB | 90 MB | -70% |
| Frame Time (1000 objects) | 25 ms | 12 ms | -52% |
| Event Listeners (1000 objects) | 3,000 | 100 | -97% |
| Draw Calls (render groups) | 100 | 20 | -80% |
| Bundle Size | 500 KB | 375 KB | -25% |
| Initialization Time | 200 ms | 180 ms | -10% |
| Memory Usage (complex scene) | 450 MB | 280 MB | -38% |

---

## Conclusion

This PRD provides a comprehensive blueprint for enhancing the CollabCanvas frontend with battle-tested performance patterns from the Common Lisp reference implementation, **combined with the powerful new features and optimizations available in PixiJS v8**.

**Key Deliverables:**
1. **PixiJS v8 Migration:** Modern, performant renderer with WebGPU-ready architecture
2. **Modular CanvasManager:** Clean architecture with v8-optimized patterns
3. **10x Performance:** Via culling, render groups, and v8's improvements
4. **70% GPU Memory Reduction:** Shared textures and GraphicsContext
5. **Multi-Object Selection:** With v8's efficient batching
6. **Centralized Events:** Maintainable, memory-efficient handling

**v8-Specific Benefits:**
- Render groups for optimal batching
- Built-in container culling
- GraphicsContext for shared graphics
- Upgraded ParticleContainer
- Simplified texture management
- Better mobile performance

**Timeline:** 4-7 days for full implementation, testing, and v8 migration

**Next Steps:**
1. Review and approve PRD
2. Begin Phase 0: v8 Migration Assessment
3. Set up Task Master tasks from this PRD
4. Daily progress check-ins and performance validation
5. Document v7 → v8 performance improvements
