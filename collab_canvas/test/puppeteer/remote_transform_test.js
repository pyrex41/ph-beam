/**
 * Puppeteer test for remote transform visualization
 *
 * This test reproduces the issue where:
 * 1. Selection boxes appear on remote clients instead of glows
 * 2. Objects appear see-through after transforms
 * 3. Visual artifacts during real-time transforms
 *
 * Run with: node test/puppeteer/remote_transform_test.js
 */

const puppeteer = require('puppeteer');
const path = require('path');
const fs = require('fs');

// Configuration
const BASE_URL = 'http://localhost:4000';
const SCREENSHOT_DIR = path.join(__dirname, 'screenshots');
const DELAY = (ms) => new Promise(resolve => setTimeout(resolve, ms));

// Ensure screenshot directory exists
if (!fs.existsSync(SCREENSHOT_DIR)) {
  fs.mkdirSync(SCREENSHOT_DIR, { recursive: true });
}

async function setupBrowser() {
  const browser = await puppeteer.launch({
    headless: false, // Keep visible to see what's happening
    defaultViewport: { width: 1400, height: 900 },
    args: ['--no-sandbox', '--disable-setuid-sandbox']
  });

  return browser;
}

async function loginAndNavigateToCanvas(page, userEmail) {
  console.log(`\n🔑 Logging in as ${userEmail}...`);

  // Navigate to home page
  await page.goto(BASE_URL, { waitUntil: 'networkidle2' });

  // Check if already logged in (look for canvas list or profile)
  const isLoggedIn = await page.evaluate(() => {
    return document.body.textContent.includes('My Canvases') ||
           document.body.textContent.includes('Create New Canvas');
  });

  if (!isLoggedIn) {
    console.log('  Not logged in, attempting Auth0 login...');
    // Click login button
    await page.click('a[href*="auth/auth0"]');
    await page.waitForNavigation({ waitUntil: 'networkidle2' });

    // Fill Auth0 credentials (this assumes test environment with auto-login or mock auth)
    // In production, you'd need to handle Auth0's actual login flow
  }

  // Find or create a test canvas
  console.log('  Looking for existing test canvas...');

  const canvasLink = await page.evaluate(() => {
    const links = Array.from(document.querySelectorAll('a[href*="/canvas/"]'));
    if (links.length > 0) {
      return links[0].href;
    }
    return null;
  });

  if (canvasLink) {
    console.log(`  Found canvas: ${canvasLink}`);
    await page.goto(canvasLink, { waitUntil: 'networkidle2' });
  } else {
    console.log('  Creating new test canvas...');
    // Create new canvas
    await page.click('button:has-text("Create New Canvas"), a:has-text("Create New Canvas")');
    await page.waitForNavigation({ waitUntil: 'networkidle2' });
  }

  // Wait for canvas to load
  await page.waitForSelector('canvas', { timeout: 10000 });
  console.log('  ✓ Canvas loaded');

  return page.url();
}

async function captureConsoleLogs(page, label) {
  const logs = [];

  page.on('console', msg => {
    const text = msg.text();
    // Filter for relevant logs
    if (text.includes('[CanvasManager]') ||
        text.includes('Remote transform') ||
        text.includes('glow') ||
        text.includes('lock')) {
      logs.push({ type: msg.type(), text, label });
      console.log(`  [${label}] ${msg.type()}: ${text}`);
    }
  });

  return logs;
}

async function createTestObject(page, type = 'rectangle') {
  console.log(`\n📦 Creating ${type} object...`);

  await page.evaluate((objectType) => {
    // Access the CanvasManager hook
    const canvasElement = document.querySelector('[phx-hook="CanvasManager"]');
    if (!canvasElement) {
      throw new Error('Canvas element not found');
    }

    // Simulate creating an object at a specific position
    // This will depend on your actual UI - you might need to:
    // 1. Select the tool
    // 2. Click on the canvas
    // 3. Or use the AI command

    // For now, let's use AI command as it's easiest
    const commandInput = document.querySelector('textarea[name="ai_command"]');
    const executeButton = document.getElementById('ai-execute-button');

    if (commandInput && executeButton) {
      commandInput.value = `Create a ${objectType} at position 200, 200 with width 150 and height 100`;
      commandInput.dispatchEvent(new Event('input', { bubbles: true }));
      executeButton.click();
    }
  }, type);

  // Wait for object creation
  await DELAY(2000);
  console.log('  ✓ Object created');
}

async function selectAndTransformObject(page, objectIndex = 0) {
  console.log(`\n🖱️  Selecting and resizing object ${objectIndex}...`);

  await page.evaluate((index) => {
    const canvas = document.querySelector('canvas');
    const rect = canvas.getBoundingClientRect();

    // Click on the object to select it
    const clickX = rect.left + 200;
    const clickY = rect.top + 200;

    const clickEvent = new MouseEvent('click', {
      bubbles: true,
      cancelable: true,
      clientX: clickX,
      clientY: clickY
    });

    canvas.dispatchEvent(clickEvent);
  }, objectIndex);

  await DELAY(500);
  console.log('  ✓ Object selected');

  // Now resize it
  console.log('  Resizing object...');

  await page.evaluate(() => {
    const canvas = document.querySelector('canvas');
    const rect = canvas.getBoundingClientRect();

    // Find resize handle (bottom-right corner)
    // Simulate drag from current position to new position
    const startX = rect.left + 275; // Approximate handle position
    const startY = rect.top + 250;
    const endX = rect.left + 350;
    const endY = rect.top + 320;

    // Mouse down
    canvas.dispatchEvent(new MouseEvent('mousedown', {
      bubbles: true,
      cancelable: true,
      clientX: startX,
      clientY: startY
    }));

    // Simulate drag with multiple move events
    const steps = 10;
    for (let i = 0; i <= steps; i++) {
      const progress = i / steps;
      const x = startX + (endX - startX) * progress;
      const y = startY + (endY - startY) * progress;

      canvas.dispatchEvent(new MouseEvent('mousemove', {
        bubbles: true,
        cancelable: true,
        clientX: x,
        clientY: y
      }));
    }

    // Mouse up
    canvas.dispatchEvent(new MouseEvent('mouseup', {
      bubbles: true,
      cancelable: true,
      clientX: endX,
      clientY: endY
    }));
  });

  await DELAY(500);
  console.log('  ✓ Object resized');
}

async function takeScreenshot(page, filename, label) {
  const filepath = path.join(SCREENSHOT_DIR, filename);
  await page.screenshot({ path: filepath, fullPage: false });
  console.log(`  📸 Screenshot saved: ${filepath} (${label})`);
  return filepath;
}

async function main() {
  console.log('\n🧪 Starting Remote Transform Visualization Test\n');
  console.log('=' .repeat(60));

  const browser = await setupBrowser();

  try {
    // Create two pages (simulating two users)
    const page1 = await browser.newPage();
    const page2 = await browser.newPage();

    // Set up console logging for both pages
    const logs1 = await captureConsoleLogs(page1, 'User A');
    const logs2 = await captureConsoleLogs(page2, 'User B');

    // Position windows side by side
    await page1.setViewport({ width: 700, height: 900 });
    await page2.setViewport({ width: 700, height: 900 });

    // User A logs in and navigates to canvas
    console.log('\n👤 Setting up User A (Editor)...');
    const canvasUrl = await loginAndNavigateToCanvas(page1, 'user-a@test.com');
    await DELAY(1000);

    // User B navigates to same canvas
    console.log('\n👤 Setting up User B (Viewer)...');
    await page2.goto(canvasUrl, { waitUntil: 'networkidle2' });
    await page2.waitForSelector('canvas', { timeout: 10000 });
    await DELAY(1000);

    // Take initial screenshots
    await takeScreenshot(page1, '1-user-a-initial.png', 'User A initial');
    await takeScreenshot(page2, '2-user-b-initial.png', 'User B initial');

    // User A creates an object
    await createTestObject(page1, 'rectangle');
    await DELAY(2000);

    await takeScreenshot(page1, '3-user-a-after-create.png', 'User A after creating object');
    await takeScreenshot(page2, '4-user-b-after-create.png', 'User B sees new object');

    // User A selects and resizes the object
    console.log('\n🔧 User A resizing object (User B should see glow, not selection box)...');
    await selectAndTransformObject(page1);

    // Capture during transform
    await DELAY(100); // Small delay to catch mid-transform
    await takeScreenshot(page1, '5-user-a-during-resize.png', 'User A during resize');
    await takeScreenshot(page2, '6-user-b-during-resize-BUG.png', 'User B during resize - SHOULD SEE GLOW');

    await DELAY(500); // Wait for transform to complete
    await takeScreenshot(page1, '7-user-a-after-resize.png', 'User A after resize');
    await takeScreenshot(page2, '8-user-b-after-resize.png', 'User B after resize');

    // Test rotation as well
    console.log('\n🔄 User A rotating object...');
    await page1.evaluate(() => {
      const canvas = document.querySelector('canvas');
      const rect = canvas.getBoundingClientRect();

      // Click rotation handle (top-right)
      const handleX = rect.left + 275;
      const handleY = rect.top + 150;

      canvas.dispatchEvent(new MouseEvent('mousedown', {
        bubbles: true,
        cancelable: true,
        clientX: handleX,
        clientY: handleY
      }));

      // Rotate by moving in a circle
      const steps = 10;
      const centerX = rect.left + 200;
      const centerY = rect.top + 200;
      const radius = 100;

      for (let i = 0; i <= steps; i++) {
        const angle = (i / steps) * Math.PI / 2; // 90 degree rotation
        const x = centerX + radius * Math.cos(angle);
        const y = centerY + radius * Math.sin(angle);

        canvas.dispatchEvent(new MouseEvent('mousemove', {
          bubbles: true,
          cancelable: true,
          clientX: x,
          clientY: y
        }));
      }

      canvas.dispatchEvent(new MouseEvent('mouseup', { bubbles: true }));
    });

    await DELAY(100);
    await takeScreenshot(page1, '9-user-a-during-rotate.png', 'User A during rotate');
    await takeScreenshot(page2, '10-user-b-during-rotate-BUG.png', 'User B during rotate - SHOULD SEE GLOW');

    await DELAY(500);
    await takeScreenshot(page1, '11-user-a-after-rotate.png', 'User A after rotate');
    await takeScreenshot(page2, '12-user-b-after-rotate.png', 'User B after rotate');

    console.log('\n' + '='.repeat(60));
    console.log('✅ Test complete!');
    console.log(`📁 Screenshots saved to: ${SCREENSHOT_DIR}`);
    console.log('\n🔍 Expected Bugs to See in Screenshots:');
    console.log('  - Screenshot 6 & 10: User B should see GLOW, but sees SELECTION BOX');
    console.log('  - Objects may appear see-through/transparent');
    console.log('  - Ghost frames/artifacts during transforms');

  } catch (error) {
    console.error('\n❌ Test failed:', error);
    throw error;
  } finally {
    console.log('\n⏸️  Keeping browser open for 10 seconds for manual inspection...');
    await DELAY(10000);

    await browser.close();
  }
}

// Run the test
if (require.main === module) {
  main().catch(error => {
    console.error('Fatal error:', error);
    process.exit(1);
  });
}

module.exports = { main };
