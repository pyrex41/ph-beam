/**
 * Test helpers for CollabCanvas E2E tests
 */

const puppeteer = require('puppeteer');

const BASE_URL = process.env.BASE_URL || 'http://localhost:4001';
const HEADLESS = process.env.HEADLESS !== 'false';

/**
 * Launch browser and create a new page
 */
async function setupBrowser() {
  const browser = await puppeteer.launch({
    headless: HEADLESS,
    args: ['--no-sandbox', '--disable-setuid-sandbox']
  });
  const page = await browser.newPage();
  await page.setViewport({ width: 1280, height: 800 });

  // Set authentication session cookie
  await page.setCookie({
    name: '_collab_canvas_key',
    value: process.env.SESSION_COOKIE || 'SFMyNTY.g3QAAAAEbQAAAAtfY3NyZl90b2tlbm0AAAAYYUdrYUpDZE84NVU1QUJ3WTBqelhjVFRUbQAAAAp1c2VyX2VtYWlsbQAAABVyZXViLmJyb29rc0BnbWFpbC5jb21tAAAAB3VzZXJfaWRhAW0AAAAJdXNlcl9uYW1lbQAAABVyZXViLmJyb29rc0BnbWFpbC5jb20.3WYffWGqfxMLUxLm_W5QBwGTBfBIgHF5yze7tOUv1Fk',
    domain: 'localhost',
    path: '/'
  });

  // Listen for console messages for debugging
  page.on('console', msg => {
    if (msg.type() === 'error') {
      console.error('Browser console error:', msg.text());
    }
  });

  return { browser, page };
}

/**
 * Wait for LiveView to be connected and ready
 */
async function waitForLiveView(page) {
  try {
    // Try to wait for liveSocket (might not be exposed)
    await page.waitForFunction(
      () => {
        const socket = window.liveSocket;
        return socket && socket.isConnected && socket.isConnected();
      },
      { timeout: 5000 }
    );
  } catch (error) {
    // Fallback: wait for LiveView hooks to be initialized
    await page.waitForFunction(
      () => {
        // Check if Phoenix LiveView has loaded
        return typeof window.Phoenix !== 'undefined' &&
               typeof window.Phoenix.LiveView !== 'undefined';
      },
      { timeout: 10000 }
    );
  }
  // Give a bit more time for initial render
  await new Promise(resolve => setTimeout(resolve, 500));
}

/**
 * Sleep helper for Puppeteer
 */
async function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

/**
 * Create a new canvas and navigate to it
 */
async function createCanvas(page, name = 'Test Canvas') {
  await page.goto(`${BASE_URL}/dashboard`, { waitUntil: 'networkidle0' });
  await waitForLiveView(page);

  // Click "New Canvas" button - use XPath to find by text
  const newCanvasButton = await page.evaluateHandle(() => {
    const buttons = Array.from(document.querySelectorAll('button'));
    return buttons.find(btn =>
      btn.textContent.includes('New Canvas') ||
      btn.getAttribute('phx-click') === 'toggle_create_form'
    );
  });
  await newCanvasButton.click();
  await sleep(300);

  // Fill in canvas name
  const nameInput = await page.$('input[name="name"], input[placeholder*="canvas"], input[phx-blur="update_name"]');
  await nameInput.type(name);

  // Submit form - find Create button by text
  const createButton = await page.evaluateHandle(() => {
    const buttons = Array.from(document.querySelectorAll('button'));
    return buttons.find(btn =>
      btn.textContent.includes('Create') ||
      btn.getAttribute('phx-click') === 'create_canvas'
    );
  });
  await createButton.click();

  // Wait for navigation to canvas page
  await page.waitForFunction(
    () => window.location.pathname.startsWith('/canvas/'),
    { timeout: 5000 }
  );
  await waitForLiveView(page);

  return page.url().match(/\/canvas\/(\d+)/)[1];
}

/**
 * Select a tool from the toolbar
 */
async function selectTool(page, toolName) {
  const toolSelector = `button[phx-click="select_tool"][phx-value-tool="${toolName}"]`;
  await page.waitForSelector(toolSelector);
  await page.click(toolSelector);
  await sleep(200);
}

/**
 * Create a rectangle on the canvas
 */
async function createRectangle(page, x, y, width, height) {
  await selectTool(page, 'rectangle');

  const canvasSelector = 'canvas';
  await page.waitForSelector(canvasSelector);

  const canvas = await page.$(canvasSelector);
  const box = await canvas.boundingBox();

  // Draw rectangle by dragging
  await page.mouse.move(box.x + x, box.y + y);
  await page.mouse.down();
  await page.mouse.move(box.x + x + width, box.y + y + height);
  await page.mouse.up();

  await sleep(300);
}

/**
 * Create a circle on the canvas
 */
async function createCircle(page, x, y, radius) {
  await selectTool(page, 'circle');

  const canvasSelector = 'canvas';
  await page.waitForSelector(canvasSelector);

  const canvas = await page.$(canvasSelector);
  const box = await canvas.boundingBox();

  // Draw circle by dragging
  await page.mouse.move(box.x + x, box.y + y);
  await page.mouse.down();
  await page.mouse.move(box.x + x + radius * 2, box.y + y + radius * 2);
  await page.mouse.up();

  await sleep(300);
}

/**
 * Select objects using lasso selection
 */
async function lassoSelect(page, points) {
  await selectTool(page, 'select');

  const canvasSelector = 'canvas';
  const canvas = await page.$(canvasSelector);
  const box = await canvas.boundingBox();

  // Hold shift for lasso selection
  await page.keyboard.down('Shift');

  // Start at first point
  await page.mouse.move(box.x + points[0].x, box.y + points[0].y);
  await page.mouse.down();

  // Draw through all points
  for (let i = 1; i < points.length; i++) {
    await page.mouse.move(box.x + points[i].x, box.y + points[i].y);
    await sleep(50);
  }

  await page.mouse.up();
  await page.keyboard.up('Shift');
  await sleep(300);
}

/**
 * Click on the canvas at specific coordinates
 */
async function clickCanvas(page, x, y) {
  const canvasSelector = 'canvas';
  const canvas = await page.$(canvasSelector);
  const box = await canvas.boundingBox();

  await page.mouse.click(box.x + x, box.y + y);
  await sleep(200);
}

/**
 * Wait for element with text content
 */
async function waitForText(page, text, timeout = 5000) {
  await page.waitForFunction(
    (searchText) => {
      const elements = Array.from(document.querySelectorAll('*'));
      return elements.some(el => el.textContent.includes(searchText));
    },
    { timeout },
    text
  );
}

/**
 * Check if text exists on page
 */
async function hasText(page, text) {
  return await page.evaluate((searchText) => {
    const elements = Array.from(document.querySelectorAll('*'));
    return elements.some(el => el.textContent.includes(searchText));
  }, text);
}

/**
 * Find button by text content (Puppeteer compatible)
 */
async function findButtonByText(page, text) {
  return await page.evaluateHandle((searchText) => {
    const buttons = Array.from(document.querySelectorAll('button'));
    return buttons.find(btn => btn.textContent.includes(searchText));
  }, text);
}

/**
 * Click button by text content
 */
async function clickButtonByText(page, text) {
  const button = await findButtonByText(page, text);
  if (button) {
    await button.click();
    return true;
  }
  return false;
}

/**
 * Get canvas object count
 */
async function getObjectCount(page) {
  return await page.evaluate(() => {
    // Access PixiJS stage to count objects
    const canvasManager = window.canvasManager;
    if (canvasManager && canvasManager.stage) {
      return canvasManager.stage.children.length;
    }
    return 0;
  });
}

module.exports = {
  BASE_URL,
  setupBrowser,
  waitForLiveView,
  createCanvas,
  selectTool,
  createRectangle,
  createCircle,
  lassoSelect,
  clickCanvas,
  waitForText,
  hasText,
  findButtonByText,
  clickButtonByText,
  getObjectCount,
  sleep
};
