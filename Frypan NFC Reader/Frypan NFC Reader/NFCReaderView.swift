//
//  NFCReaderView.swift
//  Frypan NFC Reader
//
//  Created by Claude on 8/9/2025.
//

import SwiftUI
import CoreNFC
import os.log

struct NFCReaderView: View {
    @StateObject private var nfcManager = NFCManager()
    @StateObject private var feishuService = FeishuService()
    @StateObject private var connectionManager = ConnectionManager.shared
    @State private var isPulsing = false
    @State private var showLandingPage = false
    @State private var characterID: String = ""
    @State private var isValidatingID = false
    @State private var validationMessage: String = ""
    @State private var showValidationAlert = false
    @State private var isValidationSuccessful = false
    @State private var httpAPIConnected = false
    @State private var characterData: [String: Any]?
    
    private let logger = Logger(subsystem: "com.frypan.nfc.reader", category: "NFCReaderView")
    private var httpManager: HTTPManager {
        return HTTPManager.shared
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // 背景
                Color(red: 0.00, green: 0.00, blue: 0.00)
                    .ignoresSafeArea()
                BeautifulMechGradient()
                
                VStack(spacing: 0) {
                    // NFC 讀取區域 - 移到頂部對齊 NFC 傳感器
                    ZStack {
                        // 脈衝動畫圓圈
                        Circle()
                            .stroke(Color.blue.opacity(0.8), lineWidth: 1)
                            .frame(width: 290, height: 290)
                            .scaleEffect(isPulsing ? 1.3 : 1.0)
                            .opacity(isPulsing ? 0.0 : 1.0)
                            .animation(
                                Animation.easeInOut(duration: 2.0).repeatForever(autoreverses: true),
                                value: isPulsing
                            )
                        // 主圓圈
                        Circle()
                            .stroke(Color.blue, lineWidth: 2)
                            .frame(width: 300, height: 300)
                            .background(
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            gradient: Gradient(stops: [
                                                .init(color: Color.blue.opacity(0.4), location: 0.0),
                                                .init(color: Color.blue.opacity(0.2), location: 1.0)
                                            ]),
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .frame(width: 300, height: 300)
                            )
                        
                        // 內容
                        VStack(spacing: 10) {
                            // 揚聲器圖標
                            Image(systemName: "wand.and.sparkles.inverse")
                                .font(.system(size: 90))
                                .foregroundColor(.blue)
                            
                            // 放這裡文字
                            Text("放呢度")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white.opacity(0.7))
                        }
                        
                    }
                    .padding(.top, -120)
                    
                    Spacer()
                    
                    // 狀態信息
                    VStack(spacing: 10) {
                        // NFC 讀取狀態
                        if shouldShowWelcomeMessage() {
                            Text(NFCManager.defaultMessage)
                                .font(.system(size: 16))
                                .foregroundColor(.white.opacity(0.4))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                        } else if !nfcManager.message.isEmpty && nfcManager.message != NFCManager.defaultMessage {
                            Text(nfcManager.message)
                                .font(.system(size: 16))
                                .foregroundColor(.white.opacity(0.6))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                        }
                        
                        // ID 驗證狀態
                        if isValidatingID {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .orange))
                                    .scaleEffect(0.8)
                                Text("正在驗證靈魂碎片")
                                    .font(.system(size: 14))
                                    .foregroundColor(.orange)
                            }
                        } else if !validationMessage.isEmpty {
                            Text(validationMessage)
                                .font(.system(size: 14))
                                .foregroundColor(validationMessage.contains("成功") ? .green : .red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                        }
                        
                        // NFC 讀取進度
                        if nfcManager.isReading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                                .scaleEffect(1.2)
                        }
                        
                        // 讀取到的 ID 顯示（隱藏 debug 資訊）
                        //if isValidationSuccessful {
                        //    Text("✅ 成功獲取靈魂，現在施展魔法")
                        //        .font(.system(size: 14, weight: .medium))
                        //        .foregroundColor(.green)
                        //        .padding(.top, 5)
                        //}
                        
                        // HTTP API 連接狀態
                        HStack(spacing: 6) {
                            Circle()
                                .fill(httpAPIConnected ? .green : .red)
                                .frame(width: 8, height: 8)
                            Text(httpAPIConnected ? "已連接" : "無連線")
                                .font(.system(size: 12))
                                .foregroundColor(httpAPIConnected ? .green : .red)
                        }
                        .padding(.top, 30)
                        .padding(.bottom, 25)
                    }
                    
                    // NFC 讀取按鈕
                    Button(action: {
                        startNFCReading()
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "wand.and.rays")
                                .font(.system(size:25))
                            Text("施展魔法")
                                .font(.system(size: 18, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 25)
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(stops: [
                                            .init(color: Color.blue.opacity(0.5), location: 0.0),
                                            .init(color: Color.blue.opacity(0.7), location: 1.0)
                                        ]),
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        )
                    }
                    .padding(.bottom, 20)
                    .disabled(nfcManager.isReading)
                // Logo
                Image("logo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 110)
                    .luminanceToAlpha() // 用亮度做 alpha channel
                    .colorInvert() // 變白色
                    .padding(.bottom, 10)

                    // 即時串流測試按鈕 (AVAudioPlayer)
                    /* NavigationLink(destination: MinimaxStreamTestView()) {
                        HStack(spacing: 6) {
                            Image(systemName: "waveform")
                                .font(.system(size:20))
                            Text("測試即時串流")
                                .font(.system(size: 16, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color.orange)
                                .shadow(color: .orange.opacity(0.3), radius: 5, x: 0, y: 2)
                        )
                    }
                    .padding(.bottom, 10)

                    // 即時串流測試按鈕 (AVAudioEngine)
                    NavigationLink(destination: MinimaxStreamAVEngineView()) {
                        HStack(spacing: 6) {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.system(size:20))
                            Text("測試無縫串流")
                                .font(.system(size: 16, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color.blue)
                                .shadow(color: .blue.opacity(0.3), radius: 5, x: 0, y: 2)
                        )
                    } */
                }
            }
            .onAppear {
                // 每次出現都重新初始化
                initializeNFCReaderView()
            }
            .onDisappear {
                // 停止 NFC 讀取
                nfcManager.stopReading()
            }
            .navigationDestination(isPresented: $showLandingPage) {
                LandingPageView()
                    .navigationBarBackButtonHidden(true)
                    .onAppear {
                        // 將讀取到的 character ID 設置到 HTTPManager
                        if !characterID.isEmpty {
                                HTTPManager.shared.setCharacter_id(Int(characterID) ?? 1)
                        }
                    }
            }
            .onChange(of: nfcManager.nfcTextContent) { _, newValue in
                if !newValue.isEmpty {
                    characterID = newValue
                    
                    // 開始驗證 ID
                    validateCharacterID(characterID)
                }
            }
            .alert("驗證結果", isPresented: $showValidationAlert) {
                Button("確定") { }
            } message: {
                Text(validationMessage)
            }
        }
    }
    
    private func startNFCReading() {
        nfcManager.startReading()
    }

    // MARK: - Connection ID Management (Using ConnectionManager)

    private func getNewConnectionId(characterId: Int, completion: @escaping (String?) -> Void) {
        logger.info("🔗 NFC scan 請求新 connection_id，character_id: \(characterId)")

        Task {
            do {
                let connectionId = try await connectionManager.forceCreateNewConnection(characterId: characterId)
                DispatchQueue.main.async {
                    completion(connectionId)
                }
            } catch {
                logger.error("❌ 獲取 connection_id 失敗: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
    }
    
        
    // MARK: - Character ID 驗證
    
    private func validateCharacterID(_ id: String) {
        
        // 檢查 HTTP API 連接狀態
        if !httpAPIConnected {
            logger.warning("⚠️ HTTP API 未連接，正在重新檢查...")
            checkHTTPAPIConnection()
            
            // 等待連接檢查完成
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if self.httpAPIConnected {
                    // 連接恢復，繼續驗證
                    self.performCharacterValidation(id)
                } else {
                    // 連接仍然失敗，顯示錯誤
                    self.validationMessage = "❌ 無法連接到總部，請檢查網絡"
                    self.showValidationAlert = true
                    self.logger.error("❌ HTTP API 連接失敗，停止驗證")
                }
            }
            return
        }
        
        // HTTP API 連接正常，直接進行驗證
        performCharacterValidation(id)
    }
    
    // MARK: - 執行 Character ID 驗證
    
    private func performCharacterValidation(_ id: String) {
        
        isValidatingID = true
        validationMessage = ""
        
        // 使用真實的 web service 驗證 ID
        feishuService.validateCharacterID(id) { isValid, characterData in
            DispatchQueue.main.async {
                self.isValidatingID = false
                
                if isValid {
                    self.validationMessage = "✅ 成功召喚！"
                    self.isValidationSuccessful = true
                    self.characterData = characterData
                    // self.logger.info("✅ Character ID \(id) 驗證成功，正在獲取新會話...")

                    // 記錄 character 數據
                    if let data = characterData {
                        self.logger.info("📋 Character 數據: \(data)")
                    }

                    // 獲取新 connection_id
                    guard let characterIdInt = Int(id) else {
                        self.validationMessage = "❌ Character ID 格式錯誤"
                        self.showValidationAlert = true
                        return
                    }

                    self.getNewConnectionId(characterId: characterIdInt) { connectionId in
                        if let connectionId = connectionId {
                            // ConnectionManager 會自動儲存 connection_id

                            // 設置到 HTTPManager (會委託給 ConnectionManager)
                            HTTPManager.shared.setConnectionId(connectionId)

                            // 延遲一秒讓用戶看到成功消息
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                self.showLandingPage = true
                            }
                        } else {
                            self.validationMessage = "❌ 無法建立新會話"
                            self.logger.error("❌ 獲取 connection_id 失敗")
                            self.showValidationAlert = true
                        }
                    }
                } else {
                    self.validationMessage = "❌ 搵唔到呢個靈魂呀"
                    self.isValidationSuccessful = false
                    self.logger.error("❌ Character ID \(id) 驗證失敗")
                    self.showValidationAlert = true

                    // 重置狀態，允許重新讀取
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        self.characterID = ""
                        self.validationMessage = ""
                        self.isValidationSuccessful = false
                        self.characterData = nil
                    }
                }
            }
        }
    }
    
    // MARK: - 初始化方法
    
    private func initializeNFCReaderView() {

        // 重置 NFC Manager
        nfcManager.reset()

        // 重新啟動脈衝動畫
        isPulsing = true

        // 清除所有舊資料
        clearAllData()

        // 檢查 HTTP API 連接狀態
        checkHTTPAPIConnection()

    }
    
    // MARK: - 清除資料
    
    private func clearAllData() {
        characterID = ""
        validationMessage = ""
        characterData = nil
        isValidatingID = false
        showValidationAlert = false
        isValidationSuccessful = false
        connectionManager.clearConnection()
    }
    
    // MARK: - 歡迎消息顯示邏輯

    private func shouldShowWelcomeMessage() -> Bool {
        // 當以下情況顯示歡迎消息：
        // 1. 沒有在讀取 NFC
        // 2. 沒有在驗證 ID
        // 3. 沒有顯示驗證消息
        // 4. 沒有成功讀取到 ID
        return !nfcManager.isReading && !isValidatingID && validationMessage.isEmpty && !isValidationSuccessful
    }

    // MARK: - HTTP API 連接檢查

    private func checkHTTPAPIConnection() {
        
        // 簡單的 HTTP API 連接檢查
        Task {
            do {
                // 發送健康檢查請求
                let urlString = "http://145.79.12.177:10001/api/health"
                guard let url = URL(string: urlString) else {
                    logger.error("❌ 無效的 URL: \(urlString)")
                    await MainActor.run {
                        self.httpAPIConnected = false
                    }
                    return
                }
                
                let (data, response) = try await URLSession.shared.data(from: url)
                
                if let httpResponse = response as? HTTPURLResponse,
                   httpResponse.statusCode == 200 {
                    // 檢查回應內容
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       json["status"] as? String == "healthy" {
                        await MainActor.run {
                            self.httpAPIConnected = true
                        }
                        return
                    }
                }
                
                await MainActor.run {
                    self.httpAPIConnected = false
                    self.logger.warning("⚠️ HTTP API 連接失敗")
                }
                
            } catch {
                await MainActor.run {
                    self.httpAPIConnected = false
                    self.logger.error("❌ HTTP API 連接錯誤: \(error.localizedDescription)")
                }
            }
        }
    }
}

#Preview {
    NFCReaderView()
}
