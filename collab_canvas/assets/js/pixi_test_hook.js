/**
 * PixiTest Hook - Tests basic PixiJS rendering
 *
 * This hook creates a simple PixiJS application with a rotating red square
 * to verify that PixiJS is properly installed and configured.
 */
export const PixiTest = {
  mounted() {
    // Get PIXI from window (exposed in app.js)
    const PIXI = window.PIXI;

    if (!PIXI) {
      console.error("PixiJS not found! Make sure it's imported in app.js");
      return;
    }

    console.log("PixiJS version:", PIXI.VERSION);
    console.log("PixiJS initialized successfully!");

    // Create a PixiJS Application
    const app = new PIXI.Application();

    // Initialize the application
    (async () => {
      await app.init({
        width: 800,
        height: 600,
        backgroundColor: 0x1099bb,
        resolution: window.devicePixelRatio || 1,
      });

      // Append the canvas to the container
      this.el.appendChild(app.canvas);

      // Create a red square
      const graphics = new PIXI.Graphics();
      graphics.rect(0, 0, 100, 100);
      graphics.fill(0xff0000);

      // Position the square in the center
      graphics.x = app.screen.width / 2;
      graphics.y = app.screen.height / 2;
      graphics.pivot.set(50, 50);

      // Add the square to the stage
      app.stage.addChild(graphics);

      // Animate the square (rotation)
      app.ticker.add(() => {
        graphics.rotation += 0.01;
      });

      console.log("PixiJS test rendering complete!");
    })();

    // Store app instance for cleanup
    this.pixiApp = app;
  },

  destroyed() {
    // Clean up PixiJS resources when the hook is destroyed
    if (this.pixiApp) {
      this.pixiApp.destroy(true, { children: true, texture: true });
      console.log("PixiJS app destroyed");
    }
  }
};
