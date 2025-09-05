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
    private var cancellables = Set<AnyCancellable>()
    
    override init() {
        super.init()
        setupSpeechRecognizer()
        requestPermission()
        setupWebSocketMonitoring()
    }
    
    private func setupSpeechRecognizer() {
        // 智能語言檢測，優先支持粵語和中文
        let languageOptions = [
            "zh-HK",  // 香港繁體中文（粵語）
            "zh-TW",  // 台灣繁體中文
            "zh-CN",  // 簡體中文
            "en-US",  // 美式英語
            "en-GB"   // 英式英語
        ]
        
        // 嘗試按優先順序初始化語音識別器
        for language in languageOptions {
            if let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language)) {
                if recognizer.isAvailable {
                    speechRecognizer = recognizer
                    speechRecognizer?.delegate = self
                    print("✅ 成功初始化語音識別器，語言: \(language)")
                    return
                }
            }
        }
        
        // 如果所有語言都不可用，使用系統默認
        speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
        speechRecognizer?.delegate = self
        print("ℹ️ 使用系統默認語言: \(Locale.current.identifier)")
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
                case .restricted:
                    self?.error = "語音識別功能受限"
                case .notDetermined:
                    self?.error = "語音識別權限未確定"
                @unknown default:
                    self?.error = "未知的權限狀態"
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
            error = "語音識別服務不可用"
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
        
        // 配置音頻會話
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try audioSession.setActive(true)
        } catch {
            self.error = "音頻會話配置失敗: \(error.localizedDescription)"
            return
        }
        
        // 創建識別請求
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            error = "無法創建識別請求"
            return
        }
        
        recognitionRequest.shouldReportPartialResults = true
        
        // 簡化：只使用在線識別，避免離線識別的 1101 錯誤
        recognitionRequest.requiresOnDeviceRecognition = false
        
        // 開始識別任務
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                let transcribedString = result.bestTranscription.formattedString
                DispatchQueue.main.async {
                    self.recognizedText = transcribedString
                    if result.isFinal {
                        print("🎤 語音識別完成: \(transcribedString)")
                    }
                }
            }
            
            if let error = error {
                let errorDescription = error.localizedDescription
                
                // 過濾掉正常情況的錯誤
                if errorDescription == "No speech detected" || 
                   errorDescription == "Recognition request was canceled" ||
                   errorDescription.contains("kAFAssistantErrorDomain error 216") {
                    print("ℹ️ \(errorDescription) (正常情況)")
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
        } catch {
            self.error = "音頻引擎啟動失敗: \(error.localizedDescription)"
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
            
            // 結束音頻請求
            recognitionRequest?.endAudio()
            recognitionRequest = nil
            
            // 取消識別任務
            recognitionTask?.cancel()
            recognitionTask = nil
            
            // 停用音頻會話
            do {
                try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            } catch {
                print("⚠️ 停用音頻會話失敗: \(error.localizedDescription)")
            }
            
            DispatchQueue.main.async {
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
        // 這個方法保留用於向後兼容，但實際發送邏輯應該在調用方處理
        print("📤 語音識別結果: \(recognizedText)")
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
    
    // MARK: - 語言支持檢查
    func getCurrentLanguage() -> String {
        guard let recognizer = speechRecognizer else {
            return "未知"
        }
        return recognizer.locale.identifier
    }
    
    func checkLanguageSupport() -> String {
        let supportedLanguages = [
            "zh-HK": "香港繁體中文（粵語）",
            "zh-TW": "台灣繁體中文",
            "zh-CN": "簡體中文",
            "en-US": "美式英語",
            "en-GB": "英式英語"
        ]
        
        var availableLanguages: [String] = []
        
        for (code, name) in supportedLanguages {
            if let recognizer = SFSpeechRecognizer(locale: Locale(identifier: code)) {
                if recognizer.isAvailable {
                    availableLanguages.append(name)
                }
            }
        }
        
        if availableLanguages.isEmpty {
            return "❌ 沒有可用的語音識別語言"
        } else {
            let currentLang = getCurrentLanguage()
            let currentLangName = supportedLanguages[currentLang] ?? currentLang
            return """
            ✅ 當前語言: \(currentLangName)
            
            可用語言:
            • \(availableLanguages.joined(separator: "\n• "))
            """
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
            }
        } else {
            issues.append("無法初始化語音識別器")
            recommendations.append("重啟應用程序或檢查設備設置")
        }
        
        // 添加語言支持檢查
        let languageInfo = checkLanguageSupport()
        
        if issues.isEmpty {
            return """
            ✅ 設備設置正常，語音識別功能可用
            
            \(languageInfo)
            """
        } else {
            let issueText = issues.joined(separator: "、")
            let recommendationText = recommendations.joined(separator: "\n• ")
            
            return """
            ⚠️ 設備設置問題：\(issueText)
            
            建議解決方案：
            • \(recommendationText)
            • 確保設備已連接網絡（使用在線語音識別）
            • 檢查設備語言設置是否支持粵語
            
            \(languageInfo)
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
                    // 如果不是 JSON 格式，直接作為回應處理
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