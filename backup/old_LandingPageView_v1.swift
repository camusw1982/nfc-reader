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

struct LandingPageView: View {
    @State private var showContentPage = false
    @StateObject private var speechRecognizer: SpeechRecognizer
    @State private var showSpeechPermissionAlert = false
    @State private var isPressingButton = false
    
    // 時間格式化函數
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    init() {
        self._speechRecognizer = StateObject(wrappedValue: SpeechRecognizer())
    }
    
    var body: some View {
        ZStack {
            // 背景
            Color.black
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                Spacer()
                
                // 標題和說明文字
                VStack(spacing: 20) {
                    Text("影聲")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("Please put the magic key on top of the screen, near the speaker")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .padding(.bottom, 80)
                
                Spacer()
                
                // START 按鈕
                Button(action: {
                    showContentPage = true
                }) {
                    ZStack {
                        // 外圈光暈效果
                        Circle()
                            .fill(Color.clear)
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.3), lineWidth: 2)
                            )
                            .frame(width: 140, height: 140)
                        
                        // 主按鈕
                        Circle()
                            .fill(Color.white)
                            .frame(width: 120, height: 120)
                            .shadow(color: .white.opacity(0.3), radius: 0, x: 0, y: 4)
                        
                        // START 文字
                        Text("START")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.black)
                    }
                }
                .padding(.bottom, 20)
                
                // 語音識別按鈕 - Press to Talk
                Button(action: {
                    // Empty action, using gestures instead
                }) {
                    HStack {
                        Image(systemName: speechRecognizer.isRecognizing ? "mic.fill" : "mic")
                            .font(.system(size: 20))
                        Text(speechRecognizer.isRecognizing ? "識別中..." : "按住講話")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(speechRecognizer.isRecognizing ? Color.red : (isPressingButton ? Color.blue : Color.gray))
                    .cornerRadius(25)
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            isPressingButton = true
                            if !speechRecognizer.isRecognizing {
                                startSpeechRecognition()
                            }
                        }
                        .onEnded { _ in
                            isPressingButton = false
                            if speechRecognizer.isRecognizing {
                                stopSpeechRecognition()
                            }
                        }
                )
                
                // 語音識別結果
                if !speechRecognizer.recognizedText.isEmpty {
                    VStack(spacing: 8) {
                        Text("識別結果:")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                        
                        Text(speechRecognizer.recognizedText)
                            .font(.body)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(8)
                    }
                    .padding(.top, 8)
                }
                
                // 發送狀態
                if speechRecognizer.webService.isSending {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("發送中...")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    .padding(.top, 4)
                }
                
                // 發送成功提示
                if speechRecognizer.lastSentText != nil {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                        Text("已發送")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    .padding(.top, 2)
                }
                
                // 錯誤信息
                if let error = speechRecognizer.error {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.top, 4)
                }
                
                // WebSocket 連接狀態
                HStack {
                    Circle()
                        .fill(speechRecognizer.isWebSocketConnected ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(speechRecognizer.isWebSocketConnected ? "WebSocket 已連接" : "WebSocket 未連接")
                        .font(.caption)
                        .foregroundColor(speechRecognizer.isWebSocketConnected ? Color.green : Color.red)
                }
                .padding(.top, 2)
                
                // 服務器錯誤
                if let serverError = speechRecognizer.webService.lastError {
                    Text("服務器: \(serverError)")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .padding(.top, 2)
                }
                
                // AI 回應區域
                if !speechRecognizer.llmResponse.isEmpty {
                    VStack(spacing: 12) {
                        // AI 回應標題
                        HStack {
                            Image(systemName: "brain.head.profile")
                                .foregroundColor(.blue)
                                .font(.caption)
                            Text("Gemini AI 回應")
                                .font(.headline)
                                .foregroundColor(.white)
                            Spacer()
                            if let timestamp = speechRecognizer.responseTimestamp {
                                Text(formatTime(timestamp))
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }
                        .padding(.horizontal, 4)
                        
                        // 原始文本（如果有）
                        if !speechRecognizer.originalText.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("你講咗:")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.7))
                                Text(speechRecognizer.originalText)
                                    .font(.body)
                                    .foregroundColor(.white)
                                    .multilineTextAlignment(.leading)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.gray.opacity(0.2))
                                    .cornerRadius(8)
                            }
                        }
                        
                        // AI 回應內容
                        ScrollView {
                            Text(speechRecognizer.llmResponse)
                                .font(.body)
                                .foregroundColor(.white)
                                .multilineTextAlignment(.leading)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color.blue.opacity(0.3),
                                            Color.purple.opacity(0.2)
                                        ]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.blue.opacity(0.5), lineWidth: 1)
                                )
                        }
                        .frame(maxHeight: 200)
                        .shadow(color: .blue.opacity(0.3), radius: 4, x: 0, y: 2)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                }
                
                Spacer()
                
                // 服務器功能按鈕
                HStack(spacing: 15) {
                    Button(action: {
                        speechRecognizer.webService.sendPing()
                    }) {
                        HStack {
                            Image(systemName: "waveform.path")
                                .font(.caption)
                            Text("Ping")
                                .font(.caption)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.gray.opacity(0.3))
                        .cornerRadius(12)
                    }
                    
                    Button(action: {
                        speechRecognizer.webService.clearHistory()
                    }) {
                        HStack {
                            Image(systemName: "trash")
                                .font(.caption)
                            Text("清除")
                                .font(.caption)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.red.opacity(0.3))
                        .cornerRadius(12)
                    }
                    
                    Button(action: {
                        speechRecognizer.webService.getHistory()
                    }) {
                        HStack {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.caption)
                            Text("歷史")
                                .font(.caption)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.3))
                        .cornerRadius(12)
                    }
                }
                .padding(.bottom, 10)
                
                // 底部提示
                Text("Tap START to begin NFC reading")
                    .font(.system(size: 14, weight: .regular))
                     .foregroundColor(.white.opacity(0.6))
                    .padding(.bottom, 30)
            }
        }
        .fullScreenCover(isPresented: $showContentPage) {
            ContentView()
        }
        .alert("語音識別權限", isPresented: $showSpeechPermissionAlert) {
            Button("確定", role: .cancel) { }
        } message: {
            Text("請到「設定」>「隱私權與安全性」>「語音識別」中允許此應用程式存取語音識別功能")
        }
                .onDisappear {
            // 停止語音識別
            speechRecognizer.stopRecording()
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
}

#Preview {
    LandingPageView()
}
