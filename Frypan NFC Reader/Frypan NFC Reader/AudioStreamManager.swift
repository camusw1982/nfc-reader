//
//  AudioStreamManager.swift
//  Frypan NFC Reader
//
//  Created by Claude on 5/9/2025.
//

import Foundation
import AVFoundation

// MARK: - Audio Stream Types
enum AudioStreamType {
    case minimax   // MiniMax 格式：data.audio, data.status
}

// MARK: - Audio Stream Manager Protocol
protocol AudioStreamManagerDelegate: AnyObject {
    func audioStreamManager(_ manager: AudioStreamManager, didUpdatePlayingState isPlaying: Bool)
    func audioStreamManager(_ manager: AudioStreamManager, didUpdateProgress progress: Double)
    func audioStreamManager(_ manager: AudioStreamManager, didEncounterError error: String)
}

// MARK: - Audio Stream Manager
class AudioStreamManager: NSObject {
    
    weak var delegate: AudioStreamManagerDelegate?
    
    // MARK: - Properties
    private var audioPlayer: AVAudioPlayer?
    private var isPlayingAudio = false
    private var audioProgress: Double = 0.0
    
    // MiniMax streaming properties
    private var minimaxChunks: [Data] = []
    private var isMinimaxStreaming = false
    private var currentChunkIndex = 0
    private var isLastChunkReceived = false
    
    // MARK: - Setup
    func setup() {
        setupAudioSession()
    }
    
    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            print("🎵 音頻會話設置成功")
        } catch {
            print("❌ 音頻會話設置失敗: \(error.localizedDescription)")
            delegate?.audioStreamManager(self, didEncounterError: "音頻會話設置失敗")
        }
    }
    
    // MARK: - Audio Control
    func stopAudio() {
        audioPlayer?.stop()
        audioPlayer = nil
        
        updatePlayingState(false)
        updateProgress(0.0)
        
        print("🛑 停止音頻播放")
    }
    
    func resetState() {
        print("🔄 重置音頻狀態")
        stopAudio()
        resetMinimaxStreaming()
    }
    
    private func resetMinimaxStreaming() {
        minimaxChunks.removeAll()
        isMinimaxStreaming = false
        currentChunkIndex = 0
        isLastChunkReceived = false
        print("🔄 重置 MiniMax 串流狀態")
    }
    
    // MARK: - Audio Stream Processing
    func handleAudioChunk(_ json: [String: Any]) {
        print("🔍 [DEBUG] 收到音頻數據，JSON keys: \(json.keys)")
        handleMiniMaxAudio(json)
    }
    
    
    private func handleMiniMaxAudio(_ json: [String: Any]) {
        // 檢查是否為服務器發送的格式：minimax_audio_chunk
        if let messageType = json["type"] as? String, messageType == "minimax_audio_chunk" {
            handleServerMinimaxFormat(json)
        } else {
            // 檢查是否為直接的 MiniMax 格式
            handleDirectMinimaxFormat(json)
        }
    }
    
    private func handleServerMinimaxFormat(_ json: [String: Any]) {
        guard let minimaxResponse = json["minimax_response"] as? [String: Any],
              let data = minimaxResponse["data"] as? [String: Any],
              let audioHex = data["audio"] as? String,
              let status = data["status"] as? Int,
              let audioData = Data(hexString: audioHex) else {
            print("❌ 服務器 MiniMax 音頻數據解析失敗")
            return
        }
        
        let chunkIndex = json["chunk_index"] as? Int ?? -1
        print("📦 收到服務器 MiniMax 音頻 chunk \(chunkIndex): \(audioData.count) bytes, status: \(status)")
        
        if status == 1 {
            // 普通音頻塊 - 添加到播放隊列
            minimaxChunks.append(audioData)
            
            if !isMinimaxStreaming {
                // 開始串流播放
                startMinimaxStreaming()
            } else if currentChunkIndex >= minimaxChunks.count - 1 {
                // 如果串流已停止等待更多塊，現在有新的塊了，繼續播放
                print("🔄 收到新塊，繼續串流播放")
                playMinimaxChunk(at: currentChunkIndex + 1)
            }
        } else if status == 2 {
            // 最後一個音頻塊 - 這是一個合併的大塊，不添加到播放隊列
            isLastChunkReceived = true
            print("🏁 收到最後一個服務器 MiniMax 音頻塊（合併塊，不播放）")
            
            if !isMinimaxStreaming {
                // 如果還沒開始播放，現在開始
                startMinimaxStreaming()
            }
            // 注意：不播放 status=2 的塊，因為它是合併塊
        }
    }
    
    private func handleDirectMinimaxFormat(_ json: [String: Any]) {
        guard let data = json["data"] as? [String: Any],
              let audioHex = data["audio"] as? String,
              let status = data["status"] as? Int,
              let audioData = Data(hexString: audioHex) else {
            print("❌ 直接 MiniMax 音頻數據解析失敗")
            return
        }
        
        print("📦 收到直接 MiniMax 音頻: \(audioData.count) bytes, status: \(status)")
        
        if status == 1 {
            // 普通音頻塊 - 添加到播放隊列
            minimaxChunks.append(audioData)
            
            if !isMinimaxStreaming {
                // 開始串流播放
                startMinimaxStreaming()
            }
        } else if status == 2 {
            // 最後一個音頻塊 - 這是一個合併的大塊，不添加到播放隊列
            isLastChunkReceived = true
            print("🏁 收到最後一個直接 MiniMax 音頻塊（合併塊，不播放）")
            
            if !isMinimaxStreaming {
                // 如果還沒開始播放，現在開始
                startMinimaxStreaming()
            }
            // 注意：不播放 status=2 的塊，因為它是合併塊
        }
    }
    
    private func startMinimaxStreaming() {
        guard !minimaxChunks.isEmpty && !isMinimaxStreaming else { return }
        
        isMinimaxStreaming = true
        currentChunkIndex = 0
        
        print("🎵 開始 MiniMax 音頻串流，總共 \(minimaxChunks.count) 個塊")
        
        // 播放第一個塊
        playMinimaxChunk(at: currentChunkIndex)
    }
    
    private func playMinimaxChunk(at index: Int) {
        guard index < minimaxChunks.count else {
            print("❌ MiniMax 塊索引超出範圍: \(index)")
            return
        }
        
        let chunkData = minimaxChunks[index]
        print("🎵 播放 MiniMax 塊 \(index + 1)/\(minimaxChunks.count)")
        
        playAudio(data: chunkData)
    }
    
    private func playNextMinimaxChunk() {
        currentChunkIndex += 1
        
        if currentChunkIndex < minimaxChunks.count {
            // 還有更多塊要播放
            playMinimaxChunk(at: currentChunkIndex)
        } else if isLastChunkReceived {
            // 所有塊都播放完成，且已收到最後一個塊
            print("✅ MiniMax 音頻串流完成")
            finishMinimaxStreaming()
        } else {
            // 所有已收到的塊都播放完成，但可能還有更多塊要來
            print("⏳ 等待更多 MiniMax 音頻塊...")
            // 暫時停止播放，等待更多塊
            isMinimaxStreaming = false
        }
    }
    
    private func finishMinimaxStreaming() {
        print("🏁 MiniMax 音頻串流結束")
        resetMinimaxStreaming()
    }
    
    
    private func playAudio(data: Data) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // 停止當前播放
            self.audioPlayer?.stop()
            self.audioPlayer = nil
            
            do {
                // 創建新的播放器
                self.audioPlayer = try AVAudioPlayer(data: data)
                guard let player = self.audioPlayer else {
                    print("❌ 音頻播放器創建失敗")
                    return
                }
                
                player.delegate = self
                player.volume = 1.0
                
                let success = player.play()
                if success {
                    print("✅ 音頻播放開始，時長: \(player.duration) 秒")
                    self.updatePlayingState(true)
                    self.updateProgress(0.0)
                } else {
                    print("❌ 音頻播放失敗")
                }
                
            } catch {
                print("❌ 音頻播放錯誤: \(error.localizedDescription)")
                self.delegate?.audioStreamManager(self, didEncounterError: "音頻播放失敗")
            }
        }
    }
    
    // MARK: - Helper Methods
    private func updatePlayingState(_ isPlaying: Bool) {
        isPlayingAudio = isPlaying
        delegate?.audioStreamManager(self, didUpdatePlayingState: isPlaying)
    }
    
    private func updateProgress(_ progress: Double) {
        audioProgress = progress
        delegate?.audioStreamManager(self, didUpdateProgress: progress)
    }
}

// MARK: - AVAudioPlayerDelegate
extension AudioStreamManager: AVAudioPlayerDelegate {
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        print("🎵 音頻播放完成")
        
        updatePlayingState(false)
        updateProgress(0.0)
        audioPlayer = nil
        
        // 檢查是否為 MiniMax 串流
        if isMinimaxStreaming {
            print("🔄 MiniMax 塊播放完成，播放下一個")
            playNextMinimaxChunk()
        } else {
            print("✅ 音頻播放完成")
        }
    }
    
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        print("❌ 音頻解碼錯誤: \(error?.localizedDescription ?? "未知錯誤")")
        
        updatePlayingState(false)
        updateProgress(0.0)
        audioPlayer = nil
        
        if let error = error {
            delegate?.audioStreamManager(self, didEncounterError: "音頻解碼錯誤: \(error.localizedDescription)")
        }
        
        // 檢查是否為 MiniMax 串流
        if isMinimaxStreaming {
            print("🔄 MiniMax 塊播放錯誤，嘗試播放下一個")
            playNextMinimaxChunk()
        }
    }
}

// MARK: - Data Extension for Hex String
extension Data {
    init?(hexString: String) {
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
        self = data
    }
}
