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
    let onStartRecording: () -> Void
    let onStopRecording: () -> Void
    let onCancelRecording: () -> Void
    let onConfirmRecording: () -> Void
    
    var body: some View {
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
                            .scaleEffect(voiceManager.pulseAnimation ? 1.4 : 1.0)
                            .opacity(voiceManager.pulseAnimation ? 0.2 : 0.8)
                            .animation(
                                Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true),
                                value: voiceManager.pulseAnimation
                            )
                    )
                    .frame(width: 100, height: 100)
                
                // 主按鈕
                Circle()
                    .fill(voiceManager.isPressingTalkButton ? 
                          (voiceManager.slideOffset < -50 ? Color.red : 
                           voiceManager.slideOffset > 50 ? Color.green : Color.orange) : Color.blue)
                    .frame(width: 80, height: 80)
                    .shadow(color: voiceManager.isPressingTalkButton ? 
                            (voiceManager.slideOffset < -50 ? Color.red.opacity(0.5) : 
                             voiceManager.slideOffset > 50 ? Color.green.opacity(0.5) : Color.orange.opacity(0.3)) : 
                            Color.blue.opacity(0.3), radius: 0, x: 0, y: 4)
                    .animation(.easeInOut(duration: 0.2), value: voiceManager.slideOffset)
                    .animation(.easeInOut(duration: 0.2), value: voiceManager.isPressingTalkButton)
                
                // 麥克風圖標
                Image(systemName: speechRecognizer.isRecognizing ? "mic.fill" : "mic")
                    .font(.system(size: 28, weight: .semibold))
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
            voiceManager.currentSlideAction = .none
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
                    voiceManager.resetRecordingState()
                }
            case .confirm:
                print("✅ 手指離開確認區域，確認錄音")
                onConfirmRecording()
                // 確認操作後重置狀態
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    voiceManager.resetRecordingState()
                }
            case .none:
                print("⚠️ 手指離開中性區域，視為取消")
                onStopRecording()
                // 延遲重置所有狀態
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    voiceManager.resetRecordingState()
                }
            }
        } else {
            print("⚠️ 手指離開，currentSlideAction 為 nil，視為取消")
            onStopRecording()
            // 延遲重置所有狀態
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                voiceManager.resetRecordingState()
            }
        }
        
        // 立即隱藏滑動控制
        withAnimation(.easeInOut(duration: 0.2)) {
            voiceManager.showSlideControls = false
            voiceManager.slideOffset = 0
            voiceManager.currentSlideAction = .none
        }
    }
}

// MARK: - Slide Controls View
struct SlideControlsView: View {
    @ObservedObject var voiceManager: VoiceControlManager
    
    var body: some View {
        if voiceManager.showSlideControls {
            HStack(spacing: 40) {
                // 取消按鈕
                Circle()
                    .fill(voiceManager.slideOffset < -50 ? Color.red.opacity(0.8) : Color.red.opacity(0.3))
                    .frame(width: 60, height: 60)
                    .overlay(
                        Image(systemName: "xmark")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                            .scaleEffect(voiceManager.slideOffset < -50 ? 1.2 : 1.0)
                    )
                    .animation(.easeInOut(duration: 0.2), value: voiceManager.slideOffset)
                
                // 確認按鈕
                Circle()
                    .fill(voiceManager.slideOffset > 50 ? Color.green.opacity(0.8) : Color.green.opacity(0.3))
                    .frame(width: 60, height: 60)
                    .overlay(
                        Image(systemName: "checkmark")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                            .scaleEffect(voiceManager.slideOffset > 50 ? 1.2 : 1.0)
                    )
                    .animation(.easeInOut(duration: 0.2), value: voiceManager.slideOffset)
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
