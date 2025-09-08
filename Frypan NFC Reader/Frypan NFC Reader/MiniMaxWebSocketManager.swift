//
//  MiniMaxWebSocketManager.swift
//  Frypan NFC Reader
//
//  Created by Claude on 5/9/2025.
//

import Foundation
import os.log

// MARK: - MiniMax WebSocket Manager Protocol
protocol MiniMaxWebSocketManagerDelegate: AnyObject {
    func playMP3Audio(_ data: Data)
}

// MARK: - MiniMax WebSocket 管理
class MiniMaxWebSocketManager: NSObject {
    
    // MARK: - Properties
    private var webSocketTask: URLSessionWebSocketTask?
    private var audioChunks: [String] = []
    private var isProcessing = false
    private let apiKey: String
    private let baseURL = "wss://api.minimax.io/ws/v1/t2a_v2"
    private let logger = Logger(subsystem: "com.frypan.nfc.reader", category: "MiniMax")
    
    weak var delegate: MiniMaxWebSocketManagerDelegate?
    
    // MARK: - Initialization
    init(apiKey: String) {
        self.apiKey = apiKey
        super.init()
    }
    
    // MARK: - Public Methods
    func textToSpeech(_ text: String) {
        guard !isProcessing else { 
            logger.warning("MiniMax 正在處理其他請求")
            return 
        }
        
        logger.info("開始語音合成: \(text.prefix(50))...")
        isProcessing = true
        audioChunks.removeAll()
        
        connectAndProcessText(text)
    }
    
    func disconnect() {
        logger.info("斷開 MiniMax WebSocket 連接")
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        resetState()
    }
    
    private func resetState() {
        isProcessing = false
        audioChunks.removeAll()
    }
    
    // MARK: - Private Methods
    private func connectAndProcessText(_ text: String) {
        guard let url = URL(string: baseURL) else { 
            logger.error("無效的 MiniMax WebSocket URL")
            resetState()
            return 
        }
        
        // isConnecting = true // 簡化狀態管理
        logger.info("正在建立 MiniMax WebSocket 連接...")
        
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
                self?.logger.error("MiniMax WebSocket 錯誤: \(error.localizedDescription)")
                self?.resetState()
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
            logger.info("MiniMax 連接成功")
            
        case "task_started":
            logger.info("MiniMax 任務開始")
            
        case "task_continued":
            // 處理音頻數據
            if let data = json["data"] as? [String: Any],
               let audioHex = data["audio"] as? String, !audioHex.isEmpty {
                audioChunks.append(audioHex)
                // logger.debug("收到音頻塊: \(audioHex.count) 字符")
            }
            
            // 檢查是否為最後一個塊
            if let isFinal = json["is_final"] as? Bool, isFinal {
                logger.info("音頻數據接收完成")
                processCompleteAudio()
                return
            }
            
        case "task_finished":
            logger.info("MiniMax 任務完成")
            resetState()
            disconnect()
            
        case "task_failed":
            logger.error("MiniMax 任務失敗")
            if let baseResp = json["base_resp"] as? [String: Any],
               let statusCode = baseResp["status_code"] as? Int,
               let statusMsg = baseResp["status_msg"] as? String {
                logger.error("MiniMax API 錯誤: \(statusCode) - \(statusMsg)")
            }
            resetState()
            disconnect()
            
        default:
            logger.warning("未知事件: \(event)")
            break
        }
    }
    
    private func processCompleteAudio() {
        let combinedHexAudio = audioChunks.joined()
        guard let audioData = hexStringToData(combinedHexAudio) else { 
            logger.error("音頻數據轉換失敗")
            resetState()
            disconnect()
            return 
        }
        
        logger.info("音頻數據處理完成: \(audioData.count) bytes")
        delegate?.playMP3Audio(audioData)
        
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
            "audio_setting": [
                "sample_rate": 32000,
                "format": "mp3"
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
            logger.error("WebSocket 未連接，無法發送消息")
            return 
        }
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: message)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                let wsMessage = URLSessionWebSocketTask.Message.string(jsonString)
                webSocketTask.send(wsMessage) { [weak self] error in
                    if let error = error {
                        self?.logger.error("消息發送失敗: \(error.localizedDescription)")
                        self?.resetState()
                    }
                }
            }
        } catch {
            logger.error("JSON 序列化失敗: \(error.localizedDescription)")
        }
    }
    
    private func hexStringToData(_ hexString: String) -> Data? {
        guard hexString.count % 2 == 0 else {
            logger.error("音頻 hex 字符串長度不是偶數")
            return nil
        }
        
        var data = Data(capacity: hexString.count / 2)
        var index = hexString.startIndex
        
        while index < hexString.endIndex {
            let nextIndex = hexString.index(index, offsetBy: 2)
            let byteString = String(hexString[index..<nextIndex])
            
            guard let byte = UInt8(byteString, radix: 16) else {
                logger.error("音頻 hex 字符串包含無效字符")
                return nil
            }
            
            data.append(byte)
            index = nextIndex
        }
        
        return data
    }
}
