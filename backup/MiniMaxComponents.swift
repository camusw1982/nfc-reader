//
//  MiniMaxComponents.swift
//  Frypan NFC Reader
//
//  Created by Claude on 5/9/2025.
//

import SwiftUI

// MARK: - MiniMax Connection Status View
struct MiniMaxConnectionStatusView: View {
    @ObservedObject var miniMaxManager: MiniMaxManager
    
    var body: some View {
        HStack {
            // 連接狀態指示器
            Circle()
                .fill(miniMaxManager.isConnected ? Color.green : Color.red)
                .frame(width: 12, height: 12)
                .animation(.easeInOut(duration: 0.3), value: miniMaxManager.isConnected)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("MiniMax 連接")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(miniMaxManager.connectionStatus)
                    .font(.caption2)
                    .foregroundColor(miniMaxManager.isConnected ? .green : .red)
            }
            
            Spacer()
            
            // 連接/斷開按鈕
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
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - MiniMax Text Input View
struct MiniMaxTextInputView: View {
    @ObservedObject var miniMaxManager: MiniMaxManager
    @State private var inputText: String = ""
    @State private var isExpanded: Bool = false
    
    var body: some View {
        VStack(spacing: 12) {
            // 標題
            HStack {
                Text("MiniMax 語音合成")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isExpanded.toggle()
                    }
                }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
            }
            
            if isExpanded {
                VStack(spacing: 12) {
                    // 文本輸入框
                    VStack(alignment: .leading, spacing: 8) {
                        Text("輸入要轉換為語音的文本")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
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
                    
                    // 操作按鈕
                    HStack(spacing: 12) {
                        // 生成語音按鈕
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
                        
                        // 停止生成按鈕
                        if miniMaxManager.isGenerating {
                            Button(action: {
                                miniMaxManager.stopGeneration()
                            }) {
                                HStack {
                                    Image(systemName: "stop.fill")
                                    Text("停止")
                                }
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.red)
                                .cornerRadius(8)
                            }
                        }
                        
                        Spacer()
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

// MARK: - MiniMax Audio Player View
struct MiniMaxAudioPlayerView: View {
    @ObservedObject var miniMaxManager: MiniMaxManager
    @State private var isExpanded: Bool = false
    
    var body: some View {
        VStack(spacing: 12) {
            // 標題
            HStack {
                Text("音頻播放器")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isExpanded.toggle()
                    }
                }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
            }
            
            if isExpanded {
                VStack(spacing: 12) {
                    // 播放狀態
                    HStack {
                        // 播放狀態指示器
                        Circle()
                            .fill(miniMaxManager.isPlaying ? Color.green : Color.gray)
                            .frame(width: 12, height: 12)
                            .animation(.easeInOut(duration: 0.3), value: miniMaxManager.isPlaying)
                        
                        Text(miniMaxManager.isPlaying ? "正在播放" : "已停止")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        // 音頻信息
                        if miniMaxManager.audioDuration > 0 {
                            Text("\(miniMaxManager.getFormattedCurrentTime()) / \(miniMaxManager.getFormattedDuration())")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // 進度條
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
                    }
                    
                    // 播放控制按鈕
                    HStack(spacing: 20) {
                        // 停止按鈕
                        Button(action: {
                            miniMaxManager.stopAudio()
                        }) {
                            Image(systemName: "stop.fill")
                                .font(.title2)
                                .foregroundColor(.red)
                        }
                        .disabled(!miniMaxManager.isPlaying)
                        
                        // 播放/暫停按鈕
                        Button(action: {
                            if miniMaxManager.isPlaying {
                                miniMaxManager.pauseAudio()
                            } else {
                                miniMaxManager.playAudio()
                            }
                        }) {
                            Image(systemName: miniMaxManager.isPlaying ? "pause.fill" : "play.fill")
                                .font(.title)
                                .foregroundColor(.blue)
                        }
                        .disabled(miniMaxManager.audioDuration == 0)
                        
                        // 音頻信息
                        VStack(alignment: .leading, spacing: 2) {
                            Text("狀態: \(miniMaxManager.isGenerating ? "生成中" : "就緒")")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            Text("連接: \(miniMaxManager.isConnected ? "已連接" : "未連接")")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
    
    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

// MARK: - MiniMax Error View
struct MiniMaxErrorView: View {
    let error: String
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                
                Text("MiniMax 錯誤")
                    .font(.headline)
                    .foregroundColor(.red)
                
                Spacer()
                
                Button(action: {
                    isPresented = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
            }
            
            Text(error)
                .font(.body)
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
            
            Button(action: {
                isPresented = false
            }) {
                Text("確定")
                    .font(.body)
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(Color.blue)
                    .cornerRadius(8)
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
    }
}

// MARK: - MiniMax Main View
struct MiniMaxMainView: View {
    @StateObject private var miniMaxManager: MiniMaxManager
    @State private var showError: Bool = false
    
    init(apiKey: String) {
        self._miniMaxManager = StateObject(wrappedValue: MiniMaxManager(apiKey: apiKey))
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // 連接狀態
            MiniMaxConnectionStatusView(miniMaxManager: miniMaxManager)
            
            // 文本輸入
            MiniMaxTextInputView(miniMaxManager: miniMaxManager)
            
            // 音頻播放器
            MiniMaxAudioPlayerView(miniMaxManager: miniMaxManager)
            
            Spacer()
        }
        .padding()
        .onChange(of: miniMaxManager.lastError) { _, newError in
            if newError != nil {
                showError = true
            }
        }
        .alert("MiniMax 錯誤", isPresented: $showError) {
            Button("確定") {
                miniMaxManager.lastError = nil
            }
        } message: {
            if let error = miniMaxManager.lastError {
                Text(error)
            }
        }
    }
}

// MARK: - Preview
struct MiniMaxComponents_Previews: PreviewProvider {
    static var previews: some View {
        MiniMaxMainView(apiKey: "test-api-key")
            .previewLayout(.sizeThatFits)
    }
}
