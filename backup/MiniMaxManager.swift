//
//  MiniMaxManager.swift
//  Frypan NFC Reader
//
//  Created by Claude on 5/9/2025.
//

import Foundation
import Combine
import AVFoundation

// MARK: - MiniMax Manager (簡化版本)
class MiniMaxManager: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    @Published var isConnected = false
    @Published var isGenerating = false
    @Published var isPlaying = false
    @Published var connectionStatus: String = "未連接"
    @Published var lastError: String?
    @Published var audioProgress: Double = 0.0
    @Published var audioDuration: Double = 0.0
    @Published var currentAudioTime: Double = 0.0
    
    // MARK: - Properties
    private var audioPlayer: AVAudioPlayer?
    private var cancellables = Set<AnyCancellable>()
    private let apiKey: String
    
    // MARK: - Initialization
    init(apiKey: String) {
        self.apiKey = apiKey
        super.init()
        
        setupAudio()
    }
    
    deinit {
        disconnect()
    }
    
    // MARK: - Setup
    private func setupAudio() {
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            print("❌ 音頻會話設置失敗: \(error.localizedDescription)")
        }
        #endif
    }
}

// MARK: - Connection Management
extension MiniMaxManager {
    
    func connect() {
        isConnected = true
        connectionStatus = "已連接"
    }
    
    func disconnect() {
        isConnected = false
        connectionStatus = "已斷開"
        stopAudio()
    }
}

// MARK: - Text to Speech
extension MiniMaxManager {
    
    func textToSpeech(_ text: String) {
        guard !text.isEmpty else {
            lastError = "文本不能為空"
            return
        }
        
        print("🎤 MiniMaxManager 文本轉語音: \(text.prefix(50))...")
        isGenerating = true
        
        // 這裡可以添加實際的文本轉語音邏輯
        // 目前只是一個佔位符
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.isGenerating = false
        }
    }
    
    func stopGeneration() {
        isGenerating = false
    }
}

// MARK: - Audio Control
extension MiniMaxManager {
    
    func playAudio() {
        audioPlayer?.play()
        isPlaying = true
    }
    
    func pauseAudio() {
        audioPlayer?.pause()
        isPlaying = false
    }
    
    func stopAudio() {
        audioPlayer?.stop()
        isPlaying = false
    }
    
    func seekAudio(to time: Double) {
        audioPlayer?.currentTime = time
    }
}

// MARK: - Utility Methods
extension MiniMaxManager {
    
    func getFormattedDuration() -> String {
        let duration = audioDuration
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    func getFormattedCurrentTime() -> String {
        let time = currentAudioTime
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    func getFormattedRemainingTime() -> String {
        let remaining = audioDuration - currentAudioTime
        let minutes = Int(remaining) / 60
        let seconds = Int(remaining) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}