/**
 * Tests for Voice Input Hook
 *
 * Tests push-to-talk voice recognition functionality including:
 * - Browser support detection
 * - Speech recognition lifecycle
 * - Event handlers
 * - UI state management
 * - Transcription updates
 */

import { describe, it, expect, beforeEach, vi } from 'vitest';
import VoiceInputHook from '../js/hooks/voice_input.js';

describe('VoiceInput Hook', () => {
  let hook;
  let mockElement;
  let mockInputField;
  let mockMicIcon;
  let mockListeningIndicator;

  beforeEach(() => {
    // Create mock DOM elements
    mockInputField = document.createElement('textarea');
    mockInputField.id = 'ai-command-input';
    document.body.appendChild(mockInputField);

    mockMicIcon = document.createElement('div');
    mockMicIcon.className = 'mic-icon';

    mockListeningIndicator = document.createElement('div');
    mockListeningIndicator.className = 'listening-indicator';
    mockListeningIndicator.style.display = 'none';

    mockElement = document.createElement('button');
    mockElement.appendChild(mockMicIcon);
    mockElement.appendChild(mockListeningIndicator);
    mockElement.classList.add('bg-blue-500', 'hover:bg-blue-600');
    document.body.appendChild(mockElement);

    // Create hook instance with mock context
    hook = Object.create(VoiceInputHook);
    hook.el = mockElement;
    hook.pushEvent = vi.fn();
  });

  afterEach(() => {
    // Clean up DOM
    document.body.innerHTML = '';
    vi.clearAllMocks();
  });

  describe('Initialization', () => {
    it('should initialize speech recognition when supported', () => {
      hook.mounted();

      expect(hook.recognition).toBeDefined();
      expect(hook.recognition.continuous).toBe(false);
      expect(hook.recognition.interimResults).toBe(true);
      expect(hook.recognition.lang).toBe('en-US');
      expect(hook.isListening).toBe(false);
      expect(hook.finalTranscript).toBe('');
    });

    it('should hide element when speech recognition is not supported', () => {
      // Temporarily remove Speech Recognition
      const originalSpeechRecognition = global.SpeechRecognition;
      const originalWebkitSpeechRecognition = global.webkitSpeechRecognition;
      delete global.SpeechRecognition;
      delete global.webkitSpeechRecognition;

      hook.mounted();

      expect(hook.el.style.display).toBe('none');

      // Restore
      global.SpeechRecognition = originalSpeechRecognition;
      global.webkitSpeechRecognition = originalWebkitSpeechRecognition;
    });

    it('should set up event handlers correctly', () => {
      hook.mounted();

      expect(hook.recognition.onresult).toBeTypeOf('function');
      expect(hook.recognition.onerror).toBeTypeOf('function');
      expect(hook.recognition.onend).toBeTypeOf('function');
      expect(hook.recognition.onstart).toBeTypeOf('function');
    });
  });

  describe('Voice Recognition Lifecycle', () => {
    beforeEach(() => {
      hook.mounted();
    });

    it('should start listening on mousedown', () => {
      const startSpy = vi.spyOn(hook.recognition, 'start');

      const mousedownEvent = new MouseEvent('mousedown');
      mockElement.dispatchEvent(mousedownEvent);

      expect(startSpy).toHaveBeenCalled();
    });

    it('should stop listening on mouseup', () => {
      const stopSpy = vi.spyOn(hook.recognition, 'stop');

      // Start first
      hook.isListening = true;

      const mouseupEvent = new MouseEvent('mouseup');
      mockElement.dispatchEvent(mouseupEvent);

      expect(stopSpy).toHaveBeenCalled();
    });

    it('should stop listening on mouseleave', () => {
      const stopSpy = vi.spyOn(hook.recognition, 'stop');

      // Start first
      hook.isListening = true;

      const mouseleaveEvent = new MouseEvent('mouseleave');
      mockElement.dispatchEvent(mouseleaveEvent);

      expect(stopSpy).toHaveBeenCalled();
    });

    it('should handle touch events for mobile', () => {
      const startSpy = vi.spyOn(hook, 'startListening');
      const stopSpy = vi.spyOn(hook, 'stopListening');

      const touchstartEvent = new TouchEvent('touchstart', {
        bubbles: true,
        cancelable: true
      });
      mockElement.dispatchEvent(touchstartEvent);
      expect(startSpy).toHaveBeenCalled();

      const touchendEvent = new TouchEvent('touchend', {
        bubbles: true,
        cancelable: true
      });
      mockElement.dispatchEvent(touchendEvent);
      expect(stopSpy).toHaveBeenCalled();
    });

    it('should not start if already listening', () => {
      hook.isListening = true;
      const startSpy = vi.spyOn(hook.recognition, 'start');

      hook.startListening();

      expect(startSpy).not.toHaveBeenCalled();
    });

    it('should not stop if not listening', () => {
      hook.isListening = false;
      const stopSpy = vi.spyOn(hook.recognition, 'stop');

      hook.stopListening();

      expect(stopSpy).not.toHaveBeenCalled();
    });
  });

  describe('Transcription Handling', () => {
    beforeEach(() => {
      hook.mounted();
    });

    it('should update input field with final transcript', () => {
      const mockEvent = {
        resultIndex: 0,
        results: [
          {
            0: { transcript: 'create a circle' },
            isFinal: true
          }
        ]
      };

      hook.recognition.onresult(mockEvent);

      expect(mockInputField.value).toBe('create a circle');
      expect(hook.pushEvent).toHaveBeenCalledWith('update_ai_command', {
        command: 'create a circle'
      });
    });

    it('should update input field with interim transcript', () => {
      const mockEvent = {
        resultIndex: 0,
        results: [
          {
            0: { transcript: 'create a' },
            isFinal: false
          }
        ]
      };

      hook.recognition.onresult(mockEvent);

      expect(mockInputField.value).toBe('create a');
    });

    it('should combine final and interim transcripts', () => {
      // First final result
      const finalEvent = {
        resultIndex: 0,
        results: [
          {
            0: { transcript: 'create a' },
            isFinal: true
          }
        ]
      };

      hook.recognition.onresult(finalEvent);

      // Then interim result
      const interimEvent = {
        resultIndex: 1,
        results: [
          {
            0: { transcript: 'create a' },
            isFinal: true
          },
          {
            0: { transcript: 'circle' },
            isFinal: false
          }
        ]
      };

      hook.recognition.onresult(interimEvent);

      // Note: The hook adds a space after final transcripts, so we expect 'create a ' + 'circle'
      expect(mockInputField.value).toBe('create a circle');
    });

    it('should dispatch input event when updating field', () => {
      const inputEventSpy = vi.fn();
      mockInputField.addEventListener('input', inputEventSpy);

      const mockEvent = {
        resultIndex: 0,
        results: [
          {
            0: { transcript: 'test' },
            isFinal: true
          }
        ]
      };

      hook.recognition.onresult(mockEvent);

      expect(inputEventSpy).toHaveBeenCalled();
    });
  });

  describe('Error Handling', () => {
    beforeEach(() => {
      hook.mounted();
      // Mock alert
      global.alert = vi.fn();
    });

    afterEach(() => {
      delete global.alert;
    });

    it('should handle microphone permission denial', () => {
      const consoleSpy = vi.spyOn(console, 'error');

      hook.recognition.onerror({ error: 'not-allowed' });

      expect(global.alert).toHaveBeenCalledWith(
        'Please grant microphone permissions to use voice input.'
      );
      expect(hook.isListening).toBe(false);
      expect(consoleSpy).toHaveBeenCalled();
    });

    it('should handle no-speech error silently', () => {
      const consoleWarnSpy = vi.spyOn(console, 'warn');

      hook.recognition.onerror({ error: 'no-speech' });

      expect(hook.isListening).toBe(false);
      // Should not warn for no-speech
      expect(consoleWarnSpy).not.toHaveBeenCalled();
    });

    it('should log other errors', () => {
      const consoleWarnSpy = vi.spyOn(console, 'warn');

      hook.recognition.onerror({ error: 'network' });

      expect(consoleWarnSpy).toHaveBeenCalledWith('Speech recognition error:', 'network');
    });

    it('should handle InvalidStateError when already started', () => {
      hook.isListening = false;
      hook.recognition.start = vi.fn(() => {
        const error = new Error('Already started');
        error.name = 'InvalidStateError';
        throw error;
      });

      const consoleSpy = vi.spyOn(console, 'error');
      hook.startListening();

      // Should not log error for InvalidStateError
      expect(consoleSpy).not.toHaveBeenCalled();
    });
  });

  describe('UI State Management', () => {
    beforeEach(() => {
      hook.mounted();
    });

    it('should update UI when listening starts', () => {
      hook.recognition.onstart();

      expect(hook.isListening).toBe(true);
      expect(mockElement.classList.contains('listening')).toBe(true);
      expect(mockElement.classList.contains('bg-red-500')).toBe(true);
      expect(mockElement.classList.contains('hover:bg-red-600')).toBe(true);
      expect(mockElement.classList.contains('bg-blue-500')).toBe(false);
      expect(mockListeningIndicator.style.display).toBe('block');
      expect(mockMicIcon.classList.contains('animate-pulse')).toBe(true);
    });

    it('should update UI when listening stops', () => {
      // First start
      hook.recognition.onstart();

      // Then stop
      hook.recognition.onend();

      expect(hook.isListening).toBe(false);
      expect(mockElement.classList.contains('listening')).toBe(false);
      expect(mockElement.classList.contains('bg-blue-500')).toBe(true);
      expect(mockElement.classList.contains('hover:bg-blue-600')).toBe(true);
      expect(mockElement.classList.contains('bg-red-500')).toBe(false);
      expect(mockListeningIndicator.style.display).toBe('none');
      expect(mockMicIcon.classList.contains('animate-pulse')).toBe(false);
    });
  });

  describe('Cleanup', () => {
    beforeEach(() => {
      hook.mounted();
    });

    it('should stop recognition on destroyed', () => {
      const stopSpy = vi.spyOn(hook.recognition, 'stop');

      hook.destroyed();

      expect(stopSpy).toHaveBeenCalled();
      expect(hook.recognition).toBeNull();
    });

    it('should handle errors during cleanup gracefully', () => {
      hook.recognition.stop = vi.fn(() => {
        throw new Error('Already stopped');
      });

      expect(() => hook.destroyed()).not.toThrow();
      expect(hook.recognition).toBeNull();
    });
  });

  describe('Edge Cases', () => {
    beforeEach(() => {
      hook.mounted();
    });

    it('should preserve existing content when starting new session', () => {
      mockInputField.value = 'existing text';

      hook.startListening();

      expect(hook.finalTranscript).toBe('existing text ');
    });

    it('should handle missing input field gracefully', () => {
      // Remove input field
      mockInputField.remove();
      hook.inputField = null;

      const mockEvent = {
        resultIndex: 0,
        results: [
          {
            0: { transcript: 'test' },
            isFinal: true
          }
        ]
      };

      expect(() => hook.recognition.onresult(mockEvent)).not.toThrow();
    });

    it('should handle missing UI elements gracefully', () => {
      hook.micIcon = null;
      hook.listeningIndicator = null;

      expect(() => hook.updateUI()).not.toThrow();
    });
  });
});
