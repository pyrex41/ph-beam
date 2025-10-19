/**
 * Voice Input Hook for AI Command Interface
 *
 * Provides click-to-record microphone input using Groq's Whisper API.
 * Allows users to dictate AI commands using their voice with transcription.
 *
 * Features:
 * - Click to start/stop recording
 * - Spacebar to stop recording
 * - Visual dialog with animated audio bars
 * - Draggable dialog
 * - Blurred background
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
    this.isCancelled = false;
    this.mediaRecorder = null;
    this.audioChunks = [];
    this.audioContext = null;
    this.analyser = null;
    this.dataArray = null;
    this.animationId = null;
    this.isDragging = false;
    this.dragOffset = { x: 0, y: 0 };
    this.hasLoggedAudio = false;

    // Get references to elements
    this.inputField = document.getElementById('ai-command-input');
    this.micIcon = this.el.querySelector('.mic-icon');
    this.listeningIndicator = this.el.querySelector('.listening-indicator');

    // Create dialog modal
    this.createDialog();

    // Handle button clicks (toggle recording)
    this.el.addEventListener('click', (e) => {
      e.preventDefault();
      if (this.isRecording) {
        this.stopRecording();
      } else if (!this.isTranscribing) {
        this.startRecording();
      }
    });

    // Handle keyboard shortcuts
    this.handleKeyDown = (e) => {
      // Escape to cancel recording
      if (e.code === 'Escape' && this.isRecording) {
        e.preventDefault();
        this.cancelRecording();
        return;
      }

      // Space to start/stop recording (not in input fields)
      if (e.code === 'Space') {
        const target = e.target;
        const isInputField = target.tagName === 'INPUT' ||
                           target.tagName === 'TEXTAREA' ||
                           target.id === 'ai-command-input' ||
                           target.isContentEditable;

        if (isInputField) {
          return; // Let spacebar work normally in input fields
        }

        e.preventDefault();

        if (this.isRecording) {
          this.stopRecording();
        } else if (!this.isTranscribing) {
          this.startRecording();
        }
      }
    };
    document.addEventListener('keydown', this.handleKeyDown);
  },

  createDialog() {
    // Add CSS animation for pulsing bars
    const style = document.createElement('style');
    style.textContent = `
      @keyframes bar-pulse {
        0%, 100% { opacity: 0.6; }
        50% { opacity: 1; }
      }
      .audio-bar {
        animation: bar-pulse 1.5s infinite;
      }
    `;
    document.head.appendChild(style);

    // Create floating panel (not a blocking modal)
    this.dialog = document.createElement('div');
    this.dialog.className = 'fixed hidden z-50';
    this.dialog.style.pointerEvents = 'auto';

    // Load saved position from localStorage or use default
    const savedPosition = this.loadDialogPosition();
    this.dialog.style.top = savedPosition.top;
    this.dialog.style.right = savedPosition.right;

    this.dialog.innerHTML = `
      <div id="voice-dialog-content" class="bg-white/95 backdrop-blur-sm rounded-lg p-6 shadow-2xl w-80 border border-gray-200 cursor-grab active:cursor-grabbing">
        <div class="text-center">
          <h3 class="text-lg font-semibold mb-4" id="dialog-header">Recording...</h3>
          <div id="audio-visualizer" class="flex items-center justify-center gap-1 h-24 mb-4"></div>
          <p class="text-sm text-gray-600 mb-4">
            <kbd class="px-2 py-1 bg-gray-200 rounded">Space</kbd> to stop
            <span class="mx-2">•</span>
            <kbd class="px-2 py-1 bg-gray-200 rounded">Esc</kbd> to cancel
          </p>
          <button id="stop-recording-btn" class="px-4 py-2 bg-red-500 hover:bg-red-600 text-white rounded-lg transition-colors cursor-pointer">
            Stop Recording
          </button>
        </div>
      </div>
    `;
    document.body.appendChild(this.dialog);

    // Get references
    this.dialogContent = this.dialog.querySelector('#voice-dialog-content');
    this.visualizer = this.dialog.querySelector('#audio-visualizer');
    this.dialogHeader = this.dialog.querySelector('#dialog-header');
    const stopBtn = this.dialog.querySelector('#stop-recording-btn');
    stopBtn.addEventListener('click', () => this.stopRecording());

    // Create audio bars for visualizer (10 left + 10 right mirrored)
    this.bars = [];
    for (let i = 0; i < 10; i++) {
      const bar = document.createElement('div');
      bar.className = 'audio-bar rounded-full transition-all duration-75';
      bar.style.width = '8px';
      bar.style.height = '30px';
      bar.style.minHeight = '10px';
      bar.style.background = 'linear-gradient(180deg, #4a90e2, #50c4b7)';
      bar.style.animationDelay = `${i * 0.05}s`;
      this.bars.push(bar);
      this.visualizer.appendChild(bar);
    }

    // Add center gap
    const gap = document.createElement('div');
    gap.style.width = '8px';
    this.visualizer.appendChild(gap);

    // Add mirrored right side bars
    for (let i = 9; i >= 0; i--) {
      const bar = document.createElement('div');
      bar.className = 'audio-bar rounded-full transition-all duration-75';
      bar.style.width = '8px';
      bar.style.height = '30px';
      bar.style.minHeight = '10px';
      bar.style.background = 'linear-gradient(180deg, #4a90e2, #50c4b7)';
      bar.style.animationDelay = `${i * 0.05}s`;
      this.bars.push(bar);
      this.visualizer.appendChild(bar);
    }

    // Make dialog draggable
    this.setupDragFunctionality();
  },

  loadDialogPosition() {
    try {
      const saved = localStorage.getItem('voiceDialogPosition');
      if (saved) {
        return JSON.parse(saved);
      }
    } catch (error) {
      console.error('Failed to load dialog position:', error);
    }
    // Default position
    return { top: '20px', right: '20px' };
  },

  saveDialogPosition() {
    try {
      const rect = this.dialog.getBoundingClientRect();
      const position = {
        top: `${rect.top}px`,
        right: `${window.innerWidth - rect.right}px`
      };
      localStorage.setItem('voiceDialogPosition', JSON.stringify(position));
    } catch (error) {
      console.error('Failed to save dialog position:', error);
    }
  },

  setupDragFunctionality() {
    const handleMouseDown = (e) => {
      // Allow dragging from anywhere except buttons and interactive elements
      const isButton = e.target.tagName === 'BUTTON' ||
                      e.target.closest('button') !== null ||
                      e.target.tagName === 'KBD';

      if (isButton) return;

      this.isDragging = true;
      const rect = this.dialog.getBoundingClientRect();
      this.dragOffset = {
        x: e.clientX - rect.left,
        y: e.clientY - rect.top
      };

      e.preventDefault();
    };

    const handleMouseMove = (e) => {
      if (!this.isDragging) return;

      const newX = e.clientX - this.dragOffset.x;
      const newY = e.clientY - this.dragOffset.y;

      // Keep dialog within viewport
      const maxX = window.innerWidth - this.dialog.offsetWidth;
      const maxY = window.innerHeight - this.dialog.offsetHeight;

      const clampedX = Math.max(0, Math.min(newX, maxX));
      const clampedY = Math.max(0, Math.min(newY, maxY));

      this.dialog.style.left = `${clampedX}px`;
      this.dialog.style.top = `${clampedY}px`;
      this.dialog.style.right = 'auto'; // Override right position when dragging

      e.preventDefault();
    };

    const handleMouseUp = () => {
      if (this.isDragging) {
        this.isDragging = false;
        this.saveDialogPosition();
      }
    };

    this.dialogContent.addEventListener('mousedown', handleMouseDown);
    document.addEventListener('mousemove', handleMouseMove);
    document.addEventListener('mouseup', handleMouseUp);

    // Store for cleanup
    this.dragListeners = { handleMouseDown, handleMouseMove, handleMouseUp };
  },

  async startRecording() {
    if (this.isRecording || this.isTranscribing) return;

    try {
      // Request microphone access
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });

      // Reset audio chunks, cancellation, and logging flag
      this.audioChunks = [];
      this.isCancelled = false;
      this.hasLoggedAudio = false;
      this.stream = stream;

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

        // Stop audio analysis
        if (this.animationId) {
          cancelAnimationFrame(this.animationId);
          this.animationId = null;
        }

        // Close audio context
        if (this.audioContext) {
          this.audioContext.close();
          this.audioContext = null;
        }

        // Hide dialog
        this.dialog.classList.add('hidden');

        // Only process audio if we have chunks and recording wasn't cancelled
        if (this.audioChunks.length > 0 && !this.isCancelled) {
          // Create audio blob from chunks
          const audioBlob = new Blob(this.audioChunks, { type: 'audio/webm' });

          // Send to transcription endpoint
          await this.transcribeAudio(audioBlob);
        }
      };

      // Show dialog
      this.dialog.classList.remove('hidden');

      // Start recording - MUST set isRecording BEFORE setupAudioVisualization
      this.mediaRecorder.start();
      this.isRecording = true;
      this.updateUI();

      // Setup audio visualization AFTER isRecording is true
      this.setupAudioVisualization(stream);
    } catch (error) {
      console.error('Failed to start recording:', error);

      if (error.name === 'NotAllowedError') {
        alert('Please grant microphone permissions to use voice input.');
      } else {
        alert('Failed to access microphone: ' + error.message);
      }
    }
  },

  setupAudioVisualization(stream) {
    // Create audio context and analyser
    this.audioContext = new (window.AudioContext || window.webkitAudioContext)();
    this.analyser = this.audioContext.createAnalyser();
    this.analyser.fftSize = 256; // Increased for better frequency resolution
    this.analyser.smoothingTimeConstant = 0.3; // Less smoothing for more responsive bars
    this.analyser.minDecibels = -90;
    this.analyser.maxDecibels = -10;

    const source = this.audioContext.createMediaStreamSource(stream);
    source.connect(this.analyser);

    const bufferLength = this.analyser.frequencyBinCount;
    this.dataArray = new Uint8Array(bufferLength);

    console.log('Audio visualization setup complete:', {
      fftSize: this.analyser.fftSize,
      bufferLength: bufferLength,
      sampleRate: this.audioContext.sampleRate
    });

    // Start visualization loop
    this.animateBars();
  },

  animateBars() {
    if (!this.isRecording || !this.analyser || !this.dataArray) {
      console.log('Animation stopped:', { isRecording: this.isRecording, hasAnalyser: !!this.analyser });
      return;
    }

    this.animationId = requestAnimationFrame(() => this.animateBars());

    // Get frequency data
    this.analyser.getByteFrequencyData(this.dataArray);

    // Calculate average volume for logging
    const avg = this.dataArray.reduce((a, b) => a + b, 0) / this.dataArray.length;

    // Log first frame to verify data
    if (!this.hasLoggedAudio) {
      console.log('Audio data:', {
        avg,
        sample: Array.from(this.dataArray.slice(0, 10)),
        barsCount: this.bars.length
      });
      this.hasLoggedAudio = true;
    }

    // Classic waveform: each bar responds to its own frequency bin
    // Pattern: tall edges, short middle (mirrored left/right AND top/bottom)
    const halfBars = this.bars.length / 2;

    this.bars.forEach((bar, index) => {
      // For mirrored bars, use the same frequency data
      const mirrorIndex = index < halfBars ? index : (this.bars.length - 1 - index);

      // Sample frequency data - spread across the frequency spectrum
      const dataIndex = Math.floor((mirrorIndex / halfBars) * this.dataArray.length);
      const frequencyValue = this.dataArray[dataIndex] || 0;

      // Calculate position from center (0 = center, 1 = edge)
      const positionFromCenter = index < halfBars
        ? (halfBars - index) / halfBars  // Left side
        : (index - halfBars + 1) / halfBars;  // Right side

      // Base shape: tall on edges (60px), short in middle (15px)
      const baseHeight = 15 + (positionFromCenter * 45);

      // Audio reactivity - BOOSTED for middle bars!
      // Middle bars get 2x boost, edges get normal response
      const reactivityBoost = 1 + (1 - positionFromCenter); // 2.0 at center, 1.0 at edges
      const audioHeight = (frequencyValue / 255) * 50 * reactivityBoost;

      // Combine: base shape + audio response
      const height = Math.max(10, baseHeight + audioHeight);

      // Update bar height
      bar.style.height = `${Math.round(height)}px`;
    });
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

  cancelRecording() {
    if (!this.isRecording) return;

    try {
      // Stop the recording without processing
      this.isRecording = false;
      this.isCancelled = true; // Mark as cancelled to prevent transcription
      this.audioChunks = []; // Clear audio chunks so they won't be processed

      if (this.mediaRecorder && this.mediaRecorder.state === 'recording') {
        this.mediaRecorder.stop();
      }

      // Stop all tracks immediately
      if (this.stream) {
        this.stream.getTracks().forEach(track => track.stop());
      }

      // Stop audio analysis
      if (this.animationId) {
        cancelAnimationFrame(this.animationId);
        this.animationId = null;
      }

      // Close audio context
      if (this.audioContext) {
        this.audioContext.close();
        this.audioContext = null;
      }

      // Hide dialog
      this.dialog.classList.add('hidden');

      this.updateUI();
    } catch (error) {
      console.error('Failed to cancel recording:', error);
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

        // Focus the input field so user can immediately press Enter
        this.inputField.focus();

        // Move cursor to end of text
        this.inputField.setSelectionRange(newValue.length, newValue.length);
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
    // Remove keydown listener
    if (this.handleKeyDown) {
      document.removeEventListener('keydown', this.handleKeyDown);
    }

    // Remove drag listeners
    if (this.dragListeners) {
      if (this.dialogContent) {
        this.dialogContent.removeEventListener('mousedown', this.dragListeners.handleMouseDown);
      }
      document.removeEventListener('mousemove', this.dragListeners.handleMouseMove);
      document.removeEventListener('mouseup', this.dragListeners.handleMouseUp);
    }

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

    // Clean up audio visualization
    if (this.animationId) {
      cancelAnimationFrame(this.animationId);
    }

    if (this.audioContext) {
      this.audioContext.close();
    }

    // Clean up dialog
    if (this.dialog && this.dialog.parentNode) {
      this.dialog.parentNode.removeChild(this.dialog);
    }

    // Stop stream if still active
    if (this.stream) {
      this.stream.getTracks().forEach(track => track.stop());
    }
  }
};
