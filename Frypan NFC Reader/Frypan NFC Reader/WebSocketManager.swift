//
//  WebSocketManager.swift
//  Frypan NFC Reader
//
//  Created by Claude on 5/9/2025.
//

import Foundation
import Combine
import AVFoundation

class WebSocketManager: NSObject, ObservableObject {
    @Published var isConnected = false
    @Published var connectionStatus: String = "未連接"
    @Published var lastError: String?
    @Published var receivedMessages: [String] = []
    
    // 音頻播放相關
    @Published var isPlayingAudio = false
    @Published var audioProgress: Double = 0.0
    @Published var geminiResponse: String = ""
    @Published var connectionId: String = ""
    
    private var webSocketTask: URLSessionWebSocketTask?
    private let serverURL: URL
    private var reconnectTimer: Timer?
    private let reconnectDelay: TimeInterval = 3.0
    
    // 音頻播放相關
    private var audioPlayer: AVAudioPlayer?
    private var audioChunks: [Data] = []
    private var expectedChunks: Int = 0
    private var audioSession: AVAudioSession?
    
    override init() {
        // WebSocket 服務器地址
        if let url = URL(string: "ws://145.79.12.177:10000") {
            self.serverURL = url
        } else {
            // 如果 URL 無效，使用預設值
            self.serverURL = URL(string: "ws://localhost:8080")!
        }
        
        super.init()
        
        // 生成唯一連接 ID
        self.connectionId = UUID().uuidString.prefix(8).lowercased()
        print("📱 設備連接 ID: \(self.connectionId)")
        
        // 設置音頻會話
        setupAudioSession()
    }
    
    func connect() {
        guard !isConnected else {
            print("WebSocket 已經連接")
            return
        }
        
        print("🔌 連接到 WebSocket: \(serverURL)")
        updateConnectionStatus("連接中...")
        
        // 清理舊的連接
        webSocketTask?.cancel()
        webSocketTask = nil
        
        webSocketTask = URLSession.shared.webSocketTask(with: serverURL)
        webSocketTask?.resume()
        
        // 先設置為連接中，但唔要立即設置為已連接
        // 等到收到服務器確認後先至設置為真正連接
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
                // 如果發送成功但連接狀態唔正確，更新佢
                DispatchQueue.main.async {
                    if !(self?.isConnected ?? false) {
                        self?.isConnected = true
                        self?.updateConnectionStatus("已連接")
                    }
                }
            }
        }
    }
    
    func sendTextMessage(_ text: String) {
        // 根據服務器要求嘅格式發送文本
        let requestData: [String: Any] = [
            "type": "text",
            "text": text
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: requestData, options: [])
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                sendText(jsonString)
            }
        } catch {
            lastError = "數據序列化失敗: \(error.localizedDescription)"
        }
    }
    
    func sendSpeechResult(text: String) {
        // 發送語音識別結果，直接使用 gemini_to_speech 格式
        sendTextToSpeech(text: text)
    }
    
    // MARK: - 音頻播放功能
    
    func sendTextToSpeech(text: String, voiceId: String = "moss_audio_af916082-2e36-11f0-92db-0e8893cbb430") {
        // 重置音頻狀態，確保乾淨嘅狀態
        resetAudioState()
        
        let message: [String: Any] = [
            "type": "gemini_to_speech",
            "text": text,
            "voice_id": voiceId,
            "streaming": true,
            "device_id": connectionId
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: message)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                print("🎤 發送文本到語音合成: \(text)")
                print("📤 發送完整消息: \(jsonString)")
                sendText(jsonString)
            }
        } catch {
            lastError = "語音合成請求失敗: \(error.localizedDescription)"
        }
    }
    
    func sendDirectTextToSpeech(text: String, voiceId: String = "moss_audio_af916082-2e36-11f0-92db-0e8893cbb430") {
        // 重置音頻狀態，確保乾淨嘅狀態
        resetAudioState()
        
        let message: [String: Any] = [
            "type": "text_to_speech",
            "text": text,
            "voice_id": voiceId,
            "streaming": true,
            "device_id": connectionId
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: message)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                sendText(jsonString)
                print("🎤 發送直接文本到語音合成: \(text)")
            }
        } catch {
            lastError = "語音合成請求失敗: \(error.localizedDescription)"
        }
    }
    
    private func setupAudioSession() {
        do {
            audioSession = AVAudioSession.sharedInstance()
            try audioSession?.setCategory(.playback, mode: .default)
            try audioSession?.setActive(true)
            print("🎵 音頻會話設置成功")
        } catch {
            print("❌ 音頻會話設置失敗: \(error.localizedDescription)")
        }
    }
    
    private func handleAudioChunk(_ json: [String: Any]) {
        print("🔍 開始解析音頻 chunk...")
        print("📦 收到嘅 JSON: \(json)")
        
        guard let audioDataBase64 = json["audio_data"] as? String else {
            print("❌ 音頻 chunk 解析失敗: 冇 audio_data 字段")
            return
        }
        
        guard let chunkIndex = json["chunk_index"] as? Int else {
            print("❌ 音頻 chunk 解析失敗: 冇 chunk_index 字段")
            return
        }
        
        guard let totalChunks = json["total_chunks"] as? Int else {
            print("❌ 音頻 chunk 解析失敗: 冇 total_chunks 字段")
            return
        }
        
        print("📊 音頻 chunk 資訊: index=\(chunkIndex), total=\(totalChunks), base64長度=\(audioDataBase64.count)")
        
        guard let audioData = Data(base64Encoded: audioDataBase64) else {
            print("❌ Base64 解碼失敗")
            return
        }
        
        print("✅ 音頻 chunk 解碼成功: 大小=\(audioData.count) bytes")
        
        // 存儲音頻 chunk
        audioChunks.append(audioData)
        expectedChunks = totalChunks
        
        print("🎵 收到音頻 chunk \(chunkIndex)/\(totalChunks), 總共收集到 \(audioChunks.count) 個 chunk")
        
        // 更新進度
        audioProgress = Double(audioChunks.count) / Double(totalChunks)
        
        // 如果收到所有 chunk，準備播放
        if audioChunks.count == expectedChunks {
            print("🎯 所有音頻 chunk 已收集完畢，開始播放...")
            playAudio()
        }
    }
    
    private func playAudio() {
        guard audioChunks.count == expectedChunks else {
            print("⏳ 等待更多音頻 chunk... 當前: \(audioChunks.count)/\(expectedChunks)")
            return
        }
        
        print("🔄 開始合併音頻 chunk...")
        
        // 合併所有音頻 chunk
        let combinedAudioData = audioChunks.reduce(Data()) { $0 + $1 }
        
        print("✅ 音頻合併完成: 總大小=\(combinedAudioData.count) bytes, chunk數量=\(audioChunks.count)")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // 停止並清理舊嘅音頻播放器
            self.audioPlayer?.stop()
            self.audioPlayer = nil
            
            self.isPlayingAudio = true
            self.audioProgress = 1.0
            
            print("🎵 準備播放音頻...")
            
            do {
                // 嘗試創建 AVAudioPlayer
                self.audioPlayer = try AVAudioPlayer(data: combinedAudioData)
                
                // 檢查音頻 player 係咪成功創建
                guard let player = self.audioPlayer else {
                    print("❌ 音頻 player 創建失敗")
                    self.isPlayingAudio = false
                    return
                }
                
                // 設置 delegate
                player.delegate = self
                
                // 檢查音頻時長
                let duration = player.duration
                print("🕐 音頻時長: \(duration) 秒")
                
                // 檢查音頻格式
                print("🎵 音頻資訊: URL=\(player.url?.absoluteString ?? "nil"), 數據大小=\(combinedAudioData.count) bytes")
                
                // 確保音頻會話設置正確
                do {
                    try AVAudioSession.sharedInstance().setActive(true)
                    print("🔊 音頻會話已激活")
                } catch {
                    print("⚠️ 音頻會話激活失敗: \(error.localizedDescription)")
                }
                
                // 嘗試播放
                let success = player.play()
                print("🎵 播放結果: \(success)")
                
                if success {
                    print("✅ 音頻開始播放成功")
                } else {
                    print("❌ 音頻播放失敗 (play() 返回 false)")
                    self.isPlayingAudio = false
                    self.audioPlayer = nil
                }
                
            } catch {
                print("❌ 音頻播放失敗: \(error.localizedDescription)")
                print("❌ 錯誤詳情: \(error)")
                self.lastError = "音頻播放失敗: \(error.localizedDescription)"
                self.isPlayingAudio = false
                self.audioPlayer = nil
            }
            
            // 重置為下一次音頻
            self.audioChunks.removeAll()
            self.expectedChunks = 0
        }
    }
    
    func stopAudio() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlayingAudio = false
        audioProgress = 0.0
        audioChunks.removeAll()
        expectedChunks = 0
        
        // 停用音頻會話以釋放資源
        do {
            try AVAudioSession.sharedInstance().setActive(false)
            print("🔊 音頻會話已停用")
        } catch {
            print("⚠️ 音頻會話停用失敗: \(error.localizedDescription)")
        }
        
        print("🛑 停止音頻播放")
    }
    
    func resetAudioState() {
        print("🔄 重置音頻狀態")
        stopAudio()
        geminiResponse = ""
        lastError = nil
    }
    
    // MARK: - 服務器功能
    
    func sendPing() {
        let pingMessage = ["type": "ping"]
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: pingMessage, options: [])
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                sendText(jsonString)
                print("📤 發送 ping")
            }
        } catch {
            lastError = "Ping 發送失敗: \(error.localizedDescription)"
        }
    }
    
    func checkConnectionStatus() {
        if webSocketTask != nil {
            // 如果有 webSocketTask，發送 ping 檢查連接狀態
            sendPing()
        } else if !isConnected {
            // 如果冇 webSocketTask 且未連接，嘗試重新連接
            connect()
        }
    }
    
    func clearHistory() {
        let clearMessage = ["type": "clear_history"]
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: clearMessage, options: [])
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                sendText(jsonString)
                print("📤 發送 clear_history")
            }
        } catch {
            lastError = "清除歷史記錄失敗: \(error.localizedDescription)"
        }
    }
    
    func getHistory() {
        let historyMessage = ["type": "get_history"]
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: historyMessage, options: [])
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                sendText(jsonString)
                print("📤 發送 get_history")
            }
        } catch {
            lastError = "獲取歷史記錄失敗: \(error.localizedDescription)"
        }
    }
    
    private func receiveMessage() {
        guard let webSocketTask = webSocketTask else { return }
        
        webSocketTask.receive { [weak self] result in
            switch result {
            case .success(let message):
                self?.handleMessage(message)
                self?.receiveMessage() // 繼續接收下一條消息
                
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
        print("📥 收到 WebSocket 消息:")
        print("📄 消息內容: \(text)")
        print("📏 消息長度: \(text.count) 字符")
        
        // 添加到消息列表
        receivedMessages.append(text)
        
        // 限制消息列表長度
        if receivedMessages.count > 50 {
            receivedMessages.removeFirst()
        }
        
        // 解析消息類型
        if let data = text.data(using: .utf8) {
            print("🔄 嘗試解析 JSON...")
            
            if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                print("✅ JSON 解析成功")
                print("📋 JSON 內容: \(json)")
                
                if let type = json["type"] as? String {
                    print("🏷️ 消息類型: \(type)")
                    
                    switch type {
                    case "response", "gemini_response":
                        // Gemini 服務器嘅回應
                        print("🤖 處理 Gemini 回應...")
                        if let response = json["response"] as? String {
                            print("💬 Gemini 回應內容: \(response)")
                            DispatchQueue.main.async {
                                self.geminiResponse = response
                            }
                        }
                        if let originalText = json["original_text"] as? String {
                            print("📝 原始文本: \(originalText)")
                        }
                        
                        // 重置音頻狀態準備接收新嘅音頻
                        self.resetAudioState()
                        
                    case "audio_chunk":
                        // 音頻 chunk
                        print("🎵 收到音頻 chunk，開始處理...")
                        handleAudioChunk(json)
                        
                    case "audio_complete":
                        // 音頻發送完成
                        print("🎵 音頻發送完成")
                        // 音頻會在收到所有 chunk 後自動播放
                        
                    case "pong":
                        print("🏓 收到服務器 pong 響應")
                        DispatchQueue.main.async {
                            self.isConnected = true
                            self.updateConnectionStatus("已連接")
                        }
                        
                    case "history":
                        if let history = json["history"] as? [[String: Any]] {
                            print("📚 收到歷史記錄: \(history.count) 條")
                            // 可以在這裡處理歷史記錄
                        }
                        
                    case "error":
                        if let errorMessage = json["message"] as? String {
                            lastError = "服務器錯誤: \(errorMessage)"
                            print("❌ 服務器錯誤: \(errorMessage)")
                        }
                        
                    case "connection_ack":
                        print("✅ 服務器確認連接")
                        DispatchQueue.main.async {
                            self.isConnected = true
                            self.updateConnectionStatus("已連接")
                        }
                        
                    default:
                        print("📨 收到其他類型消息: \(type)")
                        print("📦 完整消息: \(json)")
                    }
                } else {
                    print("⚠️ JSON 中冇 type 字段")
                    print("📦 完整 JSON: \(json)")
                }
            } else {
                print("❌ JSON 解析失敗")
                print("📄 原始數據: \(data.base64EncodedString())")
            }
        } else {
            print("❌ 消息轉換為 Data 失敗")
        }
        
        // 如果冇 type 字段，可能係直接嘅文本回應
        print("🤖 收到文本回應: \(text)")
    }
    
    private func handleConnectionError(_ error: Error) {
        print("❌ WebSocket 連接錯誤: \(error.localizedDescription)")
        DispatchQueue.main.async {
            self.isConnected = false
            self.lastError = "連接錯誤: \(error.localizedDescription)"
            self.updateConnectionStatus("連接斷開")
        }
        
        // 清理舊的連接
        webSocketTask = nil
        
        // 嘗試重新連接
        scheduleReconnect()
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
    
    func resetConnectionState() {
        DispatchQueue.main.async {
            self.isConnected = false
            self.updateConnectionStatus("未連接")
            self.lastError = nil
        }
    }
    
    deinit {
        disconnect()
    }
}

// MARK: - AVAudioPlayerDelegate
extension WebSocketManager: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.isPlayingAudio = false
            self.audioProgress = 0.0
            self.audioPlayer = nil  // 重置音頻播放器
            print("🎵 音頻播放完成，播放器已重置")
        }
    }
    
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        DispatchQueue.main.async {
            self.isPlayingAudio = false
            self.audioProgress = 0.0
            self.audioPlayer = nil  // 重置音頻播放器
            if let error = error {
                self.lastError = "音頻解碼錯誤: \(error.localizedDescription)"
                print("❌ 音頻解碼錯誤: \(error.localizedDescription)")
            }
        }
    }
}