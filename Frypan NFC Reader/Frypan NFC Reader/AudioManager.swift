//
//  AudioManager.swift
//  Frypan NFC Reader
//
//  Created by Claude on 5/9/2025.
//

import Foundation
import AVFoundation
import os.log

class AudioManager: NSObject, ObservableObject {
    
    @Published var isPlayingAudio = false
    
    private var audioPlayer: AVAudioPlayer?
    private let logger = Logger(subsystem: "com.frypan.nfc.reader", category: "Audio")
    
    override init() {
        super.init()
        setupAudioSession()
    }
    
    deinit {
        stopAudio()
    }
    
    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            logger.error("音頻會話設置失敗: \(error)")
        }
    }
    
    func playMP3Audio(_ data: Data) {
        DispatchQueue.main.async { [weak self] in
            self?.playAudioOnMainThread(data)
        }
    }
    
    private func playAudioOnMainThread(_ data: Data) {
        stopAudio()
        
        guard data.count > 0 else {
            logger.error("音頻數據為空")
            return
        }
        
        do {
            let player = try AVAudioPlayer(data: data, fileTypeHint: AVFileType.mp3.rawValue)
            audioPlayer = player
            player.delegate = self
            player.volume = 1.0
            
            if player.play() {
                isPlayingAudio = true
                logger.info("播放開始，時長: \(player.duration)s")
            } else {
                logger.error("播放失敗")
            }
        } catch {
            logger.error("播放錯誤: \(error)")
        }
    }
    
    func stopAudio() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlayingAudio = false
    }
}

extension AudioManager: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlayingAudio = false
        logger.info("播放完成")
    }
    
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        isPlayingAudio = false
        logger.error("解碼錯誤: \(error?.localizedDescription ?? "未知錯誤")")
    }
}
