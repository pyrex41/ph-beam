defmodule CollabCanvasWeb.WhisperController do
  @moduledoc """
  Controller for handling audio transcription via Groq's Whisper API.

  This controller provides an endpoint for transcribing audio recordings
  to text using Groq's Whisper model. It serves as a secure proxy to the
  Groq API, keeping the API key on the server side.

  ## API Endpoint

  POST /api/transcribe
  - Accepts multipart/form-data with an audio file
  - Returns JSON with the transcribed text

  ## Configuration

  Requires `GROQ_API_KEY` environment variable to be set.
  """
  use CollabCanvasWeb, :controller
  require Logger

  @groq_whisper_url "https://api.groq.com/openai/v1/audio/transcriptions"
  @whisper_model "whisper-large-v3-turbo"

  @doc """
  Transcribes audio to text using Groq's Whisper API.

  Expects a multipart form upload with an "audio" field containing
  the audio file (WAV, MP3, or WebM format).

  Returns JSON response:
  - Success: `%{text: "transcribed text"}`
  - Error: `%{error: "error message"}`
  """
  def transcribe(conn, %{"audio" => audio_upload}) do
    api_key = System.get_env("GROQ_API_KEY")

    if is_nil(api_key) or api_key == "" do
      Logger.error("GROQ_API_KEY not configured")

      conn
      |> put_status(:internal_server_error)
      |> json(%{error: "Transcription service not configured"})
    else
      # Call Groq Whisper API with file path
      case call_whisper_api(audio_upload.path, audio_upload.filename, api_key) do
        {:ok, transcription} ->
          conn
          |> put_status(:ok)
          |> json(%{text: transcription})

        {:error, reason} ->
          Logger.error("Whisper API error: #{inspect(reason)}")

          conn
          |> put_status(:bad_request)
          |> json(%{error: "Transcription failed: #{reason}"})
      end
    end
  end

  def transcribe(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing audio file"})
  end

  # Private functions

  defp call_whisper_api(file_path, filename, api_key) do
    # Read the file content
    {:ok, file_content} = File.read(file_path)

    # Build multipart body manually
    boundary = "------------------------#{:erlang.unique_integer([:positive])}"

    body = [
      "--#{boundary}\r\n",
      "Content-Disposition: form-data; name=\"file\"; filename=\"#{filename}\"\r\n",
      "Content-Type: audio/webm\r\n\r\n",
      file_content,
      "\r\n--#{boundary}\r\n",
      "Content-Disposition: form-data; name=\"model\"\r\n\r\n",
      @whisper_model,
      "\r\n--#{boundary}--\r\n"
    ] |> IO.iodata_to_binary()

    # Make HTTP request to Groq with manual multipart
    case Req.post(@groq_whisper_url,
           auth: {:bearer, api_key},
           headers: [{"content-type", "multipart/form-data; boundary=#{boundary}"}],
           body: body
         ) do
      {:ok, %{status: 200, body: response_body}} when is_binary(response_body) ->
        # Groq returns JSON with "text" field
        case Jason.decode(response_body) do
          {:ok, %{"text" => text}} ->
            {:ok, text}

          {:ok, _} ->
            {:error, "Unexpected response format"}

          {:error, _} ->
            {:error, "Failed to parse response"}
        end

      {:ok, %{status: 200, body: %{"text" => text}}} ->
        # Response already decoded as map
        {:ok, text}

      {:ok, %{status: status, body: body}} ->
        Logger.error("Groq API error: #{status} - #{inspect(body)}")
        {:error, "API returned status #{status}"}

      {:error, reason} ->
        Logger.error("HTTP request failed: #{inspect(reason)}")
        {:error, "Network error"}
    end
  end

  defp get_content_type(filename) do
    cond do
      String.ends_with?(filename, ".wav") -> "audio/wav"
      String.ends_with?(filename, ".mp3") -> "audio/mpeg"
      String.ends_with?(filename, ".webm") -> "audio/webm"
      String.ends_with?(filename, ".m4a") -> "audio/m4a"
      String.ends_with?(filename, ".ogg") -> "audio/ogg"
      true -> "audio/wav"
    end
  end
end
