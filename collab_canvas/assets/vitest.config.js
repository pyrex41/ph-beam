import { defineConfig } from 'vitest/config';
import path from 'path';

export default defineConfig({
  test: {
    globals: true,
    environment: 'happy-dom',
    setupFiles: ['./test/setup.js'],
    exclude: [
      '**/node_modules/**',
      '**/dist/**',
      '**/test/e2e/**'  // Exclude E2E tests (run separately with Puppeteer)
    ],
    coverage: {
      reporter: ['text', 'json', 'html'],
      exclude: ['node_modules/', 'test/e2e/']
    }
  },
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './js')
    }
  }
});
