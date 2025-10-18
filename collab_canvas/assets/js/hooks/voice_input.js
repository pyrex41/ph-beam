/**
 * Voice Input Hook for AI Command Interface
 *
 * Provides push-to-talk microphone input using Groq's Whisper API.
 * Allows users to dictate AI commands using their voice with transcription.
 *
 * Features:
 * - Push-to-talk microphone button
 * - Audio recording using MediaRecorder API
 * - Transcription via Groq Whisper API (backend endpoint)
 * - Visual feedback for recording/transcribing states
 * - Permission handling for microphone access
 *
 * Usage:
 * Add phx-hook="VoiceInput" to the voice button element and ensure
 * the AI command textarea has id="ai-command-input"
 */

export default {
  mounted() {
    // State tracking
    this.isRecording = false;
    this.isTranscribing = false;
    this.mediaRecorder = null;
    this.audioChunks = [];

    // Get references to elements
    this.inputField = document.getElementById('ai-command-input');
    this.micIcon = this.el.querySelector('.mic-icon');
    this.listeningIndicator = this.el.querySelector('.listening-indicator');

    // Handle button clicks
    this.el.addEventListener('mousedown', this.startRecording.bind(this));
    this.el.addEventListener('mouseup', this.stopRecording.bind(this));
    this.el.addEventListener('mouseleave', this.stopRecording.bind(this));

    // Handle touch events for mobile
    this.el.addEventListener('touchstart', (e) => {
      e.preventDefault();
      this.startRecording();
    });
    this.el.addEventListener('touchend', (e) => {
      e.preventDefault();
      this.stopRecording();
    });
  },

  async startRecording() {
    if (this.isRecording || this.isTranscribing) return;

    try {
      // Request microphone access
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });

      // Reset audio chunks
      this.audioChunks = [];

      // Create MediaRecorder
      this.mediaRecorder = new MediaRecorder(stream, {
        mimeType: 'audio/webm'
      });

      // Collect audio data
      this.mediaRecorder.ondataavailable = (event) => {
        if (event.data.size > 0) {
          this.audioChunks.push(event.data);
        }
      };

      // Handle recording stop
      this.mediaRecorder.onstop = async () => {
        // Stop all tracks to release microphone
        stream.getTracks().forEach(track => track.stop());

        // Create audio blob from chunks
        const audioBlob = new Blob(this.audioChunks, { type: 'audio/webm' });

        // Send to transcription endpoint
        await this.transcribeAudio(audioBlob);
      };

      // Start recording
      this.mediaRecorder.start();
      this.isRecording = true;
      this.updateUI();
    } catch (error) {
      console.error('Failed to start recording:', error);

      if (error.name === 'NotAllowedError') {
        alert('Please grant microphone permissions to use voice input.');
      } else {
        alert('Failed to access microphone: ' + error.message);
      }
    }
  },

  stopRecording() {
    if (!this.isRecording || !this.mediaRecorder) return;

    try {
      this.mediaRecorder.stop();
      this.isRecording = false;
      this.updateUI();
    } catch (error) {
      console.error('Failed to stop recording:', error);
    }
  },

  async transcribeAudio(audioBlob) {
    this.isTranscribing = true;
    this.updateUI();

    try {
      // Create form data
      const formData = new FormData();
      formData.append('audio', audioBlob, 'recording.webm');

      // Send to backend transcription endpoint
      const response = await fetch('/api/transcribe', {
        method: 'POST',
        body: formData
      });

      if (!response.ok) {
        const error = await response.json();
        throw new Error(error.error || 'Transcription failed');
      }

      const result = await response.json();

      // Update input field with transcription
      if (this.inputField && result.text) {
        // Append to existing text if any
        const currentValue = this.inputField.value.trim();
        const newValue = currentValue ? `${currentValue} ${result.text}` : result.text;

        this.inputField.value = newValue;

        // Push the value to LiveView
        this.pushEvent("update_ai_command", { command: newValue });

        // Trigger input event for any listeners
        this.inputField.dispatchEvent(new Event('input', { bubbles: true }));
      }
    } catch (error) {
      console.error('Transcription error:', error);
      alert('Failed to transcribe audio: ' + error.message);
    } finally {
      this.isTranscribing = false;
      this.updateUI();
    }
  },

  updateUI() {
    if (this.isRecording) {
      // Show recording state
      this.el.classList.add('listening');
      this.el.classList.add('bg-red-500', 'hover:bg-red-600');
      this.el.classList.remove('bg-blue-500', 'hover:bg-blue-600', 'bg-yellow-500', 'hover:bg-yellow-600');

      if (this.listeningIndicator) {
        this.listeningIndicator.style.display = 'block';
      }

      if (this.micIcon) {
        this.micIcon.classList.add('animate-pulse');
      }
    } else if (this.isTranscribing) {
      // Show transcribing state
      this.el.classList.add('bg-yellow-500', 'hover:bg-yellow-600');
      this.el.classList.remove('bg-blue-500', 'hover:bg-blue-600', 'bg-red-500', 'hover:bg-red-600');

      if (this.listeningIndicator) {
        this.listeningIndicator.style.display = 'block';
      }

      if (this.micIcon) {
        this.micIcon.classList.add('animate-pulse');
      }
    } else {
      // Show idle state
      this.el.classList.remove('listening');
      this.el.classList.remove('bg-red-500', 'hover:bg-red-600', 'bg-yellow-500', 'hover:bg-yellow-600');
      this.el.classList.add('bg-blue-500', 'hover:bg-blue-600');

      if (this.listeningIndicator) {
        this.listeningIndicator.style.display = 'none';
      }

      if (this.micIcon) {
        this.micIcon.classList.remove('animate-pulse');
      }
    }
  },

  destroyed() {
    // Clean up media recorder
    if (this.mediaRecorder) {
      try {
        if (this.isRecording) {
          this.mediaRecorder.stop();
        }
      } catch (error) {
        // Ignore errors when stopping
      }
      this.mediaRecorder = null;
    }
  }
};