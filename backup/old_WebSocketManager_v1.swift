//
//  WebSocketManager.swift
//  Frypan NFC Reader
//
//  Created by Claude on 5/9/2025.
//

import Foundation
import Combine
import AVFoundation
import ObjectiveC

// MARK: - Data Extension for Hex String
extension Data {
    init?(hex: String) {
        let len = hex.count / 2
        var data = Data(capacity: len)
        var i = hex.startIndex
        for _ in 0..<len {
            let j = hex.index(i, offsetBy: 2)
            let bytes = hex[i..<j]
            if var num = UInt8(bytes, radix: 16) {
                data.append(&num, count: 1)
            } else {
                return nil
            }
            i = j
        }
        self = data
    }
}

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
    @Published var currentCharacter_id: Int = 3
    
    // MARK: - Private Properties
    private var webSocketTask: URLSessionWebSocketTask?
    private let serverURL: URL
    private var reconnectTimer: Timer?
    private let reconnectDelay: TimeInterval = 3.0
    private var isManuallyDisconnected = false
    
    // MARK: - Audio Properties
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
        
        // 生成唯一連接 ID
        self.connectionId = UUID().uuidString.prefix(8).lowercased()
        print("📱 設備連接 ID: \(self.connectionId)")
        
        // 設置音頻功能
        print("🔧 開始設置音頻功能...")
        setupAudio()
        
        // 設置 MiniMax API
        print("🔧 開始設置 MiniMax API...")
        setupMiniMaxAPI()
    }
    
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
        // 從 Info.plist 獲取 MiniMax API Key
        guard let apiKey = Bundle.main.object(forInfoDictionaryKey: "MINIMAX_API_KEY") as? String,
              !apiKey.isEmpty else {
            print("⚠️ MiniMax API Key 未設置，語音合成功能將不可用")
            return
        }
        
        self.miniMaxAPIKey = apiKey
        print("🔑 MiniMax API Key 已設置: \(apiKey.prefix(20))...")
        print("✅ 簡化版語音功能已準備就緒")
    }
    
    deinit {
        disconnect()
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - WebSocket Connection Management
extension WebSocketManager {
    
    func connect() {
        // 檢查是否已經有連接任務在進行中
        if webSocketTask != nil {
            print("🔌 WebSocket 連接任務已存在，跳過重複連接")
            return
        }
        
        guard !isConnected else {
            print("🔌 WebSocket 已經連接")
            return
        }
        
        print("🔌 連接到 WebSocket: \(serverURL)")
        
        // 重置手動斷開標誌
        isManuallyDisconnected = false
        
        // 清理舊的連接
        webSocketTask?.cancel()
        webSocketTask = nil
        
        // 設置連接中狀態
        DispatchQueue.main.async {
            self.isConnected = false
        }
        updateConnectionStatus("連接中...")
        
        webSocketTask = URLSession.shared.webSocketTask(with: serverURL)
        webSocketTask?.resume()
        
        print("🔌 WebSocket 任務已創建並開始")
        
        // 開始接收消息
        receiveMessage()
        
        // 發送 ping 來測試連接
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if self.webSocketTask != nil {
                self.sendPing()
            }
        }
        
        // 不立即設置為已連接，等待實際的連接確認
    }
    
    func disconnect() {
        // 設置手動斷開標誌，防止自動重連
        isManuallyDisconnected = true
        
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        DispatchQueue.main.async {
            self.isConnected = false
        }
        updateConnectionStatus("已斷開")
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        
        // 清理音頻播放器
        audioPlayer?.stop()
        audioPlayer = nil
    }
    
    private func scheduleReconnect() {
        // 如果用戶手動斷開，不自動重連
        guard !isManuallyDisconnected else {
            return
        }
        
        reconnectTimer?.invalidate()
        
        updateConnectionStatus("3 秒後重新連接...")
        
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: reconnectDelay, repeats: false) { [weak self] _ in
            self?.connect()
        }
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
        // 發送標準的文本消息格式，包含角色 ID
        let character_idToUse = character_id ?? currentCharacter_id
        let message: [String: Any] = [
            "type": "text",
            "text": text,
            "character_id": character_idToUse
        ]
        sendJSONMessage(message)
        print("📤 發送文本到 WebSocket: \(text) (角色ID: \(character_idToUse))")
    }
    
    func sendTextToSpeech(text: String, voiceId: String = "moss_audio_af916082-2e36-11f0-92db-0e8893cbb430", character_id: Int? = nil) {
        // 停止當前播放
        audioPlayer?.stop()
        audioPlayer = nil
        
        let character_idToUse = character_id ?? currentCharacter_id
        let message: [String: Any] = [
            "type": "gemini_chat",
            "text": text,
            "voice_id": voiceId,
            "character_id": character_idToUse,
            "streaming": true,
            "device_id": connectionId
        ]
        
        sendJSONMessage(message)
        print("🎤 發送文本到語音合成: \(text) (角色ID: \(character_idToUse))")
    }
    
    func sendPing() {
        print("📡 發送 ping 測試連接")
        let pingMessage = ["type": "ping"]
        sendJSONMessage(pingMessage)
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
        guard let webSocketTask = webSocketTask else {
            print("❌ WebSocket 任務不存在，無法發送消息")
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
                            print("❌ WebSocket 發送失敗: \(error.localizedDescription)")
                        }
                        self?.updateConnectionStatus("發送失敗")
                    } else {
                        // 發送成功，靜默處理
                        // 只有在發送成功且當前狀態不是已連接時才更新狀態
                        DispatchQueue.main.async {
                            if !(self?.isConnected ?? false) {
                                self?.isConnected = true
                                self?.updateConnectionStatus("已連接")
                            }
                        }
                    }
                }
            } else {
                print("❌ JSON 字符串轉換失敗")
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
        guard let webSocketTask = webSocketTask else { 
            print("❌ receiveMessage: webSocketTask 為 nil")
            return 
        }
        
        webSocketTask.receive { [weak self] result in
            switch result {
            case .success(let message):
                self?.handleMessage(message)
                self?.receiveMessage()
                
            case .failure(let error):
                print("❌ 接收消息失敗: \(error.localizedDescription)")
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
        
        print("📨 收到 WebSocket 消息: \(text.prefix(100))...")
        
        // 解析 JSON 消息
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("❌ JSON 解析失敗: \(text.prefix(50))...")
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
                handleAudioChunk(json)
            } else {
                print("📨 收到未知格式消息")
            }
        }
    }
    
    private func handleTypedMessage(type: String, json: [String: Any]) {
        print("📋 處理消息類型: \(type)")
        
        switch type {
        case "response", "gemini_response":
            print("🤖 處理 Gemini 回應")
            handleGeminiResponse(json)
            
        case "audio_chunk":
            handleAudioChunk(json)
            
        case "minimax_audio_chunk":
            handleAudioChunk(json)
            
        case "audio_complete":
            print("🎯 音頻串流完成")
            
        case "pong":
            print("🏓 收到 pong 回應，連接正常")
            DispatchQueue.main.async {
                self.isConnected = true
                self.updateConnectionStatus("已連接")
            }
            
        case "history":
            if let history = json["history"] as? [[String: Any]] {
                print("📚 收到歷史記錄: \(history.count) 條")
            }
            
        case "error":
            if let errorMessage = json["message"] as? String {
                lastError = "服務器錯誤: \(errorMessage)"
                print("❌ 服務器錯誤: \(errorMessage)")
            }
            
        case "connection", "connection_ack":
            print("🔌 收到連接確認消息")
            DispatchQueue.main.async {
                self.isConnected = true
                self.updateConnectionStatus("已連接")
                print("✅ 連接狀態已設置為已連接，webSocketTask 存在: \(self.webSocketTask != nil)")
            }
            
        default:
            // 靜默處理其他類型消息，避免過多日誌
            break
        }
    }
    
    private func handleGeminiResponse(_ json: [String: Any]) {
        if let response = json["response"] as? String {
            print("🤖 收到 Gemini 回應")
            geminiResponse = response
            
            // 自動觸發語音合成
            triggerTextToSpeech(response)
        }
        if let originalText = json["original_text"] as? String {
            print("📝 原始文本: \(originalText)")
        }
        
        // 重置音頻狀態準備接收新音頻
        audioPlayer?.stop()
        audioPlayer = nil
    }
    
    private func triggerTextToSpeech(_ text: String) {
        guard !text.isEmpty else {
            print("⚠️ 文本為空，跳過語音合成")
            return
        }
        
        guard miniMaxAPIKey != nil else {
            print("⚠️ MiniMax API Key 未設置，跳過語音合成")
            return
        }
        
        print("🎤 開始語音合成: \(text.prefix(50))...")
        
        // 在背景線程中進行語音合成，避免阻塞 UI
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.performTextToSpeech(text)
        }
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
        let errorMessage = error.localizedDescription
        
        // 過濾常見的網絡連接錯誤
        if isNormalWebSocketDisconnectionError(errorMessage) {
            print("🔌 WebSocket 連接正常斷開")
            DispatchQueue.main.async {
                self.isConnected = false
            }
            updateConnectionStatus("已斷開")
            // 不立即設為 nil，讓連接確認消息處理
            return
        }
        
        // 只記錄真正的錯誤
        print("❌ WebSocket 連接錯誤: \(errorMessage)")
        DispatchQueue.main.async {
            self.isConnected = false
            self.lastError = "連接錯誤: \(errorMessage)"
        }
        updateConnectionStatus("斷開連接")
        
        // 只有在手動斷開時才不重連
        if !isManuallyDisconnected {
            webSocketTask = nil
            scheduleReconnect()
        }
    }
    
    private func isNormalWebSocketDisconnectionError(_ errorMessage: String) -> Bool {
        let normalErrors = [
            "Socket is not connected",
            "Connection reset by peer",
            "Broken pipe",
            "cancelled",
            "nw_read_request_report",
            "nw_flow_service_reads",
            "nw_flow_add_write_request",
            "nw_write_request_report",
            "tcp_input",
            "Connection 2: received failure notification",
            "Connection 2: failed to connect",
            "Connection 2: encountered error",
            "Connection 3: received failure notification",
            "Connection 3: failed to connect",
            "Connection 3: encountered error",
            "No output handler",
            "cannot accept write requests",
            "Send failed with error",
            "Receive failed with error",
            "flags=[R]",
            "state=LAST_ACK",
            "state=CLOSED",
            "failed parent-flow",
            "satisfied (Path is satisfied)",
            "interface: en0[802.11]",
            "ipv4, dns, uses wifi",
            "seq=",
            "ack=",
            "win=0",
            "rcv_nxt=",
            "snd_una=",
            "47.89.128.168:443"
        ]
        
        return normalErrors.contains { errorMessage.contains($0) }
    }
}

// MARK: - Audio Management Delegate
// extension WebSocketManager: AudioStreamManagerDelegate {
//     
//     func audioStreamManager(_ manager: AudioStreamManager, didUpdatePlayingState isPlaying: Bool) {
//         DispatchQueue.main.async {
//             self.isPlayingAudio = isPlaying
//         }
//     }
//     
//     func audioStreamManager(_ manager: AudioStreamManager, didUpdateProgress progress: Double) {
//         DispatchQueue.main.async {
//             self.audioProgress = progress
//         }
//     }
//     
//     func audioStreamManager(_ manager: AudioStreamManager, didEncounterError error: String) {
//         DispatchQueue.main.async {
//             self.lastError = error
//         }
//     }
// }

// MARK: - Public Audio Interface
extension WebSocketManager {
    
    func stopAudio() {
        audioPlayer?.stop()
    }
    
    func resetAudioState() {
        audioPlayer?.stop()
        audioPlayer = nil
        geminiResponse = ""
        lastError = nil
    }
    
    func checkConnectionStatus() {
        if webSocketTask != nil && isConnected {
            sendPing()
        } else if !isConnected {
            updateConnectionStatus("未連接")
        }
    }
    
    func resetConnectionState() {
        DispatchQueue.main.async {
            self.isConnected = false
            self.lastError = nil
        }
        updateConnectionStatus("未連接")
    }
    
    // MARK: - MiniMax Text-to-Speech Control
    func speakText(_ text: String) {
        triggerTextToSpeech(text)
    }
    
    func stopSpeech() {
        audioPlayer?.stop()
    }
    
    func pauseSpeech() {
        audioPlayer?.pause()
    }
    
    func resumeSpeech() {
        audioPlayer?.play()
    }
    
    // MARK: - Character Management
    func setCharacter_id(_ character_id: Int) {
        currentCharacter_id = character_id
        print("🎭 設置角色 ID: \(character_id)")
    }
    
    // MARK: - Audio Processing
    private func handleAudioChunk(_ json: [String: Any]) {
        print("🔍 [DEBUG] 收到音頻數據，JSON keys: \(json.keys)")
        
        // 檢查是否為服務器發送的格式：minimax_audio_chunk
        if let messageType = json["type"] as? String, messageType == "minimax_audio_chunk" {
            handleServerMinimaxFormat(json)
        } else {
            // 檢查是否為直接的 MiniMax 格式
            handleDirectMinimaxFormat(json)
        }
    }
    
    private func handleServerMinimaxFormat(_ json: [String: Any]) {
        guard let minimaxResponse = json["minimax_response"] as? [String: Any],
              let data = minimaxResponse["data"] as? [String: Any],
              let audioHex = data["audio"] as? String,
              let status = data["status"] as? Int,
              let audioData = Data(hex: audioHex) else {
            print("❌ 服務器 MiniMax 音頻數據解析失敗")
            return
        }
        
        let chunkIndex = json["chunk_index"] as? Int ?? -1
        print("📦 收到服務器 MiniMax 音頻 chunk \(chunkIndex): \(audioData.count) bytes, status: \(status)")
        
        if status == 1 {
            // 普通音頻塊 - 直接播放
            playAudioData(audioData)
        } else if status == 2 {
            // 最後一個音頻塊 - 合併塊，不播放
            print("🏁 收到最後一個服務器 MiniMax 音頻塊（合併塊，不播放）")
        }
    }
    
    private func handleDirectMinimaxFormat(_ json: [String: Any]) {
        guard let data = json["data"] as? [String: Any],
              let audioHex = data["audio"] as? String,
              let status = data["status"] as? Int,
              let audioData = Data(hex: audioHex) else {
            print("❌ 直接 MiniMax 音頻數據解析失敗")
            return
        }
        
        print("📦 收到直接 MiniMax 音頻: \(audioData.count) bytes, status: \(status)")
        
        if status == 1 {
            // 普通音頻塊 - 直接播放
            playAudioData(audioData)
        } else if status == 2 {
            // 最後一個音頻塊 - 合併塊，不播放
            print("🏁 收到最後一個直接 MiniMax 音頻塊（合併塊，不播放）")
        }
    }
    
    private func playAudioData(_ data: Data) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // 停止當前播放
            self.audioPlayer?.stop()
            self.audioPlayer = nil
            
            print("🔍 音頻數據大小: \(data.count) bytes")
            print("🔍 音頻數據前16字節: \(data.prefix(16).map { String(format: "%02x", $0) }.joined(separator: " "))")
            
            // 檢查音頻數據格式
            if data.count < 44 {
                print("❌ 音頻數據太小，可能不是有效的音頻文件")
                return
            }
            
            // 檢查音頻文件格式（MiniMax 使用 MP3 格式）
            let fileHeader = data.prefix(4)
            let fileSignature = String(data: fileHeader, encoding: .ascii) ?? ""
            print("🔍 音頻文件簽名: \(fileSignature)")
            
            // 檢查 MP3 標識
            if data.count >= 3 {
                let mp3Header = data.prefix(3)
                let mp3Signature = String(data: mp3Header, encoding: .ascii) ?? ""
                print("🔍 MP3 標識: \(mp3Signature)")
            }
            
            // 嘗試不同的音頻格式（優先 MP3，因為 MiniMax 使用 MP3 格式）
            let audioFormats = [
                AVFileType.mp3.rawValue,  // MiniMax 默認格式
                AVFileType.m4a.rawValue,
                AVFileType.wav.rawValue,
                AVFileType.aiff.rawValue
            ]
            
            var player: AVAudioPlayer?
            var successfulFormat: String?
            
            for format in audioFormats {
                do {
                    player = try AVAudioPlayer(data: data, fileTypeHint: format)
                    if player != nil {
                        successfulFormat = format
                        break
                    }
                } catch {
                    print("🔍 格式 \(format) 失敗: \(error.localizedDescription)")
                }
            }
            
            guard let audioPlayer = player else {
                print("❌ 所有音頻格式都失敗，嘗試從文件播放")
                self.playAudioFromFile(data)
                return
            }
            
            self.audioPlayer = audioPlayer
            audioPlayer.volume = 1.0
            audioPlayer.prepareToPlay()
            
            let success = audioPlayer.play()
            if success {
                print("✅ 音頻播放開始，格式: \(successfulFormat ?? "未知")，時長: \(audioPlayer.duration) 秒")
            } else {
                print("❌ 音頻播放失敗")
            }
        }
    }
    
    private func playAudioFromFile(_ data: Data) {
        let fileExtensions = ["mp3", "m4a", "wav", "aiff"]  // 優先 MP3 格式
        let tempDir = FileManager.default.temporaryDirectory
        
        for ext in fileExtensions {
            let tempURL = tempDir.appendingPathComponent("temp_audio.\(ext)")
            
            do {
                try data.write(to: tempURL)
                print("💾 音頻數據已保存到臨時文件: \(tempURL.path)")
                
                self.audioPlayer = try AVAudioPlayer(contentsOf: tempURL)
                guard let player = self.audioPlayer else {
                    print("❌ 從文件創建音頻播放器失敗 (格式: \(ext))")
                    continue
                }
                
                player.volume = 1.0
                player.prepareToPlay()
                
                let success = player.play()
                if success {
                    print("✅ 從文件播放音頻成功，格式: \(ext)，時長: \(player.duration) 秒")
                    
                    // 清理臨時文件
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                        try? FileManager.default.removeItem(at: tempURL)
                    }
                    return
                } else {
                    print("❌ 從文件播放音頻失敗 (格式: \(ext))")
                }
                
            } catch {
                print("❌ 保存音頻文件失敗 (格式: \(ext)): \(error.localizedDescription)")
            }
        }
        
        print("❌ 所有音頻格式都無法播放")
    }
    
    // MARK: - Text to Speech
    private func performTextToSpeech(_ text: String) {
        guard let apiKey = miniMaxAPIKey else {
            print("❌ MiniMax API Key 未設置")
            return
        }
        
        print("🎤 開始調用 MiniMax API...")
        
        // 創建請求
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
        
        // 發送請求
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                print("❌ MiniMax API 請求失敗: \(error.localizedDescription)")
                return
            }
            
            guard let data = data else {
                print("❌ 沒有收到音頻數據")
                return
            }
            
            print("✅ 收到 MiniMax 響應數據: \(data.count) bytes")
            
            // 檢查響應格式
            if let responseString = String(data: data, encoding: .utf8) {
                print("🔍 響應內容: \(responseString.prefix(200))...")
                
                // 嘗試解析 JSON 響應
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    print("🔍 JSON 響應: \(json)")
                    
                    // 檢查是否有錯誤響應
                    if let baseResp = json["base_resp"] as? [String: Any] {
                        if let statusCode = baseResp["status_code"] as? Int,
                           let statusMsg = baseResp["status_msg"] as? String {
                            
                            print("❌ MiniMax API 錯誤: \(statusCode) - \(statusMsg)")
                            
                            // 處理不同的錯誤類型
                            switch statusCode {
                            case 1002: // Rate limit
                                print("⚠️ API 調用頻率過高，請稍後再試")
                                return
                                
                            case 1001: // Invalid request
                                print("❌ 請求格式錯誤")
                                return
                                
                            case 1003: // Authentication failed
                                print("❌ API 認證失敗，請檢查 API Key")
                                return
                                
                            default:
                                print("❌ 未知錯誤: \(statusCode)")
                                return
                            }
                        }
                    }
                    
                    // 檢查是否有音頻數據
                    if let audioData = json["audio"] as? String {
                        print("🔍 找到音頻數據字符串")
                        if let audioBytes = Data(hex: audioData) {
                            print("✅ 解析音頻數據成功: \(audioBytes.count) bytes")
                            self?.playAudioData(audioBytes)
                        } else {
                            print("❌ 音頻數據解析失敗")
                        }
                    } else {
                        print("❌ 響應中沒有找到音頻數據")
                    }
                } else {
                    // 如果不是 JSON，直接嘗試播放
                    print("🔍 響應不是 JSON 格式，直接嘗試播放")
                    self?.playAudioData(data)
                }
            } else {
                print("🔍 響應不是文本格式，直接嘗試播放")
                self?.playAudioData(data)
            }
            
        }.resume()
    }
    
    func getCurrentCharacter_id() -> Int {
        return currentCharacter_id
    }
    
    // MARK: - Debug Methods
    func testSendMessage() {
        print("🧪 測試發送消息...")
        print("🔍 WebSocket 任務狀態: \(webSocketTask != nil ? "存在" : "不存在")")
        print("🔍 連接狀態: \(isConnected ? "已連接" : "未連接")")
        
        // 發送測試消息
        sendText("測試消息", character_id: 1)
    }
    
    func testSendPing() {
        print("🧪 手動測試發送 ping...")
        print("🔍 WebSocket 任務狀態: \(webSocketTask != nil ? "存在" : "不存在")")
        print("🔍 連接狀態: \(isConnected ? "已連接" : "未連接")")
        
        // 直接發送 ping
        sendPing()
    }
    
    func forceConnect() {
        print("🔧 強制重新連接...")
        disconnect()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.connect()
        }
    }
}
