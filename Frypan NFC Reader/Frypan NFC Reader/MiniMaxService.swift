//
//  MiniMaxService.swift
//  Frypan NFC Reader
//
//  Created by Claude on 5/9/2025.
//

import Foundation
import AVFoundation
import Combine

// MARK: - MiniMax Service Protocol
protocol MiniMaxServiceDelegate: AnyObject {
    func miniMaxService(_ service: MiniMaxService, didReceiveAudioData data: Data)
    func miniMaxService(_ service: MiniMaxService, didEncounterError error: String)
    func miniMaxService(_ service: MiniMaxService, didUpdateConnectionStatus isConnected: Bool)
}

// MARK: - MiniMax Service
class MiniMaxService: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    @Published var isConnected = false
    @Published var isGenerating = false
    @Published var lastError: String?
    @Published var connectionStatus: String = "未連接"
    
    // MARK: - Properties
    weak var delegate: MiniMaxServiceDelegate?
    private var webSocketTask: URLSessionWebSocketTask?
    private var audioChunks: [String] = []
    
    // 簡化的連接管理
    private var isConnecting = false
    private var isProcessingRequest = false
    private var pendingText: String?
    
    // MiniMax API 配置
    private let apiKey: String
    private let baseURL = "wss://api.minimax.io/ws/v1/t2a_v2"
    
    // 音頻設置
    private let model = "speech-02-turbo"
    private let voiceId = "moss_audio_af916082-2e36-11f0-92db-0e8893cbb430"
    private let emotion = "neutral"
    
    // MARK: - Initialization
    init(apiKey: String) {
        self.apiKey = apiKey
        super.init()
    }
    
    deinit {
        disconnect()
    }
}

// MARK: - WebSocket Connection Management
extension MiniMaxService {
    
    func connect() {
        guard !isConnected && !isConnecting else { return }
        
        guard let url = URL(string: baseURL) else {
            lastError = "無效的 WebSocket URL"
            return
        }
        
        isConnecting = true
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        webSocketTask = URLSession.shared.webSocketTask(with: request)
        webSocketTask?.resume()
        
        updateConnectionStatus("連接中...")
        receiveMessage()
    }
    
    func disconnect() {
        // 優雅地斷開連接
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        
        DispatchQueue.main.async {
            self.isConnected = false
            self.isConnecting = false
            self.isProcessingRequest = false
            self.updateConnectionStatus("已斷開")
        }
        
        // 清理音頻數據
        audioChunks.removeAll()
    }
    
    private func updateConnectionStatus(_ status: String) {
        DispatchQueue.main.async {
            self.connectionStatus = status
        }
    }
}

// MARK: - Message Handling
extension MiniMaxService {
    
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
        print("📨 MiniMax 收到消息: \(text.prefix(200))...")
        
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("❌ MiniMax 消息解析失敗")
            return
        }
        
        handleJSONMessage(json)
    }
    
    private func handleJSONMessage(_ json: [String: Any]) {
        if let event = json["event"] as? String {
            handleEventMessage(event: event, json: json)
        }
    }
    
    private func handleEventMessage(event: String, json: [String: Any]) {
        print("🎯 MiniMax 處理事件: \(event)")
        
        switch event {
        case "connected_success":
            print("✅ MiniMax 連接成功")
            DispatchQueue.main.async {
                self.isConnected = true
                self.isConnecting = false
                self.updateConnectionStatus("已連接")
                
                // 處理待處理的文本
                if let pendingText = self.pendingText {
                    self.pendingText = nil
                    self.processTextToSpeech(pendingText)
                }
            }
            
        case "task_started":
            print("🚀 MiniMax 任務開始")
            DispatchQueue.main.async {
                self.isGenerating = true
            }
            
        case "task_continued":
            // 檢查是否為最後一個塊
            if let isFinal = json["is_final"] as? Bool, isFinal {
                print("✅ MiniMax 文本處理完成")
                processCompleteAudio()
                return
            }
            
            // 處理音頻數據
            if let data = json["data"] as? [String: Any],
               let audioHex = data["audio"] as? String, !audioHex.isEmpty {
                audioChunks.append(audioHex)
                print("🎵 MiniMax 收到音頻塊: \(audioHex.count) 字符")
            }
            
        case "task_finished":
            print("🏁 MiniMax 任務完成")
            DispatchQueue.main.async {
                self.isGenerating = false
                self.isProcessingRequest = false
            }
            
            // 任務完成後保持連接，避免頻繁連接/斷開導致的 rate limit
            print("✅ MiniMax 任務完成，保持連接")
            
        case "task_failed":
            print("❌ MiniMax 任務失敗")
            DispatchQueue.main.async {
                self.isGenerating = false
                self.isProcessingRequest = false
            }
            if let baseResp = json["base_resp"] as? [String: Any],
               let statusCode = baseResp["status_code"] as? Int,
               let statusMsg = baseResp["status_msg"] as? String {
                let errorMessage = "MiniMax API 錯誤: \(statusCode) - \(statusMsg)"
                print("❌ \(errorMessage)")
                
                DispatchQueue.main.async {
                    self.lastError = errorMessage
                }
                
                // 如果是 rate limit 錯誤，等待後重試
                if statusCode == 1002 {
                    handleRateLimitError()
                }
            }
            
        case "error":
            if let errorMessage = json["message"] as? String {
                print("❌ MiniMax 錯誤: \(errorMessage)")
                DispatchQueue.main.async {
                    self.lastError = "MiniMax 錯誤: \(errorMessage)"
                    self.isGenerating = false
                    self.isProcessingRequest = false
                }
            }
            
        default:
            print("⚠️ MiniMax 未知事件: \(event)")
            break
        }
    }
    
    private func handleRateLimitError() {
        print("⏰ MiniMax Rate Limit 錯誤，等待 30 秒後重試...")
        
        DispatchQueue.main.async {
            self.updateConnectionStatus("Rate Limit，等待重試...")
        }
        
        // 等待 30 秒後重試
        DispatchQueue.main.asyncAfter(deadline: .now() + 30.0) {
            if let pendingText = self.pendingText {
                self.pendingText = nil
                self.processTextToSpeech(pendingText)
            }
        }
    }
    
    private func processCompleteAudio() {
        let combinedHexAudio = audioChunks.joined()
        
        guard let audioData = hexStringToData(combinedHexAudio) else {
            DispatchQueue.main.async {
                self.lastError = "音頻數據轉換失敗"
                self.isGenerating = false
            }
            return
        }
        
        delegate?.miniMaxService(self, didReceiveAudioData: audioData)
        
        DispatchQueue.main.async {
            self.isGenerating = false
        }
        
        sendTaskFinish()
        audioChunks.removeAll()
    }
    
    private func handleConnectionError(_ error: Error) {
        let errorMessage = error.localizedDescription
        print("❌ MiniMax 連接錯誤: \(errorMessage)")
        
        DispatchQueue.main.async {
            self.isConnected = false
            self.isConnecting = false
            self.isProcessingRequest = false
            self.lastError = "連接錯誤: \(errorMessage)"
            self.isGenerating = false
            self.updateConnectionStatus("連接錯誤")
        }
        
        // 通知代理
        delegate?.miniMaxService(self, didUpdateConnectionStatus: false)
        delegate?.miniMaxService(self, didEncounterError: "連接錯誤: \(errorMessage)")
        
    }
}

// MARK: - Text to Speech
extension MiniMaxService {
    
    func textToSpeech(_ text: String) {
        guard !text.isEmpty else {
            lastError = "文本不能為空"
            return
        }
        
        // 如果正在處理請求，直接返回
        if isProcessingRequest {
            lastError = "正在處理其他請求，請稍後再試"
            return
        }
        
        // 如果未連接，先連接
        if !isConnected && !isConnecting {
            pendingText = text
            connect()
            // 等待連接建立後再處理
            return
        }
        
        // 只有在已連接時才處理語音合成
        if isConnected {
            processTextToSpeech(text)
        } else {
            lastError = "連接未建立，請稍後再試"
        }
    }
    
    private func processTextToSpeech(_ text: String) {
        isProcessingRequest = true
        audioChunks.removeAll()
        sendTaskStart()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.sendTaskContinue(text: text)
        }
    }
    
    
    private func sendTaskStart() {
        let message: [String: Any] = [
            "event": "task_start",
            "model": model,
            "language_boost": "Chinese,Yue",
            "voice_setting": [
                "voice_id": voiceId,
                "speed": 1,
                "vol": 1,
                "pitch": 0,
                "emotion": emotion
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
        guard let webSocketTask = webSocketTask else { return }
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: message)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                let wsMessage = URLSessionWebSocketTask.Message.string(jsonString)
                webSocketTask.send(wsMessage) { [weak self] error in
                    if let error = error {
                        DispatchQueue.main.async {
                            self?.lastError = "消息發送失敗: \(error.localizedDescription)"
                        }
                    }
                }
            }
        } catch {
            DispatchQueue.main.async {
                self.lastError = "JSON 序列化失敗: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Helper Functions
extension MiniMaxService {
    
    func clearAudioData() {
        audioChunks.removeAll()
    }
    
    private func hexStringToData(_ hexString: String) -> Data? {
        let len = hexString.count / 2
        var data = Data(capacity: len)
        var i = hexString.startIndex
        for _ in 0..<len {
            let j = hexString.index(i, offsetBy: 2)
            let bytes = hexString[i..<j]
            if var num = UInt8(bytes, radix: 16) {
                data.append(&num, count: 1)
            } else {
                return nil
            }
            i = j
        }
        return data
    }
}