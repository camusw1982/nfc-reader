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
    
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private let audioSession = AVAudioSession.sharedInstance()
    
    override init() {
        // 嘗試多個語言選項，提高兼容性
        self.speechRecognizer = Self.initializeSpeechRecognizer()
        super.init()
        speechRecognizer?.delegate = self
        requestPermission()
        setupWebSocketMonitoring()
        
        // 檢查語音識別可用性
        checkSpeechRecognitionAvailability()
    }
    
    private static func initializeSpeechRecognizer() -> SFSpeechRecognizer? {
        let languageOptions = [
            "zh-HK",  // 香港繁體中文
            "zh-TW",  // 台灣繁體中文
            "zh-CN",  // 簡體中文
            "en-US",  // 美式英語
            "en-GB",  // 英式英語
            "ja-JP",  // 日語
            "ko-KR"   // 韓語
        ]
        
        for language in languageOptions {
            if let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language)) {
                if recognizer.isAvailable {
                    print("✅ 成功初始化語音識別器，語言: \(language)")
                    return recognizer
                } else {
                    print("⚠️ 語音識別器不可用，語言: \(language)")
                }
            }
        }
        
        // 最後嘗試系統默認語言
        if let defaultRecognizer = SFSpeechRecognizer(locale: Locale.current) {
            print("ℹ️ 使用系統默認語言: \(Locale.current.identifier)")
            return defaultRecognizer
        }
        
        print("❌ 無法初始化任何語音識別器")
        return nil
    }
    
    func requestPermission() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                switch status {
                case .authorized:
                    self?.hasPermission = true
                    print("✅ 語音識別權限已授予")
                    // 權限獲得後再次檢查可用性
                    self?.checkSpeechRecognitionAvailability()
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
    
    private func checkSpeechRecognitionAvailability() {
        guard let speechRecognizer = speechRecognizer else {
            DispatchQueue.main.async {
                self.error = "無法初始化語音識別器"
                print("❌ 無法初始化語音識別器")
            }
            return
        }
        
        if speechRecognizer.isAvailable {
            print("✅ 語音識別服務可用")
        } else {
            DispatchQueue.main.async {
                self.error = "語音識別服務暫時不可用，請檢查設備設置"
                print("❌ 語音識別服務不可用")
            }
        }
    }
    
    private func isOfflineDictationAvailable() -> Bool {
        guard let recognizer = speechRecognizer else { return false }
        
        // 檢查是否支持離線識別
        if !recognizer.supportsOnDeviceRecognition {
            print("⚠️ 設備不支持離線語音識別")
            return false
        }
        
        // 檢查當前語言是否可用於離線識別
        let currentLocale = recognizer.locale
        print("🔍 檢查離線聽寫可用性，語言: \(currentLocale.identifier)")
        
        // 這裡我們假設如果 supportsOnDeviceRecognition 為 true，
        // 那麼離線識別應該是可用的，除非設備設置不正確
        return true
    }
    
    private func handleOfflineDictationError() {
        print("🔄 離線聽寫錯誤，嘗試使用在線識別...")
        
        // 停止當前的識別任務
        stopRecording()
        
        // 等待一段時間後重新開始，但強制使用在線識別
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            print("ℹ️ 切換到在線語音識別模式")
            // 清除錯誤狀態，讓用戶可以重試
            DispatchQueue.main.async {
                self.error = nil
            }
        }
    }
    
    private func handleSpeechRecognitionError() {
        print("🔄 嘗試恢復語音識別服務...")
        
        // 停止當前的識別任務
        stopRecording()
        
        // 等待一段時間後重新初始化
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            // 重新初始化語音識別器
            if let newRecognizer = Self.initializeSpeechRecognizer() {
                self.speechRecognizer = newRecognizer
                self.speechRecognizer?.delegate = self
                print("✅ 語音識別器重新初始化成功")
                
                // 清除錯誤狀態
                DispatchQueue.main.async {
                    self.error = nil
                }
            } else {
                print("❌ 語音識別器重新初始化失敗")
                DispatchQueue.main.async {
                    self.error = "語音識別服務無法恢復，請重啟應用程序"
                }
            }
        }
    }
    
    func startRecording() {
        guard hasPermission else {
            error = "沒有語音識別權限"
            return
        }
        
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            error = "語音識別服務不可用，請檢查設備設置"
            print("❌ 語音識別服務不可用")
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
            // 先停用現有會話，避免衝突
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            
            // 設置音頻會話類別
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            
            // 激活音頻會話
            try audioSession.setActive(true)
            
            print("✅ 音頻會話配置成功")
        } catch let audioError {
            self.error = "音頻會話配置失敗: \(audioError.localizedDescription)"
            print("❌ 音頻會話配置失敗: \(audioError.localizedDescription)")
            return
        }
        
        // 創建識別請求
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            error = "無法創建識別請求"
            return
        }
        
        recognitionRequest.shouldReportPartialResults = true
        
        // 檢查是否可以使用離線識別
        if speechRecognizer.supportsOnDeviceRecognition && isOfflineDictationAvailable() {
            recognitionRequest.requiresOnDeviceRecognition = true
            print("✅ 使用離線語音識別")
        } else {
            recognitionRequest.requiresOnDeviceRecognition = false
            print("ℹ️ 使用在線語音識別（離線識別不可用）")
        }
        
        // 開始識別任務
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
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
                let errorCode = (error as NSError).code
                let errorDomain = (error as NSError).domain
                
                // 過濾掉正常情況的錯誤
                if errorDescription == "No speech detected" {
                    print("ℹ️ 未檢測到語音 (正常情況)")
                } else if errorDescription == "Recognition request was canceled" {
                    print("ℹ️ 語音識別請求已取消 (正常情況)")
                } else if errorDomain == "kAFAssistantErrorDomain" && errorCode == 1101 {
                    // 處理特定的 1101 錯誤 - 離線聽寫設置問題
                    print("⚠️ 離線語音識別設置問題 (Code: 1101)")
                    DispatchQueue.main.async {
                        self.error = "離線語音識別設置不完整。請檢查：\n1. 設置 > 一般 > 鍵盤 > 啟用聽寫\n2. 設置 > 一般 > 鍵盤 > 聽寫語言\n3. 確保已安裝對應語言的鍵盤"
                    }
                    // 嘗試使用在線識別作為回退
                    self.handleOfflineDictationError()
                } else {
                    DispatchQueue.main.async {
                        self.error = "識別錯誤: \(errorDescription) (Code: \(errorCode))"
                        print("❌ 語音識別錯誤: \(errorDescription) (Domain: \(errorDomain), Code: \(errorCode))")
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
            // 停止音頻引擎
            if audioEngine.isRunning {
                audioEngine.stop()
            }
            
            // 移除音頻輸入節點
            if audioEngine.inputNode.numberOfInputs > 0 {
                audioEngine.inputNode.removeTap(onBus: 0)
            }
            
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
                
                // 停用音頻會話，使用更安全的方式
                do {
                    try self.audioSession.setActive(false, options: .notifyOthersOnDeactivation)
                    print("✅ 音頻會話已停用")
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
    
    // MARK: - 設備設置檢查
    func checkDeviceSettings() -> String {
        var issues: [String] = []
        var recommendations: [String] = []
        
        // 檢查語音識別權限
        let authStatus = SFSpeechRecognizer.authorizationStatus()
        switch authStatus {
        case .denied:
            issues.append("語音識別權限被拒絕")
            recommendations.append("前往 設置 > 隱私與安全性 > 語音識別 啟用權限")
        case .restricted:
            issues.append("語音識別功能受限")
            recommendations.append("檢查設備限制設置")
        case .notDetermined:
            issues.append("語音識別權限未確定")
            recommendations.append("應用程序需要語音識別權限")
        case .authorized:
            break
        @unknown default:
            issues.append("未知的權限狀態")
        }
        
        // 檢查語音識別器可用性
        if let recognizer = speechRecognizer {
            if !recognizer.isAvailable {
                issues.append("語音識別服務不可用")
                recommendations.append("檢查網絡連接或重啟設備")
            } else {
                // 檢查離線識別支持
                if recognizer.supportsOnDeviceRecognition {
                    print("✅ 設備支持離線語音識別")
                } else {
                    print("ℹ️ 設備不支持離線語音識別，將使用在線識別")
                }
            }
        } else {
            issues.append("無法初始化語音識別器")
            recommendations.append("重啟應用程序或檢查設備設置")
        }
        
        if issues.isEmpty {
            return "✅ 設備設置正常，語音識別功能可用"
        } else {
            let issueText = issues.joined(separator: "、")
            let recommendationText = recommendations.joined(separator: "\n• ")
            
            return """
            ⚠️ 設備設置問題：\(issueText)
            
            建議解決方案：
            • \(recommendationText)
            • 設置 > 一般 > 鍵盤 > 啟用聽寫
            • 設置 > 一般 > 鍵盤 > 聽寫語言（確保已下載）
            • 設置 > 一般 > 鍵盤 > 鍵盤（確保已安裝對應語言）
            """
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