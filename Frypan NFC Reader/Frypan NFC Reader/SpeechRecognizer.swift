//
//  SpeechRecognizer.swift
//  Frypan NFC Reader
//
//  Created by Claude on 5/9/2025.
//

import Foundation
import Speech
import SwiftUI
import AVFoundation
import Combine

// ChatMessage 已移至 ChatComponents.swift

class SpeechRecognizer: NSObject, ObservableObject, SFSpeechRecognizerDelegate {
    @Published var isRecognizing = false
    @Published var recognizedText = ""
    @Published var hasPermission = false
    @Published var error: String?
    @Published var lastSentText: String?
    @Published var llmResponse: String = ""
    @Published var originalText: String = ""
    @Published var responseTimestamp: Date?
    @Published var isWebSocketConnected = false
    @Published var isRecordingCancelled = false
    
    // 對話消息數組
    @Published var messages: [ChatMessage] = []
    
    let webService = WebServiceManager()
    
    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private let audioSession = AVAudioSession.sharedInstance()
    
    override init() {
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-HK"))
        super.init()
        speechRecognizer?.delegate = self
        requestPermission()
        setupWebSocketMonitoring()
    }
    
    func requestPermission() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                switch status {
                case .authorized:
                    self?.hasPermission = true
                    print("✅ 語音識別權限已授予")
                case .denied:
                    self?.error = "語音識別權限被拒絕"
                    print("❌ 語音識別權限被拒絕")
                case .restricted:
                    self?.error = "語音識別功能受限"
                    print("❌ 語音識別功能受限")
                case .notDetermined:
                    self?.error = "語音識別權限未確定"
                    print("❌ 語音識別權限未確定")
                @unknown default:
                    self?.error = "未知的權限狀態"
                    print("❌ 未知的權限狀態")
                }
            }
        }
    }
    
    func startRecording() {
        guard hasPermission else {
            error = "沒有語音識別權限"
            return
        }
        
        guard !isRecognizing else {
            print("語音識別已在進行中")
            return
        }
        
        // 取消之前的任務
        if let recognitionTask = recognitionTask {
            recognitionTask.cancel()
            self.recognitionTask = nil
        }
        
        // 配置音頻會話 - 使用更安全的配置
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try audioSession.setActive(true)
        } catch let audioError {
            self.error = "音頻會話配置失敗: \(audioError.localizedDescription)"
            return
        }
        
        // 創建識別請求
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            error = "無法創建識別請求"
            return
        }
        
        recognitionRequest.shouldReportPartialResults = true
        
        // 開始識別任務
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                let transcribedString = result.bestTranscription.formattedString
                DispatchQueue.main.async {
                    self.recognizedText = transcribedString
                    // 只在識別完成時輸出日誌，不在每次部分結果時輸出
                    if result.isFinal {
                        print("🎤 語音識別完成: \(transcribedString)")
                    }
                }
            }
            
            if let error = error {
                let errorDescription = error.localizedDescription
                // 過濾掉正常情況的錯誤
                if errorDescription == "No speech detected" {
                    print("ℹ️ 未檢測到語音 (正常情況)")
                } else if errorDescription == "Recognition request was canceled" {
                    print("ℹ️ 語音識別請求已取消 (正常情況)")
                } else {
                    DispatchQueue.main.async {
                        self.error = "識別錯誤: \(errorDescription)"
                        print("❌ 語音識別錯誤: \(errorDescription)")
                    }
                }
            }
        }
        
        // 配置音頻輸入
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
        
        // 啟動音頻引擎
        do {
            audioEngine.prepare()
            try audioEngine.start()
            DispatchQueue.main.async {
                self.isRecognizing = true
                self.error = nil
                print("🎤 語音識別已開始")
            }
        } catch let engineError {
            self.error = "音頻引擎啟動失敗: \(engineError.localizedDescription)"
            stopRecording()
        }
    }
    
    func stopRecording() {
        stopRecording(shouldSendResult: false)
    }
    
    func stopRecording(shouldSendResult: Bool) {
        if isRecognizing {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
            
            // 先結束音頻請求，而不是取消任務
            recognitionRequest?.endAudio()
            recognitionRequest = nil
            
            // 等待一小段時間讓識別任務自然完成
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                // 只有在任務還存在時才取消
                if self.recognitionTask != nil {
                    self.recognitionTask?.cancel()
                    self.recognitionTask = nil
                }
                
                // 停用音頻會話
                do {
                    try self.audioSession.setActive(false)
                } catch {
                    print("⚠️ 停用音頻會話失敗: \(error.localizedDescription)")
                }
                
                self.isRecognizing = false
                print("🛑 語音識別已停止")
                
                // 如果有識別結果且需要發送，且錄音未被取消，發送到服務器
                if shouldSendResult && !self.recognizedText.isEmpty && !self.isRecordingCancelled {
                    self.sendToServer()
                }
                
                // 重置取消標誌
                self.isRecordingCancelled = false
            }
        }
    }
    
    private func sendToServer() {
        // 🔒 安全措施：呢個方法唔應該再被調用
        print("⚠️ sendToServer() 被調用，但根據新邏輯應該直接使用 sendTextToSpeech")
        print("📤 拒絕發送舊格式請求，請使用 sendTextToSpeech 方法")
        
        // 唔發送任何請求，確保只會通過 confirmRecording() 發送 gemini_to_speech
        return
    }
    
    func reset() {
        stopRecording()
        DispatchQueue.main.async {
            self.recognizedText = ""
            self.error = nil
            self.llmResponse = ""
            self.originalText = ""
            self.responseTimestamp = nil
            self.isRecordingCancelled = false
            self.messages.removeAll()
        }
    }
    
    func clearChat() {
        DispatchQueue.main.async {
            self.messages.removeAll()
        }
    }
    
    private func setupWebSocketMonitoring() {
        // 監聽 WebSocket 連接狀態
        if let webSocketManager = webService.getWebSocketManager() {
            webSocketManager.$isConnected.sink { [weak self] isConnected in
                DispatchQueue.main.async {
                    self?.isWebSocketConnected = isConnected
                    print("🔌 WebSocket 連接狀態: \(isConnected)")
                }
            }.store(in: &cancellables)
            
            // 監聽收到的消息
            webSocketManager.$receivedMessages.sink { [weak self] messages in
                guard let self = self, let lastMessage = messages.last else { return }
                
                // 解析 Gemini 回應
                if let data = lastMessage.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                    
                    if let type = json["type"] as? String {
                        if type == "response" || type == "gemini_response" {
                            if let response = json["response"] as? String {
                                DispatchQueue.main.async {
                                    self.llmResponse = response
                                    self.responseTimestamp = Date()
                                    print("🤖 收到 Gemini 回應: \(response)")
                                    
                                    // 添加 AI 回應到對話
                                    let aiMessage = ChatMessage(text: response, isUser: false, timestamp: Date(), isError: false)
                                    self.messages.append(aiMessage)
                                }
                            }
                            if let originalText = json["original_text"] as? String {
                                DispatchQueue.main.async {
                                    self.originalText = originalText
                                    print("📝 原始文本: \(originalText)")
                                }
                            }
                        } else if type == "pong" {
                            print("🏓 服務器響應正常")
                        } else if type == "history", let history = json["history"] as? [[String: Any]] {
                            print("📚 收到歷史記錄: \(history.count) 條對話")
                        }
                    }
                } else {
                    // 如果唔係 JSON 格式，直接作為回應處理
                    DispatchQueue.main.async {
                        self.llmResponse = lastMessage
                        print("🤖 收到文本回應: \(lastMessage)")
                        
                        // 添加 AI 回應到對話
                        let aiMessage = ChatMessage(text: lastMessage, isUser: false, timestamp: Date(), isError: false)
                        self.messages.append(aiMessage)
                    }
                }
            }.store(in: &cancellables)
        }
    }
    
    // MARK: - Combine 訂閱管理
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - SFSpeechRecognizerDelegate
    
    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        DispatchQueue.main.async {
            if available {
                print("✅ 語音識別可用")
            } else {
                print("❌ 語音識別不可用")
                self.error = "語音識別暫時不可用"
            }
        }
    }
}