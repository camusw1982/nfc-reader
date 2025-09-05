//
//  LandingPageView.swift
//  Frypan NFC Reader
//
//  Created by Claude on 4/9/2025.
//

import SwiftUI
import AVFoundation
import AVKit
import Speech
import Combine

struct LandingPageView: View {
    @StateObject private var speechRecognizer: SpeechRecognizer
    @StateObject private var voiceManager = VoiceControlManager()
    @State private var showSpeechPermissionAlert = false
    
    init() {
        self._speechRecognizer = StateObject(wrappedValue: SpeechRecognizer())
    }
    
    // 獲取 WebSocketManager 實例
    private var webSocketManager: WebSocketManager? {
        speechRecognizer.webService.getWebSocketManager()
    }
    
    var body: some View {
        ZStack {
            // 背景
            Color.black
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // 頂部標題欄
                HeaderView(webSocketManager: webSocketManager)
                
                // 對話區域
                ChatListView(messages: speechRecognizer.messages)
                
                // 語音識別狀態顯示
                SpeechRecognitionStatusView(
                    speechRecognizer: speechRecognizer,
                    voiceManager: voiceManager
                )
                
                // 錯誤信息
                ErrorMessageView(error: speechRecognizer.error)
                
                // 滑動控制區域
                SlideControlsView(voiceManager: voiceManager)
                
                // Talk 按鈕
                TalkButtonView(
                    voiceManager: voiceManager,
                    speechRecognizer: speechRecognizer,
                    onStartRecording: startSpeechRecognition,
                    onStopRecording: stopSpeechRecognition,
                    onCancelRecording: cancelRecording,
                    onConfirmRecording: confirmRecording
                )
                .padding(.bottom, 20)
                
                // 底部工具欄
                BottomToolbarView(
                    webSocketManager: webSocketManager,
                    onClearChat: { speechRecognizer.clearChat() }
                )
            }
        }
        .speechPermissionAlert(isPresented: $showSpeechPermissionAlert)
        .onAppear {
            initializeView()
        }
        .onDisappear {
            cleanup()
        }
    }
    
    // MARK: - Private Methods
    
    private func initializeView() {
        // 初始化語音控制功能
        voiceManager.initialize()
        
        // 啟動脈衝動畫
        voiceManager.startPulseAnimation()
        
        // 只在未連接時才檢查連接狀態，避免重複連接
        if webSocketManager?.isConnected != true {
            webSocketManager?.checkConnectionStatus()
        }
    }
    
    private func cleanup() {
        // 停止語音識別和斷開 WebSocket
        speechRecognizer.stopRecording()
        webSocketManager?.disconnect()
    }
    
    private func startSpeechRecognition() {
        if speechRecognizer.hasPermission {
            speechRecognizer.startRecording()
        } else {
            // 如果沒有權限，提示用戶
            showSpeechPermissionAlert = true
        }
    }
    
    private func stopSpeechRecognition() {
        speechRecognizer.stopRecording()
    }
    
    private func cancelRecording() {
        voiceManager.cancelRecording(speechRecognizer: speechRecognizer)
    }
    
    private func confirmRecording() {
        voiceManager.confirmRecording(
            speechRecognizer: speechRecognizer,
            webSocketManager: webSocketManager
        )
    }
}

#Preview {
    LandingPageView()
}