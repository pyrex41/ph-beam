/**
 * Verify authentication works with the new cookie
 */

const puppeteer = require('puppeteer');

async function verifyAuth() {
  const browser = await puppeteer.launch({
    headless: true,
    args: ['--no-sandbox', '--disable-setuid-sandbox']
  });

  const page = await browser.newPage();

  // Set the correct Phoenix session cookie
  await page.setCookie({
    name: '_collab_canvas_key',
    value: 'SFMyNTY.g3QAAAAEbQAAAAtfY3NyZl90b2tlbm0AAAAYYUdrYUpDZE84NVU1QUJ3WTBqelhjVFRUbQAAAAp1c2VyX2VtYWlsbQAAABVyZXViLmJyb29rc0BnbWFpbC5jb21tAAAAB3VzZXJfaWRhAW0AAAAJdXNlcl9uYW1lbQAAABVyZXViLmJyb29rc0BnbWFpbC5jb20.3WYffWGqfxMLUxLm_W5QBwGTBfBIgHF5yze7tOUv1Fk',
    domain: 'localhost',
    path: '/'
  });

  console.log('Navigating to dashboard...');
  await page.goto('http://localhost:4001/dashboard', { waitUntil: 'networkidle0' });
  await new Promise(resolve => setTimeout(resolve, 2000));

  const url = page.url();
  const bodyText = await page.evaluate(() => document.body.textContent);

  console.log('\n=== VERIFICATION RESULTS ===');
  console.log('✓ Current URL:', url);
  console.log('✓ On /dashboard page:', url.includes('/dashboard'));
  console.log('✓ Has "New Canvas" button:', bodyText.includes('New Canvas'));
  console.log('✓ No auth error:', !bodyText.includes('You must be logged in'));

  const liveViewStatus = await page.evaluate(() => {
    return {
      hasLiveSocket: typeof window.liveSocket !== 'undefined',
      isConnected: window.liveSocket && window.liveSocket.isConnected ? window.liveSocket.isConnected() : false
    };
  });

  console.log('✓ LiveView connected:', liveViewStatus.isConnected);

  if (url.includes('/dashboard') && !bodyText.includes('You must be logged in')) {
    console.log('\n✅ AUTHENTICATION SUCCESSFUL! Tests should now work.');
  } else {
    console.log('\n❌ AUTHENTICATION FAILED. Cookie may be expired.');
  }

  await browser.close();
}

verifyAuth().catch(console.error);
