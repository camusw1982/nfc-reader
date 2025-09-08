//
//  ServiceProtocol.swift
//  Frypan NFC Reader
//
//  Created by Claude on 8/9/2025.
//

import Foundation
import Combine

// MARK: - Service Protocol
protocol ServiceProtocol: ObservableObject {
    var isConnected: Bool { get set }
    var connectionStatus: String { get set }
    var lastError: String? { get set }
    var receivedMessages: [String] { get set }
    var isPlayingAudio: Bool { get set }
    var geminiResponse: String { get set }
    var connectionId: String { get set }
    var currentCharacter_id: Int { get set }
    var characterName: String { get set }
    
    var speechRecognizer: SpeechRecognizer? { get set }
    
    func connect()
    func disconnect()
    func sendText(_ text: String, character_id: Int?)
    func sendTextToSpeech(text: String, character_id: Int?)
    func ping()
    func clearHistory()
    func getHistory()
    func getCharacterName(for character_id: Int?)
    func updateCharacterName(_ name: String, for character_id: Int?)
    func setCharacter_id(_ character_id: Int)
    func getCurrentCharacter_id() -> Int
    func playMP3Audio(_ data: Data)
    func stopAudio()
}

// Notification names are defined in HTTPManager.swift and WebSocketManager.swift