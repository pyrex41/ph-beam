/**
 * E2E Test Runner for AI Copilot Features
 *
 * This runner executes Puppeteer-based end-to-end tests
 * for the AI copilot functionality.
 *
 * Usage: npm run test:e2e
 */

import puppeteer from 'puppeteer';
import { readFileSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Configuration
const BASE_URL = process.env.E2E_BASE_URL || 'http://localhost:4000';
const HEADLESS = process.env.E2E_HEADLESS !== 'false';
const SLOWMO = parseInt(process.env.E2E_SLOWMO || '0');

// ANSI color codes for terminal output
const colors = {
  reset: '\x1b[0m',
  green: '\x1b[32m',
  red: '\x1b[31m',
  yellow: '\x1b[33m',
  blue: '\x1b[34m',
  gray: '\x1b[90m'
};

// Test results tracking
let totalTests = 0;
let passedTests = 0;
let failedTests = 0;
const failures = [];

// Helper functions
function log(message, color = colors.reset) {
  console.log(`${color}${message}${colors.reset}`);
}

function logSuccess(message) {
  log(`✓ ${message}`, colors.green);
}

function logError(message) {
  log(`✗ ${message}`, colors.red);
}

function logInfo(message) {
  log(`ℹ ${message}`, colors.blue);
}

function logWarning(message) {
  log(`⚠ ${message}`, colors.yellow);
}

// Test runner class
class E2ETestRunner {
  constructor() {
    this.browser = null;
    this.page = null;
  }

  async setup() {
    logInfo('Starting Puppeteer...');
    this.browser = await puppeteer.launch({
      headless: HEADLESS,
      slowMo: SLOWMO,
      args: ['--no-sandbox', '--disable-setuid-sandbox']
    });

    this.page = await this.browser.newPage();
    await this.page.setViewport({ width: 1280, height: 800 });

    // Enable console logging from page
    this.page.on('console', msg => {
      if (msg.type() === 'error') {
        log(`  Browser Error: ${msg.text()}`, colors.gray);
      }
    });

    logSuccess('Puppeteer initialized');
  }

  async teardown() {
    if (this.browser) {
      await this.browser.close();
      logInfo('Browser closed');
    }
  }

  async runTest(name, testFn) {
    totalTests++;
    try {
      log(`\nRunning: ${name}`, colors.blue);
      await testFn(this.page);
      passedTests++;
      logSuccess(`Passed: ${name}`);
      return true;
    } catch (error) {
      failedTests++;
      logError(`Failed: ${name}`);
      log(`  Error: ${error.message}`, colors.red);
      failures.push({ name, error: error.message });
      return false;
    }
  }

  async waitForServer() {
    logInfo(`Waiting for server at ${BASE_URL}...`);
    const maxAttempts = 30;
    for (let i = 0; i < maxAttempts; i++) {
      try {
        const response = await fetch(BASE_URL);
        if (response.ok || response.status === 302) {
          logSuccess('Server is ready');
          return true;
        }
      } catch (error) {
        // Server not ready yet
      }
      await new Promise(resolve => setTimeout(resolve, 1000));
    }
    throw new Error(`Server not responding after ${maxAttempts} seconds`);
  }
}

// Test suite
async function runTests() {
  const runner = new E2ETestRunner();

  try {
    await runner.waitForServer();
    await runner.setup();

    // Import and run test files
    const aiCopilotTests = await import('./ai-copilot.test.js');
    await aiCopilotTests.default(runner);

    // Print summary
    log('\n' + '='.repeat(60), colors.gray);
    log('Test Summary:', colors.blue);
    log(`Total:  ${totalTests}`, colors.blue);
    log(`Passed: ${passedTests}`, colors.green);
    log(`Failed: ${failedTests}`, failedTests > 0 ? colors.red : colors.green);
    log('='.repeat(60), colors.gray);

    if (failures.length > 0) {
      log('\nFailed Tests:', colors.red);
      failures.forEach(({ name, error }) => {
        log(`  ✗ ${name}`, colors.red);
        log(`    ${error}`, colors.gray);
      });
    }

    await runner.teardown();

    // Exit with appropriate code
    process.exit(failedTests > 0 ? 1 : 0);
  } catch (error) {
    logError(`Test runner error: ${error.message}`);
    await runner.teardown();
    process.exit(1);
  }
}

// Run tests
runTests();
