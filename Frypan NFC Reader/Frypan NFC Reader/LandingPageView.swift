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
    @State private var showContentPage = false
    @StateObject private var speechRecognizer: SpeechRecognizer
    @State private var showSpeechPermissionAlert = false
    @State private var isPressingTalkButton = false
    @State private var slideOffset: CGFloat = 0
    @State private var showSlideControls = false
    @State private var isRecordingConfirmed = false
    @State private var scrollID: UUID? = nil
    @State private var isInitialized = false
    @State private var pulseAnimation: Bool = false
    @State private var currentSlideAction: SlideAction? = nil
    
    init() {
        self._speechRecognizer = StateObject(wrappedValue: SpeechRecognizer())
    }
    
    // 獲取 WebSocketManager 實例
    private var webSocketManager: WebSocketManager? {
        speechRecognizer.webService.getWebSocketManager()
    }
    
    // 滑動操作枚舉
    enum SlideAction {
        case cancel
        case confirm
        case none
    }
    
    var body: some View {
        ZStack {
            // 背景
            Color.black
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // 頂部標題欄
                VStack(spacing: 8) {
                    HStack {
                        Text("影聲")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        // WebSocket 狀態指示器
                        HStack(spacing: 6) {
                            Circle()
                                .fill(webSocketManager?.isConnected == true ? Color.green : Color.red)
                                .frame(width: 8, height: 8)
                            Text(webSocketManager?.connectionStatus ?? "未連接")
                                .font(.caption)
                                .foregroundColor(webSocketManager?.isConnected == true ? Color.green : Color.red)
                            if let connectionId = webSocketManager?.connectionId, !connectionId.isEmpty {
                                Text("(\(connectionId))")
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }
                    }
                    
                    Text("AI 語音助手")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 16)
                
                // WebSocket 和音頻狀態欄 - 已隱藏
                // if webSocketManager?.isPlayingAudio == true {
                //     HStack(spacing: 8) {
                //         Image(systemName: "speaker.wave.2.fill")
                //             .foregroundColor(.blue)
                //             .font(.system(size: 14))
                //         
                //         ProgressView(value: webSocketManager?.audioProgress ?? 0.0)
                //             .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                //             .frame(height: 4)
                //         
                //         Text("播放中...")
                //             .font(.caption)
                //             .foregroundColor(.blue)
                //         
                //         Spacer()
                //         
                //         Button(action: {
                //             webSocketManager?.stopAudio()
                //         }) {
                //             Image(systemName: "stop.fill")
                //                 .foregroundColor(.red)
                //                 .font(.system(size: 14))
                //         }
                //     }
                //     .padding(.horizontal, 16)
                //     .padding(.vertical, 8)
                //     .background(Color.blue.opacity(0.1))
                //     .cornerRadius(8)
                //     .padding(.horizontal, 20)
                //     .padding(.bottom, 8)
                // }
                
                // 對話區域
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(speechRecognizer.messages) { message in
                                ChatBubbleView(message: message)
                                    .id(message.id)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    .onChange(of: speechRecognizer.messages.count) { _, _ in
                        // 自動滾動到最新消息
                        if let lastMessage = speechRecognizer.messages.last {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                    .onAppear {
                        // 初始滾動到底部
                        if let lastMessage = speechRecognizer.messages.last {
                            DispatchQueue.main.async {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 100, maxHeight: .infinity)
                
                // 語音識別狀態顯示
                if !speechRecognizer.recognizedText.isEmpty && speechRecognizer.isRecognizing && isPressingTalkButton {
                    VStack(spacing: 4) {
                        Text("識別中...")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                        
                        Text(speechRecognizer.recognizedText)
                            .font(.body)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(8)
                    }
                    .padding(.bottom, 8)
                }
                
                // 錯誤信息
                if let error = speechRecognizer.error {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.bottom, 8)
                }
                
                // 滑動控制區域
                if showSlideControls {
                    HStack(spacing: 40) {
                        // 取消按鈕
                        Circle()
                            .fill(slideOffset < -50 ? Color.red.opacity(0.8) : Color.red.opacity(0.3))
                            .frame(width: 60, height: 60)
                            .overlay(
                                Image(systemName: "xmark")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundColor(.white)
                                    .scaleEffect(slideOffset < -50 ? 1.2 : 1.0)
                            )
                            .animation(.easeInOut(duration: 0.2), value: slideOffset)
                        
                        // 確認按鈕
                        Circle()
                            .fill(slideOffset > 50 ? Color.green.opacity(0.8) : Color.green.opacity(0.3))
                            .frame(width: 60, height: 60)
                            .overlay(
                                Image(systemName: "checkmark")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundColor(.white)
                                    .scaleEffect(slideOffset > 50 ? 1.2 : 1.0)
                            )
                            .animation(.easeInOut(duration: 0.2), value: slideOffset)
                    }
                    .padding(.horizontal, 20)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .bottom).combined(with: .opacity)
                    ))
                    .animation(.easeInOut(duration: 0.3), value: showSlideControls)
                }
                
                // Talk 按鈕
                Button(action: {
                    // Empty action, using gestures instead
                }) {
                    ZStack {
                        // 外圈動畫效果
                        Circle()
                            .fill(Color.clear)
                            .overlay(
                                Circle()
                                    .stroke(Color.blue.opacity(0.6), lineWidth: 3)
                                    .scaleEffect(pulseAnimation ? 1.4 : 1.0)
                                    .opacity(pulseAnimation ? 0.2 : 0.8)
                                    .animation(
                                        Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true),
                                        value: pulseAnimation
                                    )
                            )
                            .frame(width: 100, height: 100)
                        
                        // 主按鈕
                        Circle()
                            .fill(isPressingTalkButton ? (slideOffset < -50 ? Color.red : slideOffset > 50 ? Color.green : Color.orange) : Color.blue)
                            .frame(width: 80, height: 80)
                            .shadow(color: isPressingTalkButton ? (slideOffset < -50 ? Color.red.opacity(0.5) : slideOffset > 50 ? Color.green.opacity(0.5) : Color.orange.opacity(0.3)) : Color.blue.opacity(0.3), radius: 0, x: 0, y: 4)
                            .animation(.easeInOut(duration: 0.2), value: slideOffset)
                            .animation(.easeInOut(duration: 0.2), value: isPressingTalkButton)
                        
                        // 麥克風圖標
                        Image(systemName: speechRecognizer.isRecognizing ? "mic.fill" : "mic")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            // 確保初始化完成
                            guard isInitialized else {
                                print("⚠️ 按壓說話功能尚未初始化完成")
                                return
                            }
                            
                            isPressingTalkButton = true
                            
                            if !speechRecognizer.isRecognizing {
                                print("🎤 開始語音識別")
                                startSpeechRecognition()
                                DispatchQueue.main.async {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        showSlideControls = true
                                    }
                                }
                            } else if !showSlideControls {
                                // 如果已經在錄音但控件沒顯示，確保顯示
                                DispatchQueue.main.async {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        showSlideControls = true
                                    }
                                }
                            }
                            
                            // 計算滑動偏移，限制最大滑動距離
                            slideOffset = max(-100, min(100, value.translation.width))
                            
                            // 更新當前滑動操作狀態，但不立即執行
                            if slideOffset < -50 {
                                currentSlideAction = .cancel
                            } else if slideOffset > 50 {
                                currentSlideAction = .confirm
                            } else {
                                currentSlideAction = SlideAction.none
                            }
                        }
                        .onEnded { value in
                            isPressingTalkButton = false
                            
                            // 根據手指離開時的位置決定操作
                            if let action = currentSlideAction {
                                switch action {
                                case .cancel:
                                    print("🚫 手指離開取消區域，取消錄音")
                                    cancelRecording()
                                    // 取消操作後重置狀態
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                        self.resetRecordingState()
                                    }
                                case .confirm:
                                    print("✅ 手指離開確認區域，確認錄音")
                                    confirmRecording()
                                    // 確認操作後重置狀態
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                        self.resetRecordingState()
                                    }
                                case .none:
                                    print("⚠️ 手指離開中性區域，視為取消")
                                    if speechRecognizer.isRecognizing {
                                        stopSpeechRecognition()
                                    }
                                    // 延遲重置所有狀態
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                        self.resetRecordingState()
                                    }
                                }
                            } else {
                                print("⚠️ 手指離開，currentSlideAction 為 nil，視為取消")
                                if speechRecognizer.isRecognizing {
                                    stopSpeechRecognition()
                                }
                                // 延遲重置所有狀態
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    self.resetRecordingState()
                                }
                            }
                            
                            // 立即隱藏滑動控制
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showSlideControls = false
                                slideOffset = 0
                                currentSlideAction = SlideAction.none
                            }
                        }
                )
                .padding(.bottom, 20)
                
                // 底部工具欄
                HStack(spacing: 20) {
                    Button(action: {
                        speechRecognizer.clearChat()
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 18))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    
                    Button(action: {
                        if webSocketManager?.isConnected == true {
                            webSocketManager?.disconnect()
                        } else {
                            webSocketManager?.connect()
                        }
                    }) {
                        Image(systemName: webSocketManager?.isConnected == true ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                            .font(.system(size: 18))
                            .foregroundColor(webSocketManager?.isConnected == true ? Color.green : Color.white.opacity(0.7))
                    }
                    
                    //Button(action: {
                    //    webSocketManager?.checkConnectionStatus()
                    //}) {
                    //    Image(systemName: "network")
                    //        .font(.system(size: 18))
                    //        .foregroundColor(.white.opacity(0.7))
                    //}
                    
                    Button(action: {
                        webSocketManager?.clearHistory()
                    }) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 18))
                           .foregroundColor(.white.opacity(0.7))
                    }
                    
                    Button(action: {
                        webSocketManager?.stopAudio()
                    }) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 18))
                            .foregroundColor(webSocketManager?.isPlayingAudio == true ? Color.red : Color.white.opacity(0.5))
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
        }
        .alert("語音識別權限", isPresented: $showSpeechPermissionAlert) {
            Button("確定", role: .cancel) { }
        } message: {
            Text("請到「設定」>「隱私權與安全性」>「語音識別」中允許此應用程式存取語音識別功能")
        }
        .onAppear {
            // 初始化按壓說話功能
            initializePressToTalk()
            
            // 啟動脈衝動畫
            startPulseAnimation()
            
            // 只在未連接時才檢查連接狀態，避免重複連接
            if webSocketManager?.isConnected != true {
                webSocketManager?.checkConnectionStatus()
            }
        }
        .onDisappear {
            // 停止語音識別和斷開 WebSocket
            speechRecognizer.stopRecording()
            webSocketManager?.disconnect()
        }
    }
    
    private func initializePressToTalk() {
        // 重置所有狀態變量
        DispatchQueue.main.async {
            self.isPressingTalkButton = false
            self.slideOffset = 0
            self.showSlideControls = false
            self.isRecordingConfirmed = false
            self.currentSlideAction = SlideAction.none
            self.speechRecognizer.isRecordingCancelled = false
            
            // 確保語音識別器處於正確狀態
            if self.speechRecognizer.isRecognizing {
                self.speechRecognizer.stopRecording()
            }
            
            // 標記初始化完成
            self.isInitialized = true
            print("✅ 按壓說話功能初始化完成")
        }
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
        // 防止重複取消
        guard !isRecordingConfirmed else {
            print("⚠️ 錄音已經被處理，忽略重複取消")
            return
        }
        
        isRecordingConfirmed = true
        
        // 設置取消標誌，防止任何發送
        DispatchQueue.main.async {
            self.speechRecognizer.isRecordingCancelled = true
        }
        
        // 立即停止錄音且不發送結果
        speechRecognizer.stopRecording(shouldSendResult: false)
        
        // 立即清空識別文本，防止任何意外發送
        DispatchQueue.main.async {
            self.speechRecognizer.recognizedText = ""
        }
        
        // 震動反饋
        let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
        impactFeedback.impactOccurred()
        
        print("🚫 錄音已取消，不會發送任何內容")
    }
    
    private func resetRecordingState() {
        DispatchQueue.main.async {
            // 重置所有錄音相關狀態
            self.isRecordingConfirmed = false
            self.isPressingTalkButton = false
            self.showSlideControls = false
            self.slideOffset = 0
            self.currentSlideAction = SlideAction.none
            self.speechRecognizer.isRecordingCancelled = false
            
            // 確保語音識別器處於正確狀態
            if self.speechRecognizer.isRecognizing {
                self.speechRecognizer.stopRecording()
            }
            
            // 清空識別文本
            self.speechRecognizer.recognizedText = ""
            
            print("🔄 錄音狀態已完全重置")
        }
    }
    
    private func confirmRecording() {
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
            
            // 立即發送到 WebSocket 進行語音合成
            webSocketManager?.sendTextToSpeech(text: recognizedText)
            
            // 成功確認的震動反饋
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
        } else {
            print("⚠️ 沒有有效錄音內容，視為取消操作")
            // 如果沒有有效錄音內容，視為取消操作
            handleEmptyRecordingAsCancel()
        }
    }
    
    private func handleEmptyRecordingAsCancel() {
        // 立即清空識別文本
        DispatchQueue.main.async {
            self.speechRecognizer.recognizedText = ""
        }
        
        // 取消的震動反饋
        let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
        impactFeedback.impactOccurred()
        
        print("🚫 空錄音已視為取消，不會發送任何內容")
    }
    
    private func startPulseAnimation() {
        // 啟動脈衝動畫，3秒完整週期（1.5秒放大，1.5秒縮小）
        withAnimation(
            Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true)
        ) {
            pulseAnimation = true
        }
    }
}

// 對話氣泡視圖
struct ChatBubbleView: View {
    let message: ChatMessage
    
    var body: some View {
        HStack {
            if message.isUser {
                Spacer()
                UserBubbleView(message: message)
            } else {
                AIBubbleView(message: message)
                Spacer()
            }
        }
    }
}

// 用戶氣泡（右側）
struct UserBubbleView: View {
    let message: ChatMessage
    
    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(formatTime(message.timestamp))
                .font(.caption2)
                .foregroundColor(.white.opacity(0.6))
            
            HStack {
                Text(message.text)
                    .font(.body)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.blue, Color.blue.opacity(0.7)]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(20)
                    .shadow(color: .blue.opacity(0.3), radius: 2, x: 0, y: 2)
            }
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// AI 氣泡（左側）
struct AIBubbleView: View {
    let message: ChatMessage
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "brain.head.profile")
                    .font(.caption)
                    .foregroundColor(.blue)
                Text("Gemini AI")
                    .font(.caption)
                    .foregroundColor(.blue)
                Text(formatTime(message.timestamp))
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
            }
            
            HStack {
                Text(message.text)
                    .font(.body)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.gray.opacity(0.4), Color.gray.opacity(0.2)]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(20)
                    .shadow(color: .gray.opacity(0.2), radius: 2, x: 0, y: 2)
            }
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#Preview {
    LandingPageView()
}
