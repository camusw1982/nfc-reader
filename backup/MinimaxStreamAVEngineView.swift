//
//  MinimaxStreamAVEngineView.swift
//  Frypan NFC Reader
//
//  Created by Camus Wong on 2025-09-10.
//  使用 AVAudioEngine 實現無縫串流，同 MinimaxStreamTestView 做比較
//

import SwiftUI
import AVFoundation
import os.log

// MARK: - Minimax AVAudioEngine Stream Manager
class MinimaxAVEngineStreamManager: NSObject, ObservableObject {

    // MARK: - Properties
    @Published var isPlaying = false
    @Published var receivedChunks = 0
    @Published var firstChunkDelay: Double = 0
    @Published var totalChunksTime: Double = 0
    @Published var playbackStatus: String = "等待中..."
    @Published var errorMessage: String?

    // HTTP API相關
    private var urlSessionTask: URLSessionTask?
    private var isProcessing = false
    private var streamStartTime: Date?
    private var firstChunkTime: Date?

    // 音頻播放器 - 基本模式用（保留向下兼容）
    private var audioPlayer: AVAudioPlayer?

    // AVAudioEngine 相關
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var audioFormat: AVAudioFormat?

    // 音頻緩衝區隊列
    private var audioBufferQueue: [AVAudioPCMBuffer] = []
    private var isPlayingBuffer = false

    // 配置 - 參考現有嘅MinimaxStreamTestView
    private let groupId = "1920866061935186857"
    private let apiKey = "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJHcm91cE5hbWUiOiJDYW11cyBXb25nIiwiVXNlck5hbWUiOiJDYW11cyBXb25nIiwiQWNjb3VudCI6IiIsIlN1YmplY3RJRCI6IjE5MjA4NjYwNjE5NDM1NzU0NjUiLCJQaG9uZSI6IiIsIkdyb3VwSUQiOiIxOTIwODY2MDYxOTM1MTg2ODU3IiwiUGFnZU5hbWUiOiIiLCJNYWlsIjoiY2FtdXN3MTk4MkBnbWFpbC5jb20iLCJDcmVhdGVUaW1lIjoiMjAyNS0wOS0wNyAxODoxNDo0MiIsIlRva2VuVHlwZSI6MSwiaXNzIjoibWluaW1heCJ9.f8-AdyvvJj2tXjGi3SH8_W0KzmFANPpHypQHHTDv01MuNFS90nOt2PSs9FFzZMILJbE-uTBh2IGUPG9Kqd1JYuTQD0M_sxI9hilFlQEpd13ZK3I5rBgkO71_vUP8armkjCdqSyz6G83sUJR16B1pl7YRzFfnT37TyxzK95SVOz4RliA5b-3M8GfpEZfnPU16tXMEX0bZYs6TgaaSELhMgFzytvNi_-P5V-Rv2VsB-RWIACpL_5TeLYu-VU1FwLNWLY7c0U5aE7mkshosqQ_9cglxYyJttEeC6CNMi_IMVdQYqBl1iaqlxugcTfrXRYytOeTTvm-CjjMCkMnhtQonzA"
    private let baseURL = "https://api.minimaxi.chat/v1/t2a_v2"
    private let logger = Logger(subsystem: "com.frypan.nfc.reader", category: "MinimaxAVEngineStreamManager")

    // MARK: - Initialization
    override init() {
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
            logger.info("音頻會話設置成功 (AVAudioEngine)")
        } catch {
            logger.error("音頻會話設置失敗: \(error)")
            self.errorMessage = "音頻會話設置失敗: \(error.localizedDescription)"
        }
    }

    private func setupAudioEngine() {
        audioEngine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()

        // 使用與 API 請求相同嘅音頻格式
        audioFormat = AVAudioFormat(standardFormatWithSampleRate: 32000, channels: 1)

        guard let engine = audioEngine, let player = playerNode, let format = audioFormat else {
            logger.error("音頻引擎初始化失敗")
            return
        }

        // 連接節點
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)

        logger.info("AVAudioEngine 初始化成功，格式: 32000Hz, 1通道")
    }

    // MARK: - Public Methods
    func startStreaming(text: String, voiceId: String = "moss_audio_058cb75f-6499-11f0-9307-da5fbc4b4ec1", speed: Float = 1.0, pitch: Int = 0, emotion: String = "neutral") {
        guard !isProcessing else {
            logger.warning("正在處理其他請求")
            return
        }

        resetStreaming()

        logger.info("開始語音合成 (AVAudioEngine): \(text.prefix(50))... (voice_id: \(voiceId))")
        isProcessing = true
        isPlaying = true
        streamStartTime = Date()
        playbackStatus = "正在發送請求..."

        // 使用真正嘅 SSE 串流，跟隨 MinimaxStreamTestView
        sendSSEStreamingRequest(text, voiceId: voiceId, speed: speed, pitch: pitch, emotion: emotion)
    }

    func stopStreaming() {
        logger.info("停止串流 (AVAudioEngine)")
        isProcessing = false
        isPlaying = false
        urlSessionTask?.cancel()
        urlSessionTask = nil

        // 停止基本模式播放器
        audioPlayer?.stop()
        audioPlayer = nil

        // 停止 AVAudioEngine
        stopAudioEngine()

        DispatchQueue.main.async {
            self.playbackStatus = "已停止"
        }
    }

    private func resetStreaming() {
        receivedChunks = 0
        firstChunkDelay = 0
        totalChunksTime = 0
        firstChunkTime = nil
        audioChunks.removeAll()
        errorMessage = nil

        // 清理 AVAudioEngine 相關
        stopAudioEngine()
        audioBufferQueue.removeAll()
        isPlayingBuffer = false
    }

    private func stopAudioEngine() {
        playerNode?.stop()
        audioEngine?.stop()
        isPlayingBuffer = false
    }

    // MARK: - SSE 串流方法 - 跟隨 MinimaxStreamTestView
    private func sendSSEStreamingRequest(_ text: String, voiceId: String, speed: Float, pitch: Int, emotion: String) {
        guard let url = URL(string: "\(baseURL)?GroupId=\(groupId)") else {
            logger.error("無效的 API URL")
            handleError("無效的 API URL")
            return
        }

        logger.info("正在發送 SSE 串流 API 請求 (AVAudioEngine)...")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // 使用串流模式 - 添加 audio_setting 指定音頻格式
        let requestBody: [String: Any] = [
            "stream": true,
            "text": text,
            "model": "speech-02-hd",  // HD 模型支援串流
            "voice_setting": [
                "voice_id": voiceId,
                "speed": speed,
                "pitch": pitch,
                "emotion": emotion
            ],
            "audio_setting": [
                "sample_rate": 32000,  // 使用 Minimax 文檔指定嘅採樣率
                "format": "pcm",      // 直接使用 PCM 格式，避免轉換
                "channel": 1          // 單聲道
            ],
            "language_boost": "Chinese,Yue"
        ]

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
            request.httpBody = jsonData
        } catch {
            logger.error("JSON 序列化失敗: \(error)")
            handleError("JSON 序列化失敗")
            return
        }

        // 使用 URLSession 處理 SSE 響應
        urlSessionTask = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                self?.logger.error("SSE API 請求失敗: \(error)")
                self?.handleError("SSE API 請求失敗: \(error.localizedDescription)")
                return
            }

            guard let data = data else {
                self?.logger.error("SSE 沒有收到數據")
                self?.handleError("SSE 沒有收到數據")
                return
            }

            // 處理 SSE 響應 - 跟隨 MinimaxStreamTestView
            self?.handleSSEResponse(data)
        }

        urlSessionTask?.resume()
    }

    // MARK: - SSE 處理 - 跟隨 MinimaxStreamTestView
    private func handleSSEResponse(_ data: Data) {
        let responseString = String(data: data, encoding: .utf8) ?? ""
        logger.info("收到 SSE 響應 (AVAudioEngine)，長度: \(responseString.count)")

        // 解析 SSE 格式：data: {...}\n\n - 跟隨 MinimaxStreamTestView
        let events = responseString.components(separatedBy: "\n\n")

        for event in events {
            if event.contains("data:") {
                processSSEEvent(event)
            }
        }

        // 處理完所有 chunk 後更新狀態
        DispatchQueue.main.async {
            self.totalChunksTime = Date().timeIntervalSince(self.streamStartTime ?? Date())
            if self.receivedChunks > 0 {
                self.playbackStatus = "串流完成"
            }
        }
    }

    private func processSSEEvent(_ event: String) {
        // 提取 data: 後面嘅 JSON 內容 - 跟隨 MinimaxStreamTestView
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
            handleError("SSE API 錯誤: \(errorMsg)")
            return
        }

        // 處理音頻數據 - 跟隨 MinimaxStreamTestView
        guard let dataField = json["data"] as? [String: Any],
              let status = dataField["status"] as? Int,
              let audioHex = dataField["audio"] as? String,
              !audioHex.isEmpty else {
            // 可能係結束標記，唔係錯誤
            return
        }

        // 只有 status = 1 先有音頻數據 - 跟隨 MinimaxStreamTestView
        guard status == 1 else { return }

        // 轉換 hex 音頻數據
        guard let audioData = hexStringToData(audioHex) else {
            logger.error("SSE 音頻數據轉換失敗")
            return
        }

        // 處理音頻 chunk - 跟隨 MinimaxStreamTestView
        processAudioChunk(audioData)
    }

    // MARK: - 音頻處理 - AVAudioEngine 版本
    private func processAudioChunk(_ audioData: Data) {
        DispatchQueue.main.async {
            self.receivedChunks += 1

            // 記錄首個 chunk 延遲 - 跟隨 MinimaxStreamTestView
            if self.receivedChunks == 1 {
                self.firstChunkDelay = Date().timeIntervalSince(self.streamStartTime ?? Date())
                self.logger.info("首個音頻 chunk 收到 (AVAudioEngine)，延遲: \(self.firstChunkDelay) 秒")
                self.playbackStatus = "正在串流播放..."

                // 啟動音頻引擎
                self.startAudioEngine()
            }

            self.logger.info("處理第 \(self.receivedChunks) 個音頻 chunk (AVAudioEngine)，大小: \(audioData.count) bytes")

            // 直接創建 PCMBuffer 並加入隊列
            self.createAndQueuePCMBuffer(from: audioData)
        }
    }

    private func startAudioEngine() {
        guard let engine = audioEngine else {
            logger.error("音頻引擎未初始化")
            return
        }

        do {
            try engine.start()
            logger.info("音頻引擎啟動成功")
            isPlayingBuffer = true
        } catch {
            logger.error("音頻引擎啟動失敗: \(error)")
            handleError("音頻引擎啟動失敗: \(error.localizedDescription)")
        }
    }

    private func createAndQueuePCMBuffer(from audioData: Data) {
        guard let format = audioFormat else { return }

        // PCM 數據每個樣本 2 bytes (16-bit)，單聲道 = 2 bytes per frame
        let frameCount = AVAudioFrameCount(audioData.count) / 2
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            logger.error("創建 PCM 緩衝區失敗")
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

        logger.info("創建 PCM 緩衝區: \(frameCount) 幀")

        // 加入隊列並播放
        audioBufferQueue.append(pcmBuffer)
        playNextBuffer()
    }

  
    private func playNextBuffer() {
        guard !audioBufferQueue.isEmpty else {
            self.logger.warning("音頻緩衝區隊列為空")
            isPlayingBuffer = false
            return
        }

        // 檢查引擎狀態
        guard let engine = self.audioEngine, let player = self.playerNode else {
            self.logger.error("音頻組件未正確初始化")
            return
        }

        // 確保引擎運行
        if !engine.isRunning {
            do {
                try engine.start()
                self.logger.info("AVAudioEngine 啟動成功")
            } catch {
                self.logger.error("AVAudioEngine 啟動失敗: \(error)")
                return
            }
        }

        // 確保播放節點運行
        if !player.isPlaying {
            player.play()
            isPlayingBuffer = true
            self.logger.info("AVAudioPlayerNode 開始播放")
        }

        // 取出第一個 buffer 進行播放
        let buffer = audioBufferQueue.removeFirst()
        self.logger.info("播放音頻緩衝區: \(buffer.frameLength) 幀，隊列剩餘: \(self.audioBufferQueue.count)")

        // 安排播放
        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: { [weak self] in
            DispatchQueue.main.async {
                self?.logger.info("音頻緩衝區播放完成")
                // 播完當前 buffer 後，立即播放下一個
                self?.playNextBuffer()
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

    // 基本模式音頻處理 (保持向下兼容)
    private var audioChunks: [Data] = []
    private func playAudio(_ audioData: Data) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let tempFileURL = FileManager.default.temporaryDirectory.appendingPathComponent("audio_\(Date().timeIntervalSince1970).mp3")
                try audioData.write(to: tempFileURL)

                DispatchQueue.main.async {
                    do {
                        let player = try AVAudioPlayer(contentsOf: tempFileURL)
                        self?.audioPlayer = player
                        player.play()

                        DispatchQueue.global().asyncAfter(deadline: .now() + TimeInterval(player.duration + 1.0)) {
                            try? FileManager.default.removeItem(at: tempFileURL)
                        }

                    } catch {
                        self?.logger.error("音頻播放失敗: \(error)")
                    }
                }

            } catch {
                self?.logger.error("音頻文件處理失敗: \(error)")
            }
        }
    }
}

// MARK: - SwiftUI View
struct MinimaxStreamAVEngineView: View {
    @StateObject private var streamManager = MinimaxAVEngineStreamManager()
    @State private var inputText = "從前有個可愛的小姑娘，誰見了都喜歡，但最喜歡她的是她的奶奶，簡直是她要什麼就給她什麼。 一次，奶奶送給小女孩一頂用絲絨做的小紅帽，戴在她的頭上正好合適。 從此，女孩再也不願意戴任何別的帽子，於是大家便叫她小紅帽。"
    @State private var selectedVoice = "moss_audio_058cb75f-6499-11f0-9307-da5fbc4b4ec1"
    @State private var speed: Float = 1.0
    @State private var pitch: Int = 0
    @State private var selectedEmotion = "neutral"

    let voices = [
        "moss_audio_058cb75f-6499-11f0-9307-da5fbc4b4ec1": "子謙",
        "moss_audio_af916082-2e36-11f0-92db-0e8893cbb430": "標叔"
    ]

    let emotions = [
        "neutral": "中性",
        "happy": "開心",
        "sad": "悲傷",
        "angry": "憤怒"
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 設置區域
                settingsSection

                // 文字輸入
                textInputSection

                // 控制按鈕
                controlButtonsSection

                // 狀態顯示
                statusSection

                // 性能統計
                statisticsSection
            }
            .padding()
        }
        .navigationTitle("AVAudioEngine 串流測試")
        .onAppear {
            // 設置音頻會話
        }
        .alert("錯誤", isPresented: .constant(streamManager.errorMessage != nil), actions: {
            Button("確定") {
                streamManager.errorMessage = nil
            }
        }, message: {
            Text(streamManager.errorMessage ?? "")
        })
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("語音設置")
                .font(.headline)

            // 語音選擇
            VStack(alignment: .leading) {
                Text("語音")
                    .font(.subheadline)
                Picker("語音", selection: $selectedVoice) {
                    ForEach(voices.keys.sorted(), id: \.self) { voiceId in
                        Text(voices[voiceId] ?? voiceId).tag(voiceId)
                    }
                }
                .pickerStyle(.segmented)
            }

            // 語速同音調
            HStack {
                VStack(alignment: .leading) {
                    Text("語速: \(speed, specifier: "%.2f")")
                        .font(.subheadline)
                    Slider(value: $speed, in: 0.5...2.0, step: 0.05)
                }

                VStack(alignment: .leading) {
                    Text("音調: \(pitch)")
                        .font(.subheadline)
                    Slider(value: Binding(
                        get: { Double(pitch) },
                        set: { pitch = Int($0) }
                    ), in: -12...12, step: 1)
                }
            }

            // 情感選擇
            VStack(alignment: .leading) {
                Text("情感")
                    .font(.subheadline)
                Picker("情感", selection: $selectedEmotion) {
                    ForEach(emotions.keys.sorted(), id: \.self) { emotion in
                        Text(emotions[emotion] ?? emotion).tag(emotion)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }

    private var textInputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("文字輸入")
                .font(.headline)
            TextEditor(text: $inputText)
                .frame(height: 120)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray, lineWidth: 1)
                )
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }

    private var controlButtonsSection: some View {
        HStack(spacing: 15) {
            Button(action: {
                streamManager.startStreaming(
                    text: inputText,
                    voiceId: selectedVoice,
                    speed: speed,
                    pitch: pitch,
                    emotion: selectedEmotion
                )
            }) {
                Label("開始串流", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(streamManager.isPlaying)

            Button(action: {
                streamManager.stopStreaming()
            }) {
                Label("停止", systemImage: "stop.fill")
            }
            .buttonStyle(.bordered)
            .disabled(!streamManager.isPlaying)
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("播放狀態")
                .font(.headline)

            HStack {
                Circle()
                    .fill(streamManager.isPlaying ? Color.green : Color.gray)
                    .frame(width: 10, height: 10)
                Text(streamManager.playbackStatus)
                    .font(.subheadline)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }

    private var statisticsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("性能統計")
                .font(.headline)

            HStack {
                VStack(alignment: .leading) {
                    Text("已接收塊數: \(streamManager.receivedChunks)")
                        .font(.subheadline)
                    Text("首個塊延遲: \(streamManager.firstChunkDelay, specifier: "%.2f")秒")
                        .font(.subheadline)
                }

                VStack(alignment: .leading) {
                    Text("總耗時: \(streamManager.totalChunksTime, specifier: "%.2f")秒")
                        .font(.subheadline)
                    Text("播放狀態: \(streamManager.isPlaying ? "播放中" : "停止")")
                        .font(.subheadline)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }

}

#Preview {
    NavigationView {
        MinimaxStreamAVEngineView()
    }
}