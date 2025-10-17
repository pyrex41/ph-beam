/**
 * Color Picker Hook
 *
 * Enhances the color picker LiveComponent with client-side interactivity:
 * - Real-time slider preview
 * - Keyboard shortcuts
 * - Copy color to clipboard
 * - Color format conversion
 */

export const ColorPickerHook = {
  mounted() {
    this.setupKeyboardShortcuts();
    this.setupClipboard();
    this.setupColorSquare();
    this.updateSliderGradients();
  },

  updated() {
    this.updateSliderGradients();
  },

  /**
   * Safely push event to server (ignores if not connected)
   */
  safePushEventTo(target, eventName, payload) {
    try {
      this.pushEventTo(target, eventName, payload);
    } catch (error) {
      // Silently ignore if LiveView not connected
      // Connection will be established shortly
    }
  },

  /**
   * Update slider background gradients based on current HSL values
   */
  updateSliderGradients() {
    const hue = parseInt(this.el.querySelector('[phx-change="hue_changed"]')?.value || 0);
    const saturation = parseInt(this.el.querySelector('[phx-change="saturation_changed"]')?.value || 100);
    const lightness = parseInt(this.el.querySelector('[phx-change="lightness_changed"]')?.value || 50);

    // Update saturation slider gradient based on current hue and lightness
    const satSlider = this.el.querySelector('[phx-change="saturation_changed"]');
    if (satSlider) {
      const leftColor = this.hslToHex(hue, 0, lightness);
      const rightColor = this.hslToHex(hue, 100, lightness);
      satSlider.style.background = `linear-gradient(to right, ${leftColor}, ${rightColor})`;
    }

    // Update lightness slider gradient based on current hue and saturation
    const lightSlider = this.el.querySelector('[phx-change="lightness_changed"]');
    if (lightSlider) {
      const leftColor = this.hslToHex(hue, saturation, 0);
      const middleColor = this.hslToHex(hue, saturation, 50);
      const rightColor = this.hslToHex(hue, saturation, 100);
      lightSlider.style.background = `linear-gradient(to right, ${leftColor}, ${middleColor}, ${rightColor})`;
    }
  },

  /**
   * Setup keyboard shortcuts for color picker
   */
  setupKeyboardShortcuts() {
    this.handleKeydown = (e) => {
      // Ctrl/Cmd + C to copy color
      if ((e.ctrlKey || e.metaKey) && e.key === 'c') {
        const hexInput = this.el.querySelector('input[type="text"]');
        if (hexInput && !hexInput.contains(e.target)) {
          e.preventDefault();
          this.copyToClipboard(hexInput.value);
        }
      }

      // Ctrl/Cmd + F to add to favorites
      if ((e.ctrlKey || e.metaKey) && e.key === 'f') {
        e.preventDefault();
        const favButton = this.el.querySelector('[phx-click="add_to_favorites"]');
        favButton?.click();
      }
    };

    this.el.addEventListener('keydown', this.handleKeydown);
  },

  /**
   * Setup clipboard functionality
   */
  setupClipboard() {
    const hexInput = this.el.querySelector('input[type="text"]');
    if (hexInput) {
      hexInput.addEventListener('click', (e) => {
        e.target.select();
      });

      hexInput.addEventListener('dblclick', (e) => {
        e.target.select();
        this.copyToClipboard(e.target.value);
      });
    }
  },

  /**
   * Copy text to clipboard and show feedback
   */
  copyToClipboard(text) {
    navigator.clipboard.writeText(text).then(() => {
      // Show temporary feedback
      const hexInput = this.el.querySelector('input[type="text"]');
      if (hexInput) {
        const originalBorder = hexInput.style.borderColor;
        hexInput.style.borderColor = '#10b981'; // green
        setTimeout(() => {
          hexInput.style.borderColor = originalBorder;
        }, 300);
      }
    });
  },

  /**
   * Convert HSL to hex color
   */
  hslToHex(h, s, l) {
    s /= 100;
    l /= 100;

    const c = (1 - Math.abs(2 * l - 1)) * s;
    const x = c * (1 - Math.abs(((h / 60) % 2) - 1));
    const m = l - c / 2;

    let r, g, b;

    if (h < 60) {
      [r, g, b] = [c, x, 0];
    } else if (h < 120) {
      [r, g, b] = [x, c, 0];
    } else if (h < 180) {
      [r, g, b] = [0, c, x];
    } else if (h < 240) {
      [r, g, b] = [0, x, c];
    } else if (h < 300) {
      [r, g, b] = [x, 0, c];
    } else {
      [r, g, b] = [c, 0, x];
    }

    r = Math.round((r + m) * 255);
    g = Math.round((g + m) * 255);
    b = Math.round((b + m) * 255);

    return `#${r.toString(16).padStart(2, '0')}${g.toString(16).padStart(2, '0')}${b.toString(16).padStart(2, '0')}`.toUpperCase();
  },

  /**
   * Setup 2D color square interaction
   */
  setupColorSquare() {
    const square = this.el.querySelector('#color-picker-square');
    if (!square) return;

    let isDragging = false;

    const updateColorFromSquare = (e) => {
      const rect = square.getBoundingClientRect();
      const x = Math.max(0, Math.min(e.clientX - rect.left, rect.width));
      const y = Math.max(0, Math.min(e.clientY - rect.top, rect.height));

      // Convert position to saturation and lightness
      // X axis: 0 (left) = 0% saturation, width (right) = 100% saturation
      // Y axis: 0 (top) = 100% lightness, height (bottom) = 0% lightness
      const saturation = (x / rect.width) * 100;
      const lightness = 100 - (y / rect.height) * 100;

      // Push event to server (safely - ignores if not connected)
      this.safePushEventTo(this.el, 'picker_square_changed', {
        saturation: saturation.toString(),
        lightness: lightness.toString()
      });
    };

    square.addEventListener('mousedown', (e) => {
      isDragging = true;
      updateColorFromSquare(e);
      e.preventDefault();
    });

    document.addEventListener('mousemove', (e) => {
      if (isDragging) {
        updateColorFromSquare(e);
      }
    });

    document.addEventListener('mouseup', () => {
      isDragging = false;
    });
  },

  destroyed() {
    if (this.handleKeydown) {
      this.el.removeEventListener('keydown', this.handleKeydown);
    }
  }
};
