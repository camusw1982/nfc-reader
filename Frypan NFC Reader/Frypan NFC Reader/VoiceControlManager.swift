//
//  VoiceControlManager.swift
//  Frypan NFC Reader
//
//  Created by Claude on 5/9/2025.
//

import Foundation
import AVFoundation
import SwiftUI
import UIKit

// MARK: - Voice Control Manager
class VoiceControlManager: ObservableObject {
    @Published var isPressingTalkButton = false
    @Published var slideOffset: CGFloat = 0
    @Published var showSlideControls = false
    @Published var isRecordingConfirmed = false
    @Published var currentSlideAction: SlideAction? = nil
    @Published var isInitialized = false
    
    // 滑動操作枚舉
    enum SlideAction {
        case cancel
        case confirm
        case none
    }
    
    func initialize() {
        DispatchQueue.main.async {
            self.isPressingTalkButton = false
            self.slideOffset = 0
            self.showSlideControls = false
            self.isRecordingConfirmed = false
            self.currentSlideAction = SlideAction.none
            self.isInitialized = true
            print("✅ 語音控制管理器初始化完成")
        }
    }
    
    func resetRecordingState() {
        DispatchQueue.main.async {
            self.isRecordingConfirmed = false
            self.isPressingTalkButton = false
            self.showSlideControls = false
            self.slideOffset = 0
            self.currentSlideAction = SlideAction.none
            print("🔄 錄音狀態已完全重置")
        }
    }
    
    func resetRecordingState(speechRecognizer: SpeechRecognizer) {
        DispatchQueue.main.async {
            self.isRecordingConfirmed = false
            self.isPressingTalkButton = false
            self.showSlideControls = false
            self.slideOffset = 0
            self.currentSlideAction = SlideAction.none
            // 清空識別文本
            speechRecognizer.recognizedText = ""
            print("🔄 錄音狀態已完全重置，包括識別文本")
        }
    }
    
    // MARK: - Recording Actions
    
    func cancelRecording(speechRecognizer: SpeechRecognizer) {
        // 防止重複取消
        guard !isRecordingConfirmed else {
            print("⚠️ 錄音已經被處理，忽略重複取消")
            return
        }
        
        isRecordingConfirmed = true
        
        // 設置取消標誌，防止任何發送
        DispatchQueue.main.async {
            speechRecognizer.isRecordingCancelled = true
        }
        
        // 立即停止錄音且不發送結果
        speechRecognizer.stopRecording(shouldSendResult: false)
        
        // 立即清空識別文本，防止任何意外發送
        DispatchQueue.main.async {
            speechRecognizer.recognizedText = ""
        }
        
        // 震動反饋
        let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
        impactFeedback.impactOccurred()
        
        print("🚫 錄音已取消，不會發送任何內容")
    }
    
    func confirmRecording(speechRecognizer: SpeechRecognizer, serviceManager: (any ServiceProtocol)?) {
        // 防止重複確認
        guard !isRecordingConfirmed else {
            print("⚠️ 錄音已經被處理，忽略重複確認")
            return
        }
        
        isRecordingConfirmed = true
        let recognizedText = speechRecognizer.recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        print("✅ 確認錄音，識別文本: '\(recognizedText)'")
        
        // 先停止錄音，但不發送結果（因為我們會手動發送）
        speechRecognizer.stopRecording(shouldSendResult: false)
        
        // 檢查是否有有效的錄音內容
        if !recognizedText.isEmpty && recognizedText.count > 0 {
            // 立即添加用戶消息到對話列表
            let userMessage = ChatMessage(text: recognizedText, isUser: true, timestamp: Date(), isError: false)
            speechRecognizer.messages.append(userMessage)
            
            print("📤 準備發送文本到服務器: '\(recognizedText)'")
            
            // 立即發送到服務器進行語音合成
            serviceManager?.sendTextToSpeech(text: recognizedText, character_id: nil)
            
            // 成功確認的震動反饋
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
        } else {
            print("⚠️ 沒有有效錄音內容，視為取消操作")
            // 如果沒有有效錄音內容，視為取消操作
            handleEmptyRecordingAsCancel(speechRecognizer: speechRecognizer)
        }
    }
    
    private func handleEmptyRecordingAsCancel(speechRecognizer: SpeechRecognizer) {
        // 立即清空識別文本
        DispatchQueue.main.async {
            speechRecognizer.recognizedText = ""
        }
        
        // 取消的震動反饋
        let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
        impactFeedback.impactOccurred()
        
        print("🚫 空錄音已視為取消，不會發送任何內容")
    }
}
