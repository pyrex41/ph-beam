# CollabCanvas E2E Tests

End-to-end tests for CollabCanvas workflow features using Puppeteer.

## Features Tested

- **WF-01: Object Grouping** - Group/ungroup objects, move groups together
- **WF-02: Lasso Selection** - Select multiple objects with lasso tool
- **WF-03: Layer Management** - Z-index manipulation (bring to front, send to back, etc.)
- **WF-04: Export** - Export canvas and objects as JSON
- **WF-05: Color Palettes** - Create, edit, delete palettes and manage colors

## Prerequisites

- Node.js 18+ (for native test runner)
- Phoenix server running on port 4001
- Test user already authenticated (or auth disabled for tests)

## Setup

Install dependencies:

```bash
cd e2e
npm install
```

## Running Tests

Make sure the Phoenix server is running on port 4001:

```bash
# In the main project directory
PORT=4001 mix phx.server
```

Then run the tests:

```bash
# Run all tests
npm test

# Run specific test suites
npm run test:palette
npm run test:grouping
npm run test:workflow

# Run with visible browser (for debugging)
HEADLESS=false npm test

# Run against different URL
BASE_URL=http://localhost:4000 npm test
```

## Test Structure

```
e2e/
├── package.json           # Dependencies and scripts
├── test/
│   ├── helpers.js        # Shared test utilities
│   ├── color-palette.test.js   # WF-05 tests
│   ├── grouping.test.js        # WF-01, WF-02 tests
│   └── workflow.test.js        # WF-03, WF-04 tests
└── README.md
```

## Writing Tests

Tests use Node.js native test runner and Puppeteer. Example:

```javascript
const { test, describe, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert');
const { setupBrowser, createCanvas } = require('./helpers');

describe('My Feature', () => {
  let browser, page;

  beforeEach(async () => {
    ({ browser, page } = await setupBrowser());
  });

  afterEach(async () => {
    if (browser) {
      await browser.close();
    }
  });

  test('should do something', async () => {
    await createCanvas(page, 'Test Canvas');
    // ... test logic
    assert.ok(true);
  });
});
```

## Environment Variables

- `BASE_URL` - Server URL (default: `http://localhost:4001`)
- `HEADLESS` - Run browser headless (default: `true`, set to `false` to see browser)

## Troubleshooting

**Tests fail to connect:**
- Ensure Phoenix server is running on the correct port
- Check that the application is accessible at the BASE_URL

**Tests timeout:**
- Increase timeout in individual tests
- Check for JavaScript errors in browser console (visible when `HEADLESS=false`)

**Authentication issues:**
- Tests assume user is already authenticated
- Configure test user in application or disable auth for test environment

**Selector not found:**
- Run with `HEADLESS=false` to inspect the page
- Check if the UI structure has changed
- Update selectors in test files or helpers

## CI/CD Integration

For CI/CD pipelines:

```bash
# Install dependencies
cd e2e && npm ci

# Run in headless mode (default)
npm test

# Or with explicit headless flag
HEADLESS=true npm test
```

Example GitHub Actions workflow:

```yaml
- name: Run E2E Tests
  run: |
    PORT=4001 mix phx.server &
    sleep 5
    cd e2e
    npm ci
    npm test
```

## Test Coverage

Current test coverage:

- ✅ Color Palette creation, editing, deletion
- ✅ Color addition/removal from palettes
- ✅ Palette persistence
- ✅ Lasso selection
- ✅ Object grouping/ungrouping
- ✅ Group movement
- ✅ Layer ordering (z-index)
- ✅ Export functionality
- ✅ Object property preservation

## Adding New Tests

1. Create a new test file in `test/` directory
2. Import helpers: `const { setupBrowser, ... } = require('./helpers')`
3. Use `describe` and `test` blocks
4. Add browser cleanup in `afterEach`
5. Add new script to `package.json` if needed
