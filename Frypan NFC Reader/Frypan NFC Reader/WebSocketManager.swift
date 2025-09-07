//
//  WebSocketManager.swift
//  Frypan NFC Reader
//
//  Created by Claude on 5/9/2025.
//

import Foundation
import Combine
import AVFoundation

// MARK: - MiniMax WebSocket 管理
class MiniMaxWebSocketManager: NSObject {
    private var webSocketTask: URLSessionWebSocketTask?
    private var audioChunks: [String] = []
    private var isProcessingRequest = false
    private var isConnected = false
    private var isConnecting = false
    private let apiKey: String
    private let baseURL = "wss://api.minimax.io/ws/v1/t2a_v2"
    
    weak var delegate: WebSocketManager?
    
    init(apiKey: String) {
        self.apiKey = apiKey
        super.init()
    }
    
    func textToSpeech(_ text: String) {
        guard !isProcessingRequest else { 
            print("⚠️ MiniMax 正在處理其他請求，請稍後再試")
            return 
        }
        
        // 每次語音合成都需要建立新的連接
        print("🎤 開始語音合成: \(text.prefix(50))...")
        DispatchQueue.main.async {
            self.isProcessingRequest = true
        }
        audioChunks.removeAll()
        
        // 建立新連接並處理語音合成
        connectAndProcessText(text)
    }
    
    private func connectAndProcessText(_ text: String) {
        guard let url = URL(string: baseURL) else { 
            print("❌ MiniMax 無效的 WebSocket URL")
            DispatchQueue.main.async {
                self.isProcessingRequest = false
            }
            return 
        }
        
        DispatchQueue.main.async {
            self.isConnecting = true
        }
        print("🔌 MiniMax 正在建立 WebSocket 連接...")
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        webSocketTask = URLSession.shared.webSocketTask(with: request)
        webSocketTask?.resume()
        
        // 設置接收消息的處理
        receiveMessage()
        
        // 等待連接建立後發送任務開始
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.sendTaskStart()
            
            // 再等待一下後發送文本
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.sendTaskContinue(text: text)
            }
        }
    }
    
    
    private func receiveMessage() {
        guard let webSocketTask = webSocketTask else { return }
        
        webSocketTask.receive { [weak self] result in
            switch result {
            case .success(let message):
                self?.handleMessage(message)
                self?.receiveMessage()
            case .failure(let error):
                print("❌ MiniMax WebSocket 錯誤: \(error.localizedDescription)")
                // 連接錯誤時重置狀態
                DispatchQueue.main.async {
                    self?.isConnected = false
                    self?.isConnecting = false
                    self?.isProcessingRequest = false
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
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let event = json["event"] as? String else { return }
        
        switch event {
        case "connected_success":
            print("✅ MiniMax 連接成功")
            DispatchQueue.main.async {
                self.isConnected = true
                self.isConnecting = false
            }
            
        case "task_started":
            print("🚀 MiniMax 任務開始")
            
        case "task_continued":
            // 處理音頻數據
            if let data = json["data"] as? [String: Any],
               let audioHex = data["audio"] as? String, !audioHex.isEmpty {
                audioChunks.append(audioHex)
                // print("🎵 MiniMax 收到音頻塊: \(audioHex.count) 字符")
            }
            
            // 檢查是否為最後一個塊
            if let isFinal = json["is_final"] as? Bool, isFinal {
                print("✅ MiniMax 音頻數據接收完成")
                processCompleteAudio()
                return
            }
            
        case "task_finished":
            print("🏁 MiniMax 任務完成")
            DispatchQueue.main.async {
                self.isProcessingRequest = false
            }
            // 任務完成後斷開連接（按照 MiniMax API 規範）
            disconnect()
            
        case "task_failed":
            print("❌ MiniMax 任務失敗")
            DispatchQueue.main.async {
                self.isProcessingRequest = false
            }
            if let baseResp = json["base_resp"] as? [String: Any],
               let statusCode = baseResp["status_code"] as? Int,
               let statusMsg = baseResp["status_msg"] as? String {
                print("❌ MiniMax API 錯誤: \(statusCode) - \(statusMsg)")
            }
            // 任務失敗後斷開連接
            disconnect()
            
        default:
            print("⚠️ MiniMax 未知事件: \(event)")
            break
        }
    }
    
    private func processCompleteAudio() {
        let combinedHexAudio = audioChunks.joined()
        guard let audioData = hexStringToData(combinedHexAudio) else { 
            print("❌ MiniMax 音頻數據轉換失敗")
            DispatchQueue.main.async {
                self.isProcessingRequest = false
            }
            disconnect()
            return 
        }
        
        print("🎵 MiniMax 音頻數據處理完成: \(audioData.count) bytes")
        
        DispatchQueue.main.async {
            self.delegate?.playMP3Audio(audioData)
        }
        
        // 發送 task_finish 事件（按照 MiniMax API 規範）
        sendTaskFinish()
        audioChunks.removeAll()
    }
    
    private func sendTaskStart() {
        let message: [String: Any] = [
            "event": "task_start",
            "model": "speech-02-turbo",
            "language_boost": "Chinese,Yue",
            "voice_setting": [
                "voice_id": "moss_audio_af916082-2e36-11f0-92db-0e8893cbb430",
                "speed": 1,
                "vol": 1,
                "pitch": 0
            ],
            "pronunciation_dict": [:],
            "audio_setting": [
                "sample_rate": 32000,
                "bitrate": 128000,
                "format": "mp3",
                "channel": 1
            ]
        ]
        sendJSONMessage(message)
    }
    
    private func sendTaskContinue(text: String) {
        let message: [String: Any] = [
            "event": "task_continue",
            "text": text
        ]
        sendJSONMessage(message)
    }
    
    private func sendTaskFinish() {
        let message = ["event": "task_finish"]
        sendJSONMessage(message)
    }
    
    private func sendJSONMessage(_ message: [String: Any]) {
        guard let webSocketTask = webSocketTask else { 
            print("❌ MiniMax WebSocket 未連接，無法發送消息")
            return 
        }
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: message)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                let wsMessage = URLSessionWebSocketTask.Message.string(jsonString)
                webSocketTask.send(wsMessage) { [weak self] error in
                    if let error = error {
                        print("❌ MiniMax 消息發送失敗: \(error.localizedDescription)")
                        // 發送失敗時重置連接狀態
                        DispatchQueue.main.async {
                            self?.isConnected = false
                            self?.isProcessingRequest = false
                        }
                    }
                }
            }
        } catch {
            print("❌ MiniMax JSON 序列化失敗: \(error.localizedDescription)")
        }
    }
    
    private func hexStringToData(_ hexString: String) -> Data? {
        // 使用更簡單的方法將 hex 字符串轉換為 Data
        guard hexString.count % 2 == 0 else {
            print("❌ MiniMax 音頻 hex 字符串長度不是偶數")
            return nil
        }
        
        var data = Data()
        var index = hexString.startIndex
        
        while index < hexString.endIndex {
            let nextIndex = hexString.index(index, offsetBy: 2)
            let byteString = String(hexString[index..<nextIndex])
            
            if let byte = UInt8(byteString, radix: 16) {
                data.append(byte)
            } else {
                print("❌ MiniMax 音頻 hex 字符串包含無效字符: \(byteString)")
                return nil
            }
            
            index = nextIndex
        }
        
        print("✅ MiniMax 音頻 hex 轉換成功: \(hexString.count) 字符 -> \(data.count) bytes")
        return data
    }
    
    func disconnect() {
        print("🔌 MiniMax 斷開 WebSocket 連接")
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        DispatchQueue.main.async {
            self.isConnected = false
            self.isConnecting = false
            self.isProcessingRequest = false
        }
        audioChunks.removeAll()
    }
    
}

// MARK: - WebSocket Manager Protocol
protocol WebSocketManagerProtocol: ObservableObject {
    var isConnected: Bool { get }
    var connectionStatus: String { get }
    var connectionId: String { get }
    var isPlayingAudio: Bool { get }
}

// MARK: - Data Extension for Hex String (已移除，MiniMax 現在直接返回 MP3 格式)

// MARK: - WebSocket Manager
class WebSocketManager: NSObject, ObservableObject, WebSocketManagerProtocol {
    
    // MARK: - Published Properties
    @Published var isConnected = false
    @Published var connectionStatus: String = "未連接"
    @Published var lastError: String?
    @Published var receivedMessages: [String] = []
    @Published var isPlayingAudio = false
    @Published var audioProgress: Double = 0.0
    @Published var geminiResponse: String = ""
    @Published var connectionId: String = ""
    @Published var currentCharacterId: Int = 3
    
    // MARK: - Private Properties
    private var webSocketTask: URLSessionWebSocketTask?
    private let serverURL: URL
    private var audioPlayer: AVAudioPlayer?
    private var miniMaxWebSocketManager: MiniMaxWebSocketManager?
    private var isConnecting = false
    
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
        let newConnectionId = UUID().uuidString.prefix(8).lowercased()
        self.connectionId = newConnectionId
        print("📱 設備連接 ID: \(newConnectionId)")
        
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
        
        // 初始化 MiniMax WebSocket 管理器
        self.miniMaxWebSocketManager = MiniMaxWebSocketManager(apiKey: apiKey)
        self.miniMaxWebSocketManager?.delegate = self
        print("🔑 MiniMax WebSocket 管理器已初始化")
    }
}

// MARK: - WebSocket Connection
extension WebSocketManager {
    
    func connect() {
        guard !isConnected && !isConnecting else {
            print("🔌 WebSocket 已經連接或正在連接中")
            return
        }
        
        print("🔌 連接到 WebSocket: \(serverURL)")
        
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
    
    func sendText(_ text: String, characterId: Int? = nil) {
        let characterIdToUse = characterId ?? currentCharacterId
        let message: [String: Any] = [
            "type": "text",
            "text": text,
            "character_id": characterIdToUse
        ]
        sendJSONMessage(message)
        print("📤 發送文本: \(text)")
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
            print("❌ JSON 序列化失敗: \(error.localizedDescription)")
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
                print("❌ 接收消息失敗: \(error.localizedDescription)")
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
            }
            triggerTextToSpeech(response)
        }
    }
    
    private func triggerTextToSpeech(_ text: String) {
        guard !text.isEmpty, let miniMaxManager = miniMaxWebSocketManager else { 
            print("⚠️ MiniMax WebSocket 管理器未初始化")
            return 
        }
        
        // print("🎤 開始語音合成: \(text.prefix(50))...")
        
        // 使用 MiniMax WebSocket 管理器進行文本轉語音
        miniMaxManager.textToSpeech(text)
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
    
}

// MARK: - MiniMax WebSocket Manager Delegate
extension WebSocketManager {
    
    func playMP3Audio(_ data: Data) {
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
                    self.isPlayingAudio = true
                } else {
                    print("❌ MP3 音頻播放失敗")
                    self.isPlayingAudio = false
                }
            } catch {
                print("❌ MP3 音頻播放錯誤: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Public Interface
extension WebSocketManager {
    
    func stopAudio() {
        DispatchQueue.main.async { [weak self] in
            self?.audioPlayer?.stop()
            self?.isPlayingAudio = false
            self?.audioProgress = 0.0
        }
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