//
//  AudioManager.swift
//  Frypan NFC Reader
//
//  Created by Claude on 5/9/2025.
//

import Foundation
import AVFoundation
import os.log

// MARK: - Audio Manager Protocol
protocol AudioManagerProtocol: ObservableObject {
    var isPlayingAudio: Bool { get }
    var audioProgress: Double { get }
    
    func playMP3Audio(_ data: Data)
    func stopAudio()
}

// MARK: - Audio Manager
class AudioManager: NSObject, AudioManagerProtocol {
    
    // MARK: - Published Properties
    @Published var isPlayingAudio = false
    @Published var audioProgress: Double = 0.0
    
    // MARK: - Private Properties
    private var audioPlayer: AVAudioPlayer?
    private let logger = Logger(subsystem: "com.frypan.nfc.reader", category: "Audio")
    
    // MARK: - Initialization
    override init() {
        super.init()
        setupAudio()
    }
    
    deinit {
        stopAudio()
    }
    
    // MARK: - Setup Methods
    private func setupAudio() {
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            logger.info("音頻會話設置成功")
        } catch {
            logger.error("音頻會話設置失敗: \(error.localizedDescription)")
        }
        #else
        logger.info("音頻設置完成 (macOS)")
        #endif
    }
    
    // MARK: - Public Methods
    func playMP3Audio(_ data: Data) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // 停止當前播放
            self.audioPlayer?.stop()
            self.audioPlayer = nil
            
            logger.info("播放 MP3 音頻數據: \(data.count) bytes")
            
            // 檢查數據大小
            guard data.count > 0 else {
                logger.error("音頻數據為空")
                return
            }
            
            // MiniMax 直接返回 MP3 格式，直接播放
            do {
                let player = try AVAudioPlayer(data: data, fileTypeHint: AVFileType.mp3.rawValue)
                self.audioPlayer = player
                player.volume = 1.0
                player.prepareToPlay()
                
                if player.play() {
                    logger.info("MP3 音頻播放開始，時長: \(player.duration) 秒")
                    self.isPlayingAudio = true
                } else {
                    logger.error("MP3 音頻播放失敗")
                    self.isPlayingAudio = false
                }
            } catch {
                logger.error("MP3 音頻播放錯誤: \(error.localizedDescription)")
            }
        }
    }
    
    func stopAudio() {
        // 直接在主線程執行，避免在釋放過程中使用 weak self
        audioPlayer?.stop()
        audioPlayer = nil
        isPlayingAudio = false
        audioProgress = 0.0
    }
}
