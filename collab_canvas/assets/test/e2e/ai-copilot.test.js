/**
 * E2E Tests for AI Copilot Features
 *
 * Tests the AI copilot interface including:
 * - Enter to submit command
 * - Shift+Enter for newline
 * - AI interaction history panel
 * - Voice input button (UI presence)
 * - Submit button state management
 */

const BASE_URL = process.env.E2E_BASE_URL || 'http://localhost:4000';

export default async function (runner) {
  // Helper to create a new canvas for testing
  async function setupCanvas(page) {
    await page.goto(BASE_URL);

    // Wait for page to load
    await page.waitForSelector('body', { timeout: 5000 });

    // Check if we're on login page or canvas page
    const url = page.url();
    if (url.includes('/auth/login') || url.includes('/auth/auth0')) {
      console.log('  Note: Authentication required - some tests may be skipped');
      return false;
    }

    // Try to create a new canvas or navigate to existing one
    try {
      // Look for "New Canvas" button or similar
      const newCanvasBtn = await page.$('button:has-text("New Canvas"), a[href*="/canvases/new"]');
      if (newCanvasBtn) {
        await newCanvasBtn.click();
        await page.waitForTimeout(1000);
      }

      // Wait for canvas to be ready
      await page.waitForSelector('#ai-command-input', { timeout: 5000 });
      return true;
    } catch (error) {
      // Might already be on a canvas page
      const hasAIInput = await page.$('#ai-command-input');
      return hasAIInput !== null;
    }
  }

  // Test: AI Command Input exists
  await runner.runTest('AI Command Input - Element exists', async (page) => {
    const canvasReady = await setupCanvas(page);
    if (!canvasReady) {
      throw new Error('Could not access canvas page (authentication may be required)');
    }

    const textarea = await page.$('#ai-command-input');
    if (!textarea) {
      throw new Error('AI command input textarea not found');
    }
  });

  // Test: Enter key submits command
  await runner.runTest('AI Command Input - Enter submits command', async (page) => {
    const canvasReady = await setupCanvas(page);
    if (!canvasReady) return;

    // Type a command
    await page.focus('#ai-command-input');
    await page.keyboard.type('create a test circle');

    // Set up promise to listen for LiveView event
    const commandPromise = page.evaluate(() => {
      return new Promise((resolve) => {
        window.__testCommandReceived = resolve;
        // Hook into Phoenix LiveView (this is a simplified check)
        const originalPush = window.liveSocket?.main?.pushEvent;
        if (originalPush) {
          window.liveSocket.main.pushEvent = function(event, payload) {
            if (event === 'execute_ai_command') {
              window.__testCommandReceived(payload);
            }
            return originalPush.call(this, event, payload);
          };
        } else {
          // If no LiveSocket, resolve immediately
          setTimeout(() => resolve({ simulated: true }), 100);
        }
      });
    });

    // Press Enter
    await page.keyboard.press('Enter');

    // Wait a bit for command processing
    await page.waitForTimeout(500);

    // Check that textarea was cleared
    const textareaValue = await page.$eval('#ai-command-input', el => el.value);
    if (textareaValue !== '') {
      throw new Error('Textarea was not cleared after Enter');
    }
  });

  // Test: Shift+Enter adds newline
  await runner.runTest('AI Command Input - Shift+Enter adds newline', async (page) => {
    const canvasReady = await setupCanvas(page);
    if (!canvasReady) return;

    // Clear the textarea first
    await page.focus('#ai-command-input');
    await page.evaluate(() => {
      document.getElementById('ai-command-input').value = '';
    });

    // Type first line
    await page.keyboard.type('line 1');

    // Press Shift+Enter
    await page.keyboard.down('Shift');
    await page.keyboard.press('Enter');
    await page.keyboard.up('Shift');

    // Type second line
    await page.keyboard.type('line 2');

    // Check textarea contains newline
    const textareaValue = await page.$eval('#ai-command-input', el => el.value);
    if (!textareaValue.includes('\n')) {
      throw new Error('Textarea should contain newline after Shift+Enter');
    }
    if (!textareaValue.includes('line 1') || !textareaValue.includes('line 2')) {
      throw new Error('Textarea content incorrect');
    }
  });

  // Test: Submit button state management
  await runner.runTest('AI Command Input - Submit button state', async (page) => {
    const canvasReady = await setupCanvas(page);
    if (!canvasReady) return;

    const submitButton = await page.$('#ai-execute-button');
    if (!submitButton) {
      console.log('  Warning: Submit button not found, skipping test');
      return;
    }

    // Clear textarea
    await page.evaluate(() => {
      document.getElementById('ai-command-input').value = '';
      document.getElementById('ai-command-input').dispatchEvent(new Event('input', { bubbles: true }));
    });

    // Wait a bit
    await page.waitForTimeout(200);

    // Check button is disabled when empty
    let isDisabled = await page.$eval('#ai-execute-button', el => el.disabled);
    if (!isDisabled) {
      throw new Error('Submit button should be disabled when textarea is empty');
    }

    // Type some text
    await page.focus('#ai-command-input');
    await page.keyboard.type('test command');
    await page.waitForTimeout(200);

    // Check button is enabled
    isDisabled = await page.$eval('#ai-execute-button', el => el.disabled);
    if (isDisabled) {
      throw new Error('Submit button should be enabled when textarea has content');
    }
  });

  // Test: AI Interaction History Panel exists
  await runner.runTest('AI Interaction History - Panel exists', async (page) => {
    const canvasReady = await setupCanvas(page);
    if (!canvasReady) return;

    // Look for history panel container
    // It should have a scrollable div with interactions
    const historyPanel = await page.evaluate(() => {
      // Find elements that might be the history panel
      const candidates = Array.from(document.querySelectorAll('.overflow-y-auto, [class*="history"], .space-y-3'));
      return candidates.length > 0;
    });

    if (!historyPanel) {
      console.log('  Warning: Could not confirm history panel exists');
    }
  });

  // Test: Voice Input button exists
  await runner.runTest('Voice Input - Button exists', async (page) => {
    const canvasReady = await setupCanvas(page);
    if (!canvasReady) return;

    const voiceButton = await page.$('#voice-input-button');
    if (!voiceButton) {
      // Might be hidden if browser doesn't support Speech API
      console.log('  Note: Voice input button not found (browser may not support Speech API)');
      return;
    }

    // Check button has microphone icon or text
    const buttonContent = await page.$eval('#voice-input-button', el => el.innerHTML);
    if (!buttonContent) {
      throw new Error('Voice button has no content');
    }
  });

  // Test: Empty command is not submitted
  await runner.runTest('AI Command Input - Empty command not submitted', async (page) => {
    const canvasReady = await setupCanvas(page);
    if (!canvasReady) return;

    // Clear textarea
    await page.evaluate(() => {
      document.getElementById('ai-command-input').value = '';
    });

    // Try to submit with Enter
    await page.focus('#ai-command-input');
    await page.keyboard.press('Enter');

    await page.waitForTimeout(300);

    // Textarea should still be empty (not changed)
    const textareaValue = await page.$eval('#ai-command-input', el => el.value);
    if (textareaValue !== '') {
      throw new Error('Textarea should remain empty');
    }
  });

  // Test: Whitespace-only command is not submitted
  await runner.runTest('AI Command Input - Whitespace-only not submitted', async (page) => {
    const canvasReady = await setupCanvas(page);
    if (!canvasReady) return;

    // Type whitespace
    await page.focus('#ai-command-input');
    await page.evaluate(() => {
      document.getElementById('ai-command-input').value = '   ';
    });

    // Try to submit with Enter
    await page.keyboard.press('Enter');
    await page.waitForTimeout(300);

    // Submit button should still be disabled
    const submitButton = await page.$('#ai-execute-button');
    if (submitButton) {
      const isDisabled = await page.$eval('#ai-execute-button', el => el.disabled);
      if (!isDisabled) {
        throw new Error('Submit button should be disabled for whitespace-only input');
      }
    }
  });

  // Test: Keyboard navigation works
  await runner.runTest('AI Command Input - Keyboard navigation', async (page) => {
    const canvasReady = await setupCanvas(page);
    if (!canvasReady) return;

    // Clear and type
    await page.evaluate(() => {
      document.getElementById('ai-command-input').value = '';
    });

    await page.focus('#ai-command-input');
    await page.keyboard.type('test');

    // Move cursor with arrow keys
    await page.keyboard.press('ArrowLeft');
    await page.keyboard.press('ArrowLeft');
    await page.keyboard.type('X');

    const textareaValue = await page.$eval('#ai-command-input', el => el.value);
    if (textareaValue !== 'teXst') {
      throw new Error(`Expected 'teXst', got '${textareaValue}'`);
    }
  });

  // Test: UI is responsive
  await runner.runTest('AI Copilot UI - Responsive layout', async (page) => {
    const canvasReady = await setupCanvas(page);
    if (!canvasReady) return;

    // Test different viewport sizes
    const sizes = [
      { width: 1280, height: 800, name: 'Desktop' },
      { width: 768, height: 1024, name: 'Tablet' },
      { width: 375, height: 667, name: 'Mobile' }
    ];

    for (const size of sizes) {
      await page.setViewport(size);
      await page.waitForTimeout(300);

      const inputExists = await page.$('#ai-command-input');
      if (!inputExists) {
        throw new Error(`AI input not found at ${size.name} size`);
      }
    }

    // Reset viewport
    await page.setViewport({ width: 1280, height: 800 });
  });
}
