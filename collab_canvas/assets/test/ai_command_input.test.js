/**
 * Tests for AI Command Input Hook
 *
 * Tests keyboard shortcut functionality including:
 * - Enter to submit command
 * - Shift+Enter to add newline
 * - Submit button state management
 * - Input validation
 */

import { describe, it, expect, beforeEach, vi } from 'vitest';
import AICommandInputHook from '../js/hooks/ai_command_input.js';

describe('AICommandInput Hook', () => {
  let hook;
  let mockTextarea;
  let mockSubmitButton;

  beforeEach(() => {
    // Create mock textarea
    mockTextarea = document.createElement('textarea');
    mockTextarea.id = 'ai-command-input';
    document.body.appendChild(mockTextarea);

    // Create mock submit button
    mockSubmitButton = document.createElement('button');
    mockSubmitButton.id = 'ai-execute-button';
    mockSubmitButton.classList.add('bg-gray-300', 'text-gray-500', 'cursor-not-allowed');
    mockSubmitButton.disabled = true;
    document.body.appendChild(mockSubmitButton);

    // Create hook instance with mock context
    hook = Object.create(AICommandInputHook);
    hook.el = mockTextarea;
    hook.pushEvent = vi.fn();

    // Mount the hook
    hook.mounted();
  });

  afterEach(() => {
    // Clean up DOM
    document.body.innerHTML = '';
    vi.clearAllMocks();
  });

  describe('Enter Key Behavior', () => {
    it('should submit command on Enter key press', () => {
      mockTextarea.value = 'create a circle';

      const event = new KeyboardEvent('keydown', {
        key: 'Enter',
        shiftKey: false,
        bubbles: true,
        cancelable: true
      });

      mockTextarea.dispatchEvent(event);

      expect(hook.pushEvent).toHaveBeenCalledWith('execute_ai_command', {
        command: 'create a circle'
      });
      expect(mockTextarea.value).toBe('');
      expect(hook.pushEvent).toHaveBeenCalledWith('update_ai_command', {
        command: ''
      });
    });

    it('should prevent default Enter behavior when submitting', () => {
      mockTextarea.value = 'test command';

      const event = new KeyboardEvent('keydown', {
        key: 'Enter',
        shiftKey: false,
        bubbles: true,
        cancelable: true
      });

      const preventDefaultSpy = vi.spyOn(event, 'preventDefault');
      mockTextarea.dispatchEvent(event);

      expect(preventDefaultSpy).toHaveBeenCalled();
    });

    it('should not submit empty command', () => {
      mockTextarea.value = '   ';  // Only whitespace

      const event = new KeyboardEvent('keydown', {
        key: 'Enter',
        shiftKey: false,
        bubbles: true,
        cancelable: true
      });

      mockTextarea.dispatchEvent(event);

      expect(hook.pushEvent).not.toHaveBeenCalledWith('execute_ai_command', expect.anything());
    });

    it('should not submit when field is empty', () => {
      mockTextarea.value = '';

      const event = new KeyboardEvent('keydown', {
        key: 'Enter',
        shiftKey: false,
        bubbles: true,
        cancelable: true
      });

      mockTextarea.dispatchEvent(event);

      expect(hook.pushEvent).not.toHaveBeenCalledWith('execute_ai_command', expect.anything());
    });

    it('should trim whitespace from command before submission', () => {
      mockTextarea.value = '  create a circle  ';

      const event = new KeyboardEvent('keydown', {
        key: 'Enter',
        shiftKey: false,
        bubbles: true,
        cancelable: true
      });

      mockTextarea.dispatchEvent(event);

      expect(hook.pushEvent).toHaveBeenCalledWith('execute_ai_command', {
        command: 'create a circle'
      });
    });
  });

  describe('Shift+Enter Behavior', () => {
    it('should allow newline on Shift+Enter', () => {
      mockTextarea.value = 'line 1';

      const event = new KeyboardEvent('keydown', {
        key: 'Enter',
        shiftKey: true,
        bubbles: true,
        cancelable: true
      });

      const preventDefaultSpy = vi.spyOn(event, 'preventDefault');
      mockTextarea.dispatchEvent(event);

      // Should NOT prevent default (allow newline)
      expect(preventDefaultSpy).not.toHaveBeenCalled();
      // Should NOT submit command
      expect(hook.pushEvent).not.toHaveBeenCalledWith('execute_ai_command', expect.anything());
    });

    it('should not clear field on Shift+Enter', () => {
      mockTextarea.value = 'multi-line\ncommand';

      const event = new KeyboardEvent('keydown', {
        key: 'Enter',
        shiftKey: true,
        bubbles: true,
        cancelable: true
      });

      mockTextarea.dispatchEvent(event);

      // Field should still have content
      expect(mockTextarea.value).toBe('multi-line\ncommand');
    });
  });

  describe('Submit Button State Management', () => {
    it('should enable submit button when textarea has content', () => {
      mockTextarea.value = 'test';

      const event = new Event('input', { bubbles: true });
      mockTextarea.dispatchEvent(event);

      expect(mockSubmitButton.disabled).toBe(false);
      expect(mockSubmitButton.classList.contains('bg-blue-600')).toBe(true);
      expect(mockSubmitButton.classList.contains('text-white')).toBe(true);
      expect(mockSubmitButton.classList.contains('hover:bg-blue-700')).toBe(true);
      expect(mockSubmitButton.classList.contains('bg-gray-300')).toBe(false);
      expect(mockSubmitButton.classList.contains('text-gray-500')).toBe(false);
      expect(mockSubmitButton.classList.contains('cursor-not-allowed')).toBe(false);
    });

    it('should disable submit button when textarea is empty', () => {
      // First add content
      mockTextarea.value = 'test';
      mockTextarea.dispatchEvent(new Event('input', { bubbles: true }));

      // Then clear it
      mockTextarea.value = '';
      mockTextarea.dispatchEvent(new Event('input', { bubbles: true }));

      expect(mockSubmitButton.disabled).toBe(true);
      expect(mockSubmitButton.classList.contains('bg-gray-300')).toBe(true);
      expect(mockSubmitButton.classList.contains('text-gray-500')).toBe(true);
      expect(mockSubmitButton.classList.contains('cursor-not-allowed')).toBe(true);
      expect(mockSubmitButton.classList.contains('bg-blue-600')).toBe(false);
    });

    it('should disable submit button when textarea has only whitespace', () => {
      mockTextarea.value = '   ';

      const event = new Event('input', { bubbles: true });
      mockTextarea.dispatchEvent(event);

      expect(mockSubmitButton.disabled).toBe(true);
    });

    it('should handle missing submit button gracefully', () => {
      // Remove submit button
      mockSubmitButton.remove();

      mockTextarea.value = 'test';

      expect(() => {
        mockTextarea.dispatchEvent(new Event('input', { bubbles: true }));
      }).not.toThrow();
    });
  });

  describe('Other Key Presses', () => {
    it('should not interfere with other keys', () => {
      mockTextarea.value = 'test';

      const event = new KeyboardEvent('keydown', {
        key: 'a',
        bubbles: true,
        cancelable: true
      });

      const preventDefaultSpy = vi.spyOn(event, 'preventDefault');
      mockTextarea.dispatchEvent(event);

      expect(preventDefaultSpy).not.toHaveBeenCalled();
      expect(hook.pushEvent).not.toHaveBeenCalledWith('execute_ai_command', expect.anything());
    });

    it('should not interfere with Ctrl/Cmd keys', () => {
      mockTextarea.value = 'test';

      const event = new KeyboardEvent('keydown', {
        key: 'c',
        ctrlKey: true,
        bubbles: true,
        cancelable: true
      });

      const preventDefaultSpy = vi.spyOn(event, 'preventDefault');
      mockTextarea.dispatchEvent(event);

      expect(preventDefaultSpy).not.toHaveBeenCalled();
    });
  });

  describe('Multi-line Commands', () => {
    it('should handle multi-line commands correctly', () => {
      mockTextarea.value = 'create a circle\nwith red color\nand position at 100,200';

      const event = new KeyboardEvent('keydown', {
        key: 'Enter',
        shiftKey: false,
        bubbles: true,
        cancelable: true
      });

      mockTextarea.dispatchEvent(event);

      expect(hook.pushEvent).toHaveBeenCalledWith('execute_ai_command', {
        command: 'create a circle\nwith red color\nand position at 100,200'
      });
    });
  });

  describe('Event Sequence', () => {
    it('should call both execute and update events in correct order', () => {
      mockTextarea.value = 'test command';

      const event = new KeyboardEvent('keydown', {
        key: 'Enter',
        shiftKey: false,
        bubbles: true,
        cancelable: true
      });

      mockTextarea.dispatchEvent(event);

      expect(hook.pushEvent).toHaveBeenNthCalledWith(1, 'execute_ai_command', {
        command: 'test command'
      });
      expect(hook.pushEvent).toHaveBeenNthCalledWith(2, 'update_ai_command', {
        command: ''
      });
    });

    it('should clear field immediately after submission', () => {
      mockTextarea.value = 'test command';

      const event = new KeyboardEvent('keydown', {
        key: 'Enter',
        shiftKey: false,
        bubbles: true,
        cancelable: true
      });

      mockTextarea.dispatchEvent(event);

      expect(mockTextarea.value).toBe('');
    });
  });

  describe('Cleanup', () => {
    it('should have destroyed method for cleanup', () => {
      expect(hook.destroyed).toBeTypeOf('function');
      expect(() => hook.destroyed()).not.toThrow();
    });
  });

  describe('Edge Cases', () => {
    it('should handle rapid Enter presses', () => {
      mockTextarea.value = 'command 1';

      const event1 = new KeyboardEvent('keydown', {
        key: 'Enter',
        shiftKey: false,
        bubbles: true,
        cancelable: true
      });
      mockTextarea.dispatchEvent(event1);

      // Immediately press Enter again (field is now empty)
      const event2 = new KeyboardEvent('keydown', {
        key: 'Enter',
        shiftKey: false,
        bubbles: true,
        cancelable: true
      });
      mockTextarea.dispatchEvent(event2);

      // Should only submit once (second is empty)
      expect(hook.pushEvent).toHaveBeenCalledTimes(2); // execute + update
    });

    it('should handle special characters in command', () => {
      mockTextarea.value = 'create <div> with "quotes" and \'apostrophes\'';

      const event = new KeyboardEvent('keydown', {
        key: 'Enter',
        shiftKey: false,
        bubbles: true,
        cancelable: true
      });

      mockTextarea.dispatchEvent(event);

      expect(hook.pushEvent).toHaveBeenCalledWith('execute_ai_command', {
        command: 'create <div> with "quotes" and \'apostrophes\''
      });
    });

    it('should handle unicode characters', () => {
      mockTextarea.value = 'create 🎨 with emoji 🚀';

      const event = new KeyboardEvent('keydown', {
        key: 'Enter',
        shiftKey: false,
        bubbles: true,
        cancelable: true
      });

      mockTextarea.dispatchEvent(event);

      expect(hook.pushEvent).toHaveBeenCalledWith('execute_ai_command', {
        command: 'create 🎨 with emoji 🚀'
      });
    });

    it('should handle very long commands', () => {
      const longCommand = 'a'.repeat(10000);
      mockTextarea.value = longCommand;

      const event = new KeyboardEvent('keydown', {
        key: 'Enter',
        shiftKey: false,
        bubbles: true,
        cancelable: true
      });

      mockTextarea.dispatchEvent(event);

      expect(hook.pushEvent).toHaveBeenCalledWith('execute_ai_command', {
        command: longCommand
      });
    });
  });
});
