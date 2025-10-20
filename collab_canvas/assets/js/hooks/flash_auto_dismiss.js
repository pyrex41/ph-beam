/**
 * Flash Auto Dismiss Hook
 *
 * Automatically dismisses flash messages after a configured delay.
 * Default: 7 seconds (7000ms)
 */
const FlashAutoDismiss = {
  mounted() {
    // Get delay from data attribute or use default of 7 seconds
    const delay = parseInt(this.el.dataset.autoDismissDelay || "7000", 10);

    // Set a timeout to auto-dismiss the flash message
    this.dismissTimer = setTimeout(() => {
      // Trigger the same click event that manual dismiss uses
      this.el.click();
    }, delay);
  },

  destroyed() {
    // Clean up timer if component is destroyed before auto-dismiss
    if (this.dismissTimer) {
      clearTimeout(this.dismissTimer);
    }
  }
};

export default FlashAutoDismiss;
