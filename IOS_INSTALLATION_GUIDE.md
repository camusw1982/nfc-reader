# iOS 應用程式安裝到 iPhone 測試指南

## 方法一：使用 Xcode 直接安裝（推薦用於開發測試）

### 準備工作
1. **Apple ID**
   - 需要一個有效的 Apple ID
   - 不需要付費開發者帳號（免費帳號即可）

2. **設備準備**
   - iPhone 與 Mac 在同一 WiFi 網絡
   - 或使用 USB 線連接 iPhone 和 Mac

### 安裝步驟

#### 1. 在 Xcode 中配置專案
```bash
# 打開專案
open YourNFCApp.xcodeproj
```

#### 2. 設置 Bundle Identifier
- 在 Xcode 中選擇專案
- 點擊 "Signing & Capabilities"
- 修改 Bundle Identifier 為唯一值（例如：com.yourname.nfcreader）

#### 3. 配置簽名
- 選擇 "Automatically manage signing"
- 選擇你的 Apple ID 作為 Team

#### 4. 連接 iPhone
- 使用 USB 線連接 iPhone
- 或在同一 WiFi 網絡下選擇 "Connect via Network"

#### 5. 選擇設備並運行
- 在 Xcode 左上角選擇你的 iPhone
- 點擊 "Run" 按鈕（▶️）
- Xcode 會自動構建並安裝到 iPhone

#### 6. 信任應用程式
- 首次運行時，iPhone 會顯示 "Untrusted Developer"
- 前往 設置 → 通用 → VPN 與裝置管理
- 找到你的 Apple ID 並點擊信任

## 方法二：使用 TestFlight（推薦用於分享測試）

### 準備工作
1. **付費 Apple Developer 帳號**（每年 $99）
2. **App Store Connect 帳號**

### 步驟

#### 1. 上傳到 App Store Connect
```bash
# 在 Xcode 中
1. Product → Archive
2. 點擊 "Upload to App Store"
3. 登入 Apple Developer 帳號
4. 選擇 "iOS App"
5. 填寫應用程式資訊
```

#### 2. 配置 TestFlight
- 登入 [App Store Connect](https://appstoreconnect.apple.com)
- 選擇你的應用程式
- 點擊 "TestFlight" 標籤
- 上傳構建版本

#### 3. 邀請測試者
- 添加測試者郵箱
- 測試者會收到邀請郵件
- 在 iPhone 上安裝 TestFlight 應用程式
- 通過 TestFlight 安裝你的應用程式

## 方法三：使用第三方服務（適用於無開發者帳號）

### 服務選項
1. **Diawi** (https://www.diawi.com)
2. **InstallOnAir** (https://installonair.com)
3. **Appetize.io** (https://appetize.io)

### 使用 Diawi 的步驟

#### 1. 構建 IPA 文件
```bash
# 在 Xcode 中
1. Product → Archive
2. 點擊 "Distribute App"
3. 選擇 "Ad Hoc"
4. 選擇 "Export"
5. 保存 IPA 文件
```

#### 2. 上傳到 Diawi
- 訪問 https://www.diawi.com
- 拖拽 IPA 文件到上傳區域
- 點擊 "Upload"
- 等待處理完成

#### 3. 安裝到 iPhone
- 獲取 Diawi 提供的下載連結
- 在 iPhone Safari 中打開連結
- 點擊安裝按鈕
- 信任應用程式（如方法一）

## 方法四：使用企業簽名（適用於企業內部測試）

### 準備工作
1. **Apple Developer Enterprise Program**（每年 $299）
2. **企業證書**

### 步驟
1. 申請企業開發者帳號
2. 創建企業證書
3. 使用企業證書簽名應用程式
4. 分發 IPA 文件供下載安裝

## 常見問題解決

### 1. "Untrusted Developer" 錯誤
```
解決方法：
設定 → 通用 → VPN 與裝置管理 → 開發者應用程式 → 信任
```

### 2. "Unable to Install" 錯誤
```
可能原因：
- iOS 版本過低
- 應用程式與設備不相容
- 簽名問題
- 存儲空間不足
```

### 3. "App Installation Failed" 錯誤
```
解決方法：
- 檢查 Bundle Identifier 是否唯一
- 確認簽名配置正確
- 重新啟動 iPhone
- 清理 Xcode 構建緩存
```

### 4. NFC 權限問題
```
確保在 Info.plist 中添加：
- NFCReaderUsageDescription
- 適當的權利設定
```

## 測試建議

### 1. 設備兼容性測試
- 在多種 iPhone 型號上測試
- 測試不同 iOS 版本
- 確認 NFC 功能正常工作

### 2. 網絡環境測試
- 在不同網絡環境下測試
- 測試離線場景
- 測試網路切換

### 3. 用戶場景測試
- 模擬真實使用場景
- 測試各種 NFC 標籤
- 測試錯誤處理

### 4. 性能測試
- 測試應用程式啟動速度
- 測試 NFC 讀取速度
- 測試電池消耗

## 安全注意事項

1. **應用程式簽名**
   - 始終使用正確的簽名
   - 不要使用來源不明的證書

2. **數據安全**
   - 不要在應用程式中存儲敏感信息
   - 使用安全的網絡連接

3. **用戶隱私**
   - 遵循 Apple 的隱私政策
   - 明確說明 NFC 使用目的

## 總結

對於個人開發測試，**方法一（Xcode 直接安裝）**是最簡單和推薦的方式。如果你需要與他人分享測試，可以考慮使用 TestFlight 或第三方服務。

選擇適合你需求的方法，按照步驟操作，就可以將你的 NFC 應用程式安裝到 iPhone 上進行測試了。