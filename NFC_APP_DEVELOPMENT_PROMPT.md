# CineSpark (星聲) NFC URL 讀取器應用程式開發提示

## 應用程式概述
建立一個名為「星聲」(CineSpark) 的 iOS NFC URL 讀取器應用程式。此應用程式能讀取包含 URL 的 NFC 晶片並自動在 Safari 中開啟連結，提供流暢的用戶體驗，包含清晰的指示和回饋。

## 主要需求

### 核心功能
1. **NFC 讀取**：偵測並讀取包含 URL 資料的 NFC 標籤（NDEF 記錄，URI 類型）
2. **URL 啟動**：自動在 Web browser (coudl be safari / Chrome etc.) 中開啟偵測到的 URL
3. **用戶指引**：清晰的指示，引導用戶將 NFC 晶片放在 iPhone 聽筒上
4. **狀態回饋**：NFC 掃描過程中的即時回饋

### 技術需求
- **iOS 版本**：支援 iOS 13.0+（Core NFC 從 iOS 13 開始可用）
- **裝置相容性**：iPhone 7 及更新型號，具備 NFC 功能
- **框架**：Core NFC 框架
- **語言**：使用 Swift 和 SwiftUI 進行現代 iOS 開發
- **架構**：建議使用 MVVM 模式

## 用戶流程

### 1. 應用程式啟動
```
用戶開啟應用程式 → 檢查 NFC 可用性 → 顯示主畫面
```

### 2. 主畫面
- 顯示訊息：「請將 NFC 晶片放在 iPhone 屏幕上近聽筒位置面
- 顯示 NFC 掃描動畫/指示器
- 顯示裝置狀態（準備中/掃描中/錯誤）

### 3. NFC 偵測
```
偵測到 NFC 晶片 → 讀取 URL 資料 → 驗證 URL → 在 browser 中開啟
```

### 4. 錯誤處理
- NFC 不可用：顯示適當訊息
- 未偵測到 NFC 標籤：10 秒後超時
- 無效 URL：顯示錯誤並提供重試選項
- 權限被拒絕：請求 NFC 存取權限

## 實作詳情

### 核心組件

#### 1. NFC 讀取管理器
```swift
import CoreNFC

class NFCReaderManager: NSObject, NFCNDEFReaderSessionDelegate {
    // 處理 NFC 會話管理
    // 處理 NDEF 訊息
    // 從 NFC 記錄中提取 URL
}
```

#### 2. 主畫面視圖模型
```swift
class NFCReaderViewModel: ObservableObject {
    @Published var status: NFCStatus
    @Published var errorMessage: String?
    @Published var isScanning: Bool
    
    // 管理 NFC 掃描狀態
    // 處理 URL 啟動
    // 提供狀態更新
}
```

#### 3. 主畫面（SwiftUI）
```swift
struct ContentView: View {
    @StateObject private var viewModel = NFCReaderViewModel()
    
    var body: some View {
        VStack {
            // 狀態訊息
            // NFC 動畫
            // 操作按鈕
        }
    }
}
```

### 需要實作的主要功能

#### 1. NFC 會話管理
- 應用程式啟動時開始 NFC 會話
- 處理會話生命週期（開始/運行中/結束）
- 如有需要，管理背景掃描

#### 2. URL 驗證
- 驗證提取的 URL
- 處理不同的 URL 格式
- 惡意 URL 的安全檢查

#### 3. 用戶體驗
- NFC 偵測時的觸覺回饋
- 成功/錯誤的音效
- 掃描期間的視覺動畫
- 無障礙支援

#### 4. 錯誤處理
- NFC 硬體不可用
- 用戶取消掃描
- 無效的 NFC 資料格式
- 網路連線問題

## 配置需求

### 1. Info.plist 設定
```xml
<key>NFCReaderUsageDescription</key>
<string>此應用程式需要存取 NFC 以讀取 NFC 標籤中的 URL</string>
<key>LSRequiresIPhoneOS</key>
<true/>
<key>UIRequiredDeviceCapabilities</key>
<array>
    <string>nfc</string>
</array>
```

### 2. 權利設定
```xml
<key>com.apple.developer.nfc.readersession.formats</key>
<array>
    <string>NDEF</string>
</array>
```

## 開發步驟

### 第一階段：設定
1. 在 Xcode 中建立新的 iOS 專案
2. 新增 Core NFC 框架
3. 配置 Info.plist 和權利設定
4. 設定基本的 SwiftUI 視圖結構

### 第二階段：NFC 整合
1. 實作 NFCReaderManager
2. 設定 NFC 會話代理
3. 處理 NDEF 訊息解析
4. 使用實際 NFC 標籤進行測試

### 第三階段：URL 處理
1. 實作從 NDEF 記錄中提取 URL
2. 新增 URL 驗證
3. 實作 Safari 整合
4. 測試各種 URL 格式

### 第四階段：完善
1. 新增動畫和視覺回饋
2. 實作錯誤處理
3. 新增無障礙功能
4. 效能優化

## 測試策略

### 1. 裝置測試
- 在多種 iPhone 型號上測試
- 使用不同的 NFC 標籤類型測試
- 測試各種 URL 格式
- 測試邊界情況和錯誤情境

### 2. 用戶測試
- 與實際用戶測試
- 收集用戶體驗回饋
- 測試無障礙功能
- 效能測試

## 最佳實踐

### 1. 安全性
- 開啟前驗證所有 URL
- 處理惡意 URL 嘗試
- 敏感 URL 的用戶確認
- 隱私考量

### 2. 效能
- 優化 NFC 會話管理
- 最小化電池使用量
- 快速回應時間
- 記憶體效率

### 3. 用戶體驗
- 清晰簡潔的指示
- 即時回饋
- 流暢的動畫
- 無障礙合規性

## 已知限制

1. **裝置相容性**：僅適用於具備 NFC 功能的 iPhone
2. **背景模式**：有限的背景 NFC 掃描
3. **標籤類型**：僅支援 NDEF 格式的 URI 記錄
4. **iOS 限制**：必須在前台才能進行 NFC 讀取

## 交付成果

1. 完整的 iOS 應用程式原始碼
2. 可運作的應用程式，能讀取 NFC URL
3. 適當的錯誤處理和用戶回饋
4. 設定和使用說明文件
5. 測試案例和測試程序

此提示為開發 iOS NFC URL 讀取器應用程式提供了全面的基礎，包含清晰的需求、技術規格和實作指導。