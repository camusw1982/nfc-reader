# NFC 應用程式設置指南

## 必要步驟

### 1. 啟用 NFC 功能
在 Xcode 中打開項目後：

1. 選擇項目設置 (Project Settings)
2. 選擇你的 App Target
3. 點擊 "Signing & Capabilities" 標籤
4. 點擊 "+ Capability" 按鈕
5. 搜索並添加 "Near Field Communication Tag Reading"

### 2. 添加權限描述
在 Info.plist 中已經包含以下權限：
- `NFCReaderUsageDescription`: 需要使用 NFC 功能來讀取標籤信息
- `com.apple.developer.nfc.readersession.iso7816.select-identifiers`: 支援所有 ISO7816 標籤

### 3. 測試設備要求
- iPhone 7 或更新型號
- iOS 13.0 或更新版本
- 確保設備支援 NFC 功能

### 4. 支援的 NFC 標籤類型
- MiFare 標籤
- ISO7816 標籤 (如信用卡、交通卡等)
- FeliCa 標籤 (主要用於日本)

### 5. 運行測試
1. 連接支援 NFC 的 iOS 設備
2. 在 Xcode 中選擇該設備作為運行目標
3. 點擊 "Run" 按鈕
4. 應用程式啟動後，點擊 "開始掃描" 按鈕
5. 將 NFC 標籤靠近設備背面進行讀取

## 常見問題

### 設備不支援 NFC
- 確保使用 iPhone 7 或更新型號
- 檢查 iOS 版本是否為 13.0 或更新版本

### NFC 讀取失敗
- 確保 NFC 標籤靠近設備背面
- 檢查標籤類型是否受支援
- 確保沒有其他 NFC 應用程式正在運行

### 權限問題
- 確保已在 Xcode 中添加 NFC Capability
- 檢查 Info.plist 中的權限描述是否正確