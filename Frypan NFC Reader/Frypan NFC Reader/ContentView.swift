//
//  ContentView.swift
//  Frypan NFC Reader
//
//  Created by Wong Chi Man on 3/9/2025.
//

import SwiftUI
import CoreNFC

struct ContentView: View {
    @StateObject private var nfcManager = NFCManager()
    @Environment(\.dismiss) private var dismiss
    @State private var hasStartedReading = false
    
    var body: some View {
        ZStack {
            // 背景
            Color(red: 0.15, green: 0.15, blue: 0.15)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // 頂部導航欄
                HStack {
                    Button(action: {
                        dismiss()
                    }) {
                        HStack {
                            Image(systemName: "arrow.left")
                                .font(.system(size: 18, weight: .semibold))
                            Text("Back")
                                .font(.system(size: 18, weight: .semibold))
                        }
                        .foregroundColor(.white)
                    }
                    
                    Spacer()
                    
                    Text("NFC Reader")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    // 佔位符保持對稱
                    HStack {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 18, weight: .semibold))
                            .opacity(0)
                        Text("Back")
                            .font(.system(size: 18, weight: .semibold))
                            .opacity(0)
                    }
                    .foregroundColor(.white)
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                
                Spacer()
                
                // NFC 讀取狀態顯示
                VStack(spacing: 20) {
                    if !hasStartedReading {
                        // 等待開始讀取的界面
                        VStack(spacing: 20) {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.system(size: 60))
                                .foregroundColor(.white.opacity(0.6))
                            
                            Text("Ready to read NFC")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                            
                            Text("Please place your NFC tag near the top of the device")
                                .font(.body)
                                .foregroundColor(.white.opacity(0.8))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                        }
                    } else if nfcManager.isReading {
                        // 正在讀取的界面
                        VStack(spacing: 20) {
                            // 動畫掃描效果
                            ZStack {
                                Circle()
                                    .stroke(Color.white.opacity(0.3), lineWidth: 2)
                                    .frame(width: 100, height: 100)
                                
                                Circle()
                                    .stroke(Color.blue, lineWidth: 3)
                                    .frame(width: 80, height: 80)
                                    .scaleEffect(hasStartedReading ? 1.2 : 1.0)
                                    .opacity(hasStartedReading ? 0.6 : 1.0)
                                    .animation(Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: hasStartedReading)
                                
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                    .font(.system(size: 40))
                                    .foregroundColor(.white)
                            }
                            
                            Text("Reading NFC...")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                            
                            Text(nfcManager.message)
                                .font(.body)
                                .foregroundColor(.white.opacity(0.8))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                        }
                    }
                    
                    Spacer()
                    
                    // NFC 讀取結果顯示
                    if let tagInfo = nfcManager.detectedTag {
                        VStack(spacing: 16) {
                            // 只顯示文本內容
                            if !nfcManager.nfcTextContent.isEmpty {
                                VStack(spacing: 8) {
                                    Text("NFC Message")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    
                                    ScrollView {
                                        Text(nfcManager.nfcTextContent)
                                            .font(.system(.body, design: .monospaced))
                                            .foregroundColor(.white)
                                            .padding()
                                            .background(Color.blue.opacity(0.2))
                                            .cornerRadius(12)
                                    }
                                    .frame(maxHeight: 200)
                                    .padding(.horizontal)
                                }
                            } else {
                                // 如果沒有文本內容，顯示基本標籤信息
                                VStack(spacing: 8) {
                                    Text("NFC Tag Detected")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    
                                    ScrollView {
                                        Text(tagInfo)
                                            .font(.system(.body, design: .monospaced))
                                            .foregroundColor(.white)
                                            .padding()
                                            .background(Color.blue.opacity(0.2))
                                            .cornerRadius(12)
                                    }
                                    .frame(maxHeight: 200)
                                    .padding(.horizontal)
                                }
                            }
                        }
                        .padding(.bottom, 40)
                    }
                    
                    // 設備兼容性提示
                    if !NFCTagReaderSession.readingAvailable {
                        Text("This device does not support NFC")
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(.bottom, 20)
                    }
                }
            }
        }
        .onAppear {
            // 頁面出現時自動開始讀取
            if !hasStartedReading {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    nfcManager.startReading()
                    hasStartedReading = true
                }
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
