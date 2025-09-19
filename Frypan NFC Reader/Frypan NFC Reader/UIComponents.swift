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
    @ObservedObject private var httpManager: HTTPManager
    
    init(httpManager: HTTPManager?) {
        self.httpManager = httpManager ?? HTTPManager.shared
    }
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("影聲")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text(getCharacterName())
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                }
                
                Spacer()
                
                // HTTP 狀態指示器
                ConnectionStatusView(httpManager: httpManager)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 10)
    }
    
    private func getCharacterName() -> String {
        return httpManager.characterName
    }
}

// MARK: - Connection Status View
struct ConnectionStatusView: View {
    @ObservedObject var httpManager: HTTPManager
    
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(httpManager.isConnected ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text(httpManager.connectionStatus)
                .font(.caption)
                .foregroundColor(httpManager.isConnected ? Color.green : Color.red)
            //if !httpManager.connectionId.isEmpty {
            //    Text("(\(httpManager.connectionId))")
            //        .font(.caption2)
            //        .foregroundColor(.white.opacity(0.6))
            //}
        }
    }
}

// MARK: - Bottom Toolbar View
struct BottomToolbarView: View {
    @ObservedObject private var httpManager: HTTPManager
    let onClearChat: () -> Void
    
    init(httpManager: HTTPManager?, onClearChat: @escaping () -> Void) {
        self.httpManager = httpManager ?? HTTPManager.shared
        self.onClearChat = onClearChat
    }
    
    var body: some View {
        HStack(spacing: 20) {
            Button(action: onClearChat) {
                Image(systemName: "trash")
                    .font(.system(size: 18))
                    .foregroundColor(.white.opacity(0.7))
            }
            
            Button(action: {
                if httpManager.isConnected {
                    httpManager.disconnect()
                } else {
                    httpManager.connect()
                }
            }) {
                Image(systemName: httpManager.isConnected ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                    .font(.system(size: 18))
                    .foregroundColor(httpManager.isConnected ? Color.green : Color.white.opacity(0.7))
            }
            
            /*Button(action: {
                httpManager.clearHistory()
            }) {
                Image(systemName: "clock.badge.xmark")
                    .font(.system(size: 18))
                    .foregroundColor(.white.opacity(0.7))
            }*/
            
            Button(action: {
                // 停止所有音頻播放
                httpManager.stopAudio()  // 停止所有音頻播放
            }) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 18))
                    .foregroundColor(httpManager.isPlayingAudio ? Color.red : Color.white.opacity(0.5))
            }
            
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
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
                .padding(.bottom, 10)
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
