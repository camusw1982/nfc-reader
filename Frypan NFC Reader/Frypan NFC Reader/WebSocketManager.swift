//
//  WebSocketManager.swift
//  Frypan NFC Reader
//
//  Created by Claude on 5/9/2025.
//

import Foundation
import Combine
import os.log

// MARK: - WebSocket Manager Protocol
protocol WebSocketManagerProtocol: ObservableObject {
    var isConnected: Bool { get }
    var connectionStatus: String { get }
    var connectionId: String { get }
    var isPlayingAudio: Bool { get }
}

// MARK: - WebSocket Manager
class WebSocketManager: NSObject, ObservableObject, WebSocketManagerProtocol, WebSocketServiceProtocol, MiniMaxWebSocketManagerDelegate {
    
    // MARK: - Published Properties
    @Published var isConnected = false
    @Published var connectionStatus: String = "未連接"
    @Published var lastError: String?
    @Published var receivedMessages: [String] = []
    @Published var isPlayingAudio = false
    @Published var audioProgress: Double = 0.0
    @Published var geminiResponse: String = ""
    @Published var connectionId: String = ""
    @Published var currentCharacterId: Int = 1
    
    // MARK: - Speech Recognizer Reference
    weak var speechRecognizer: SpeechRecognizer?
    
    // MARK: - Private Properties
    private var webSocketTask: URLSessionWebSocketTask?
    private let serverURL: URL
    private var audioManager: AudioManager
    private var miniMaxWebSocketManager: MiniMaxWebSocketManager?
    private var isConnecting = false
    private let logger = Logger(subsystem: "com.frypan.nfc.reader", category: "WebSocket")
    
    // MARK: - Initialization
    override init() {
        // WebSocket 服務器地址
        self.serverURL = Self.createServerURL()
        self.audioManager = AudioManager()
        
        super.init()
        
        // 生成唯一連接 ID
        let newConnectionId = UUID().uuidString.prefix(8).lowercased()
        self.connectionId = newConnectionId
        logger.info("設備連接 ID: \(newConnectionId)")
        
        setupMiniMaxAPI()
        setupAudioBinding()
    }
    
    deinit {
        disconnect()
    }
    
    // MARK: - Setup Methods
    private static func createServerURL() -> URL {
        // 優先從環境變數或配置檔案讀取
        if let customURL = ProcessInfo.processInfo.environment["WEBSOCKET_URL"],
           let url = URL(string: customURL) {
            return url
        }
        
        // 預設地址
        if let url = URL(string: "ws://145.79.12.177:10000") {
            return url
        }
        
        // 備用地址
        return URL(string: "ws://localhost:8080")!
    }
    
    private func setupAudioBinding() {
        // 綁定音頻管理器的狀態到 WebSocket 管理器
        audioManager.$isPlayingAudio
            .assign(to: &$isPlayingAudio)
        
        audioManager.$audioProgress
            .assign(to: &$audioProgress)
    }
    
    private func setupMiniMaxAPI() {
        guard let apiKey = Bundle.main.object(forInfoDictionaryKey: "MINIMAX_API_KEY") as? String,
              !apiKey.isEmpty else {
            logger.warning("MiniMax API Key 未設置，語音合成功能將不可用")
            return
        }
        
        // 初始化 MiniMax WebSocket 管理器
        self.miniMaxWebSocketManager = MiniMaxWebSocketManager(apiKey: apiKey)
        self.miniMaxWebSocketManager?.delegate = self
        logger.info("MiniMax WebSocket 管理器已初始化")
    }
}

// MARK: - WebSocket Connection
extension WebSocketManager {
    
    func connect() {
        guard !isConnected && !isConnecting else {
            logger.info("WebSocket 已經連接或正在連接中")
            return
        }
        
        logger.info("連接到 WebSocket: \(self.serverURL)")
        
        // 設置連接狀態
        isConnecting = true
        
        // 先斷開現有連接（如果有的話）
        if webSocketTask != nil {
            webSocketTask?.cancel(with: .goingAway, reason: nil)
            webSocketTask = nil
        }
        
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
        
        // 斷開 MiniMax WebSocket 連接
        miniMaxWebSocketManager?.disconnect()
        
        DispatchQueue.main.async {
            self.isConnected = false
            self.isConnecting = false
        }
        
        updateConnectionStatus("已斷開")
        
        // 停止音頻播放
        audioManager.stopAudio()
    }
    
    private func updateConnectionStatus(_ status: String) {
        DispatchQueue.main.async {
            self.connectionStatus = status
        }
    }
}

// MARK: - Message Sending
extension WebSocketManager {
    
    func sendText(_ text: String, characterId: Int? = nil) {
        let characterIdToUse = characterId ?? currentCharacterId
        let message: [String: Any] = [
            "type": "text",
            "text": text,
            "character_id": characterIdToUse
        ]
        sendJSONMessage(message)
        logger.info("發送文本: \(text)")
    }
    
    func sendTextToSpeech(text: String, characterId: Int? = nil) {
        let characterIdToUse = characterId ?? currentCharacterId
        let message: [String: Any] = [
            "type": "gemini_chat",
            "text": text,
            "character_id": characterIdToUse,
            "streaming": true
        ]
        
        sendJSONMessage(message)
        logger.info("發送語音合成請求: \(text)")
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
            logger.error("WebSocket 未連接")
            DispatchQueue.main.async {
                self.lastError = "WebSocket 未連接"
            }
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
                                self?.isConnecting = false
                                self?.updateConnectionStatus("已連接")
                            }
                        }
                    }
                }
            }
        } catch {
            logger.error("JSON 序列化失敗: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.lastError = "數據序列化失敗: \(error.localizedDescription)"
            }
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
                self?.logger.error("接收消息失敗: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self?.isConnected = false
                    self?.isConnecting = false
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
        DispatchQueue.main.async {
            self.receivedMessages.append(text)
            if self.receivedMessages.count > 50 {
                self.receivedMessages.removeFirst()
            }
        }
        
        logger.info("收到消息: \(text.prefix(100))...")
        
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
                self.isConnecting = false
                self.updateConnectionStatus("已連接")
            }
        case "connection", "connection_ack":
            DispatchQueue.main.async {
                self.isConnected = true
                self.isConnecting = false
                self.updateConnectionStatus("已連接")
            }
        case "error":
            if let errorMessage = json["message"] as? String {
                DispatchQueue.main.async {
                    self.lastError = "服務器錯誤: \(errorMessage)"
                }
            }
        default:
            break
        }
    }
    
    private func handleGeminiResponse(_ json: [String: Any]) {
        if let response = json["response"] as? String {
            DispatchQueue.main.async {
                self.geminiResponse = response
                
                // 添加 AI 回應到聊天消息列表
                let aiMessage = ChatMessage(text: response, isUser: false, timestamp: Date(), isError: false)
                self.speechRecognizer?.messages.append(aiMessage)
                
                print("🤖 添加 AI 回應到聊天: \(response)")
            }
            triggerTextToSpeech(response)
        }
    }
    
    private func triggerTextToSpeech(_ text: String) {
        guard !text.isEmpty, let miniMaxManager = miniMaxWebSocketManager else { 
            logger.warning("MiniMax WebSocket 管理器未初始化")
            return 
        }
        
        // 使用 MiniMax WebSocket 管理器進行文本轉語音
        miniMaxManager.textToSpeech(text)
    }
}

// MARK: - Audio Processing
extension WebSocketManager {
    
    private func handleAudioChunk(_ json: [String: Any]) {
        logger.info("收到音頻數據，JSON keys: \(json.keys)")
        
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
            logger.error("無法獲取音頻數據")
            return
        }
        
        logger.info("收到 MP3 音頻數據: \(audio.count) bytes")
        playMP3Audio(audio)
    }
    
}

// MARK: - MiniMax WebSocket Manager Delegate
extension WebSocketManager {
    
    func playMP3Audio(_ data: Data) {
        audioManager.playMP3Audio(data)
    }
}

// MARK: - Public Interface
extension WebSocketManager {
    
    func stopAudio() {
        audioManager.stopAudio()
    }
    
    func stopSpeech() {
        stopAudio()
    }
    
    func setCharacterId(_ characterId: Int) {
        DispatchQueue.main.async {
            self.currentCharacterId = characterId
        }
    }
    
    func getCurrentCharacterId() -> Int {
        return currentCharacterId
    }
}