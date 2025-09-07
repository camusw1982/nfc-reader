//
//  EntryView.swift
//  Frypan NFC Reader
//
//  Created by Claude on 7/9/2025.
//

import SwiftUI

struct EntryView: View {
    @State private var selectedCharacter: Int? = nil
    @State private var navigateToLanding = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                // 背景
                Color(red: 0.15, green: 0.15, blue: 0.15)
                    .ignoresSafeArea()
                
                VStack(spacing: 40) {
                    // 標題
                    Text("選擇人物")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.top, 60)
                    
                    // 人物選擇區域
                    HStack(spacing: 30) {
                        // 人物1
                        CharacterCircle(
                            name: "人物1",
                            characterId: 1,
                            selectedCharacter: $selectedCharacter
                        )
                        
                        // 人物2
                        CharacterCircle(
                            name: "人物2", 
                            characterId: 2,
                            selectedCharacter: $selectedCharacter
                        )
                        
                        // 人物3
                        CharacterCircle(
                            name: "人物3",
                            characterId: 3,
                            selectedCharacter: $selectedCharacter
                        )
                    }
                    .padding(.horizontal, 20)
                    
                    Spacer()
                    
                    // 確認按鈕
                    Button(action: {
                        if let characterId = selectedCharacter {
                            print("✅ 確認選擇人物 ID: \(characterId)")
                            // 設置選擇的人物到 WebSocketManager
                            WebSocketManager.shared.setCharacterId(characterId)
                            print("📡 已發送人物 ID 到 WebSocketManager")
                            navigateToLanding = true
                        }
                    }) {
                        Text("確認")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 120, height: 50)
                            .background(
                                RoundedRectangle(cornerRadius: 25)
                                    .fill(selectedCharacter != nil ? Color.blue : Color.gray)
                            )
                    }
                    .disabled(selectedCharacter == nil)
                    .padding(.bottom, 50)
                }
            }
            .navigationDestination(isPresented: $navigateToLanding) {
                LandingPageView()
                    .navigationBarBackButtonHidden(false)
            }
        }
    }
}

struct CharacterCircle: View {
    let name: String
    let characterId: Int
    @Binding var selectedCharacter: Int?
    
    var body: some View {
        VStack(spacing: 15) {
            // 圓形按鈕
            Button(action: {
                print("🎯 點擊了人物: \(name) (ID: \(characterId))")
                selectedCharacter = characterId
            }) {
                ZStack {
                    Circle()
                        .fill(selectedCharacter == characterId ? Color.blue : Color.gray.opacity(0.3))
                        .frame(width: 100, height: 100)
                    
                    // 人物圖標 (使用 SF Symbols)
                    Image(systemName: "person.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.white)
                }
            }
            .scaleEffect(selectedCharacter == characterId ? 1.1 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: selectedCharacter)
            
            // 人物名稱
            Text(name)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
        }
    }
}

#Preview {
    EntryView()
}