//
//  VoiceControlComponents.swift
//  Frypan NFC Reader
//
//  Created by Claude on 5/9/2025.
//

import SwiftUI
import AVFoundation

// MARK: - Talk Button View
struct TalkButtonView: View {
    @ObservedObject var voiceManager: VoiceControlManager
    @ObservedObject var speechRecognizer: SpeechRecognizer
    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0.6
    let onStartRecording: () -> Void
    let onStopRecording: () -> Void
    let onCancelRecording: () -> Void
    let onConfirmRecording: () -> Void
    
    var body: some View {
        Button(action: {
            // Empty action, using gestures instead
        }) {
            ZStack {
                // 外圈脈衝動畫 - 持續顯示以吸引用戶
                Circle()
                    .stroke(Color.blue.opacity(0.6), lineWidth: 3)
                    .scaleEffect(pulseScale)
                    .opacity(pulseOpacity)
                    .frame(width: 110, height: 110)
                    .animation(
                        .easeInOut(duration: 1.1).repeatForever(autoreverses: true),
                        value: pulseScale
                    )
                
                // 主按鈕
                Circle()
                    .fill(voiceManager.isPressingTalkButton ? 
                          (voiceManager.slideOffset < -50 ? Color.red : 
                            voiceManager.slideOffset > 50 ? Color.green : Color.gray) : Color.blue.opacity(0.6))
                    .frame(width: 90, height: 90)
                    .animation(.easeInOut(duration: 0.1), value: voiceManager.slideOffset)
                    .animation(.easeInOut(duration: 0.1), value: voiceManager.isPressingTalkButton)
                
                // 麥克風圖標
                Image(systemName: speechRecognizer.isRecognizing ? "microphone.badge.ellipsis.fill" : "microphone.fill")
                    .font(.system(size: 50, weight: .regular))
                    .foregroundColor(.white)
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    handleDragChanged(value)
                }
                .onEnded { value in
                    handleDragEnded(value)
                }
        )
        .onAppear {
            // 啟動脈衝動畫
            startPulseAnimation()
        }
    }
    
    private func startPulseAnimation() {
        // 設置脈衝動畫目標值
        pulseScale = 1.3
        pulseOpacity = 0.2
    }
    
    private func handleDragChanged(_ value: DragGesture.Value) {
        // 確保初始化完成
        guard voiceManager.isInitialized else {
            print("⚠️ 按壓說話功能尚未初始化完成")
            return
        }
        
        voiceManager.isPressingTalkButton = true
        
        if !speechRecognizer.isRecognizing {
            print("🎤 開始語音識別")
            // 清空之前的識別文本
            speechRecognizer.recognizedText = ""
            onStartRecording()
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.3)) {
                    voiceManager.showSlideControls = true
                }
            }
        } else if !voiceManager.showSlideControls {
            // 如果已經在錄音但控件沒顯示，確保顯示
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.3)) {
                    voiceManager.showSlideControls = true
                }
            }
        }
        
        // 計算滑動偏移，限制最大滑動距離
        voiceManager.slideOffset = max(-100, min(100, value.translation.width))
        
        // 更新當前滑動操作狀態，但不立即執行
        if voiceManager.slideOffset < -50 {
            voiceManager.currentSlideAction = .cancel
        } else if voiceManager.slideOffset > 50 {
            voiceManager.currentSlideAction = .confirm
        } else {
            voiceManager.currentSlideAction = VoiceControlManager.SlideAction.none
        }
    }
    
    private func handleDragEnded(_ value: DragGesture.Value) {
        voiceManager.isPressingTalkButton = false
        
        // 根據手指離開時的位置決定操作
        if let action = voiceManager.currentSlideAction {
            switch action {
            case .cancel:
                print("🚫 手指離開取消區域，取消錄音")
                onCancelRecording()
                // 取消操作後重置狀態
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    voiceManager.resetRecordingState(speechRecognizer: speechRecognizer)
                }
            case .confirm:
                print("✅ 手指離開確認區域，確認錄音")
                onConfirmRecording()
                // 確認操作後重置狀態
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    voiceManager.resetRecordingState(speechRecognizer: speechRecognizer)
                }
            case .none:
                print("⚠️ 手指離開中性區域，視為取消")
                onStopRecording()
                // 延遲重置所有狀態
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    voiceManager.resetRecordingState(speechRecognizer: speechRecognizer)
                }
            }
        } else {
            print("⚠️ 手指離開，currentSlideAction 為 nil，視為取消")
            onStopRecording()
            // 延遲重置所有狀態
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                voiceManager.resetRecordingState(speechRecognizer: speechRecognizer)
            }
        }
        
        // 立即隱藏滑動控制
        withAnimation(.easeInOut(duration: 0.2)) {
            voiceManager.showSlideControls = false
            voiceManager.slideOffset = 0
            voiceManager.currentSlideAction = VoiceControlManager.SlideAction.none
        }
    }
}

// MARK: - Slide Controls View
struct SlideControlsView: View {
    @ObservedObject var voiceManager: VoiceControlManager
    
    var body: some View {
        if voiceManager.showSlideControls {
            HStack(spacing: 110) {
                // 取消按鈕
                Circle()
                    .fill(voiceManager.slideOffset < -50 ? Color.red.opacity(0.8) : Color.red.opacity(0.3))
                    .frame(width: 80, height: 80)
                    .overlay(
                        Image(systemName: "xmark")
                            .font(.system(size: 33, weight: .bold))
                            .foregroundColor(.white)
                            .scaleEffect(voiceManager.slideOffset < -50 ? 1.2 : 1.0)
                    )
                    .animation(.easeInOut(duration: 0.2), value: voiceManager.slideOffset)
                
                // 確認按鈕
                Circle()
                    .fill(voiceManager.slideOffset > 50 ? Color.green.opacity(0.8) : Color.green.opacity(0.3))
                    .frame(width: 80, height: 80)
                    .overlay(
                        Image(systemName: "checkmark")
                            .font(.system(size: 33, weight: .bold))
                            .foregroundColor(.white)
                            .scaleEffect(voiceManager.slideOffset > 50 ? 1.2 : 1.0)
                    )
                    .animation(.easeInOut(duration: 0.3), value: voiceManager.slideOffset)
            }
            .padding(.horizontal, 20)
            .transition(.asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity),
                removal: .move(edge: .bottom).combined(with: .opacity)
            ))
            .animation(.easeInOut(duration: 0.3), value: voiceManager.showSlideControls)
        }
    }
}

// MARK: - Speech Recognition Status View
struct SpeechRecognitionStatusView: View {
    @ObservedObject var speechRecognizer: SpeechRecognizer
    @ObservedObject var voiceManager: VoiceControlManager
    
    var body: some View {
        if !speechRecognizer.recognizedText.isEmpty && speechRecognizer.isRecognizing && voiceManager.isPressingTalkButton {
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
    }
}
