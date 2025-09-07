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
    @State private var showMiniMaxView = false
    @State private var miniMaxApiKey = "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJHcm91cE5hbWUiOiJDYW11cyBXb25nIiwiVXNlck5hbWUiOiJDYW11cyBXb25nIiwiQWNjb3VudCI6IiIsIlN1YmplY3RJRCI6IjE5MjA4NjYwNjE5NDM1NzU0NjUiLCJQaG9uZSI6IiIsIkdyb3VwSUQiOiIxOTIwODY2MDYxOTM1MTg2ODU3IiwiUGFnZU5hbWUiOiIiLCJNYWlsIjoiY2FtdXN3MTk4MkBnbWFpbC5jb20iLCJDcmVhdGVUaW1lIjoiMjAyNS0wOC0xNSAwMDowOTowNSIsIlRva2VuVHlwZSI6MSwiaXNzIjoibWluaW1heCJ9.mQVVfhvyQ_1mp7sKlVF98EQgvp0X2BYI9lS_47a3s4G4PG4h_QRMTuCr1oaCldbjFx5lQYWo1eIwIEiIpXwZinWb4G1UKIXBiR3_1D8IEYNE1MRdPKGL5GA_4kN2d7IrdyPy0lX6ek0OO14FujUCG0LnnO91LmgVopnkt29OxcO0hsvuw3p6Lx1TI-zVvXQdPXqUKlqUvgKlTN2MaFNwe0XJrI-oE_bhB1DYKSBE6wcImxu6KjemVNoojTVbXJarkf-M_rfr20yyA1Hqm0cMRwTgFfq9s-IyS41SWpfg5oFya-aTRjF82Aa8NFuQELJUhR82nQ3-w4oUzCH3ZxjO9Q"
    
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
            Color(red: 0.15, green: 0.15, blue: 0.15)
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
                    onClearChat: { speechRecognizer.clearChat() },
                    onShowMiniMax: { showMiniMaxView = true }
                )
            }
        }
        .speechPermissionAlert(isPresented: $showSpeechPermissionAlert)
        .sheet(isPresented: $showMiniMaxView) {
            MiniMaxTestView(apiKey: miniMaxApiKey)
        }
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
        
        // 自動連接到 WebSocket
        if let webSocketManager = webSocketManager {
            webSocketManager.connect()
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

// MARK: - MiniMax Test View
struct MiniMaxTestView: View {
    let apiKey: String
    @Environment(\.presentationMode) var presentationMode
    @StateObject private var miniMaxManager: MiniMaxManager
    @State private var inputText: String = "鬼滅之刃係講熱血少年炭治郎，為咗將變成鬼嘅妹妹禰豆子變返做人，並為家人報仇，決定加入鬼殺隊斬妖除魔。佢同夥伴們一齊成長，面對各種惡鬼同挑戰，展現堅韌嘅意志同兄妹情誼。"
    
    init(apiKey: String) {
        self.apiKey = apiKey
        self._miniMaxManager = StateObject(wrappedValue: MiniMaxManager(apiKey: apiKey))
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // 標題
                VStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .font(.system(size: 48))
                        .foregroundColor(.blue)
                    
                    Text("MiniMax 語音合成")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("直接連接到 MiniMax API 進行語音合成")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 20)
                
                // 連接狀態
                HStack {
                    Circle()
                        .fill(miniMaxManager.isConnected ? Color.green : Color.red)
                        .frame(width: 12, height: 12)
                        .animation(.easeInOut(duration: 0.3), value: miniMaxManager.isConnected)
                    
                    Text(miniMaxManager.connectionStatus)
                        .font(.caption)
                        .foregroundColor(miniMaxManager.isConnected ? .green : .red)
                    
                    Spacer()
                    
                    Button(action: {
                        if miniMaxManager.isConnected {
                            miniMaxManager.disconnect()
                        } else {
                            miniMaxManager.connect()
                        }
                    }) {
                        Text(miniMaxManager.isConnected ? "斷開" : "連接")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(miniMaxManager.isConnected ? Color.red.opacity(0.2) : Color.green.opacity(0.2))
                            .foregroundColor(miniMaxManager.isConnected ? .red : .green)
                            .cornerRadius(4)
                    }
                }
                .padding(.horizontal)
                
                // 文本輸入
                VStack(alignment: .leading, spacing: 8) {
                    Text("輸入要轉換為語音的文本")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    TextEditor(text: $inputText)
                        .frame(minHeight: 80, maxHeight: 120)
                        .padding(8)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                }
                .padding(.horizontal)
                
                // 操作按鈕
                HStack(spacing: 12) {
                    Button(action: {
                        miniMaxManager.textToSpeech(inputText)
                    }) {
                        HStack {
                            if miniMaxManager.isGenerating {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Image(systemName: "waveform")
                            }
                            
                            Text(miniMaxManager.isGenerating ? "生成中..." : "生成語音")
                        }
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            miniMaxManager.isGenerating ? 
                            Color.orange : 
                            (miniMaxManager.isConnected ? Color.blue : Color.gray)
                        )
                        .cornerRadius(8)
                    }
                    .disabled(!miniMaxManager.isConnected || inputText.isEmpty || miniMaxManager.isGenerating)
                    
                    if miniMaxManager.isPlaying {
                        Button(action: {
                            miniMaxManager.pauseAudio()
                        }) {
                            HStack {
                                Image(systemName: "pause.fill")
                                Text("暫停")
                            }
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.orange)
                            .cornerRadius(8)
                        }
                    } else if miniMaxManager.audioDuration > 0 {
                        Button(action: {
                            miniMaxManager.playAudio()
                        }) {
                            HStack {
                                Image(systemName: "play.fill")
                                Text("播放")
                            }
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.green)
                            .cornerRadius(8)
                        }
                    }
                    
                    Spacer()
                }
                .padding(.horizontal)
                
                // 音頻進度
                if miniMaxManager.audioDuration > 0 {
                    VStack(spacing: 4) {
                        ProgressView(value: miniMaxManager.audioProgress)
                            .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                        
                        HStack {
                            Text(miniMaxManager.getFormattedCurrentTime())
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            Text(miniMaxManager.getFormattedRemainingTime())
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal)
                }
                
                Spacer()
                
                // 關閉按鈕
                Button(action: {
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Text("關閉")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 20)
            }
            .navigationBarHidden(true)
        }
        .onAppear {
            miniMaxManager.connect()
        }
        .onDisappear {
            miniMaxManager.disconnect()
        }
    }
}

#Preview {
    LandingPageView()
}
    