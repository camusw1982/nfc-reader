//
//  UIComponents.swift
//  Frypan NFC Reader
//
//  Created by Claude on 5/9/2025.
//

import SwiftUI
import Foundation

// MARK: - Header View
struct HeaderView: View {
    let webSocketManager: WebSocketManager?
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("影聲")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                
                Spacer()
                
                // WebSocket 狀態指示器
                if let webSocketManager = webSocketManager {
                    ConnectionStatusView(webSocketManager: webSocketManager)
                } else {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                        Text("未連接")
                            .font(.caption)
                            .foregroundColor(Color.red)
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
    }
}

// MARK: - Connection Status View
struct ConnectionStatusView: View {
    @ObservedObject var webSocketManager: WebSocketManager
    
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(webSocketManager.isConnected ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text(webSocketManager.connectionStatus)
                .font(.caption)
                .foregroundColor(webSocketManager.isConnected ? Color.green : Color.red)
            if !webSocketManager.connectionId.isEmpty {
                Text("(\(webSocketManager.connectionId))")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
            }
        }
    }
}

// MARK: - Bottom Toolbar View
struct BottomToolbarView: View {
    let webSocketManager: WebSocketManager?
    let onClearChat: () -> Void
    let onShowMiniMax: () -> Void
    
    var body: some View {
        HStack(spacing: 20) {
            Button(action: onClearChat) {
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
                webSocketManager?.clearHistory()
            }) {
                Image(systemName: "clock.badge.xmark")
                    .font(.system(size: 18))
                    .foregroundColor(.white.opacity(0.7))
            }
            
            Button(action: {
                // 停止所有音頻播放
                webSocketManager?.stopAudio()  // 停止 AudioStreamManager 音頻
                webSocketManager?.stopSpeech() // 停止 MiniMax 語音合成
            }) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 18))
                    .foregroundColor(webSocketManager?.isPlayingAudio == true ? Color.red : Color.white.opacity(0.5))
            }
            
            // Button(action: onShowMiniMax) {
            //    Image(systemName: "waveform")
            //        .font(.system(size: 18))
            //        .foregroundColor(.blue)
            // }
            
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }
}

// MARK: - Error Message View
struct ErrorMessageView: View {
    let error: String?
    
    var body: some View {
        if let error = error {
            Text(error)
                .font(.caption)
                .foregroundColor(.red)
                .padding(.bottom, 8)
        }
    }
}

// MARK: - Permission Alert
struct PermissionAlert: ViewModifier {
    @Binding var isPresented: Bool
    
    func body(content: Content) -> some View {
        content
            .alert("語音識別權限", isPresented: $isPresented) {
                Button("確定", role: .cancel) { }
            } message: {
                Text("請到「設定」>「隱私權與安全性」>「語音識別」中允許此應用程式存取語音識別功能")
            }
    }
}

extension View {
    func speechPermissionAlert(isPresented: Binding<Bool>) -> some View {
        self.modifier(PermissionAlert(isPresented: isPresented))
    }
}
