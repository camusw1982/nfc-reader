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

// MARK: - Character Response Models
struct HTTPCharacterValidationResponse: Codable {
    let data: CharacterData
    let success: Bool
    let message: String?
}

struct CharacterData: Codable {
    let character_id: Int
    let name: String
    let voice_id: String
    let available: String

    // 計算屬性，方便使用
    var isActive: Bool {
        return available.lowercased() == "active" || available.lowercased() == "true"
    }
}

struct HTTPSessionResponse: Codable {
    let connection_id: String
    let success: Bool
    let message: String?
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
    @Published var currentCharacter_id: Int = 9999 {
        didSet {
            logger.info("Character ID changed from \(oldValue) to \(self.currentCharacter_id)")
        }
    }
    @Published var characterName: String = "Unknown Character"
    
    // MARK: - Speech Recognizer Reference
    weak var speechRecognizer: SpeechRecognizer?
    
    // MARK: - Private Properties
    private let serverURL: URL
    private let characterServerURL: URL
    private let audioManager: AudioManager
    private var miniMaxStreamManager: MiniMaxStreamManager?
    private let logger = Logger(subsystem: "com.frypan.nfc.reader", category: "HTTP")
    private var connectionCheckTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Character Cache
    private var characterCache: [Int: String] = [:]
    private var characterVoiceCache: [Int: String] = [:]
    private let cacheValidityDuration: TimeInterval = 300 // 5 minutes

    // MARK: - Initialization
    override init() {
        // HTTP 服務器地址
        self.serverURL = Self.createServerURL()
        self.characterServerURL = Self.createCharacterServerURL()
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

    private static func createCharacterServerURL() -> URL {
        if let customURL = ProcessInfo.processInfo.environment["CHARACTER_SERVER_URL"],
           let url = URL(string: customURL) {
            return url
        }
        return URL(string: "http://145.79.12.177:10001")!
    }
    
    private func setupAudioBinding() {
        // 綁定音頻管理器的狀態到 HTTP 管理器
        audioManager.$isPlayingAudio
            .sink { [weak self] audioPlaying in
                DispatchQueue.main.async {
                    self?.updatePlayingState()
                }
            }
            .store(in: &cancellables)

        // 監聽 MiniMaxStreamManager 嘅播放狀態
        if let streamManager = miniMaxStreamManager {
            streamManager.$isPlaying
                .sink { [weak self] streamPlaying in
                    DispatchQueue.main.async {
                        self?.updatePlayingState()
                    }
                }
                .store(in: &cancellables)
        }
    }

    private func updatePlayingState() {
        let audioPlaying = audioManager.isPlayingAudio
        let streamPlaying = miniMaxStreamManager?.isPlaying ?? false
        let newState = streamPlaying || audioPlaying

        logger.info("更新播放狀態 - AudioManager: \(audioPlaying), MiniMax: \(streamPlaying), 新狀態: \(newState)")

        // 只有當狀態真正改變時先更新
        if self.isPlayingAudio != newState {
            self.isPlayingAudio = newState
            logger.info("播放狀態已更改為: \(newState)")
        }
    }
    
    private func setupMiniMaxStreamManager() {
        guard let apiKey = Bundle.main.object(forInfoDictionaryKey: "MINIMAX_API_KEY") as? String,
              !apiKey.isEmpty else {
            logger.warning("MiniMax API Key 未設置，語音合成功能將不可用")
            return
        }

        // 清理現有嘅訂閱
        cancellables.removeAll()

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

        // 清理 Combine 訂閱
        cancellables.removeAll()

        // 清理快取
        characterCache.removeAll()
        characterVoiceCache.removeAll()

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
            
            if previousState != connected {
                NotificationCenter.default.post(
                    name: .HTTPConnectionChanged,
                    object: connected
                )
                self.logger.info("HTTP 連接狀態變更: \(connected)")
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
    
    /// 發送聊天消息 (使用新架構)
    func sendText(_ text: String, character_id: Int? = nil) {
        let character_idToUse = character_id ?? currentCharacter_id

        Task {
            do {
                // 如果冇 connection_id，先創建會話
                if self.connectionId.isEmpty {
                    let newConnectionId = try await createSession(characterId: character_idToUse)
                    await setConnectionId(newConnectionId)
                }

                let request = HTTPChatRequest(
                    type: "text",
                    text: text,
                    character_id: character_idToUse,
                    streaming: nil,
                    connection_id: connectionId
                )

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
    
    /// 發送語音合成請求 (使用新架構)
    func sendTextToSpeech(text: String, character_id: Int? = nil) {
        let character_idToUse = character_id ?? currentCharacter_id

        Task {
            do {
                // 如果冇 connection_id，先創建會話
                if self.connectionId.isEmpty {
                    let newConnectionId = try await createSession(characterId: character_idToUse)
                    await setConnectionId(newConnectionId)
                }

                let request = HTTPChatRequest(
                    type: "gemini_chat",
                    text: text,
                    character_id: character_idToUse,
                    streaming: true,
                    connection_id: connectionId
                )

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
                    method: "GET",
                    body: Optional<String>.none
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
                    method: "POST",
                    body: Optional<String>.none
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
                    method: "GET",
                    body: Optional<String>.none
                )
                
                if let response = try? JSONDecoder().decode(HTTPHistoryResponse.self, from: data) {
                    logger.info("獲取歷史記錄: \(response.messages.count) 條消息")
                }
                
            } catch {
                handleHTTPError(error)
            }
        }
    }
    
    // MARK: - New Architecture Methods

    /// 驗證角色 ID (使用 character_login_server, port 10001)
    func validateCharacter(_ characterId: Int) async throws -> CharacterData {
        let url = characterServerURL.appendingPathComponent("/api/character/\(characterId)")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30.0

        logger.info("嘗試驗證角色: \(url)")
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        logger.info("角色驗證回應狀態: \(httpResponse.statusCode)")
        logger.info("角色驗證回應數據: \(String(data: data, encoding: .utf8) ?? "Invalid UTF-8")")

        guard (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let validationResponse = try JSONDecoder().decode(HTTPCharacterValidationResponse.self, from: data)

        guard validationResponse.success else {
            throw NSError(domain: "CharacterValidation", code: 0, userInfo: [NSLocalizedDescriptionKey: validationResponse.message ?? "Character validation failed"])
        }

        return validationResponse.data
    }

    /// 創建會話 (使用 http_server, port 10000)
    func createSession(characterId: Int) async throws -> String {
        let sessionRequest = ["character_id": characterId]
        let (data, _) = try await performHTTPCall(
            endpoint: "/api/session/new",
            method: "POST",
            body: sessionRequest
        )

        let sessionResponse = try JSONDecoder().decode(HTTPSessionResponse.self, from: data)

        guard sessionResponse.success else {
            throw NSError(domain: "SessionCreation", code: 0, userInfo: [NSLocalizedDescriptionKey: sessionResponse.message ?? "Failed to create session"])
        }

        return sessionResponse.connection_id
    }

    /// 獲取角色名稱 (使用新架構 + fallback)
    func getCharacterName(for character_id: Int? = nil) {
        let targetId = character_id ?? currentCharacter_id

        // 檢查快取
        if let cachedName = characterCache[targetId] {
            DispatchQueue.main.async {
                self.characterName = cachedName
            }
            return
        }

        Task {
            do {
                // 嘗試使用新架構 (port 10001)
                let characterData = try await validateCharacter(targetId)
                await handleCharacterValidationResponse(characterData)
            } catch {
                logger.warning("新架構角色驗證失敗，回退到舊架構: \(error.localizedDescription)")

                // Fallback: 嘗試舊架構 (port 10000)
                do {
                    logger.info("嘗試舊架構角色獲取: /api/character")
                    let request = HTTPCharacterRequest(character_id: targetId)
                    let (data, _) = try await performHTTPCall(
                        endpoint: "/api/character",
                        method: "POST",
                        body: request
                    )

                    logger.info("舊架構回應數據: \(String(data: data, encoding: .utf8) ?? "Invalid UTF-8")")

                    if let response = try? JSONDecoder().decode(HTTPCharacterResponse.self, from: data) {
                        await handleCharacterResponse(response)
                    }
                } catch {
                    logger.error("角色驗證完全失敗: \(error.localizedDescription)")
                    handleHTTPError(error)
                }
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
        request.timeoutInterval = 30.0

        if let body = body {
            request.httpBody = try JSONEncoder().encode(body)
        }

        return try await performRequestWithRetry(request)
    }

    private func performRequestWithRetry(_ request: URLRequest, maxRetries: Int = 2) async throws -> (Data, URLResponse) {
        var lastError: Error?

        for attempt in 0...maxRetries {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }

                guard (200...299).contains(httpResponse.statusCode) else {
                    throw URLError(.badServerResponse)
                }

                return (data, response)
            } catch {
                lastError = error

                if attempt < maxRetries {
                    let delay = Double(attempt + 1) * 1.0
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }
            }
        }

        throw lastError ?? URLError(.unknown)
    }
}

// MARK: - Response Handling
extension HTTPManager {
    
    @MainActor
    private func handleChatResponse(_ response: HTTPChatResponse) {
        if response.success {
            self.geminiResponse = response.response

            let aiMessage = ChatMessage(text: response.response, isUser: false, timestamp: Date(), isError: false)
            self.speechRecognizer?.messages.append(aiMessage)

            // 優先從角色快取獲取 voice_id，其次使用 response 中的 voice_id，最後使用預設值
            let characterId = response.character_id ?? currentCharacter_id
            let voiceId = characterVoiceCache[characterId] ?? response.voice_id ?? "moss_audio_af916082-2e36-11f0-92db-0e8893cbb430"

            logger.info("使用 voice ID: \(voiceId) for character ID: \(characterId)")
            triggerTextToSpeech(response.response, voiceId: voiceId)

        } else {
            self.lastError = response.error ?? "Unknown error"
        }
    }
    
    @MainActor
    private func handleCharacterValidationResponse(_ characterData: CharacterData) {
        updateCharacterName(characterData.name, for: characterData.character_id)
        // 更新快取
        characterCache[characterData.character_id] = characterData.name
        characterVoiceCache[characterData.character_id] = characterData.voice_id
        logger.info("角色驗證成功: \(characterData.name) (ID: \(characterData.character_id), Status: \(characterData.available), Voice: \(characterData.voice_id))")
    }

    @MainActor
    private func handleCharacterResponse(_ response: HTTPCharacterResponse) {
        if response.success {
            updateCharacterName(response.character_name, for: response.character_id)
            // 更新快取
            characterCache[response.character_id] = response.character_name
            // 注意：舊架構冇 voice_id，需要從其他地方獲取
        } else {
            self.lastError = response.error ?? "Failed to get character name"
        }
    }
    
    private func triggerTextToSpeech(_ text: String, voiceId: String) {
        guard !text.isEmpty, let miniMaxManager = miniMaxStreamManager else {
            logger.warning("MiniMax 串流管理器未初始化")
            return
        }

        miniMaxManager.startStreaming(text: text, voiceId: voiceId)
    }
}

// MARK: - Public Interface
extension HTTPManager {
    
    func stopAudio() {
        miniMaxStreamManager?.stopStreaming()
        audioManager.stopAudio()
    }
    
    func setCharacter_id(_ character_id: Int) {
        DispatchQueue.main.async {
            self.currentCharacter_id = character_id
            self.characterName = "Unknown Character"
            self.getCharacterName(for: character_id)
        }
    }

    /// 強制刷新角色數據以獲取最新嘅 voice_id
    func refreshCharacterData(_ character_id: Int? = nil) {
        let targetId = character_id ?? currentCharacter_id

        Task {
            do {
                logger.info("刷新角色數據: \(targetId)")
                let characterData = try await validateCharacter(targetId)
                await handleCharacterValidationResponse(characterData)
            } catch {
                logger.warning("刷新角色數據失敗: \(error.localizedDescription)")
            }
        }
    }
    
    func getCurrentCharacter_id() -> Int {
        return currentCharacter_id
    }

    @MainActor
    func setConnectionId(_ connectionId: String) {
        self.connectionId = connectionId
        logger.info("設置連接 ID: \(connectionId)")
    }

    /// 重置連接 ID
    func resetConnectionId() {
        DispatchQueue.main.async {
            self.connectionId = ""
            self.logger.info("重置連接 ID")
        }
    }

    func getConnectionId() -> String {
        return connectionId
    }

    func playPCMAudio(_ data: Data) {
        audioManager.playMP3Audio(data)
    }
}