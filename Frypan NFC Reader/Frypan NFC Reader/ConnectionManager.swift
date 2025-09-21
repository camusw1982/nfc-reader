//
//  ConnectionManager.swift
//  Frypan NFC Reader
//
//  Created by Claude on 21/9/2025.
//

import Foundation
import Combine
import os.log
import SwiftUI

// MARK: - Connection State
enum ConnectionState {
    case disconnected
    case connecting
    case connected(String)
    case error(String)
}

// MARK: - Connection Error
enum ConnectionError: Error, LocalizedError {
    case sessionCreationFailed(String)
    case networkError(Error)
    case invalidResponse
    case serverError(Int, String)

    var errorDescription: String? {
        switch self {
        case .sessionCreationFailed(let message):
            return "會話創建失敗: \(message)"
        case .networkError(let error):
            return "網絡錯誤: \(error.localizedDescription)"
        case .invalidResponse:
            return "服務器響應格式錯誤"
        case .serverError(let code, let message):
            return "服務器錯誤 (\(code)): \(message)"
        }
    }
}

// MARK: - Connection Manager
class ConnectionManager: ObservableObject {
    static let shared = ConnectionManager()

    @Published var connectionState: ConnectionState = .disconnected
    @Published var currentConnectionId: String = ""
    @Published var currentCharacterId: Int = 0
    @Published var isLoading: Bool = false
    @Published var lastError: String?

    private let logger = Logger(subsystem: "ConnectionManager", category: "Connection")
    private let serverURL = URL(string: "http://145.79.12.177:10000")!
    private var cancellables = Set<AnyCancellable>()

    // UserDefaults keys
    private enum StorageKeys {
        static let connectionId = "current_connection_id"
        static let characterId = "current_character_id"
    }

    private init() {
        setupObservers()
        // 從持久化存儲加載連接信息
        loadConnectionFromStorage()
    }

    // MARK: - Public Methods

    /// 創建新會話
    func createSession(characterId: Int) async throws -> String {
        await MainActor.run {
            self.connectionState = .connecting
            self.isLoading = true
            self.lastError = nil
        }

        do {
            let connectionId = try await performSessionCreation(characterId: characterId)

            await MainActor.run {
                self.currentConnectionId = connectionId
                self.currentCharacterId = characterId
                self.connectionState = .connected(connectionId)
                self.isLoading = false

                // 持久化存儲連接信息
                self.saveConnectionToStorage()
            }

            return connectionId
        } catch {
            await MainActor.run {
                self.connectionState = .error(error.localizedDescription)
                self.isLoading = false
                self.lastError = error.localizedDescription
                self.logger.error("❌ 會話創建失敗: \(error.localizedDescription)")
            }
            throw error
        }
    }

    /// 獲取當前連接 ID
    func getCurrentConnectionId() -> String {
        return currentConnectionId
    }

    /// 檢查連接是否有效
    func isConnectionValid() -> Bool {
        switch connectionState {
        case .connected:
            return !currentConnectionId.isEmpty
        case .disconnected, .connecting, .error:
            return false
        }
    }

    /// 清除當前連接
    func clearConnection() {
        Task { @MainActor in
            currentConnectionId = ""
            currentCharacterId = 0
            connectionState = .disconnected
            lastError = nil

            // 清除持久化存儲
            clearConnectionFromStorage()
        }
    }

    /// 驗證並刷新連接
    func validateAndRefreshConnection(characterId: Int) async throws -> String {
        if isConnectionValid() && currentCharacterId == characterId {
            return self.currentConnectionId
        } else {
            return try await createSession(characterId: characterId)
        }
    }

    /// 強制創建新連接 (用於 NFC scan 後)
    func forceCreateNewConnection(characterId: Int) async throws -> String {
        // 先清除現有連接
        await MainActor.run {
            clearConnection()
        }

        // 創建新連接
        return try await createSession(characterId: characterId)
    }

    // MARK: - Private Methods

    private func performSessionCreation(characterId: Int) async throws -> String {
        let url = serverURL.appendingPathComponent("/api/session/new")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30.0

        let body = ["character_id": characterId]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)


        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConnectionError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ConnectionError.serverError(httpResponse.statusCode, errorMessage)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let success = json["success"] as? Bool,
              success,
              let connectionId = json["connection_id"] as? String else {
            throw ConnectionError.invalidResponse
        }

        return connectionId
    }

    private func setupObservers() {
        // 監聽連接狀態變化
        $connectionState
            .sink { [weak self] state in
                self?.logConnectionState(state)
            }
            .store(in: &cancellables)
    }

    private func logConnectionState(_ state: ConnectionState) {
        switch state {
        case .error(let error):
            logger.error("📡 連接狀態: 錯誤 (\(error))")
        case .disconnected, .connecting, .connected:
            break
        }
    }

    // MARK: - Persistent Storage Methods

    private func saveConnectionToStorage() {
        DispatchQueue.main.async {
            let defaults = UserDefaults.standard
            defaults.set(self.currentConnectionId, forKey: StorageKeys.connectionId)
            defaults.set(self.currentCharacterId, forKey: StorageKeys.characterId)
        }
    }

    private func loadConnectionFromStorage() {
        DispatchQueue.main.async {
            let defaults = UserDefaults.standard
            let savedConnectionId = defaults.string(forKey: StorageKeys.connectionId) ?? ""
            let savedCharacterId = defaults.integer(forKey: StorageKeys.characterId)

            if !savedConnectionId.isEmpty && savedCharacterId > 0 {
                self.currentConnectionId = savedConnectionId
                self.currentCharacterId = savedCharacterId
                self.connectionState = .connected(savedConnectionId)
            } else {
            }
        }
    }

    private func clearConnectionFromStorage() {
        DispatchQueue.main.async {
            let defaults = UserDefaults.standard
            defaults.removeObject(forKey: StorageKeys.connectionId)
            defaults.removeObject(forKey: StorageKeys.characterId)
        }
    }
}

// MARK: - Connection Response
struct ConnectionSessionResponse: Codable {
    let connection_id: String
    let success: Bool
    let message: String?
}