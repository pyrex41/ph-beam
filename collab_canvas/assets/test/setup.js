// Vitest setup file
import { beforeEach, vi } from 'vitest';

// Mock Phoenix LiveView socket methods
global.mockLiveViewHook = () => ({
  el: null,
  pushEvent: vi.fn(),
  pushEventTo: vi.fn(),
  handleEvent: vi.fn(),
  upload: vi.fn(),
  uploadTo: vi.fn()
});

// Mock Web Speech API
class MockSpeechRecognition {
  constructor() {
    this.continuous = false;
    this.interimResults = false;
    this.lang = 'en-US';
    this.onresult = null;
    this.onerror = null;
    this.onend = null;
    this.onstart = null;
  }

  start() {
    if (this.onstart) {
      this.onstart();
    }
  }

  stop() {
    if (this.onend) {
      this.onend();
    }
  }

  abort() {
    if (this.onend) {
      this.onend();
    }
  }
}

// Add to global for browser APIs
global.SpeechRecognition = MockSpeechRecognition;
global.webkitSpeechRecognition = MockSpeechRecognition;

beforeEach(() => {
  // Clear all mocks before each test
  vi.clearAllMocks();
});
