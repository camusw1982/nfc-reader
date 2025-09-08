//
//  WebSocketManager.swift
//  Frypan NFC Reader
//
//  Created by Claude on 5/9/2025.
//

import Foundation
import Combine
import AVFoundation

// MARK: - Data Extension for Hex String (已移除，MiniMax 現在直接返回 MP3 格式)

// MARK: - WebSocket Manager
class WebSocketManager: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    @Published var isConnected = false
    @Published var connectionStatus: String = "未連接"
    @Published var lastError: String?
    @Published var receivedMessages: [String] = []
    @Published var geminiResponse: String = ""
    @Published var currentCharacter_id: Int = 3
    
    // MARK: - Private Properties
    private var webSocketTask: URLSessionWebSocketTask?
    private let serverURL: URL
    private var audioPlayer: AVAudioPlayer?
    private var miniMaxAPIKey: String?
    
    // MARK: - Initialization
    override init() {
        // WebSocket 服務器地址
        if let url = URL(string: "ws://145.79.12.177:10000") {
            self.serverURL = url
        } else {
            self.serverURL = URL(string: "ws://localhost:8080")!
        }
        
        super.init()
        
        setupAudio()
        setupMiniMaxAPI()
    }
    
    deinit {
        disconnect()
    }
    
    // MARK: - Setup Methods
    private func setupAudio() {
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            print("✅ 音頻會話設置成功")
        } catch {
            print("❌ 音頻會話設置失敗: \(error.localizedDescription)")
        }
        #else
        print("✅ 音頻設置完成 (macOS)")
        #endif
    }
    
    private func setupMiniMaxAPI() {
        guard let apiKey = Bundle.main.object(forInfoDictionaryKey: "MINIMAX_API_KEY") as? String,
              !apiKey.isEmpty else {
            print("⚠️ MiniMax API Key 未設置，語音合成功能將不可用")
            return
        }
        
        self.miniMaxAPIKey = apiKey
        print("🔑 MiniMax API Key 已設置")
    }
}

// MARK: - WebSocket Connection
extension WebSocketManager {
    
    func connect() {
        guard !isConnected else {
            print("🔌 WebSocket 已經連接")
            return
        }
        
        print("🔌 連接到 WebSocket: \(serverURL)")
        
        webSocketTask = URLSession.shared.webSocketTask(with: serverURL)
        webSocketTask?.resume()
        
        updateConnectionStatus("連接中...")
        receiveMessage()
        
        // 發送 ping 測試連接
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.sendPing()
        }
    }
    
    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        
        DispatchQueue.main.async {
            self.isConnected = false
        }
        
        updateConnectionStatus("已斷開")
        
        // 清理音頻播放器
        audioPlayer?.stop()
        audioPlayer = nil
    }
    
    private func updateConnectionStatus(_ status: String) {
        DispatchQueue.main.async {
            self.connectionStatus = status
        }
    }
}

// MARK: - Message Sending
extension WebSocketManager {
    
    func sendText(_ text: String, character_id: Int? = nil) {
        let character_idToUse = character_id ?? currentCharacter_id
        let message: [String: Any] = [
            "type": "text",
            "text": text,
            "character_id": character_idToUse
        ]
        sendJSONMessage(message)
        print("📤 發送文本: \(text)")
    }
    
    func sendTextToSpeech(text: String, character_id: Int? = nil) {
        let character_idToUse = character_id ?? currentCharacter_id
        let message: [String: Any] = [
            "type": "gemini_chat",
            "text": text,
            "character_id": character_idToUse,
            "streaming": true
        ]
        
        sendJSONMessage(message)
        print("🎤 發送語音合成請求: \(text)")
    }
    
    func sendPing() {
        let pingMessage = ["type": "ping"]
        sendJSONMessage(pingMessage)
    }
    
    func clearHistory() {
        let clearMessage = ["type": "clear_history"]
        sendJSONMessage(clearMessage)
    }
    
    func getHistory() {
        let historyMessage = ["type": "get_history"]
        sendJSONMessage(historyMessage)
    }
    
    private func sendJSONMessage(_ message: [String: Any]) {
        guard let webSocketTask = webSocketTask else {
            print("❌ WebSocket 未連接")
            lastError = "WebSocket 未連接"
            return
        }
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: message)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                let wsMessage = URLSessionWebSocketTask.Message.string(jsonString)
                webSocketTask.send(wsMessage) { [weak self] error in
                    if let error = error {
                        DispatchQueue.main.async {
                            self?.lastError = "發送失敗: \(error.localizedDescription)"
                            self?.isConnected = false
                        }
                    } else {
                        DispatchQueue.main.async {
                            if !(self?.isConnected ?? false) {
                                self?.isConnected = true
                                self?.updateConnectionStatus("已連接")
                            }
                        }
                    }
                }
            }
        } catch {
            print("❌ JSON 序列化失敗: \(error.localizedDescription)")
            lastError = "數據序列化失敗: \(error.localizedDescription)"
        }
    }
}

// MARK: - Message Receiving
extension WebSocketManager {
    
    private func receiveMessage() {
        guard let webSocketTask = webSocketTask else { return }
        
        webSocketTask.receive { [weak self] result in
            switch result {
            case .success(let message):
                self?.handleMessage(message)
                self?.receiveMessage()
                
            case .failure(let error):
                print("❌ 接收消息失敗: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self?.isConnected = false
                    self?.lastError = "連接錯誤: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            handleTextMessage(text)
        case .data(let data):
            if let text = String(data: data, encoding: .utf8) {
                handleTextMessage(text)
            }
        @unknown default:
            break
        }
    }
    
    private func handleTextMessage(_ text: String) {
        // 添加到消息列表
        receivedMessages.append(text)
        if receivedMessages.count > 50 {
            receivedMessages.removeFirst()
        }
        
        print("📨 收到消息: \(text.prefix(100))...")
        
        // 解析 JSON 消息
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        
        handleJSONMessage(json)
    }
    
    private func handleJSONMessage(_ json: [String: Any]) {
        guard let type = json["type"] as? String else { return }
        
        switch type {
        case "response", "gemini_response":
            handleGeminiResponse(json)
        case "audio_chunk", "minimax_audio_chunk":
            handleAudioChunk(json)
        case "pong":
            DispatchQueue.main.async {
                self.isConnected = true
                self.updateConnectionStatus("已連接")
            }
        case "connection", "connection_ack":
            DispatchQueue.main.async {
                self.isConnected = true
                self.updateConnectionStatus("已連接")
            }
        case "error":
            if let errorMessage = json["message"] as? String {
                lastError = "服務器錯誤: \(errorMessage)"
            }
        default:
            break
        }
    }
    
    private func handleGeminiResponse(_ json: [String: Any]) {
        if let response = json["response"] as? String {
            geminiResponse = response
            triggerTextToSpeech(response)
        }
    }
    
    private func triggerTextToSpeech(_ text: String) {
        guard !text.isEmpty, miniMaxAPIKey != nil else { return }
        
        print("🎤 開始語音合成: \(text.prefix(50))...")
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.performTextToSpeech(text)
        }
    }
}

// MARK: - Audio Processing
extension WebSocketManager {
    
    private func handleAudioChunk(_ json: [String: Any]) {
        print("🔍 收到音頻數據，JSON keys: \(json.keys)")
        
        // MiniMax 現在直接返回 MP3 格式，不再使用 hex 編碼
        var audioData: Data?
        
        // 檢查服務器格式：minimax_audio_chunk
        if let messageType = json["type"] as? String, messageType == "minimax_audio_chunk",
           let minimaxResponse = json["minimax_response"] as? [String: Any],
           let data = minimaxResponse["data"] as? [String: Any] {
            // 直接獲取 MP3 數據
            if let mp3Data = data["audio"] as? Data {
                audioData = mp3Data
            }
        }
        // 檢查直接格式
        else if let data = json["data"] as? [String: Any] {
            // 直接獲取 MP3 數據
            if let mp3Data = data["audio"] as? Data {
                audioData = mp3Data
            }
        }
        
        guard let audio = audioData else {
            print("❌ 無法獲取音頻數據")
            return
        }
        
        print("📦 收到 MP3 音頻數據: \(audio.count) bytes")
        playMP3Audio(audio)
    }
    
    private func playMP3Audio(_ data: Data) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // 停止當前播放
            self.audioPlayer?.stop()
            self.audioPlayer = nil
            
            print("🔍 播放 MP3 音頻數據: \(data.count) bytes")
            
            // 檢查數據大小
            guard data.count > 0 else {
                print("❌ 音頻數據為空")
                return
            }
            
            // MiniMax 直接返回 MP3 格式，直接播放
            do {
                let player = try AVAudioPlayer(data: data, fileTypeHint: AVFileType.mp3.rawValue)
                self.audioPlayer = player
                player.volume = 1.0
                player.prepareToPlay()
                
                if player.play() {
                    print("✅ MP3 音頻播放開始，時長: \(player.duration) 秒")
                } else {
                    print("❌ MP3 音頻播放失敗")
                }
            } catch {
                print("❌ MP3 音頻播放錯誤: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Text to Speech
extension WebSocketManager {
    
    private func performTextToSpeech(_ text: String) {
        guard let apiKey = miniMaxAPIKey else {
            print("❌ MiniMax API Key 未設置")
            return
        }
        
        let url = URL(string: "https://api.minimax.io/v1/text_to_speech")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody: [String: Any] = [
            "text": text,
            "voice_id": "moss_audio_af916082-2e36-11f0-92db-0e8893cbb430",
            "model": "speech-02-turbo",
            "emotion": "neutral"
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            print("❌ 請求體創建失敗: \(error.localizedDescription)")
            return
        }
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                print("❌ MiniMax API 請求失敗: \(error.localizedDescription)")
                return
            }
            
            guard let data = data else {
                print("❌ 沒有收到音頻數據")
                return
            }
            
            // 檢查響應格式
            if let _ = String(data: data, encoding: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                
                // 檢查錯誤響應
                if let baseResp = json["base_resp"] as? [String: Any],
                   let statusCode = baseResp["status_code"] as? Int,
                   let statusMsg = baseResp["status_msg"] as? String {
                    print("❌ MiniMax API 錯誤: \(statusCode) - \(statusMsg)")
                    return
                }
                
                // 檢查音頻數據（現在直接是 MP3 格式）
                if let audioData = json["audio"] as? Data {
                    self?.playMP3Audio(audioData)
                }
            } else {
                // 直接嘗試播放 MP3 數據
                self?.playMP3Audio(data)
            }
        }.resume()
    }
}

// MARK: - Public Interface
extension WebSocketManager {
    
    func stopAudio() {
        audioPlayer?.stop()
    }
    
    func setCharacter_id(_ character_id: Int) {
        currentCharacter_id = character_id
    }
    
    func getCurrentCharacter_id() -> Int {
        return currentCharacter_id
    }
}