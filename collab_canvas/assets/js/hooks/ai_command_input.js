/**
 * AI Command Input Hook
 *
 * Enhances the AI command textarea with keyboard shortcuts:
 * - Enter: Submit the command
 * - Shift+Enter: Add a newline
 *
 * This improves user experience for quick command execution
 * while still allowing multi-line commands when needed.
 *
 * Usage:
 * Add phx-hook="AICommandInput" to the textarea element
 */

export default {
  mounted() {
    // Handle keydown events on the textarea
    this.el.addEventListener('keydown', (event) => {
      // Check if Enter key is pressed
      if (event.key === 'Enter') {
        // If Shift is NOT held, submit the command
        if (!event.shiftKey) {
          event.preventDefault();

          // Get the current command value
          const command = this.el.value.trim();

          // Only submit if there's actual content
          if (command) {
            // Push the execute command event to LiveView
            this.pushEvent('execute_ai_command', { command });

            // Clear the field after submission
            this.el.value = '';

            // Also update the LiveView state
            this.pushEvent('update_ai_command', { command: '' });
          }
        }
        // If Shift+Enter, allow default behavior (new line)
      }
    });

    // Update LiveView state and button on input
    this.el.addEventListener('input', () => {
      const command = this.el.value;

      // Update LiveView state so @ai_command stays in sync
      this.pushEvent('update_ai_command', { command: command });
    });
  },

  destroyed() {
    // Clean up event listeners if needed
  }
};