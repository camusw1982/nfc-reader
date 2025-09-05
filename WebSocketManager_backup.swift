//
//  WebSocketManager.swift
//  Frypan NFC Reader
//
//  Created by Claude on 5/9/2025.
//

import Foundation
import Combine
import AVFoundation

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

class WebSocketManager: NSObject, ObservableObject {
    @Published var isConnected = false
    @Published var connectionStatus: String = "未連接"
    @Published var lastError: String?
    @Published var receivedMessages: [String] = []
    
    // 音頻播放相關
    @Published var isPlayingAudio = false
    @Published var audioProgress: Double = 0.0
    private var hasStartedPlayback = false
    @Published var geminiResponse: String = ""
    @Published var connectionId: String = ""
    
    private var webSocketTask: URLSessionWebSocketTask?
    private let serverURL: URL
    private var reconnectTimer: Timer?
    private let reconnectDelay: TimeInterval = 3.0
    
    // 音頻播放相關
    private var audioPlayer: AVAudioPlayer?
    private var audioChunks: [Data] = []
    private var audioQueue: [Data] = []  // 用於流式播放的音頻隊列
    private var expectedChunks: Int = 0
    private var audioSession: AVAudioSession?
    private var playbackTimer: Timer?
    private var lastChunkTime: Date = .distantPast
    
    override init() {
        // WebSocket 服務器地址
        if let url = URL(string: "ws://145.79.12.177:10000") {
            self.serverURL = url
        } else {
            // 如果 URL 無效，使用預設值
            self.serverURL = URL(string: "ws://localhost:8080")!
        }
        
        super.init()
        
        // 生成唯一連接 ID
        self.connectionId = UUID().uuidString.prefix(8).lowercased()
        print("📱 設備連接 ID: \(self.connectionId)")
        
        // 設置音頻會話
        setupAudioSession()
    }
    
    func connect() {
        guard !isConnected else {
            print("WebSocket 已經連接")
            return
        }
        
        print("🔌 連接到 WebSocket: \(serverURL)")
        
        // 清理舊的連接
        webSocketTask?.cancel()
        webSocketTask = nil
        
        webSocketTask = URLSession.shared.webSocketTask(with: serverURL)
        webSocketTask?.resume()
        
        // 立即設置為已連接狀態，因為 WebSocket 連接已經建立
        isConnected = true
        updateConnectionStatus("已連接")
        
        receiveMessage()
    }
    
    func disconnect() {
        print("🔌 斷開 WebSocket 連接")
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        DispatchQueue.main.async {
            self.isConnected = false
            self.updateConnectionStatus("已斷開")
        }
        reconnectTimer?.invalidate()
        reconnectTimer = nil
    }
    
    func sendText(_ text: String) {
        guard let webSocketTask = webSocketTask else {
            lastError = "WebSocket 未連接"
            return
        }
        
        print("📤 發送文本到 WebSocket: \(text)")
        
        let message = URLSessionWebSocketTask.Message.string(text)
        webSocketTask.send(message) { [weak self] error in
            if let error = error {
                DispatchQueue.main.async {
                    self?.lastError = "發送失敗: \(error.localizedDescription)"
                    print("❌ WebSocket 發送失敗: \(error.localizedDescription)")
                }
            } else {
                print("✅ WebSocket 發送成功")
                // 如果發送成功但連接狀態唔正確，更新佢
                DispatchQueue.main.async {
                    if !(self?.isConnected ?? false) {
                        self?.isConnected = true
                        self?.updateConnectionStatus("已連接")
                    }
                }
            }
        }
    }
    
    func sendTextMessage(_ text: String) {
        // 根據服務器要求嘅格式發送文本
        let requestData: [String: Any] = [
            "type": "text",
            "text": text
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: requestData, options: [])
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                sendText(jsonString)
            }
        } catch {
            lastError = "數據序列化失敗: \(error.localizedDescription)"
        }
    }
    
    func sendSpeechResult(text: String) {
        // 發送語音識別結果，直接使用 gemini_to_speech 格式
        sendTextToSpeech(text: text)
    }
    
    // MARK: - 音頻播放功能
    
    func sendTextToSpeech(text: String, voiceId: String = "moss_audio_af916082-2e36-11f0-92db-0e8893cbb430") {
        // 重置音頻狀態，確保乾淨嘅狀態
        resetAudioState()
        
        let message: [String: Any] = [
            "type": "gemini_to_speech",
            "text": text,
            "voice_id": voiceId,
            "streaming": true,
            "device_id": connectionId
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: message)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                print("🎤 發送文本到語音合成: \(text)")
                print("📤 發送完整消息: \(jsonString)")
                sendText(jsonString)
            }
        } catch {
            lastError = "語音合成請求失敗: \(error.localizedDescription)"
        }
    }
    
    func sendDirectTextToSpeech(text: String, voiceId: String = "moss_audio_af916082-2e36-11f0-92db-0e8893cbb430") {
        // 重置音頻狀態，確保乾淨嘅狀態
        resetAudioState()
        
        let message: [String: Any] = [
            "type": "text_to_speech",
            "text": text,
            "voice_id": voiceId,
            "streaming": true,
            "device_id": connectionId
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: message)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                sendText(jsonString)
                print("🎤 發送直接文本到語音合成: \(text)")
            }
        } catch {
            lastError = "語音合成請求失敗: \(error.localizedDescription)"
        }
    }
    
    private func setupAudioSession() {
        do {
            audioSession = AVAudioSession.sharedInstance()
            
            // 先停用音頻會話，然後重新設置
            try audioSession?.setActive(false)
            
            // 使用更簡單的 playback 類別設置
            try audioSession?.setCategory(.playback, mode: .default)
            try audioSession?.setActive(true)
            print("🎵 音頻會話設置成功")
            
            // 監聽音頻會話中斷通知
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleAudioSessionInterruption),
                name: AVAudioSession.interruptionNotification,
                object: audioSession
            )
            
            // 監聽音頻路線變化通知
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleAudioRouteChange),
                name: AVAudioSession.routeChangeNotification,
                object: audioSession
            )
            
        } catch {
            print("❌ 音頻會話設置失敗: \(error.localizedDescription)")
            print("❌ 錯誤代碼: \(error)")
            
            // 如果設置失敗，嘗試最基本的設置
            do {
                try audioSession?.setCategory(.playback)
                print("🎵 音頻會話基本設置成功")
            } catch {
                print("❌ 音頻會話基本設置也失敗: \(error.localizedDescription)")
            }
        }
    }
    
    @objc private func handleAudioSessionInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        switch type {
        case .began:
            print("🔇 音頻會話被中斷")
            DispatchQueue.main.async {
                self.isPlayingAudio = false
                self.audioPlayer?.pause()
            }
        case .ended:
            print("🔊 音頻會話中斷結束")
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    print("🔄 恢復音頻播放")
                    DispatchQueue.main.async {
                        self.audioPlayer?.play()
                    }
                }
            }
        @unknown default:
            break
        }
    }
    
    @objc private func handleAudioRouteChange(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        
        switch reason {
        case .oldDeviceUnavailable:
            print("🎧 音頻設備不可用")
            DispatchQueue.main.async {
                self.audioPlayer?.pause()
                self.isPlayingAudio = false
            }
        case .newDeviceAvailable:
            print("🎧 新音頻設備可用")
        default:
            break
        }
    }
    
    private func handleAudioChunk(_ json: [String: Any]) {
        print("🔍 [DEBUG] 收到音頻數據，JSON keys: \(json.keys)")
        
        // 如果是第一個 chunk，重置狀態
        if let chunkIndex = json["chunk_index"] as? Int, chunkIndex == 0 {
            resetAudioState()
        }
        
        // 檢查是否為 MiniMax 格式
        if let data = json["data"] as? [String: Any],
           let audioHex = data["audio"] as? String,
           let status = data["status"] as? Int {
            
            print("🔍 檢測到 MiniMax 格式數據（嵌套），status: \(status)")
            // MiniMax 格式處理
            handleMiniMaxAudioChunk(audioHex: audioHex, status: status)
            return
        }
        
        // 也檢查頂層是否有 MiniMax 格式字段
        if let audioHex = json["audio"] as? String,
           let status = json["status"] as? Int {
            
            print("🔍 檢測到 MiniMax 格式數據（頂層），status: \(status)")
            // MiniMax 格式處理
            handleMiniMaxAudioChunk(audioHex: audioHex, status: status)
            return
        }
        
        print("🔍 [DEBUG] 未檢測到 MiniMax 格式，使用舊邏輯")
        
        // 兼容舊格式
        guard let audioDataBase64 = json["audio_data"] as? String else {
            print("❌ 音頻 chunk 解析失敗: 冇 audio_data 字段")
            return
        }
        
        guard let chunkIndex = json["chunk_index"] as? Int else {
            print("❌ 音頻 chunk 解析失敗: 冇 chunk_index 字段")
            return
        }
        
        // 處理 total_chunks，可能為 nil 或 -1（表示未知總數）
        let totalChunks = json["total_chunks"] as? Int ?? -1
        
        guard let audioData = Data(base64Encoded: audioDataBase64) else {
            print("❌ Base64 解碼失敗")
            return
        }
        
        // 檢查是否為完整音頻文件（通常是最後一個 chunk 或大於某個閾值）
        let isCompleteAudio = chunkIndex == totalChunks - 1 || audioData.count > 100000
        
        if isCompleteAudio {
            // 如果是完整音頻，直接播放，不使用隊列
            print("🎯 檢測到完整音頻文件，直接播放")
            audioChunks = [audioData]  // 替換所有 chunks
            expectedChunks = 1
            audioProgress = 1.0
            hasStartedPlayback = false  // 重置播放狀態
            
            // 清除播放計時器
            playbackTimer?.invalidate()
            playbackTimer = nil
            
            // 直接播放
            playAudio()
            return
        }
        
        // 對於部分 chunks，使用隊列進行流式播放
        if !hasStartedPlayback {
            audioQueue.append(audioData)
            print("📝 添加音頻 chunk 到隊列，當前隊列長度: \(audioQueue.count)")
            
            // 如果是第一個 chunk，立即開始播放
            if audioQueue.count == 1 {
                print("🎵 開始流式播放第一個 chunk")
                playNextQueuedChunk()
            }
        } else {
            print("⏭️ 已經開始播放，忽略新的 chunk \(chunkIndex)")
            return
        }
        
        // 如果 totalChunks 有效，設置 expectedChunks
        if totalChunks > 0 {
            expectedChunks = totalChunks
        }
        
        // 更新進度（如果知道總數）
        if expectedChunks > 0 {
            audioProgress = Double(audioChunks.count) / Double(expectedChunks)
        } else {
            // 如果唔知道總數，基於已收到嘅 chunk 數量估算進度
            audioProgress = min(Double(audioChunks.count) / 10.0, 0.95) // 假設最多 10 個 chunk，最多到 95%
        }
        
        // 調試信息
        debugAudioChunk(chunkIndex, totalChunks, audioData)
        
        // 檢查是否應該開始播放
        checkAndStartPlayback()
        
        // 使用 chunkIndex 進行調試（避免編譯警告）
        if chunkIndex == 0 {
            print("🚀 開始接收音頻串流...")
        }
    }
    
    private func handleMiniMaxAudioChunk(audioHex: String, status: Int) {
        // 將 hex 字符串轉換為 Data
        guard let audioData = Data(hexString: audioHex) else {
            print("❌ Hex 音頻數據解碼失敗")
            return
        }
        
        print("📦 收到 MiniMax 音頻 chunk: \(audioData.count) bytes, status: \(status)")
        
        if status == 1 {
            // 進行中的 chunk - 實現真正的流式播放
            audioQueue.append(audioData)
            print("📝 添加音頻 chunk 到隊列，當前隊列長度: \(audioQueue.count)")
            
            // 如果是第一個 chunk 且沒有在播放，立即開始播放
            if audioQueue.count == 1 && !isPlayingAudio {
                print("🎵 開始流式播放第一個 chunk")
                playNextQueuedChunk()
            }
            
        } else if status == 2 {
            // 最終 chunk
            audioQueue.append(audioData)
            print("🎯 收到最終 chunk，隊列長度: \(audioQueue.count)")
            
            // 如果還沒開始播放，現在開始
            if !isPlayingAudio && !audioQueue.isEmpty {
                print("🎵 開始播放最終 chunk")
                playNextQueuedChunk()
            }
        }
    }
    
    private func playNextQueuedChunk() {
        guard !audioQueue.isEmpty else {
            print("⏳ 音頻隊列為空")
            return
        }
        
        let nextChunk = audioQueue.removeFirst()
        print("🎵 播放隊列中的音頻 chunk，剩餘隊列: \(audioQueue.count)")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // 停止並清理舊的音頻播放器
            self.audioPlayer?.stop()
            self.audioPlayer = nil
            
            self.isPlayingAudio = true
            
            do {
                // 嘗試創建 AVAudioPlayer
                self.audioPlayer = try AVAudioPlayer(data: nextChunk)
                
                // 檢查音頻 player 是否成功創建
                guard let player = self.audioPlayer else {
                    print("❌ 音頻 player 創建失敗")
                    self.isPlayingAudio = false
                    // 如果創建失敗，嘗試播放下一個
                    if !self.audioQueue.isEmpty {
                        self.playNextQueuedChunk()
                    }
                    return
                }
                
                // 設置 delegate
                player.delegate = self
                
                // 檢查音頻時長
                let duration = player.duration
                print("🕐 音頻時長: \(duration) 秒")
                
                // 安全激活音頻會話
                _ = self.safeActivateAudioSession()
                
                // 設置音量為最大
                player.volume = 1.0
                
                // 嘗試播放
                let success = player.play()
                
                if success {
                    print("✅ 音頻播放開始")
                } else {
                    print("❌ 音頻播放失敗")
                    self.isPlayingAudio = false
                    self.audioPlayer = nil
                    // 如果播放失敗，嘗試播放下一個
                    if !self.audioQueue.isEmpty {
                        self.playNextQueuedChunk()
                    }
                }
                
            } catch {
                print("❌ 音頻播放失敗: \(error.localizedDescription)")
                self.isPlayingAudio = false
                self.audioPlayer = nil
                // 如果播放失敗，嘗試播放下一個
                if !self.audioQueue.isEmpty {
                    self.playNextQueuedChunk()
                }
            }
        }
    }
    
    
    private func checkAndStartPlayback() {
        // 如果正在播放音頻，不要開始新的播放
        if isPlayingAudio {
            print("🎵 音頻正在播放中，等待完成...")
            return
        }
        
        // 如果已經開始播放，不要重複播放
        if hasStartedPlayback {
            print("🎵 音頻已經開始播放，跳過重複播放...")
            return
        }
        
        // 更新最後收到 chunk 嘅時間
        lastChunkTime = Date()
        
        print("📊 音頻緩衝狀態: \(audioChunks.count) chunks, 期望: \(expectedChunks), 已開始播放: \(hasStartedPlayback)")
        
        // 如果知道總數且已收集完所有 chunk，立即播放
        if expectedChunks > 0 && audioChunks.count == expectedChunks {
            print("🎯 音頻串流完成，播放緩衝內容...")
            playAudio()
            return
        }
        
        // 如果唔知道總數，只在第一次收到足夠 chunk 時設置計時器
        // 但不要與流式播放衝突
        if expectedChunks <= 0 && playbackTimer == nil && !hasStartedPlayback && audioQueue.isEmpty {
            // 如果收到至少 3 個 chunk，設置 0.5 秒後播放（更快的響應）
            if audioChunks.count >= 3 {
                print("⏰ 設置 0.5 秒後播放計時器...")
                playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                    self?.playAudio()
                }
            }
        }
        
        // 如果收到好多 chunk 但冇播放，強制播放（但不要中斷當前播放）
        if audioChunks.count >= 10 && expectedChunks <= 0 && !isPlayingAudio && !hasStartedPlayback {
            print("🚀 緩衝區已滿，開始播放...")
            playAudio()
        }
    }
    
    private func playAudio() {
        // 允許播放即使唔知道總 chunk 數量
        guard !audioChunks.isEmpty else {
            print("⏳ 冇音頻 chunk 可播放")
            return
        }
        
        // 清除播放計時器
        playbackTimer?.invalidate()
        playbackTimer = nil
        
        // 標記已開始播放
        hasStartedPlayback = true
        
        print("🔄 開始合併音頻 chunk: \(audioChunks.count) 個")
        
        // 合併所有音頻 chunk
        let combinedAudioData = audioChunks.reduce(Data()) { $0 + $1 }
        
        print("✅ 音頻合併完成: 總大小=\(combinedAudioData.count) bytes")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // 停止並清理舊嘅音頻播放器
            self.audioPlayer?.stop()
            self.audioPlayer = nil
            
            self.isPlayingAudio = true
            self.audioProgress = 1.0
            
            do {
                // 嘗試創建 AVAudioPlayer
                self.audioPlayer = try AVAudioPlayer(data: combinedAudioData)
                
                // 檢查音頻 player 係咪成功創建
                guard let player = self.audioPlayer else {
                    print("❌ 音頻 player 創建失敗")
                    self.isPlayingAudio = false
                    return
                }
                
                // 設置 delegate
                player.delegate = self
                
                // 檢查音頻時長
                let duration = player.duration
                print("🕐 音頻時長: \(duration) 秒")
                
                // 安全激活音頻會話
                _ = self.safeActivateAudioSession()
                
                // 設置音量為最大
                player.volume = 1.0
                
                // 嘗試播放
                let success = player.play()
                
                if success {
                    print("✅ 音頻播放開始")
                } else {
                    print("❌ 音頻播放失敗")
                    self.isPlayingAudio = false
                    self.audioPlayer = nil
                }
                
            } catch {
                print("❌ 音頻播放失敗: \(error.localizedDescription)")
                self.lastError = "音頻播放失敗: \(error.localizedDescription)"
                self.isPlayingAudio = false
                self.audioPlayer = nil
            }
            
            // 清空當前播放的 chunk，但保留 expectedChunks 用於後續播放
            self.audioChunks.removeAll()
        }
    }
    
    func stopAudio() {
        // 停止音頻播放器
        audioPlayer?.stop()
        audioPlayer = nil
        
        isPlayingAudio = false
        audioProgress = 0.0
        hasStartedPlayback = false
        audioChunks.removeAll()
        expectedChunks = 0
        
        // 清理計時器
        playbackTimer?.invalidate()
        playbackTimer = nil
        
        print("🛑 停止音頻播放")
    }
    
    func resetAudioState() {
        print("🔄 重置音頻狀態，開始新的音頻流")
        stopAudio()
        geminiResponse = ""
        lastError = nil
        
        // 重置音頻播放相關狀態
        audioChunks.removeAll()
        audioQueue.removeAll()
        expectedChunks = 0
        hasStartedPlayback = false
        audioProgress = 0.0
        playbackTimer?.invalidate()
        playbackTimer = nil
        isPlayingAudio = false
        audioPlayer?.stop()
        audioPlayer = nil
    }
    
    // MARK: - 音頻播放處理
    
    private func debugAudioChunk(_ chunkIndex: Int, _ totalChunks: Int, _ audioData: Data) {
        print("📦 Chunk \(chunkIndex)/\(totalChunks > 0 ? String(totalChunks) : "?"): \(audioData.count) bytes")
        print("📊 緩衝區狀態: \(audioChunks.count) chunks, 總大小: \(audioChunks.reduce(0) { $0 + $1.count }) bytes")
    }
    
    private func safeActivateAudioSession() -> Bool {
        do {
            let session = AVAudioSession.sharedInstance()
            
            // 先停用會話，避免衝突
            try session.setActive(false, options: .notifyOthersOnDeactivation)
            
            // 設置音頻會話類別
            try session.setCategory(.playback, mode: .default, options: [])
            
            // 激活會話
            try session.setActive(true)
            return true
        } catch {
            // 靜默處理錯誤，不輸出日誌
            return false
        }
    }
    
    private func streamAudioChunk(_ audioData: Data) {
        // 將音頻數據添加到緩衝區，統一使用緩衝區播放
        audioChunks.append(audioData)
        checkAndStartPlayback()
    }
    
    private func audioDataToPCMBuffer(_ data: Data) -> AVAudioPCMBuffer? {
        // MiniMax 音頻格式檢測和處理
        print("🔍 分析音頻數據格式: \(data.count) bytes")
        
        // 檢查是否為 MP3 格式
        if data.count > 3 {
            let header = data.subdata(in: 0..<3)
            if header[0] == 0xFF && (header[1] & 0xE0) == 0xE0 {
                print("🎵 檢測到 MP3 格式")
                return nil // MP3 不能直接轉換為 PCM buffer，使用 AVAudioPlayer
            }
        }
        
        // 檢查是否為 WAV 格式
        if data.count > 44 && String(data: data.subdata(in: 0..<4), encoding: .ascii) == "RIFF" {
            print("🎵 檢測到 WAV 格式")
            // 提取 PCM 數據（跳過 WAV header）
            let pcmData = data.subdata(in: 44..<data.count)
            return convertPCMDataToBuffer(pcmData, sampleRate: 24000.0, channels: 1)
        }
        
        // 檢查是否為其他音頻格式
        if data.count > 4 {
            let header = data.subdata(in: 0..<4)
            let headerString = String(data: header, encoding: .ascii) ?? ""
            print("🎵 音頻頭部: \(headerString)")
        }
        
        // 對於未知格式，嘗試作為原始 PCM 處理
        print("🎵 嘗試作為原始 PCM 數據處理")
        return convertPCMDataToBuffer(data, sampleRate: 24000.0, channels: 1)
    }
    
    private func convertPCMDataToBuffer(_ pcmData: Data, sampleRate: Double, channels: UInt32) -> AVAudioPCMBuffer? {
        // 創建音頻格式
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: channels, interleaved: false) else {
            print("❌ 音頻格式創建失敗")
            return nil
        }
        
        let bytesPerFrame = format.streamDescription.pointee.mBytesPerFrame
        let frameCount = UInt32(pcmData.count) / bytesPerFrame
        
        guard frameCount > 0 else {
            print("❌ 音頻數據太短: \(pcmData.count) bytes")
            return nil
        }
        
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            print("❌ 音頻緩衝區創建失敗")
            return nil
        }
        
        buffer.frameLength = frameCount
        
        // 將 16-bit PCM 數據轉換為 Float32
        let channelData = buffer.floatChannelData![0]
        pcmData.withUnsafeBytes { (rawBytes: UnsafeRawBufferPointer) in
            let int16Data = rawBytes.bindMemory(to: Int16.self)
            for i in 0..<Int(frameCount) {
                if i < int16Data.count {
                    channelData[i] = Float(int16Data[i]) / Float(Int16.max)
                }
            }
        }
        
        print("✅ 音頻數據轉換成功: \(frameCount) frames, \(format.sampleRate)Hz, \(format.channelCount) channels")
        return buffer
    }
    
    // MARK: - 服務器功能
    
    func sendPing() {
        let pingMessage = ["type": "ping"]
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: pingMessage, options: [])
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                sendText(jsonString)
                print("📤 發送 ping")
            }
        } catch {
            lastError = "Ping 發送失敗: \(error.localizedDescription)"
        }
    }
    
    func checkConnectionStatus() {
        if webSocketTask != nil {
            // 如果有 webSocketTask，發送 ping 檢查連接狀態
            sendPing()
        } else if !isConnected {
            // 如果冇 webSocketTask 且未連接，嘗試重新連接
            connect()
        }
    }
    
    func clearHistory() {
        let clearMessage = ["type": "clear_history"]
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: clearMessage, options: [])
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                sendText(jsonString)
                print("📤 發送 clear_history")
            }
        } catch {
            lastError = "清除歷史記錄失敗: \(error.localizedDescription)"
        }
    }
    
    func getHistory() {
        let historyMessage = ["type": "get_history"]
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: historyMessage, options: [])
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                sendText(jsonString)
                print("📤 發送 get_history")
            }
        } catch {
            lastError = "獲取歷史記錄失敗: \(error.localizedDescription)"
        }
    }
    
    private func receiveMessage() {
        guard let webSocketTask = webSocketTask else { return }
        
        webSocketTask.receive { [weak self] result in
            switch result {
            case .success(let message):
                self?.handleMessage(message)
                self?.receiveMessage() // 繼續接收下一條消息
                
            case .failure(let error):
                DispatchQueue.main.async {
                    self?.handleConnectionError(error)
                }
            }
        }
    }
    
    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            DispatchQueue.main.async { [weak self] in
                self?.handleTextMessage(text)
            }
            
        case .data(let data):
            DispatchQueue.main.async { [weak self] in
                if let text = String(data: data, encoding: .utf8) {
                    self?.handleTextMessage(text)
                }
            }
            
        @unknown default:
            print("⚠️ 未知的 WebSocket 消息類型")
        }
    }
    
    private func handleTextMessage(_ text: String) {
        // 添加到消息列表
        receivedMessages.append(text)
        
        // 限制消息列表長度
        if receivedMessages.count > 50 {
            receivedMessages.removeFirst()
        }
        
        // 解析消息類型
        if let data = text.data(using: .utf8) {
            if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                if let type = json["type"] as? String {
                    switch type {
                    case "response", "gemini_response":
                        // Gemini 服務器嘅回應
                        if let response = json["response"] as? String {
                            print("🤖 收到 Gemini 回應")
                            DispatchQueue.main.async {
                                self.geminiResponse = response
                            }
                        }
                        if let originalText = json["original_text"] as? String {
                            print("📝 原始文本: \(originalText)")
                        }
                        
                        // 重置音頻狀態準備接收新嘅音頻
                        self.resetAudioState()
                        
                    case "audio_chunk":
                        // 音頻 chunk（靜默處理）
                        handleAudioChunk(json)
                        
                    case "audio_complete":
                        // 音頻發送完成
                        print("🎯 音頻串流完成，等待播放...")
                        // 不強制播放，讓 audioPlayerDidFinishPlaying 來處理
                        
                    case "pong":
                        print("🏓 收到服務器 pong 響應")
                        DispatchQueue.main.async {
                            self.isConnected = true
                            self.updateConnectionStatus("已連接")
                        }
                        
                    case "history":
                        if let history = json["history"] as? [[String: Any]] {
                            print("📚 收到歷史記錄: \(history.count) 條")
                        }
                        
                    case "error":
                        if let errorMessage = json["message"] as? String {
                            lastError = "服務器錯誤: \(errorMessage)"
                            print("❌ 服務器錯誤: \(errorMessage)")
                        }
                        
                    case "connection_ack":
                        print("✅ 服務器確認連接")
                        DispatchQueue.main.async {
                            self.isConnected = true
                            self.updateConnectionStatus("已連接")
                        }
                        
                    default:
                        print("📨 收到其他類型消息: \(type)")
                    }
                } else {
                    // 沒有 type 字段，檢查是否為 MiniMax 音頻格式
                    if json["data"] is [String: Any],
                       let data = json["data"] as? [String: Any],
                       data["audio"] is String {
                        print("🎵 檢測到 MiniMax 音頻格式（無 type 字段）")
                        handleAudioChunk(json)
                    } else {
                        print("📨 收到未知格式消息")
                    }
                }
            }
        }
    }
    
    private func handleConnectionError(_ error: Error) {
        print("❌ WebSocket 連接錯誤: \(error.localizedDescription)")
        DispatchQueue.main.async {
            self.isConnected = false
            self.lastError = "連接錯誤: \(error.localizedDescription)"
            self.updateConnectionStatus("連接斷開")
        }
        
        // 清理舊的連接
        webSocketTask = nil
        
        // 嘗試重新連接
        scheduleReconnect()
    }
    
    private func scheduleReconnect() {
        reconnectTimer?.invalidate()
        
        DispatchQueue.main.async {
            self.updateConnectionStatus("3 秒後重新連接...")
        }
        
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: reconnectDelay, repeats: false) { [weak self] _ in
            self?.connect()
        }
    }
    
    private func updateConnectionStatus(_ status: String) {
        connectionStatus = status
        print("📊 連接狀態: \(status)")
    }
    
    func resetConnectionState() {
        DispatchQueue.main.async {
            self.isConnected = false
            self.updateConnectionStatus("未連接")
            self.lastError = nil
        }
    }
    
    deinit {
        disconnect()
        // 移除通知監聽器
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - AVAudioPlayerDelegate
extension WebSocketManager: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.isPlayingAudio = false
            self.audioProgress = 0.0
            self.audioPlayer = nil  // 重置音頻播放器
            print("🎵 音頻播放完成，播放器已重置")
            
            // 檢查是否還有隊列中的音頻需要播放（真正的流式播放）
            if !self.audioQueue.isEmpty {
                print("🔄 播放隊列中的下一個音頻 chunk...")
                self.playNextQueuedChunk()
                return
            }
            
            // 對於舊格式，檢查是否有新的 chunk
            if !self.audioChunks.isEmpty && self.expectedChunks <= 0 {
                // 只有在不知道總 chunk 數量的情況下才檢查新 chunk
                print("🔄 檢測到新 chunk，開始播放...")
                self.playAudio()
            } else {
                print("✅ 所有音頻播放完成")
                // 重置狀態為下一次音頻流做準備
                self.expectedChunks = 0
                self.hasStartedPlayback = false
            }
        }
    }
    
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        DispatchQueue.main.async {
            self.isPlayingAudio = false
            self.audioProgress = 0.0
            self.audioPlayer = nil  // 重置音頻播放器
            if let error = error {
                self.lastError = "音頻解碼錯誤: \(error.localizedDescription)"
                print("❌ 音頻解碼錯誤: \(error.localizedDescription)")
            }
        }
    }
}