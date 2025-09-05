# iPhone App WebSocket Integration Guide

## Overview
Your iPhone app can now connect to the WebSocket server to get both text responses from Gemini and audio responses from MiniMax TTS.

## WebSocket Connection
```swift
let url = URL(string: "ws://145.79.12.177:10000")!
let webSocketTask = URLSession.shared.webSocketTask(with: url)
```

## Message Types

### 1. Text to Speech (Direct)
Send text directly to MiniMax for speech synthesis:
```json
{
  "type": "text_to_speech",
  "text": "你好，我想聽呢句說話",
  "voice_id": "moss_audio_af916082-2e36-11f0-92db-0e8893cbb430",
  "streaming": true
}
```

### 2. Gemini to Speech (Recommended)
Send text to Gemini first, then convert the response to speech:
```json
{
  "type": "gemini_to_speech",
  "text": "請問今日天氣點樣？",
  "voice_id": "moss_audio_af916082-2e36-11f0-92db-0e8893cbb430",
  "streaming": true
}
```

### 3. Text Only (No Audio)
Get only text response from Gemini:
```json
{
  "type": "text",
  "text": "你好"
}
```

## Server Response Types

### 1. Gemini Response (Text)
```json
{
  "type": "gemini_response",
  "original_text": "你的訊息",
  "response": "Gemini 的回應",
  "timestamp": 1634567890.123
}
```

### 2. Audio Chunk
```json
{
  "type": "audio_chunk",
  "chunk_index": 0,
  "total_chunks": 4,
  "audio_data": "base64_encoded_audio_data",
  "timestamp": 1634567890.456
}
```

### 3. Audio Complete
```json
{
  "type": "audio_complete",
  "timestamp": 1634567890.789
}
```

## iPhone App Implementation

### Swift Code Example

```swift
import UIKit
import AVFoundation

class WebSocketAudioPlayer: NSObject, URLSessionWebSocketDelegate {
    private var webSocketTask: URLSessionWebSocketTask?
    private var audioPlayer: AVAudioPlayer?
    private var audioChunks: [Data] = []
    private var expectedChunks: Int = 0
    
    func connect() {
        guard let url = URL(string: "ws://145.79.12.177:10000") else { return }
        
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: OperationQueue())
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()
        
        // Start receiving messages
        receiveMessage()
    }
    
    func sendTextToSpeech(text: String) {
        let message: [String: Any] = [
            "type": "gemini_to_speech",
            "text": text,
            "voice_id": "moss_audio_af916082-2e36-11f0-92db-0e8893cbb430",
            "streaming": true
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: message)
            webSocketTask?.send(.data(jsonData)) { error in
                if let error = error {
                    print("Error sending message: \(error)")
                }
            }
        } catch {
            print("Error encoding message: \(error)")
        }
    }
    
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                self?.handleMessage(message)
                self?.receiveMessage() // Continue receiving
            case .failure(let error):
                print("Error receiving message: \(error)")
            }
        }
    }
    
    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .data(let data):
            handleDataMessage(data)
        case .string(let text):
            handleStringMessage(text)
        @unknown default:
            break
        }
    }
    
    private func handleStringMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        
        if let type = json["type"] as? String {
            switch type {
            case "gemini_response":
                if let response = json["response"] as? String {
                    print("Gemini response: \(response)")
                    // Update UI with text response
                }
                
            case "audio_chunk":
                handleAudioChunk(json)
                
            case "audio_complete":
                playAudio()
                
            case "error":
                if let errorMessage = json["message"] as? String {
                    print("Error: \(errorMessage)")
                }
                
            default:
                break
            }
        }
    }
    
    private func handleDataMessage(_ data: Data) {
        // Handle binary data if needed
    }
    
    private func handleAudioChunk(_ json: [String: Any]) {
        guard let audioDataBase64 = json["audio_data"] as? String,
              let chunkIndex = json["chunk_index"] as? Int,
              let totalChunks = json["total_chunks"] as? Int,
              let audioData = Data(base64Encoded: audioDataBase64) else {
            return
        }
        
        // Store audio chunk
        audioChunks.append(audioData)
        expectedChunks = totalChunks
        
        print("Received audio chunk \(chunkIndex)/\(totalChunks)")
    }
    
    private func playAudio() {
        guard audioChunks.count == expectedChunks else {
            print("Waiting for more audio chunks...")
            return
        }
        
        // Combine all audio chunks
        let combinedAudioData = audioChunks.reduce(Data()) { $0 + $1 }
        
        do {
            audioPlayer = try AVAudioPlayer(data: combinedAudioData)
            audioPlayer?.delegate = self
            audioPlayer?.play()
            
            print("Playing audio, size: \(combinedAudioData.count) bytes")
            
        } catch {
            print("Error playing audio: \(error)")
        }
        
        // Reset for next audio
        audioChunks.removeAll()
        expectedChunks = 0
    }
}

extension WebSocketAudioPlayer: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        print("Audio playback finished")
    }
}
```

## Audio Playback Setup

Add this to your AppDelegate or SceneDelegate:

```swift
import AVFoundation

func setupAudioSession() {
    do {
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try AVAudioSession.sharedInstance().setActive(true)
    } catch {
        print("Failed to setup audio session: \(error)")
    }
}
```

## Available Voice IDs

- Default: `"moss_audio_af916082-2e36-11f0-92db-0e8893cbb430"`
- You can request additional voice IDs from MiniMax

## Audio Format

- Format: MP3
- Sample Rate: 32000 Hz
- Bitrate: 128 kbps
- Channels: 1 (Mono)

## Error Handling

Common errors and solutions:

1. **Connection Error**: Check network connectivity
2. **Audio Decode Error**: Ensure proper base64 decoding
3. **Playback Error**: Check AVAudioSession configuration

## Performance Tips

1. Use streaming mode for better performance
2. Cache frequently used audio responses
3. Implement proper audio session management
4. Handle network interruptions gracefully

## Testing

Use the provided test script to verify the server functionality:
```bash
python test_websocket.py
```

This will show you the exact flow of messages and audio chunks.