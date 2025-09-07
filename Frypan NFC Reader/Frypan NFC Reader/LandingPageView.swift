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
    @StateObject private var speechRecognizer = SpeechRecognizer()
    @StateObject private var voiceManager = VoiceControlManager()
    @StateObject private var webServiceManager = WebServiceManager()
    @State private var showSpeechPermissionAlert = false
    
    // 使用共享的 WebSocketManager 實例，避免重複創建
    private var webSocketManager: WebSocketManager {
        return WebSocketManager.shared
    }
    
    var body: some View {
        ZStack {
            // 背景
            Color(red: 0.08, green: 0.08, blue: 0.08)
                .ignoresSafeArea()
            
            // 背景橢圓形顏色塊與漸變效果
            Ellipse()
                .fill(
                    LinearGradient(
                        stops: [
                            Gradient.Stop(color: Color(red: 0.12, green: 0.24, blue: 0.59), location: 0.00),
                            Gradient.Stop(color: .black.opacity(0), location: 1.00),
                        ],
                        startPoint: UnitPoint(x: 0.5, y: 0),
                        endPoint: UnitPoint(x: 0.5, y: 0.76)
                    )
                )
                .frame(width: 340, height: 448)
                .offset(x: -60, y: -200) // 設置具體的 x, y 位置
                .blur(radius: 100)
            
            Ellipse()
                .fill(
                    LinearGradient(
                        stops: [
                            Gradient.Stop(color: Color(red: 0.41, green: 0.28, blue: 0.07), location: 0.00),
                            Gradient.Stop(color: .black.opacity(0), location: 1.00),
                        ],
                        startPoint: UnitPoint(x: 0.5, y: 0),
                        endPoint: UnitPoint(x: 0.5, y: 0.76)
                    )
                )
                .frame(width: 340, height: 448)
                .offset(x: 150, y: 150) // 設置具體的 x, y 位置
                .blur(radius: 100)
                
            
            VStack(spacing: 0) {
                // 頂部標題欄
                HeaderView(webSocketManager: webSocketManager)
                
                // 對話區域
                ChatListView(messages: speechRecognizer.messages.compactMap { $0 as? ChatMessage })
                
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
        // 設置服務管理器之間的關聯
        webServiceManager.setWebSocketManager(webSocketManager)
        speechRecognizer.webService = webServiceManager
        
        // 設置 WebSocketManager 的 speechRecognizer 引用
        webSocketManager.speechRecognizer = speechRecognizer
        
        // 初始化語音控制功能
        voiceManager.initialize()
        
        // 自動連接到 WebSocket
        webSocketManager.connect()
        
        // 只有在人物名稱為空時才獲取當前人物名稱
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if webSocketManager.characterName.isEmpty || webSocketManager.characterName == "AI 語音助手" {
                webSocketManager.getCharacterName()
            }
        }
    }
    
    private func cleanup() {
        // 停止語音識別和斷開 WebSocket
        speechRecognizer.stopRecording()
        webSocketManager.disconnect()
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
    
