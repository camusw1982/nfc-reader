//
//  HTTPManager.swift
//  Frypan NFC Reader
//
//  Created by Claude on 8/9/2025.
//

import Foundation
import Combine
import os.log
import AVFoundation

// MARK: - Notification Names
extension Notification.Name {
    static let HTTPConnectionChanged = Notification.Name("HTTPConnectionChanged")
}

// MARK: - HTTP Response Models
struct HTTPChatResponse: Codable {
    let response: String
    let voice_id: String?
    let character_id: Int?
    let success: Bool
    let error: String?
}

struct HTTPCharacterResponse: Codable {
    let character_id: Int
    let character_name: String
    let success: Bool
    let error: String?
}

struct HTTPHistoryResponse: Codable {
    let messages: [ChatMessage]
    let success: Bool
    let error: String?
}

struct HTTPClearHistoryResponse: Codable {
    let success: Bool
    let message: String
    let error: String?
}

// MARK: - HTTP Request Models
struct HTTPChatRequest: Codable {
    let type: String
    let text: String
    let character_id: Int
    let streaming: Bool?
    let connection_id: String?
}

struct HTTPCharacterRequest: Codable {
    let character_id: Int
}

// MARK: - HTTP Manager
class HTTPManager: NSObject, ObservableObject, ServiceProtocol {
    
    // MARK: - Shared Instance
    static let shared = HTTPManager()
    
    // MARK: - Published Properties
    @Published var isConnected = false
    @Published var connectionStatus: String = "未連接"
    @Published var lastError: String?
    @Published var receivedMessages: [String] = []
    @Published var isPlayingAudio = false
    @Published var geminiResponse: String = ""
    @Published var connectionId: String = ""
    @Published var currentCharacter_id: Int = 9999 {  // Debug: 明顯嘅默認值
        didSet {
            print("🔄 HTTPManager currentCharacter_id 從 \(oldValue) 變更為 \(currentCharacter_id)")
        }
    }
    @Published var characterName: String = "DEBUG_CHARACTER_X"  // Debug: 明顯嘅默認名稱
    
    // MARK: - Speech Recognizer Reference
    weak var speechRecognizer: SpeechRecognizer?
    
    // MARK: - Private Properties
    private let serverURL: URL
    private let audioManager: AudioManager
    private var miniMaxStreamManager: MiniMaxStreamManager?
    private let logger = Logger(subsystem: "com.frypan.nfc.reader", category: "HTTP")
    private var connectionCheckTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization
    override init() {
        // HTTP 服務器地址
        self.serverURL = Self.createServerURL()
        self.audioManager = AudioManager()
        
        super.init()
        
        // 生成唯一連接 ID
        let newConnectionId = UUID().uuidString.prefix(8).lowercased()
        self.connectionId = newConnectionId
        logger.info("設備連接 ID: \(newConnectionId)")
        
        setupMiniMaxStreamManager()
        setupAudioBinding()
        checkConnection()
    }
    
    deinit {
        disconnect()
        connectionCheckTimer?.invalidate()
    }
    
    // MARK: - Setup Methods
    private static func createServerURL() -> URL {
        if let customURL = ProcessInfo.processInfo.environment["HTTP_SERVER_URL"],
           let url = URL(string: customURL) {
            return url
        }
        return URL(string: "http://145.79.12.177:10000")!
    }
    
    private func setupAudioBinding() {
        // 綁定音頻管理器的狀態到 HTTP 管理器
        audioManager.$isPlayingAudio
            .assign(to: &$isPlayingAudio)

        // 監聽 MiniMaxStreamManager 嘅播放狀態
        if let streamManager = miniMaxStreamManager {
            streamManager.$isPlaying
                .sink { [weak self] isStreamPlaying in
                    DispatchQueue.main.async {
                        // 如果 MiniMax 正喺播放，優先顯示佢嘅狀態
                        if isStreamPlaying {
                            self?.isPlayingAudio = true
                        } else {
                            // 如果 MiniMax 冇播放，使用 AudioManager 嘅狀態
                            self?.isPlayingAudio = self?.audioManager.isPlayingAudio ?? false
                        }
                    }
                }
                .store(in: &cancellables)
        }
    }
    
    private func setupMiniMaxStreamManager() {
        guard let apiKey = Bundle.main.object(forInfoDictionaryKey: "MINIMAX_API_KEY") as? String,
              !apiKey.isEmpty else {
            logger.warning("MiniMax API Key 未設置，語音合成功能將不可用")
            return
        }

        // 初始化 MiniMax 串流管理器
        self.miniMaxStreamManager = MiniMaxStreamManager()
        logger.info("MiniMax 串流管理器已初始化")

        // 重新設置音頻綁定以包含 MiniMaxStreamManager
        setupAudioBinding()
    }
    
    private func checkConnection() {
        connectionCheckTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.ping()
        }
    }
}

// MARK: - HTTP Connection
extension HTTPManager {
    
    func connect() {
        logger.info("檢查 HTTP 服務器連接: \(self.serverURL)")
        
        updateConnectionStatus("連接中...")
        
        // 測試連接
        ping()
    }
    
    func disconnect() {
        // 停止音頻播放
        audioManager.stopAudio()

        // 停止 MiniMax 串流
        miniMaxStreamManager?.stopStreaming()

        // 停止連接檢查
        connectionCheckTimer?.invalidate()

        setConnected(false)
    }
    
    private func updateConnectionStatus(_ status: String) {
        DispatchQueue.main.async {
            self.connectionStatus = status
        }
    }
    
    private func setConnected(_ connected: Bool) {
        DispatchQueue.main.async {
            let previousState = self.isConnected
            self.isConnected = connected
            self.updateConnectionStatus(connected ? "已連接" : "已斷開")
            
            // 只有在狀態改變時才發送通知
            if previousState != connected {
                NotificationCenter.default.post(
                    name: .HTTPConnectionChanged,
                    object: connected
                )
                self.logger.info("🌐 HTTP 連接狀態變更: \(connected)，已發送通知")
            }
        }
    }
    
    private func handleHTTPError(_ error: Error) {
        DispatchQueue.main.async {
            self.lastError = "HTTP 請求失敗: \(error.localizedDescription)"
            self.setConnected(false)
        }
        logger.error("HTTP 請求失敗: \(error.localizedDescription)")
    }
}

// MARK: - HTTP Requests
extension HTTPManager {
    
    func sendText(_ text: String, character_id: Int? = nil) {
        let character_idToUse = character_id ?? currentCharacter_id
        
        print("🎯 HTTPManager sendText: 傳入 character_id=\(character_id ?? 0), currentCharacter_id=\(currentCharacter_id), 最終使用=\(character_idToUse)")
        
        Task {
            do {
                let request = HTTPChatRequest(
                    type: "text",
                    text: text,
                    character_id: character_idToUse,
                    streaming: nil,
                    connection_id: connectionId
                )
                
                print("📤 發送文本消息，使用人物 ID: \(character_idToUse)")
                
                // Debug: 打印完整的 request 內容
                do {
                    let requestData = try JSONEncoder().encode(request)
                    if let requestString = String(data: requestData, encoding: .utf8) {
                        print("🔍 DEBUG: HTTP Request JSON: \(requestString)")
                    }
                } catch {
                    print("🔍 DEBUG: Failed to encode request: \(error)")
                }
                
                let (data, _) = try await performHTTPCall(
                    endpoint: "/api/chat",
                    method: "POST",
                    body: request
                )
                
                if let response = try? JSONDecoder().decode(HTTPChatResponse.self, from: data) {
                    await handleChatResponse(response)
                }
                
                logger.info("發送文本: \(text)")
                
            } catch {
                handleHTTPError(error)
            }
        }
    }
    
    func sendTextToSpeech(text: String, character_id: Int? = nil) {
        let character_idToUse = character_id ?? currentCharacter_id
        
        print("🎯 HTTPManager sendTextToSpeech: 傳入 character_id=\(character_id ?? 0), currentCharacter_id=\(currentCharacter_id), 最終使用=\(character_idToUse)")
        
        Task {
            do {
                let request = HTTPChatRequest(
                    type: "gemini_chat",
                    text: text,
                    character_id: character_idToUse,
                    streaming: true,
                    connection_id: connectionId
                )
                
                print("🎤 發送語音合成請求，使用人物 ID: \(character_idToUse)")
                
                // Debug: 打印完整的 request 內容
                do {
                    let requestData = try JSONEncoder().encode(request)
                    if let requestString = String(data: requestData, encoding: .utf8) {
                        print("🔍 DEBUG: HTTP Request JSON: \(requestString)")
                    }
                } catch {
                    print("🔍 DEBUG: Failed to encode request: \(error)")
                }
                
                let (data, _) = try await performHTTPCall(
                    endpoint: "/api/chat",
                    method: "POST",
                    body: request
                )
                
                if let response = try? JSONDecoder().decode(HTTPChatResponse.self, from: data) {
                    await handleChatResponse(response)
                }
                
                logger.info("發送語音合成請求: \(text)")
                
            } catch {
                handleHTTPError(error)
            }
        }
    }
    
    func ping() {
        Task {
            do {
                let (data, _) = try await performHTTPCall(
                    endpoint: "/api/ping",
                    method: "GET"
                )
                
                if let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let success = response["success"] as? Bool, success {
                    setConnected(true)
                } else {
                    setConnected(false)
                }
                
            } catch {
                handleHTTPError(error)
            }
        }
    }
    
    func clearHistory() {
        Task {
            do {
                let (data, _) = try await performHTTPCall(
                    endpoint: "/api/history/clear",
                    method: "POST"
                )
                
                if let response = try? JSONDecoder().decode(HTTPClearHistoryResponse.self, from: data) {
                    logger.info("清除歷史記錄: \(response.message)")
                }
                
            } catch {
                handleHTTPError(error)
            }
        }
    }
    
    func getHistory() {
        Task {
            do {
                let (data, _) = try await performHTTPCall(
                    endpoint: "/api/history",
                    method: "GET"
                )
                
                if let response = try? JSONDecoder().decode(HTTPHistoryResponse.self, from: data) {
                    logger.info("獲取歷史記錄: \(response.messages.count) 條消息")
                }
                
            } catch {
                handleHTTPError(error)
            }
        }
    }
    
    func getCharacterName(for character_id: Int? = nil) {
        let targetId = character_id ?? currentCharacter_id
        
        Task {
            do {
                let request = HTTPCharacterRequest(character_id: targetId)
                let (data, _) = try await performHTTPCall(
                    endpoint: "/api/character",
                    method: "POST",
                    body: request
                )
                
                if let response = try? JSONDecoder().decode(HTTPCharacterResponse.self, from: data) {
                    await handleCharacterResponse(response)
                }
                
            } catch {
                handleHTTPError(error)
            }
        }
    }
    
    func updateCharacterName(_ name: String, for character_id: Int? = nil) {
        DispatchQueue.main.async {
            let targetId = character_id ?? self.currentCharacter_id
            if targetId == self.currentCharacter_id {
                self.characterName = name
            }
            self.logger.info("更新人物 ID \(targetId) 的名稱為: \(name)")
        }
    }
    
    // MARK: - Private HTTP Methods
    private func performHTTPCall<T: Encodable>(
        endpoint: String,
        method: String,
        body: T? = nil
    ) async throws -> (Data, URLResponse) {
        
        let url = serverURL.appendingPathComponent(endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let body = body {
            request.httpBody = try JSONEncoder().encode(body)
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        
        return (data, response)
    }
    
    private func performHTTPCall(
        endpoint: String,
        method: String
    ) async throws -> (Data, URLResponse) {
        
        let url = serverURL.appendingPathComponent(endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        
        return (data, response)
    }
}

// MARK: - Response Handling
extension HTTPManager {
    
    @MainActor
    private func handleChatResponse(_ response: HTTPChatResponse) {
        if response.success {
            self.geminiResponse = response.response
            
            // 添加 AI 回應到聊天消息列表
            let aiMessage = ChatMessage(text: response.response, isUser: false, timestamp: Date(), isError: false)
            self.speechRecognizer?.messages.append(aiMessage)
            
            print("🤖 添加 AI 回應到聊天: \(response.response)")
            
            // 提取 voice_id 並觸發 TTS
            let voiceId = response.voice_id ?? "moss_audio_af916082-2e36-11f0-92db-0e8893cbb430"
            print("🎵 使用 voice_id: \(voiceId)")
            triggerTextToSpeech(response.response, voiceId: voiceId)
            
        } else {
            self.lastError = response.error ?? "Unknown error"
        }
    }
    
    @MainActor
    private func handleCharacterResponse(_ response: HTTPCharacterResponse) {
        if response.success {
            updateCharacterName(response.character_name, for: response.character_id)
        } else {
            self.lastError = response.error ?? "Failed to get character name"
        }
    }
    
    private func triggerTextToSpeech(_ text: String, voiceId: String = "DEBUG_VOICE_ID_NONE") {
        guard !text.isEmpty, let miniMaxManager = miniMaxStreamManager else {
            logger.warning("MiniMax 串流管理器未初始化")
            return
        }

        // 使用 MiniMax 串流管理器進行文本轉語音，傳遞正確的 voice_id
        print("🎵 觸發 TTS: text=\(text.prefix(30))..., voiceId=\(voiceId)")
        miniMaxManager.startStreaming(text: text, voiceId: voiceId)
    }
}

// MARK: - Audio Processing
extension HTTPManager {
    
    func playMP3Audio(_ data: Data) {
        audioManager.playMP3Audio(data)
    }
}

// MARK: - Public Interface
extension HTTPManager {
    
    func stopAudio() {
        logger.info("🛑 停止所有音頻播放")

        // 停止 MiniMax 串流管理器
        miniMaxStreamManager?.stopStreaming()
        logger.info("✅ MiniMax 串流管理器已停止")

        // 停止音頻管理器
        audioManager.stopAudio()
        logger.info("✅ 音頻管理器已停止")
    }
    
    func setCharacter_id(_ character_id: Int) {
        DispatchQueue.main.async {
            print("🎭 HTTPManager 接收到人物 ID 設置: \(character_id)")
            self.currentCharacter_id = character_id
            self.characterName = "DEBUG_RESET_NAME" // 重置為調試名稱
            print("✅ HTTPManager 已更新當前人物 ID 為: \(self.currentCharacter_id)")
            
            // 請求新人物的名稱
            self.getCharacterName(for: character_id)
        }
    }
    
    func getCurrentCharacter_id() -> Int {
        return currentCharacter_id
    }

    func setConnectionId(_ connectionId: String) {
        DispatchQueue.main.async {
            print("🔗 HTTPManager 接收到 connection_id 設置: \(connectionId)")
            self.connectionId = connectionId
            print("✅ HTTPManager 已更新 connection_id 為: \(self.connectionId)")
        }
    }

    func getConnectionId() -> String {
        return connectionId
    }
}