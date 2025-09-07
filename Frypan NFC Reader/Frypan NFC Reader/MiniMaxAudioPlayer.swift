//
//  MiniMaxAudioPlayer.swift
//  Frypan NFC Reader
//
//  Created by Claude on 5/9/2025.
//

import Foundation
import AVFoundation
import Combine

// MARK: - MiniMax Audio Player Protocol
protocol MiniMaxAudioPlayerDelegate: AnyObject {
    func miniMaxAudioPlayer(_ player: MiniMaxAudioPlayer, didStartPlaying: Bool)
    func miniMaxAudioPlayer(_ player: MiniMaxAudioPlayer, didFinishPlaying: Bool)
    func miniMaxAudioPlayer(_ player: MiniMaxAudioPlayer, didUpdateProgress progress: Double)
    func miniMaxAudioPlayer(_ player: MiniMaxAudioPlayer, didEncounterError error: String)
}

// MARK: - MiniMax Audio Player
class MiniMaxAudioPlayer: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    @Published var isPlaying = false
    @Published var isPaused = false
    @Published var progress: Double = 0.0
    @Published var duration: Double = 0.0
    @Published var currentTime: Double = 0.0
    @Published var lastError: String?
    
    // MARK: - Properties
    weak var delegate: MiniMaxAudioPlayerDelegate?
    private var audioPlayer: AVAudioPlayer?
    private var progressTimer: Timer?
    private var audioChunks: [Data] = []
    private var currentChunkIndex = 0
    private var isStreamingMode = false
    
    // MARK: - Initialization
    override init() {
        super.init()
        setupAudioSession()
    }
    
    deinit {
        stop()
        progressTimer?.invalidate()
    }
    
    // MARK: - Audio Session Setup
    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            
            // 檢查當前類別，避免重複設置
            if session.category != .playback {
                // 設置音頻類別
                try session.setCategory(.playback, mode: .default, options: [.allowBluetooth, .allowBluetoothA2DP])
            }
            
            // 只有在未激活時才激活
            if !session.isOtherAudioPlaying {
                try session.setActive(true)
            }
            
        } catch {
            // 如果設置失敗，嘗試更簡單的配置
            do {
                let session = AVAudioSession.sharedInstance()
                if session.category != .playback {
                    try session.setCategory(.playback)
                }
                if !session.isOtherAudioPlaying {
                    try session.setActive(true)
                }
            } catch {
                // 忽略 -50 錯誤，這是正常的音頻會話衝突
                if (error as NSError).code != -50 {
                    lastError = "音頻會話設置失敗: \(error.localizedDescription)"
                    delegate?.miniMaxAudioPlayer(self, didEncounterError: "音頻會話設置失敗: \(error.localizedDescription)")
                }
            }
        }
    }
}

// MARK: - Audio Control
extension MiniMaxAudioPlayer {
    
    func playAudioData(_ data: Data) {
        guard !data.isEmpty else {
            lastError = "音頻數據為空"
            return
        }
        
        
        do {
            // 停止當前播放
            stop()
            
            // 創建新的播放器
            audioPlayer = try AVAudioPlayer(data: data)
            guard let player = audioPlayer else {
                lastError = "音頻播放器創建失敗"
                return
            }
            
            player.delegate = self
            player.volume = 1.0
            player.prepareToPlay()
            
            let success = player.play()
            if success {
                duration = player.duration
                isPlaying = true
                isPaused = false
                startProgressTimer()
                delegate?.miniMaxAudioPlayer(self, didStartPlaying: true)
            } else {
                lastError = "音頻播放失敗"
                delegate?.miniMaxAudioPlayer(self, didEncounterError: "音頻播放失敗")
            }
            
        } catch {
            lastError = "音頻播放錯誤: \(error.localizedDescription)"
            delegate?.miniMaxAudioPlayer(self, didEncounterError: "音頻播放錯誤: \(error.localizedDescription)")
        }
    }
    
    func playAudioChunks(_ chunks: [Data]) {
        guard !chunks.isEmpty else {
            lastError = "音頻塊為空"
            return
        }
        
        
        // 合併所有音頻塊
        let combinedData = chunks.reduce(Data(), +)
        playAudioData(combinedData)
    }
    
    func playStreamingChunk(_ data: Data, chunkIndex: Int) {
        if !isStreamingMode {
            // 開始串流模式
            isStreamingMode = true
            audioChunks.removeAll()
            currentChunkIndex = 0
        }
        
        audioChunks.append(data)
        
        // 如果是第一個塊，立即開始播放
        if chunkIndex == 0 {
            playAudioData(data)
        }
    }
    
    func finishStreaming() {
        guard isStreamingMode else { return }
        
        isStreamingMode = false
        
        // 如果有未播放的塊，合併播放
        if currentChunkIndex < audioChunks.count - 1 {
            let remainingChunks = Array(audioChunks[(currentChunkIndex + 1)...])
            if !remainingChunks.isEmpty {
                let combinedData = remainingChunks.reduce(Data(), +)
                playAudioData(combinedData)
            }
        }
    }
    
    func pause() {
        guard let player = audioPlayer, player.isPlaying else { return }
        
        player.pause()
        isPlaying = false
        isPaused = true
        stopProgressTimer()
    }
    
    func resume() {
        guard let player = audioPlayer, isPaused else { return }
        
        let success = player.play()
        if success {
            isPlaying = true
            isPaused = false
            startProgressTimer()
        }
    }
    
    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        
        isPlaying = false
        isPaused = false
        progress = 0.0
        currentTime = 0.0
        duration = 0.0
        
        stopProgressTimer()
        
        // 重置串流狀態
        isStreamingMode = false
        audioChunks.removeAll()
        currentChunkIndex = 0
        
    }
    
    func seek(to time: Double) {
        guard let player = audioPlayer, duration > 0 else { return }
        
        let seekTime = min(max(time, 0), duration)
        player.currentTime = seekTime
        currentTime = seekTime
        progress = duration > 0 ? seekTime / duration : 0.0
        
    }
}

// MARK: - Progress Timer
extension MiniMaxAudioPlayer {
    
    private func startProgressTimer() {
        stopProgressTimer()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateProgress()
        }
    }
    
    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }
    
    private func updateProgress() {
        guard let player = audioPlayer, duration > 0 else { return }
        
        currentTime = player.currentTime
        progress = currentTime / duration
        
        delegate?.miniMaxAudioPlayer(self, didUpdateProgress: progress)
    }
}

// MARK: - AVAudioPlayerDelegate
extension MiniMaxAudioPlayer: AVAudioPlayerDelegate {
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        
        isPlaying = false
        isPaused = false
        progress = 1.0
        currentTime = duration
        
        stopProgressTimer()
        audioPlayer = nil
        
        delegate?.miniMaxAudioPlayer(self, didFinishPlaying: flag)
        
        // 如果是串流模式且還有更多塊，播放下一個
        if isStreamingMode && currentChunkIndex < audioChunks.count - 1 {
            currentChunkIndex += 1
            let nextChunk = audioChunks[currentChunkIndex]
            playAudioData(nextChunk)
        }
    }
    
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        
        isPlaying = false
        isPaused = false
        stopProgressTimer()
        audioPlayer = nil
        
        let errorMessage = "音頻解碼錯誤: \(error?.localizedDescription ?? "未知錯誤")"
        lastError = errorMessage
        delegate?.miniMaxAudioPlayer(self, didEncounterError: errorMessage)
        
        // 如果是串流模式，嘗試播放下一個塊
        if isStreamingMode && currentChunkIndex < audioChunks.count - 1 {
            currentChunkIndex += 1
            let nextChunk = audioChunks[currentChunkIndex]
            playAudioData(nextChunk)
        }
    }
}

// MARK: - Utility Methods
extension MiniMaxAudioPlayer {
    
    func getFormattedTime(_ time: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    func getFormattedDuration() -> String {
        return getFormattedTime(duration)
    }
    
    func getFormattedCurrentTime() -> String {
        return getFormattedTime(currentTime)
    }
    
    func getFormattedRemainingTime() -> String {
        let remaining = duration - currentTime
        return "-\(getFormattedTime(remaining))"
    }
}
