//
//  ChatComponents.swift
//  Frypan NFC Reader
//
//  Created by Claude on 5/9/2025.
//

import SwiftUI

// MARK: - Notification Names
extension Notification.Name {
    static let scrollToBottom = Notification.Name("scrollToBottom")
}

// MARK: - Chat Message Model
struct ChatMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let text: String
    let isUser: Bool
    let timestamp: Date
    let isError: Bool
    let isLoading: Bool

    init(text: String, isUser: Bool, timestamp: Date = Date(), isError: Bool = false, isLoading: Bool = false) {
        self.id = UUID()
        self.text = text
        self.isUser = isUser
        self.timestamp = timestamp
        self.isError = isError
        self.isLoading = isLoading
    }

    // Equatable 實現 - 基於 ID 判斷相等性
    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - Loading Animation View
struct LoadingAnimationView: View {
    @State private var animationScale: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.gray.opacity(0.7))
                    .frame(width: 8, height: 8)
                    .scaleEffect(animationScale ? 0.6 : 1)
                    .animation(
                        Animation.easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.2),
                        value: animationScale
                    )
            }
        }
        .onAppear {
            animationScale = true
        }
    }
}

// MARK: - Chat Bubble View
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

// MARK: - User Bubble (Right Side)
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
                            gradient: Gradient(colors: [Color.blue.opacity(0.8), Color.blue.opacity(0.6)]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(20)
                    .shadow(color: .black.opacity(0.3), radius: 2, x: 2, y: 2)
            }
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - AI Bubble (Left Side)
struct AIBubbleView: View {
    let message: ChatMessage
    @StateObject private var httpManager = HTTPManager.shared
    @State private var isAnimating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "brain.head.profile")
                    .font(.caption)
                    .foregroundColor(.blue)
                Text(httpManager.characterName)
                    .font(.caption)
                    .foregroundColor(.blue)
                Text(formatTime(message.timestamp))
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
            }

            HStack {
                if message.isLoading {
                    // Loading 動畫
                    LoadingAnimationView()
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
                        .shadow(color: .black.opacity(0.3), radius: 2, x: 2, y: 2)
                } else {
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
                        .shadow(color: .black.opacity(0.3), radius: 2, x: 2, y: 2)
                }
            }
        }
        .onAppear {
            // 當消息從 loading 變為正常狀態時，觸發滾動
            if !message.isLoading {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    NotificationCenter.default.post(name: .scrollToBottom, object: message.id)
                }
            }
        }
        .onChange(of: message.isLoading) { _, isLoading in
            // 當 isLoading 從 true 變為 false 時，觸發滾動
            if !isLoading {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    NotificationCenter.default.post(name: .scrollToBottom, object: message.id)
                }
            }
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Chat List View
struct ChatListView: View {
    let messages: [ChatMessage]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(messages) { message in
                        ChatBubbleView(message: message)
                            .id(message.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .onChange(of: messages) { oldMessages, newMessages in
                // 自動滾動到最新消息
                if let lastMessage = newMessages.last {
                    // 添加小延遲確保 UI 更新完成
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .scrollToBottom)) { notification in
                // 處理滾動通知
                if let messageId = notification.object as? UUID {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(messageId, anchor: .bottom)
                    }
                }
            }
            .onAppear {
                // 初始滾動到底部
                if let lastMessage = messages.last {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2秒
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 140) // 為底部按鈕留出空間
        .clipped() // 確保內容不會洩漏到 padding 區域
    }
}
