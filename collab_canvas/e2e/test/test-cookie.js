/**
 * Test if session cookie is working
 */

const puppeteer = require('puppeteer');

async function testCookie() {
  const browser = await puppeteer.launch({
    headless: false,
    args: ['--no-sandbox', '--disable-setuid-sandbox']
  });

  const page = await browser.newPage();

  // Set cookie
  await page.setCookie({
    name: '_collab_canvas_key',
    value: '6194f93a79dbf1b608d4576b13525c5dfec6251004e199d4f3df2ad78432577d',
    domain: 'localhost',
    path: '/'
  });

  console.log('Cookie set, navigating to dashboard...');

  // Navigate to dashboard
  await page.goto('http://localhost:4001/dashboard', { waitUntil: 'networkidle0' });

  // Wait a bit
  await new Promise(resolve => setTimeout(resolve, 2000));

  // Check where we are
  const url = page.url();
  const title = await page.title();
  const bodyText = await page.evaluate(() => document.body.textContent);

  console.log('\n=== TEST RESULTS ===');
  console.log('URL:', url);
  console.log('Title:', title);
  console.log('Body contains "logged in":', bodyText.includes('logged in'));
  console.log('Body contains "dashboard":', bodyText.toLowerCase().includes('dashboard'));
  console.log('Body contains "New Canvas":', bodyText.includes('New Canvas'));

  // Check cookies
  const cookies = await page.cookies();
  console.log('\nCookies after navigation:');
  cookies.forEach(cookie => {
    console.log(`  ${cookie.name}: ${cookie.value.substring(0, 20)}...`);
  });

  // Check LiveView
  const liveViewStatus = await page.evaluate(() => {
    return {
      hasLiveSocket: typeof window.liveSocket !== 'undefined',
      isConnected: window.liveSocket && window.liveSocket.isConnected ? window.liveSocket.isConnected() : false,
      hasPhoenix: typeof window.Phoenix !== 'undefined'
    };
  });

  console.log('\nLiveView status:', liveViewStatus);

  console.log('\n=== END ===');

  await new Promise(resolve => setTimeout(resolve, 5000));
  await browser.close();
}

testCookie().catch(console.error);
