/**
 * Voice Input Hook for AI Command Interface
 *
 * Provides push-to-talk microphone input using the Web Speech API.
 * Allows users to dictate AI commands using their voice with live transcription.
 *
 * Features:
 * - Push-to-talk microphone button
 * - Live transcription into the AI input field
 * - Visual feedback for listening/transcribing states
 * - Graceful fallback if Speech API is unavailable
 * - Permission handling for microphone access
 *
 * Usage:
 * Add phx-hook="VoiceInput" to the voice button element and ensure
 * the AI command textarea has id="ai-command-input"
 */

export default {
  mounted() {
    // Check if browser supports speech recognition
    const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;

    if (!SpeechRecognition) {
      console.warn("Speech Recognition API not supported in this browser");
      this.el.style.display = 'none';
      return;
    }

    // Initialize speech recognition
    this.recognition = new SpeechRecognition();
    this.recognition.continuous = false;
    this.recognition.interimResults = true;
    this.recognition.lang = 'en-US';

    // State tracking
    this.isListening = false;
    this.finalTranscript = '';

    // Get references to elements
    this.inputField = document.getElementById('ai-command-input');
    this.micIcon = this.el.querySelector('.mic-icon');
    this.listeningIndicator = this.el.querySelector('.listening-indicator');

    // Set up event handlers
    this.setupEventHandlers();

    // Handle button clicks
    this.el.addEventListener('mousedown', this.startListening.bind(this));
    this.el.addEventListener('mouseup', this.stopListening.bind(this));
    this.el.addEventListener('mouseleave', this.stopListening.bind(this));

    // Handle touch events for mobile
    this.el.addEventListener('touchstart', (e) => {
      e.preventDefault();
      this.startListening();
    });
    this.el.addEventListener('touchend', (e) => {
      e.preventDefault();
      this.stopListening();
    });
  },

  setupEventHandlers() {
    // Handle recognition results
    this.recognition.onresult = (event) => {
      let interimTranscript = '';

      for (let i = event.resultIndex; i < event.results.length; i++) {
        const transcript = event.results[i][0].transcript;

        if (event.results[i].isFinal) {
          this.finalTranscript += transcript + ' ';
        } else {
          interimTranscript += transcript;
        }
      }

      // Update input field with current transcription
      if (this.inputField) {
        const currentValue = this.finalTranscript + interimTranscript;
        this.inputField.value = currentValue.trim();

        // Push the value to LiveView
        this.pushEvent("update_ai_command", { command: currentValue.trim() });

        // Trigger input event for any listeners
        this.inputField.dispatchEvent(new Event('input', { bubbles: true }));
      }
    };

    // Handle recognition errors
    this.recognition.onerror = (event) => {
      console.error('Speech recognition error:', event.error);

      if (event.error === 'not-allowed') {
        alert('Please grant microphone permissions to use voice input.');
      } else if (event.error === 'no-speech') {
        // Normal - user didn't speak
      } else {
        console.warn('Speech recognition error:', event.error);
      }

      this.stopListening();
    };

    // Handle recognition end
    this.recognition.onend = () => {
      this.isListening = false;
      this.updateUI();
    };

    // Handle recognition start
    this.recognition.onstart = () => {
      this.isListening = true;
      this.updateUI();
    };
  },

  startListening() {
    if (this.isListening) return;

    try {
      // Reset transcript when starting new session
      this.finalTranscript = this.inputField ? this.inputField.value + ' ' : '';
      this.recognition.start();
    } catch (error) {
      if (error.name === 'InvalidStateError') {
        // Already started, ignore
      } else {
        console.error('Failed to start speech recognition:', error);
      }
    }
  },

  stopListening() {
    if (!this.isListening) return;

    try {
      this.recognition.stop();
    } catch (error) {
      console.error('Failed to stop speech recognition:', error);
    }
  },

  updateUI() {
    if (this.isListening) {
      // Show listening state
      this.el.classList.add('listening');
      this.el.classList.add('bg-red-500', 'hover:bg-red-600');
      this.el.classList.remove('bg-blue-500', 'hover:bg-blue-600');

      if (this.listeningIndicator) {
        this.listeningIndicator.style.display = 'block';
      }

      // Update button text/icon
      if (this.micIcon) {
        this.micIcon.classList.add('animate-pulse');
      }
    } else {
      // Show idle state
      this.el.classList.remove('listening');
      this.el.classList.remove('bg-red-500', 'hover:bg-red-600');
      this.el.classList.add('bg-blue-500', 'hover:bg-blue-600');

      if (this.listeningIndicator) {
        this.listeningIndicator.style.display = 'none';
      }

      // Update button text/icon
      if (this.micIcon) {
        this.micIcon.classList.remove('animate-pulse');
      }
    }
  },

  destroyed() {
    // Clean up speech recognition
    if (this.recognition) {
      try {
        this.recognition.stop();
      } catch (error) {
        // Ignore errors when stopping
      }
      this.recognition = null;
    }
  }
};