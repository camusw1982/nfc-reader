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
    @Environment(\.dismiss) private var dismiss
    
    // 使用共享的 HTTPManager 實例，避免重複創建
    private var httpManager: HTTPManager {
        return HTTPManager.shared
    }
    var body: some View {
        
        ZStack {
            Color(red: 0.07, green: 0.07, blue: 0.07)
                .ignoresSafeArea()
            BeautifulMechGradient()
            
            // 背景
            /* Color(red: 0.08, green: 0.08, blue: 0.08)
             .ignoresSafeArea()
                
            // 背景橢圓形顏色塊與漸變效果
            Ellipse()
                .fill(
                    LinearGradient(
                        stops: [
                            Gradient.Stop(color: Color(red: 0.22, green: 0.34, blue: 0.69), location: 0.00),
                            Gradient.Stop(color: .black.opacity(0), location: 1.00),
                        ],
                        startPoint: UnitPoint(x: 0.5, y: 0),
                        endPoint: UnitPoint(x: 0.5, y: 0.76)
                    )
                )
                .frame(width: 340, height: 448)
                .offset(x: -60, y: -200) // 設置具體的 x, y 位置
                .blur(radius: 120)
            
            Ellipse()
                .fill(
                    LinearGradient(
                        stops: [
                            Gradient.Stop(color: Color(red: 0.51, green: 0.38, blue: 0.17), location: 0.00),
                            Gradient.Stop(color: .black.opacity(0), location: 1.00),
                        ],
                        startPoint: UnitPoint(x: 0.5, y: 0),
                        endPoint: UnitPoint(x: 0.5, y: 0.76)
                    )
                )
                .frame(width: 340, height: 448)
                .offset(x: 180, y: 160) // 設置具體的 x, y 位置
                .blur(radius: 120) */
                
            
            ZStack {
                // 主要內容區域 - 佔滿整個屏幕
                VStack(spacing: 0) {
                    // 頂部標題欄
                    HeaderView(httpManager: httpManager)
                    
                    // 對話區域 - 佔滿剩餘空間
                    ChatListView(messages: speechRecognizer.messages.compactMap { $0 as? ChatMessage })
                    
                    // 對話與Talk按鈕之間的間距
                    .padding(.bottom, 8)
                }
                
                // 底部覆蓋層 - 包含語音控制元素
                VStack {
                    Spacer()
                    
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
                        httpManager: httpManager,
                        onStartRecording: startSpeechRecognition,
                        onStopRecording: stopSpeechRecognition,
                        onCancelRecording: cancelRecording,
                        onConfirmRecording: confirmRecording
                    )
                    .padding(.horizontal, 100)
                    .padding(.vertical, 0)
                    
                    // 底部工具欄
                    BottomToolbarView(
                        httpManager: httpManager,
                        onClearChat: { speechRecognizer.clearChat() }
                    )
                }
                
                // 右下角返回按鈕
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: {
                            goBackToNFCReader()
                        }) {
                            Image(systemName: "arrow.backward.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.blue.opacity(0.8))
                                .background(
                                    Circle()
                                        .fill(Color.white.opacity(0.1))
                                        .frame(width: 40, height: 40)
                                )
                        }
                        .padding(.trailing, 20)
                        .padding(.bottom, 10)
                    }
                }
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
        // webServiceManager.setWebSocketManager(httpManager) // TODO: 需要更新 WebServiceManager 來支持 HTTPManager
        speechRecognizer.webService = webServiceManager
        
        // 設置 HTTPManager 的 speechRecognizer 引用
        httpManager.speechRecognizer = speechRecognizer
        
        // 初始化語音控制功能
        voiceManager.initialize()
        
        // 自動連接到 HTTP 服務器
        httpManager.connect()
        
        // 只有在人物名稱為空時才獲取當前人物名稱
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if httpManager.characterName.isEmpty || httpManager.characterName == "AI 語音助手" {
                httpManager.getCharacterName()
            }
        }
    }
    
    private func cleanup() {
        // 停止語音識別和斷開 HTTP 連接
        speechRecognizer.stopRecording()
        httpManager.disconnect()
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
            serviceManager: httpManager
        )
    }
    
    private func goBackToNFCReader() {
        // 清理當前狀態
        cleanup()
        
        // 返回到 NFCReaderView
        dismiss()
    }
}


#Preview {
    LandingPageView()
}
    
