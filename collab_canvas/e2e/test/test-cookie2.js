/**
 * Test cookie with different approach
 */

const puppeteer = require('puppeteer');

async function testCookie() {
  const browser = await puppeteer.launch({
    headless: false,
    args: ['--no-sandbox', '--disable-setuid-sandbox']
  });

  const page = await browser.newPage();

  console.log('Step 1: Visit home page first...');
  await page.goto('http://localhost:4001/', { waitUntil: 'networkidle0' });
  await new Promise(resolve => setTimeout(resolve, 1000));

  console.log('Step 2: Set cookie...');
  // Try setting with the exact value format Phoenix uses
  await page.setCookie({
    name: '_collab_canvas_key',
    value: '6194f93a79dbf1b608d4576b13525c5dfec6251004e199d4f3df2ad78432577d',
    domain: 'localhost',
    path: '/',
    httpOnly: true,
    secure: false
  });

  console.log('Step 3: Navigate to dashboard...');
  await page.goto('http://localhost:4001/dashboard', { waitUntil: 'networkidle0' });
  await new Promise(resolve => setTimeout(resolve, 2000));

  // Check where we are
  const url = page.url();
  const bodyText = await page.evaluate(() => document.body.textContent);

  console.log('\n=== RESULTS ===');
  console.log('URL:', url);
  console.log('On dashboard:', url.includes('/dashboard'));
  console.log('Has "New Canvas":', bodyText.includes('New Canvas'));
  console.log('Has error message:', bodyText.includes('You must be logged in'));

  // Get actual cookies
  const cookies = await page.cookies();
  const sessionCookie = cookies.find(c => c.name === '_collab_canvas_key');
  console.log('\nSession cookie value:', sessionCookie ? sessionCookie.value : 'NOT FOUND');

  await new Promise(resolve => setTimeout(resolve, 3000));
  await browser.close();
}

testCookie().catch(console.error);
