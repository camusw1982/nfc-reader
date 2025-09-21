//
//  MiniMaxStreamManager.swift
//  Frypan NFC Reader
//
//  Created by Claude on 19/9/2025.
//  專門用於主 app 流程的 MiniMax 串流管理器，基於 MinimaxStreamAVEngineView.swift 嘅成功實現
//

import Foundation
import AVFoundation
import os.log

// MARK: - MiniMax Stream Manager
class MiniMaxStreamManager: NSObject, ObservableObject {

    // MARK: - Properties
    @Published var isPlaying = false
    @Published var errorMessage: String?

    // HTTP API相關
    private var urlSessionTask: URLSessionTask?
    private var isProcessing = false


    // AVAudioEngine 相關
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var audioFormat: AVAudioFormat?

    // 音頻緩衝區隊列
    private var audioBufferQueue: [AVAudioPCMBuffer] = []

    // 預加載配置
    private let minBufferCount = 3  // 最小緩衝區數量
    private let maxBufferCount = 10 // 最大緩衝區數量

    // 配置
    private let groupId: String
    private let apiKey: String
    private let baseURL = "https://api.minimaxi.chat/v1/t2a_v2"
    private let logger = Logger(subsystem: "com.frypan.nfc.reader", category: "MiniMaxStreamManager")

    // MARK: - Audio Format Configuration
    private struct AudioConfig {
        static let sampleRate: Double = 32000
        static let channels: UInt32 = 1
        static let format: String = "pcm"
        static let bytesPerSample: Int = 2  // 16-bit PCM
        static let bytesPerFrame: Int = bytesPerSample * Int(channels)  // 2 bytes per frame for mono
    }

    // MARK: - Initialization
    override init() {
        self.apiKey = Bundle.main.object(forInfoDictionaryKey: "MINIMAX_API_KEY") as! String
        self.groupId = Bundle.main.object(forInfoDictionaryKey: "MINIMAX_GROUP_ID") as! String
        super.init()
        setupAudioSession()
        setupAudioEngine()
    }

    // MARK: - Setup Methods
    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default, options: [])
            try audioSession.setActive(true)
        } catch {
            logger.error("音頻會話設置失敗: \(error)")
            self.errorMessage = "音頻會話設置失敗: \(error.localizedDescription)"
        }
    }

    // MARK: - Audio Engine Management

    // 過度保守嘅錯誤恢復已移除，使用直接嘅錯誤處理

    private func setupAudioEngine() {

        // 如果已經存在，先清理
        if let existingEngine = audioEngine {
            if existingEngine.isRunning {
                existingEngine.stop()
            }
            if let existingPlayer = playerNode {
                existingEngine.detach(existingPlayer)
            }
        }

        audioEngine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()
        audioFormat = AVAudioFormat(standardFormatWithSampleRate: AudioConfig.sampleRate, channels: AudioConfig.channels)

        guard let engine = audioEngine, let player = playerNode, let format = audioFormat else {
            logger.error("音頻引擎初始化失敗")
            return
        }

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    private func reinitializeAudioEngine() {

        stopAudioEngine()
        audioBufferQueue.removeAll()

        setupAudioEngine()
    }

    // MARK: - Public Methods
    func startStreaming(text: String, voiceId: String = "moss_audio_058cb75f-6499-11f0-9307-da5fbc4b4ec1", speed: Float = 1.0, pitch: Int = 0, emotion: String = "") {
        guard !isProcessing else {
            logger.warning("正在處理其他請求")
            return
        }

        // 先重置狀態
        resetStreaming()

        // 確保音頻引擎完全停止後再開始新串流
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.logger.info("開始語音合成 (MiniMaxStreamManager): \(text.prefix(50))... (voice_id: \(voiceId))")
            self.isProcessing = true
            self.isPlaying = true

            // 使用 SSE 串流
            self.sendSSEStreamingRequest(text, voiceId: voiceId, speed: speed, pitch: pitch, emotion: emotion)
        }
    }

    func stopStreaming() {
        logger.info("停止串流")
        isProcessing = false
        isPlaying = false
        urlSessionTask?.cancel()
        urlSessionTask = nil

        // 立即停止所有音頻播放
        stopAudioEngineImmediately()

        // 清理緩衝區
        audioBufferQueue.removeAll()

        // UI 狀態已經通過 isPlaying 處理
    }

    // MARK: - Private Methods
    private func resetStreaming() {
        logger.info("重置串流狀態")

        // 重置狀態
        isProcessing = false
        isPlaying = false
        errorMessage = nil

        // 停止現有任務
        urlSessionTask?.cancel()
        urlSessionTask = nil

        // 清理 AVAudioEngine 相關
        reinitializeAudioEngine()

        // 重置播放狀態
        // UI 狀態已經通過 isPlaying 處理

        logger.info("串流狀態重置完成")
    }

    private func stopAudioEngine() {
        logger.info("停止音頻引擎")

        // 停止播放節點
        if let player = playerNode {
            player.stop()
            logger.info("AVAudioPlayerNode 已停止")
        }

        // 停止音頻引擎
        if let engine = audioEngine {
            if engine.isRunning {
                engine.stop()
                logger.info("AVAudioEngine 已停止")
            }
        }
    }

    private func stopAudioEngineImmediately() {
        logger.info("立即停止音頻引擎")

        // 立即停止播放節點
        if let player = playerNode {
            player.stop()
            logger.info("AVAudioPlayerNode 立即停止")
        }

        // 立即停止音頻引擎
        if let engine = audioEngine {
            if engine.isRunning {
                engine.stop()
                logger.info("AVAudioEngine 立即停止")
            }
        }

        // 重置音頻引擎以確保完全停止
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            self.reinitializeAudioEngine()
        }
    }

    // MARK: - SSE 串流方法
    private func sendSSEStreamingRequest(_ text: String, voiceId: String, speed: Float, pitch: Int, emotion: String) {
        guard let url = URL(string: "\(baseURL)?GroupId=\(groupId)") else {
            logger.error("無效的 API URL")
            handleError("配置錯誤")
            return
        }

        logger.info("正在發送 SSE 串流 API 請求...")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // 使用串流模式 - 添加 audio_setting 指定音頻格式
        let requestBody: [String: Any] = [
            "stream": true,
            "text": text,
            "model": "speech-2.5-hd-preview",  // HD 模型支援串流
            "voice_setting": [
                "voice_id": voiceId,
                "speed": speed,
                "pitch": pitch,
                "emotion": emotion
            ],
            "audio_setting": [
                "sample_rate": AudioConfig.sampleRate,
                "format": AudioConfig.format,
                "channel": AudioConfig.channels
            ],
            "language_boost": "Chinese,Yue"
        ]

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
            request.httpBody = jsonData
        } catch {
            logger.error("JSON 序列化失敗: \(error)")
            handleError("請求格式錯誤")
            return
        }

        // 使用 URLSession 處理 SSE 響應
        urlSessionTask = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                self?.logger.error("SSE API 請求失敗: \(error)")
                self?.handleError("網絡請求失敗")
                return
            }

            guard let data = data else {
                self?.logger.error("SSE 沒有收到數據")
                self?.handleError("SSE 沒有收到數據")
                return
            }

            // 處理 SSE 響應
            self?.handleSSEResponse(data)
        }

        urlSessionTask?.resume()
    }

    // MARK: - SSE 處理 - 跟隨 MinimaxStreamAVEngineView 成功版本
    private func handleSSEResponse(_ data: Data) {
        let responseString = String(data: data, encoding: .utf8) ?? ""
        logger.info("收到 SSE 響應，長度: \(responseString.count)")

        // 解析 SSE 格式：data: {...}\n\n
        let events = responseString.components(separatedBy: "\n\n")

        for event in events {
            if event.contains("data:") {
                processSSEEvent(event)
            }
        }

        // 處理完所有 chunk 後，標記串流完成，但唔立即設置播放狀態
        DispatchQueue.main.async {
            // 標記 SSE 處理完成，但播放狀態由音頻隊列決定
            self.logger.info("SSE 串流處理完成")

            // SSE 串流完成，標記處理結束
            self.isProcessing = false
        }
    }

    private func processSSEEvent(_ event: String) {
        // 提取 data: 後面嘅 JSON 內容
        guard let dataRange = event.range(of: "data: ") else { return }
        let jsonString = String(event[dataRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)

        guard let jsonData = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            logger.error("SSE JSON 解析失敗")
            return
        }

        // 檢查 API 響應狀態
        guard let baseResp = json["base_resp"] as? [String: Any],
              let statusCode = baseResp["status_code"] as? Int,
              statusCode == 0 else {
            let errorMsg = (json["base_resp"] as? [String: Any])?["status_msg"] as? String ?? "SSE API 返回錯誤"
            logger.error("SSE API 錯誤: \(errorMsg)")
            handleError("服務器錯誤")
            return
        }

        // 處理音頻數據
        guard let dataField = json["data"] as? [String: Any],
              let status = dataField["status"] as? Int,
              let audioHex = dataField["audio"] as? String,
              !audioHex.isEmpty else {
            // 可能係結束標記，唔係錯誤
            return
        }

        // 只有 status = 1 先有音頻數據
        guard status == 1 else { return }

        // 轉換 hex 音頻數據
        guard let audioData = hexStringToData(audioHex) else {
            logger.error("音頻數據轉換失敗")
            return
        }

        // 處理音頻 chunk
        processAudioChunk(audioData)
    }

    // MARK: - 音頻處理
    private func processAudioChunk(_ audioData: Data) {
        DispatchQueue.main.async {
            // self.logger.debug("處理音頻 chunk，大小: \(audioData.count) bytes")

            // 創建 PCM 緩衝區並加入隊列
            self.createAndQueuePCMBuffer(from: audioData)

            // 當緩衝區達到閾值時啟動播放
            if !self.isPlaying && self.audioBufferQueue.count >= self.minBufferCount {
                self.logger.info("緩衝區達到預加載閾值，開始播放")
                self.startAudioEngine()
            }
        }
    }

    private func startAudioEngine() {
        logger.info("啟動音頻引擎")

        // 檢查音頻組件狀態
        guard let engine = audioEngine, let player = playerNode else {
            logger.error("音頻組件未正確初始化")
            handleError("音頻引擎初始化失敗")
            return
        }

        // 如果引擎已經喺運行，先停止
        if engine.isRunning {
            logger.info("音頻引擎已經喺運行，重新啟動")
            engine.stop()
            player.stop()
        }

        do {
            try engine.start()
            logger.info("音頻引擎啟動成功")
            isPlaying = true
        } catch {
            logger.error("音頻引擎啟動失敗: \(error)")
            handleError("音頻引擎啟動失敗")
        }
    }

    private func createAndQueuePCMBuffer(from audioData: Data) {
        guard let format = audioFormat else { return }

        // 防止緩衝區過度積壓
        guard audioBufferQueue.count < maxBufferCount else {
            logger.warning("音頻緩衝區已達最大限制，跳過當前 chunk")
            return
        }

        // 計算音頻幀數
        let frameCount = AVAudioFrameCount(audioData.count / AudioConfig.bytesPerFrame)
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            logger.error("創建音頻緩衝區失敗")
            return
        }

        // 直接將 Int16 PCM 數據轉換為 Float32
        audioData.withUnsafeBytes { (rawBufferPointer: UnsafeRawBufferPointer) in
            guard let int16Pointer = rawBufferPointer.baseAddress?.assumingMemoryBound(to: Int16.self) else { return }

            let floatData = pcmBuffer.floatChannelData![0]  // 單聲道
            let sampleCount = Int(frameCount)

            for i in 0..<sampleCount {
                floatData[i] = Float(int16Pointer[i]) / Float(Int16.max)
            }
        }

        pcmBuffer.frameLength = frameCount

        // 降低日誌級別，減少冗餘輸出

        // 加入隊列
        audioBufferQueue.append(pcmBuffer)

        // 只有在音頻引擎運行且緩衝區達到閾值時先播放
        if isPlaying && audioBufferQueue.count >= minBufferCount {
            playNextBuffer()
        }
    }


    private func playNextBuffer() {
        guard !audioBufferQueue.isEmpty else {
            // 檢查是否播放完成 - 當隊列為空且 SSE 串流已經完成時
            if !isProcessing {
                handlePlaybackCompletion()
            }
            return
        }

        // 檢查引擎狀態
        guard let engine = self.audioEngine, let player = self.playerNode else {
            self.logger.error("音頻組件未正確初始化")
            self.handleError("音頻引擎初始化失敗")
            return
        }

        // 確保引擎運行
        if !engine.isRunning {
            do {
                try engine.start()
                self.logger.info("AVAudioEngine 啟動成功")
            } catch {
                self.logger.error("AVAudioEngine 啟動失敗: \(error)")
                self.handleError("音頻引擎啟動失敗")
                return
            }
        }

        // 確保播放節點運行
        if !player.isPlaying {
            player.play()
            self.logger.info("AVAudioPlayerNode 開始播放")
        }

        // 取出第一個 buffer 進行播放
        let buffer = audioBufferQueue.removeFirst()
        // 減少冗餘播放日誌

        // 安排播放 - 使用更精確的播放完成回調
        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                // 減少播放完成日誌

                // 延遲一小段時間確保播放狀態更新
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                    self.playNextBuffer()
                }
            }
        })
    }

    // MARK: - 輔助方法
    private func hexStringToData(_ hexString: String) -> Data? {
        guard hexString.count % 2 == 0 else {
            logger.error("音頻 hex 字符串長度不是偶數")
            return nil
        }

        var data = Data(capacity: hexString.count / 2)
        var index = hexString.startIndex

        while index < hexString.endIndex {
            let nextIndex = hexString.index(index, offsetBy: 2)
            let byteString = String(hexString[index..<nextIndex])

            guard let byte = UInt8(byteString, radix: 16) else {
                logger.error("音頻 hex 字符串包含無效字符")
                return nil
            }

            data.append(byte)
            index = nextIndex
        }

        return data
    }

    private func handleError(_ error: String) {
        DispatchQueue.main.async {
            self.errorMessage = error
        }
    }

    private func handlePlaybackCompletion() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // 檢查是否應該標記播放完成
            guard self.isPlaying else {
                return // 已經唔係播放狀態，唔需要處理
            }

            // 確認隊列為空且串流完成
            guard self.audioBufferQueue.isEmpty && !self.isProcessing else {
                return // 還有數據要播放或串流未完成
            }

            self.logger.info("播放完成")
            self.isPlaying = false
            self.isProcessing = false
        }
    }


    // MARK: - Cleanup
    deinit {
        stopStreaming()
    }
}