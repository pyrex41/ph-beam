/**
 * Debug test to see what's on the page
 */

const puppeteer = require('puppeteer');

async function debug() {
  const browser = await puppeteer.launch({
    headless: false, // Show browser
    args: ['--no-sandbox']
  });

  const page = await browser.newPage();
  await page.setViewport({ width: 1280, height: 800 });

  console.log('Navigating to dashboard...');
  await page.goto('http://localhost:4001/dashboard', {
    waitUntil: 'networkidle0'
  });

  // Wait a bit
  await new Promise(resolve => setTimeout(resolve, 2000));

  // Check current URL (might redirect)
  const url = page.url();
  console.log('Current URL:', url);

  // Check page content
  const bodyText = await page.evaluate(() => {
    return {
      title: document.title,
      bodyText: document.body.textContent.substring(0, 200),
      hasPhoenix: typeof window.Phoenix !== 'undefined',
      hasLiveView: typeof window.Phoenix?.LiveView !== 'undefined',
      hasLiveSocket: typeof window.liveSocket !== 'undefined',
      scriptTags: Array.from(document.querySelectorAll('script')).map(s => s.src),
      h1Text: document.querySelector('h1')?.textContent || 'no h1'
    };
  });

  console.log('Page info:', JSON.stringify(bodyText, null, 2));

  // Keep browser open for inspection
  console.log('\nBrowser will stay open for 30 seconds for inspection...');
  await new Promise(resolve => setTimeout(resolve, 30000));

  await browser.close();
}

debug().catch(console.error);
