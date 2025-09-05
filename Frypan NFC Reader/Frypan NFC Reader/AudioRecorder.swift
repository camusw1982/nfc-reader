//
//  AudioRecorder.swift
//  Frypan NFC Reader
//
//  Created by Wong Chi Man on 4/9/2025.
//

import Foundation
import AVFoundation
import SwiftUI

extension Notification.Name {
    static let audioRecordingFinished = Notification.Name("audioRecordingFinished")
    static let audioRecordingFailed = Notification.Name("audioRecordingFailed")
}

class AudioRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published var isRecording = false
    @Published var audioURL: URL?
    @Published var recordingTime: TimeInterval = 0
    
    private var audioRecorder: AVAudioRecorder?
    private var timer: Timer?
    
    // Opus 音頻設定
    private let audioSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC, // 改用 AAC 格式，iOS 對 Opus 支持唔係咁好
        AVSampleRateKey: 44100,
        AVNumberOfChannelsKey: 1,
        AVEncoderBitRateKey: 128000,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
    ]
    
    override init() {
        super.init()
        setupAudioSession()
    }
    
    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
            print("Audio session setup successfully")
        } catch {
            print("Failed to setup audio session: \(error)")
        }
    }
    
    func startRecording() {
        guard !isRecording else { return }
        
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let filename = "recording_\(Date().timeIntervalSince1970).m4a" // 改用 .m4a 副檔名
        let audioFileURL = documentsPath.appendingPathComponent(filename)
        
        do {
            audioRecorder = try AVAudioRecorder(url: audioFileURL, settings: audioSettings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true
            
            if audioRecorder?.record() == true {
                isRecording = true
                audioURL = audioFileURL
                startTimer()
                print("Recording started at: \(audioFileURL.path)")
            } else {
                print("Failed to start recording")
            }
        } catch {
            print("Failed to start recording: \(error)")
        }
    }
    
    func stopRecording() {
        guard isRecording else { return }
        
        isRecording = false  // 立即更新狀態
        audioRecorder?.stop()
        stopTimer()
        
        // 等待錄音器完全停止
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.audioRecorder = nil
            print("Recording stopped successfully")
        }
    }
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.recordingTime += 0.1
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        isRecording = false
        if flag {
            print("Recording finished successfully")
            // 通知錄音完成
            NotificationCenter.default.post(name: .audioRecordingFinished, object: audioURL)
        } else {
            print("Recording failed")
            NotificationCenter.default.post(name: .audioRecordingFailed, object: nil)
        }
    }
    
    func formatRecordingTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let milliseconds = Int((time.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%02d:%02d.%d", minutes, seconds, milliseconds)
    }
    
    func resetRecording() {
        recordingTime = 0
        audioURL = nil
        isRecording = false
    }
}