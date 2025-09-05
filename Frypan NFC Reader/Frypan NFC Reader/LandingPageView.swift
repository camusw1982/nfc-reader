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
                
                // WebSocket 和音頻狀態欄
                if webSocketManager?.isPlayingAudio == true {
                    HStack(spacing: 8) {
                        Image(systemName: "speaker.wave.2.fill")
                            .foregroundColor(.blue)
                            .font(.system(size: 14))
                        
                        ProgressView(value: webSocketManager?.audioProgress ?? 0.0)
                            .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                            .frame(height: 4)
                        
                        Text("播放中...")
                            .font(.caption)
                            .foregroundColor(.blue)
                        
                        Spacer()
                        
                        Button(action: {
                            webSocketManager?.stopAudio()
                        }) {
                            Image(systemName: "stop.fill")
                                .foregroundColor(.red)
                                .font(.system(size: 14))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                }
                
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
                                VStack(spacing: 2) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 18, weight: .bold))
                                        .foregroundColor(.white)
                                        .scaleEffect(slideOffset < -50 ? 1.2 : 1.0)
                                    Text("取消")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(.white)
                                }
                            )
                            .animation(.easeInOut(duration: 0.2), value: slideOffset)
                        
                        // 確認按鈕
                        Circle()
                            .fill(slideOffset > 50 ? Color.green.opacity(0.8) : Color.green.opacity(0.3))
                            .frame(width: 60, height: 60)
                            .overlay(
                                VStack(spacing: 2) {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 18, weight: .bold))
                                        .foregroundColor(.white)
                                        .scaleEffect(slideOffset > 50 ? 1.2 : 1.0)
                                    Text("確認")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(.white)
                                }
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
                                    .stroke(Color.blue.opacity(0.5), lineWidth: 2)
                                    .scaleEffect(isPressingTalkButton ? 1.2 : 1.0)
                                    .opacity(isPressingTalkButton ? 0.3 : 0.8)
                            )
                            .frame(width: 100, height: 100)
                        
                        // 主按鈕
                        Circle()
                            .fill(isPressingTalkButton ? (slideOffset < -50 ? Color.red : slideOffset > 50 ? Color.green : Color.orange) : Color.blue)
                            .frame(width: 80, height: 80)
                            .shadow(color: isPressingTalkButton ? (slideOffset < -50 ? Color.red.opacity(0.5) : slideOffset > 50 ? Color.green.opacity(0.5) : Color.orange.opacity(0.3)) : Color.blue.opacity(0.3), radius: 0, x: 0, y: 4)
                            .animation(.easeInOut(duration: 0.2), value: slideOffset)
                            .animation(.easeInOut(duration: 0.2), value: isPressingTalkButton)
                        
                        // 麥克風圖標和文字
                        VStack(spacing: 4) {
                            Image(systemName: speechRecognizer.isRecognizing ? "mic.fill" : "mic")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundColor(.white)
                            Text(speechRecognizer.isRecognizing ? (slideOffset < -50 ? "滑動取消" : slideOffset > 50 ? "滑動確認" : "錄音中") : "按住講話")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white)
                        }
                    }
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isPressingTalkButton = true
                            
                            if !speechRecognizer.isRecognizing {
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
                            
                            // 檢查是否達到取消或確認閾值
                            if slideOffset < -60 && !isRecordingConfirmed {
                                // 取消錄音
                                cancelRecording()
                            } else if slideOffset > 60 && !isRecordingConfirmed {
                                // 確認錄音
                                confirmRecording()
                            }
                        }
                        .onEnded { value in
                            isPressingTalkButton = false
                            
                            if !isRecordingConfirmed {
                                // 如果冇確認，正常停止錄音
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
                    
                    Button(action: {
                        webSocketManager?.checkConnectionStatus()
                    }) {
                        Image(systemName: "network")
                            .font(.system(size: 18))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    
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
            // 自動連接 WebSocket
            webSocketManager?.connect()
            
            // 延遲檢查連接狀態
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                webSocketManager?.checkConnectionStatus()
            }
            
            // 定期檢查連接狀態
            Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { timer in
                if webSocketManager?.isConnected != true {
                    webSocketManager?.checkConnectionStatus()
                }
            }
        }
        .onDisappear {
            // 停止語音識別和斷開 WebSocket
            speechRecognizer.stopRecording()
            webSocketManager?.disconnect()
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
        
        // 立即添加取消消息
        let cancelMessage = ChatMessage(text: "❌ 錄音已取消", isUser: true, timestamp: Date(), isError: true)
        speechRecognizer.messages.append(cancelMessage)
        
        // 震動反饋
        let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
        impactFeedback.impactOccurred()
        
        // 重置錄音狀態
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.resetRecordingState()
        }
        
        print("🚫 錄音已取消，不會發送任何內容")
    }
    
    private func resetRecordingState() {
        DispatchQueue.main.async {
            self.isRecordingConfirmed = false
            self.isPressingTalkButton = false
            self.showSlideControls = false
            self.slideOffset = 0
            self.speechRecognizer.isRecordingCancelled = false
            print("🔄 錄音狀態已重置")
        }
    }
    
    private func confirmRecording() {
        isRecordingConfirmed = true
        let recognizedText = speechRecognizer.recognizedText
        speechRecognizer.stopRecording()
        
        // 發送到 WebSocket 進行語音合成
        if !recognizedText.isEmpty {
            // 立即添加用戶消息到對話列表
            let userMessage = ChatMessage(text: recognizedText, isUser: true, timestamp: Date(), isError: false)
            speechRecognizer.messages.append(userMessage)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                // 發送到 WebSocket 進行語音合成
                webSocketManager?.sendTextToSpeech(text: recognizedText)
                
                // 重置錄音狀態
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.resetRecordingState()
                }
            }
        } else {
            // 如果冇識別文本，直接重置狀態
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.resetRecordingState()
            }
        }
        
        // 震動反饋
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
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
                            gradient: Gradient(colors: [Color.blue, Color.blue.opacity(0.8)]),
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
                            gradient: Gradient(colors: [Color.gray.opacity(0.3), Color.gray.opacity(0.2)]),
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
