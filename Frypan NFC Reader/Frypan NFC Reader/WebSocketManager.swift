//
//  WebSocketManager.swift
//  Frypan NFC Reader
//
//  Created by Claude on 5/9/2025.
//

import Foundation
import Combine
import AVFoundation

// MARK: - WebSocket Manager
class WebSocketManager: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    @Published var isConnected = false
    @Published var connectionStatus: String = "未連接"
    @Published var lastError: String?
    @Published var receivedMessages: [String] = []
    @Published var isPlayingAudio = false
    @Published var audioProgress: Double = 0.0
    @Published var geminiResponse: String = ""
    @Published var connectionId: String = ""
    
    // MARK: - Private Properties
    private var webSocketTask: URLSessionWebSocketTask?
    private let serverURL: URL
    private var reconnectTimer: Timer?
    private let reconnectDelay: TimeInterval = 3.0
    
    // MARK: - Audio Properties
    private let audioManager = AudioStreamManager()
    
    // MARK: - Initialization
    override init() {
        // WebSocket 服務器地址
        if let url = URL(string: "ws://145.79.12.177:10000") {
            self.serverURL = url
        } else {
            self.serverURL = URL(string: "ws://localhost:8080")!
        }
        
        super.init()
        
        // 生成唯一連接 ID
        self.connectionId = UUID().uuidString.prefix(8).lowercased()
        print("📱 設備連接 ID: \(self.connectionId)")
        
        // 設置音頻管理器
        setupAudioManager()
    }
    
    private func setupAudioManager() {
        audioManager.delegate = self
        audioManager.setup()
    }
    
    deinit {
        disconnect()
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - WebSocket Connection Management
extension WebSocketManager {
    
    func connect() {
        guard !isConnected else {
            print("WebSocket 已經連接")
            return
        }
        
        print("🔌 連接到 WebSocket: \(serverURL)")
        
        // 清理舊的連接
        webSocketTask?.cancel()
        webSocketTask = nil
        
        webSocketTask = URLSession.shared.webSocketTask(with: serverURL)
        webSocketTask?.resume()
        
        isConnected = true
        updateConnectionStatus("已連接")
        
        receiveMessage()
    }
    
    func disconnect() {
        print("🔌 斷開 WebSocket 連接")
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        DispatchQueue.main.async {
            self.isConnected = false
            self.updateConnectionStatus("已斷開")
        }
        reconnectTimer?.invalidate()
        reconnectTimer = nil
    }
    
    private func scheduleReconnect() {
        reconnectTimer?.invalidate()
        
        DispatchQueue.main.async {
            self.updateConnectionStatus("3 秒後重新連接...")
        }
        
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: reconnectDelay, repeats: false) { [weak self] _ in
            self?.connect()
        }
    }
    
    private func updateConnectionStatus(_ status: String) {
        connectionStatus = status
        print("📊 連接狀態: \(status)")
    }
}

// MARK: - Message Sending
extension WebSocketManager {
    
    func sendText(_ text: String) {
        guard let webSocketTask = webSocketTask else {
            lastError = "WebSocket 未連接"
            return
        }
        
        print("📤 發送文本到 WebSocket: \(text)")
        
        let message = URLSessionWebSocketTask.Message.string(text)
        webSocketTask.send(message) { [weak self] error in
            if let error = error {
                DispatchQueue.main.async {
                    self?.lastError = "發送失敗: \(error.localizedDescription)"
                    print("❌ WebSocket 發送失敗: \(error.localizedDescription)")
                }
            } else {
                print("✅ WebSocket 發送成功")
                DispatchQueue.main.async {
                    if !(self?.isConnected ?? false) {
                        self?.isConnected = true
                        self?.updateConnectionStatus("已連接")
                    }
                }
            }
        }
    }
    
    func sendTextToSpeech(text: String, voiceId: String = "moss_audio_af916082-2e36-11f0-92db-0e8893cbb430") {
        audioManager.resetState()
        
        let message: [String: Any] = [
            "type": "gemini_to_speech",
            "text": text,
            "voice_id": voiceId,
            "streaming": true,
            "device_id": connectionId
        ]
        
        sendJSONMessage(message)
        print("🎤 發送文本到語音合成: \(text)")
    }
    
    func sendDirectTextToSpeech(text: String, voiceId: String = "moss_audio_af916082-2e36-11f0-92db-0e8893cbb430") {
        audioManager.resetState()
        
        let message: [String: Any] = [
            "type": "text_to_speech",
            "text": text,
            "voice_id": voiceId,
            "streaming": true,
            "device_id": connectionId
        ]
        
        sendJSONMessage(message)
        print("🎤 發送直接文本到語音合成: \(text)")
    }
    
    func sendPing() {
        let pingMessage = ["type": "ping"]
        sendJSONMessage(pingMessage)
        print("📤 發送 ping")
    }
    
    func clearHistory() {
        let clearMessage = ["type": "clear_history"]
        sendJSONMessage(clearMessage)
        print("📤 發送 clear_history")
    }
    
    func getHistory() {
        let historyMessage = ["type": "get_history"]
        sendJSONMessage(historyMessage)
        print("📤 發送 get_history")
    }
    
    private func sendJSONMessage(_ message: [String: Any]) {
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: message)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                sendText(jsonString)
            }
        } catch {
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
                DispatchQueue.main.async {
                    self?.handleConnectionError(error)
                }
            }
        }
    }
    
    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            DispatchQueue.main.async { [weak self] in
                self?.handleTextMessage(text)
            }
            
        case .data(let data):
            DispatchQueue.main.async { [weak self] in
                if let text = String(data: data, encoding: .utf8) {
                    self?.handleTextMessage(text)
                }
            }
            
        @unknown default:
            print("⚠️ 未知的 WebSocket 消息類型")
        }
    }
    
    private func handleTextMessage(_ text: String) {
        // 添加到消息列表
        receivedMessages.append(text)
        if receivedMessages.count > 50 {
            receivedMessages.removeFirst()
        }
        
        // 解析 JSON 消息
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("❌ JSON 解析失敗")
            return
        }
        
        handleJSONMessage(json)
    }
    
    private func handleJSONMessage(_ json: [String: Any]) {
        if let type = json["type"] as? String {
            handleTypedMessage(type: type, json: json)
        } else {
            // 檢查是否為音頻數據
            if isAudioMessage(json) {
                audioManager.handleAudioChunk(json)
            } else {
                print("📨 收到未知格式消息")
            }
        }
    }
    
    private func handleTypedMessage(type: String, json: [String: Any]) {
        switch type {
        case "response", "gemini_response":
            handleGeminiResponse(json)
            
        case "audio_chunk":
            audioManager.handleAudioChunk(json)
            
        case "minimax_audio_chunk":
            audioManager.handleAudioChunk(json)
            
        case "audio_complete":
            print("🎯 音頻串流完成")
            
        case "pong":
            print("🏓 收到服務器 pong 響應")
            isConnected = true
            updateConnectionStatus("已連接")
            
        case "history":
            if let history = json["history"] as? [[String: Any]] {
                print("📚 收到歷史記錄: \(history.count) 條")
            }
            
        case "error":
            if let errorMessage = json["message"] as? String {
                lastError = "服務器錯誤: \(errorMessage)"
                print("❌ 服務器錯誤: \(errorMessage)")
            }
            
        case "connection_ack":
            print("✅ 服務器確認連接")
            isConnected = true
            updateConnectionStatus("已連接")
            
        default:
            print("📨 收到其他類型消息: \(type)")
        }
    }
    
    private func handleGeminiResponse(_ json: [String: Any]) {
        if let response = json["response"] as? String {
            print("🤖 收到 Gemini 回應")
            geminiResponse = response
        }
        if let originalText = json["original_text"] as? String {
            print("📝 原始文本: \(originalText)")
        }
        
        // 重置音頻狀態準備接收新音頻
        audioManager.resetState()
    }
    
    private func isAudioMessage(_ json: [String: Any]) -> Bool {
        // 檢查服務器發送的 MiniMax 格式
        if let messageType = json["type"] as? String, messageType == "minimax_audio_chunk" {
            return true
        }
        
        // 檢查直接的 MiniMax 格式
        if let data = json["data"] as? [String: Any],
           data["audio"] is String {
            return true
        }
        
        return false
    }
    
    private func handleConnectionError(_ error: Error) {
        print("❌ WebSocket 連接錯誤: \(error.localizedDescription)")
        DispatchQueue.main.async {
            self.isConnected = false
            self.lastError = "連接錯誤: \(error.localizedDescription)"
            self.updateConnectionStatus("連接斷開")
        }
        
        webSocketTask = nil
        scheduleReconnect()
    }
}

// MARK: - Audio Management Delegate
extension WebSocketManager: AudioStreamManagerDelegate {
    
    func audioStreamManager(_ manager: AudioStreamManager, didUpdatePlayingState isPlaying: Bool) {
        DispatchQueue.main.async {
            self.isPlayingAudio = isPlaying
        }
    }
    
    func audioStreamManager(_ manager: AudioStreamManager, didUpdateProgress progress: Double) {
        DispatchQueue.main.async {
            self.audioProgress = progress
        }
    }
    
    func audioStreamManager(_ manager: AudioStreamManager, didEncounterError error: String) {
        DispatchQueue.main.async {
            self.lastError = error
        }
    }
}

// MARK: - Public Audio Interface
extension WebSocketManager {
    
    func stopAudio() {
        audioManager.stopAudio()
    }
    
    func resetAudioState() {
        audioManager.resetState()
        geminiResponse = ""
        lastError = nil
    }
    
    func checkConnectionStatus() {
        if webSocketTask != nil {
            sendPing()
        } else if !isConnected {
            connect()
        }
    }
    
    func resetConnectionState() {
        DispatchQueue.main.async {
            self.isConnected = false
            self.updateConnectionStatus("未連接")
            self.lastError = nil
        }
    }
}
