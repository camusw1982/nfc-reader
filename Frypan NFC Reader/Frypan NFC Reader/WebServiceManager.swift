//
//  WebServiceManager.swift
//  Frypan NFC Reader
//
//  Created by Claude on 5/9/2025.
//

import Foundation

class WebServiceManager: ObservableObject {
    @Published var isSending = false
    @Published var lastError: String?
    @Published var lastResponse: String?
    @Published var useWebSocket = true  // 預設使用 WebSocket
    
    // WebSocket 管理器
    private var webSocketManager: WebSocketManager?
    
    // 你的 web server 地址
    private let serverURL: URL
    
    init() {
        // 安全地創建 URL，如果失敗則使用預設值
        if let url = URL(string: "http://145.79.12.177:10000/api/speech-result") {
            self.serverURL = url
        } else {
            // 如果 URL 無效，使用一個安全的預設 URL
            self.serverURL = URL(string: "http://localhost:8080/api/speech-result")!
        }
        
        // 初始化 WebSocket 管理器，但不自動連接
        self.webSocketManager = WebSocketManager()
        // 移除自動連接，讓用戶手動控制連接
    }
    
    func sendSpeechResult(text: String, completion: @escaping (Bool) -> Void) {
        guard !text.isEmpty else {
            lastError = "語音識別結果為空"
            completion(false)
            return
        }
        
        isSending = true
        lastError = nil
        
        // 優先使用 WebSocket
        if useWebSocket {
            sendViaWebSocket(text: text, completion: completion)
        } else {
            sendViaHTTP(text: text, completion: completion)
        }
    }
    
    private func sendViaWebSocket(text: String, completion: @escaping (Bool) -> Void) {
        guard let webSocketManager = webSocketManager else {
            lastError = "WebSocket 管理器未初始化"
            completion(false)
            return
        }
        
        print("📤 通過 WebSocket 發送語音識別結果到 Gemini 語音合成")
        
        // 直接發送 gemini_to_speech 請求
        webSocketManager.sendTextToSpeech(text: text)
        
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
        
        print("📤 發送原始文本: \(text)")
        print("📤 文本 UTF8 編碼: \(text.data(using: .utf8)?.base64EncodedString() ?? "無法編碼")")
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: requestData, options: [])
            
            // 創建 URL 請求
            var request = URLRequest(url: serverURL)
            request.httpMethod = "POST"
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Accept")
            request.httpBody = jsonData
            
            print("📤 JSON 數據大小: \(jsonData.count) bytes")
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                print("📤 JSON 字符串: \(jsonString)")
            }
            
            // 發送請求
            let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
                DispatchQueue.main.async {
                    self?.isSending = false
                    
                    if let error = error {
                        self?.lastError = "網絡錯誤: \(error.localizedDescription)"
                        completion(false)
                        return
                    }
                    
                    if let httpResponse = response as? HTTPURLResponse {
                        print("🌐 服務器響應狀態: \(httpResponse.statusCode)")
                        
                        if httpResponse.statusCode == 200 {
                            // 請求成功
                            if let data = data,
                               let responseString = String(data: data, encoding: .utf8) {
                                self?.lastResponse = responseString
                                print("✅ 服務器響應: \(responseString)")
                            }
                            completion(true)
                        } else {
                            self?.lastError = "服務器錯誤 (狀態碼: \(httpResponse.statusCode))"
                            completion(false)
                        }
                    }
                }
            }
            
            task.resume()
            
        } catch {
            DispatchQueue.main.async {
                self.isSending = false
                self.lastError = "數據序列化失敗: \(error.localizedDescription)"
                completion(false)
            }
        }
    }
    
    // MARK: - WebSocket 管理方法
    
    func getWebSocketManager() -> WebSocketManager? {
        return webSocketManager
    }
    
    func toggleWebSocket() {
        useWebSocket.toggle()
        if useWebSocket {
            webSocketManager?.connect()
            print("🔌 切換到 WebSocket 模式")
        } else {
            webSocketManager?.disconnect()
            print("🌐 切換到 HTTP 模式")
        }
    }
    
    func reconnectWebSocket() {
        webSocketManager?.disconnect()
        webSocketManager?.connect()
        print("🔄 重新連接 WebSocket")
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