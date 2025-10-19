/**
 * Script to fix :has-text() selectors in test files
 */

const fs = require('fs');
const path = require('path');

const testDir = './test';
const testFiles = [
  'color-palette.test.js',
  'grouping.test.js',
  'integration.test.js',
  'workflow.test.js'
];

// Helper to replace await page.$('button:has-text("Text")') with findButtonByText
function fixFile(filePath) {
  let content = fs.readFileSync(filePath, 'utf8');
  let modified = false;

  // Fix: await page.$('button:has-text("Text")') → await findButtonByText(page, 'Text')
  content = content.replace(
    /await page\.\$\('button:has-text\("([^"]+)"\)(?:, button\[([^\]]+)\])?\'/g,
    (match, text) => {
      modified = true;
      return `await findButtonByText(page, '${text}')`;
    }
  );

  // Fix: await page.click('button:has-text("Text")') → await clickButtonByText(page, 'Text')
  content = content.replace(
    /await page\.click\('button(?:\[aria-label\*="[^"]+"\], )?:has-text\("([^"]+)"\)'/g,
    (match, text) => {
      modified = true;
      return `await clickButtonByText(page, '${text}')`;
    }
  );

  // Fix: await page.waitForSelector('button:has-text("Text")') → await findButtonByText(page, 'Text')
  content = content.replace(
    /await page\.waitForSelector\('button(?:\[aria-label\*="[^"]+"\], )?:has-text\("([^"]+)"\)'/g,
    (match, text) => {
      modified = true;
      return `await findButtonByText(page, '${text}')`;
    }
  );

  // Add import if modified
  if (modified) {
    if (!content.includes('findButtonByText')) {
      content = content.replace(
        /(const \{[^}]+)\} = require\('\.\/helpers'\);/,
        (match, imports) => {
          return imports + ',\n  findButtonByText,\n  clickButtonByText\n} = require(\'./helpers\');';
        }
      );
    }
  }

  if (modified) {
    fs.writeFileSync(filePath, content);
    console.log(`✓ Fixed ${path.basename(filePath)}`);
  } else {
    console.log(`- No changes needed in ${path.basename(filePath)}`);
  }
}

testFiles.forEach(file => {
  const filePath = path.join(testDir, file);
  if (fs.existsSync(filePath)) {
    fixFile(filePath);
  }
});

console.log('\nDone!');
