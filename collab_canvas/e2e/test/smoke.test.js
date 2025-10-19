/**
 * Smoke tests - Basic functionality verification
 */

const { test, describe, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert');
const {
  setupBrowser,
  BASE_URL,
  waitForLiveView
} = require('./helpers');

describe('Smoke Tests', () => {
  let browser, page;

  beforeEach(async () => {
    ({ browser, page } = await setupBrowser());
  });

  afterEach(async () => {
    if (browser) {
      await browser.close();
    }
  });

  test('should load dashboard page', async () => {
    await page.goto(`${BASE_URL}/dashboard`, { waitUntil: 'networkidle0' });
    await waitForLiveView(page);

    const title = await page.title();
    assert.ok(title.includes('CollabCanvas') || title.length > 0,
      'Page should have a title');

    const hasContent = await page.evaluate(() => document.body.textContent.length > 0);
    assert.ok(hasContent, 'Page should have content');

    console.log('✅ Dashboard loads successfully');
  });

  test('should have LiveView connected', async () => {
    await page.goto(`${BASE_URL}/dashboard`, { waitUntil: 'networkidle0' });
    await waitForLiveView(page);

    const isConnected = await page.evaluate(() => {
      return window.liveSocket && window.liveSocket.isConnected();
    });

    assert.ok(isConnected, 'LiveView should be connected');
    console.log('✅ LiveView is connected');
  });

  test('should be able to navigate to create canvas', async () => {
    await page.goto(`${BASE_URL}/dashboard`, { waitUntil: 'networkidle0' });
    await waitForLiveView(page);

    // Look for "New Canvas" or similar button
    const hasNewButton = await page.evaluate(() => {
      const buttons = Array.from(document.querySelectorAll('button'));
      return buttons.some(btn =>
        btn.textContent.includes('New') ||
        btn.textContent.includes('Create')
      );
    });

    assert.ok(hasNewButton, 'Should have button to create new canvas');
    console.log('✅ Can navigate to create canvas');
  });

  test('should load JavaScript assets', async () => {
    await page.goto(`${BASE_URL}/dashboard`, { waitUntil: 'networkidle0' });

    // Check if app.js loaded
    const hasAppJs = await page.evaluate(() => {
      return document.querySelector('script[src*="app.js"]') !== null;
    });

    assert.ok(hasAppJs, 'Should load app.js');

    // Check if Phoenix LiveView is available
    const hasLiveView = await page.evaluate(() => {
      return typeof window.liveSocket !== 'undefined';
    });

    assert.ok(hasLiveView, 'Phoenix LiveView should be loaded');
    console.log('✅ JavaScript assets loaded');
  });

  test('should load CSS assets', async () => {
    await page.goto(`${BASE_URL}/dashboard`, { waitUntil: 'networkidle0' });

    // Check if app.css loaded
    const hasCss = await page.evaluate(() => {
      return document.querySelector('link[href*="app.css"]') !== null;
    });

    assert.ok(hasCss, 'Should load app.css');
    console.log('✅ CSS assets loaded');
  });
});
