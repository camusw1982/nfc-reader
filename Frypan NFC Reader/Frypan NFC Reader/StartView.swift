//
//  StartView.swift
//  Frypan NFC Reader
//
//  Created by Claude on 4/9/2025.
//

import SwiftUI

struct StartView: View {
    @State private var isAnimating = false
    
    var body: some View {
        ZStack {
            // 背景
            Color(red: 0.11, green: 0.11, blue: 0.11)
                .ignoresSafeArea()
            
            VStack {
                Spacer()
                
                // 主要文字
                Text("唸緊咒，請稍等，請緊佢黎...")
                    .font(.custom("SF Pro", size: 20))
                    .fontWeight(.semibold)
                    .foregroundColor(Color(red: 0.46, green: 0.46, blue: 0.46))
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 100)
                
                Spacer()
                
                // 圓形文字排列
                ZStack {
                    CircularTextView(
                        text: "請把時光之匙放在圈中。",
                        radius: 167,
                        fontSize: 16
                    )
                    
                    // 光圈效果
                    LightCircleView()
                        .frame(width: 250, height: 250)
                        .offset(y: -52)
                }
                .frame(width: 334, height: 334)
                .padding(.leading, 16)
                
                Spacer()
            }
        }
        .onAppear {
            withAnimation(Animation.linear(duration: 20).repeatForever(autoreverses: false)) {
                isAnimating = true
            }
        }
    }
}

struct CircularTextView: View {
    let text: String
    let radius: CGFloat
    let fontSize: CGFloat
    
    var body: some View {
        ZStack {
            ForEach(Array(text.enumerated()), id: \.offset) { index, character in
                Text(String(character))
                    .font(.custom("SF Pro", size: fontSize))
                    .fontWeight(.regular)
                    .foregroundColor(.white)
                    .rotationEffect(.degrees(Double(index) * (360.0 / Double(text.count))))
                    .offset(y: -radius)
            }
        }
        .rotationEffect(.degrees(-90))
    }
}

struct LightCircleView: View {
    @State private var pulseAnimation = false
    
    var body: some View {
        ZStack {
            // 外圈光暈
            Circle()
                .fill(Color.clear)
                .overlay(
                    Circle()
                        .stroke(Color(red: 0.85, green: 0.60, blue: 0.16), lineWidth: 2)
                        .opacity(pulseAnimation ? 0.3 : 0.8)
                )
                .frame(width: 100, height: 100)
            
            // 內圈光暈
            Circle()
                .fill(Color.clear)
                .overlay(
                    Circle()
                        .stroke(Color(red: 0.85, green: 0.60, blue: 0.16), lineWidth: 1)
                        .opacity(pulseAnimation ? 0.5 : 1.0)
                )
                .frame(width: 60, height: 60)
            
            // 中心光點
            Circle()
                .fill(Color(red: 0.85, green: 0.60, blue: 0.16))
                .frame(width: 8, height: 8)
                .opacity(pulseAnimation ? 0.6 : 1.0)
        }
        .onAppear {
            withAnimation(Animation.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                pulseAnimation = true
            }
        }
    }
}

#Preview {
    StartView()
}