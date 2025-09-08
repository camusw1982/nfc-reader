//
//  WebServiceManager.swift
//  Frypan NFC Reader
//
//  Created by Claude on 5/9/2025.
//

import Foundation
import os.log
import Combine

// MARK: - WebSocket Service Protocol
protocol WebSocketServiceProtocol: ObservableObject {
    var isConnected: Bool { get }
    var receivedMessages: [String] { get }
    
    func connect()
    func disconnect()
    func sendTextToSpeech(text: String, character_id: Int?)
    func sendPing()
    func clearHistory()
    func getHistory()
}

class WebServiceManager: ObservableObject {
    @Published var isSending = false
    @Published var lastError: String?
    @Published var lastResponse: String?
    @Published var useWebSocket = true  // 預設使用 WebSocket
    
    // WebSocket 管理器
    private var webSocketManager: (any WebSocketServiceProtocol)?
    
    // 配置
    private let serverURL: URL
    private let logger = Logger(subsystem: "com.frypan.nfc.reader", category: "WebService")
    
    // MARK: - Initialization
    
    init() {
        // 從配置或環境變數獲取服務器地址
        self.serverURL = Self.createServerURL()
        
        // 初始化 WebSocket 管理器（不自動連接，由 UI 控制）
        // 注意：這裡需要延遲初始化以避免循環依賴
        self.webSocketManager = nil
        
        logger.info("WebServiceManager 初始化完成，服務器地址: \(self.serverURL.absoluteString)")
    }
    
    private static func createServerURL() -> URL {
        // 優先從環境變數或配置檔案讀取
        if let customURL = ProcessInfo.processInfo.environment["SERVER_URL"],
           let url = URL(string: customURL) {
            return url
        }
        
        // 預設地址
        if let url = URL(string: "http://145.79.12.177:10000/api/speech-result") {
            return url
        }
        
        // 備用地址
        return URL(string: "http://localhost:8080/api/speech-result")!
    }
    
    // MARK: - Public Methods
    
    func sendSpeechResult(text: String, completion: @escaping (Bool) -> Void) {
        guard !text.isEmpty else {
            handleError("語音識別結果為空", completion: completion)
            return
        }
        
        logger.info("開始發送語音識別結果，長度: \(text.count) 字符")
        
        isSending = true
        lastError = nil
        
        // 優先使用 WebSocket
        if useWebSocket {
            sendViaWebSocket(text: text, completion: completion)
        } else {
            sendViaHTTP(text: text, completion: completion)
        }
    }
    
    // MARK: - Private Methods
    
    private func sendViaWebSocket(text: String, completion: @escaping (Bool) -> Void) {
        guard let webSocketManager = webSocketManager else {
            handleError("WebSocket 管理器未初始化", completion: completion)
            return
        }
        
        logger.info("通過 WebSocket 發送語音識別結果到 Gemini 語音合成")
        
        // 直接發送 gemini_chat 請求
        webSocketManager.sendTextToSpeech(text: text, character_id: nil)
        
        // WebSocket 是異步的，我們假設發送成功
        // 實際應用中可以通過 WebSocket 確認機制來確保發送成功
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.isSending = false
            completion(true)
        }
    }
    
    private func sendViaHTTP(text: String, completion: @escaping (Bool) -> Void) {
        // 創建請求數據，確保使用 UTF-8 編碼
        let requestData: [String: Any] = [
            "text": text,
            "timestamp": Date().timeIntervalSince1970,
            "language": "zh-HK",
            "device": "iOS"
        ]
        
        logger.info("發送原始文本: \(text.prefix(50))...")
        logger.debug("文本 UTF8 編碼: \(text.data(using: .utf8)?.base64EncodedString() ?? "無法編碼")")
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: requestData, options: [])
            
            // 創建 URL 請求
            var request = URLRequest(url: serverURL)
            request.httpMethod = "POST"
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Accept")
            request.httpBody = jsonData
            
            logger.debug("JSON 數據大小: \(jsonData.count) bytes")
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                logger.debug("JSON 字符串: \(jsonString)")
            }
            
            // 發送請求
            let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
                DispatchQueue.main.async {
                    self?.isSending = false
                    
                    if let error = error {
                        self?.handleError("網絡錯誤: \(error.localizedDescription)", completion: completion)
                        return
                    }
                    
                    if let httpResponse = response as? HTTPURLResponse {
                        self?.logger.info("服務器響應狀態: \(httpResponse.statusCode)")
                        
                        if httpResponse.statusCode == 200 {
                            // 請求成功
                            if let data = data,
                               let responseString = String(data: data, encoding: .utf8) {
                                self?.lastResponse = responseString
                                self?.logger.info("服務器響應: \(responseString)")
                            }
                            completion(true)
                        } else {
                            self?.handleError("服務器錯誤 (狀態碼: \(httpResponse.statusCode))", completion: completion)
                        }
                    }
                }
            }
            
            task.resume()
            
        } catch {
            handleError("數據序列化失敗: \(error.localizedDescription)", completion: completion)
        }
    }
    
    private func handleError(_ message: String, completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.async {
            self.isSending = false
            self.lastError = message
            self.logger.error("\(message)")
            completion(false)
        }
    }
    
    // MARK: - WebSocket 管理方法
    
    func setWebSocketManager(_ manager: any WebSocketServiceProtocol) {
        self.webSocketManager = manager
    }
    
    func getWebSocketManager() -> (any WebSocketServiceProtocol)? {
        return webSocketManager
    }
    
    func toggleWebSocket() {
        useWebSocket.toggle()
        if useWebSocket {
            webSocketManager?.connect()
            logger.info("切換到 WebSocket 模式")
        } else {
            webSocketManager?.disconnect()
            logger.info("切換到 HTTP 模式")
        }
    }
    
    func reconnectWebSocket() {
        webSocketManager?.disconnect()
        webSocketManager?.connect()
        logger.info("重新連接 WebSocket")
    }
    
    // MARK: - 服務器功能方法
    
    func sendPing() {
        webSocketManager?.sendPing()
    }
    
    func clearHistory() {
        webSocketManager?.clearHistory()
    }
    
    func getHistory() {
        webSocketManager?.getHistory()
    }
}