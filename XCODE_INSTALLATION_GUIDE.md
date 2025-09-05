# Xcode 介紹與安裝指南

## 什麼是 Xcode？

### Xcode 概述
Xcode 是 Apple 官方嘅集成開發環境（IDE），專門用嚟開發 macOS、iOS、iPadOS、watchOS 同 tvOS 應用程式。佢係開發 Apple 平台應用程式嘅必備工具。

### 主要功能

#### 1. **程式碼編輯器**
- 語法高亮顯示
- 自動完成功能
- 程式碼摺疊
- 多文件編輯
- 實時錯誤檢查

#### 2. **界面設計器**
- Storyboard 編輯器
- SwiftUI Canvas
- Interface Builder
- 拖放式界面設計

#### 3. **編譯器與構建系統**
- Swift 編譯器
- Objective-C 編譯器
- 自動構建系統
- 依賴管理

#### 4. **調試工具**
- 斷點調試
- 變數監視
- 記憶體分析
- 性能分析器

#### 5. **模擬器**
- iPhone 模擬器
- iPad 模擬器
- Apple Watch 模擬器
- Apple TV 模擬器

#### 6. **版本控制**
- Git 集成
- Source Code Management
- 協作開發支持

#### 7. **測試工具**
- 單元測試框架
- UI 測試
- 性能測試
- 自動化測試

#### 8. **應用程式發布**
- App Store Connect 集成
- 應用程式打包
- 代碼簽名
- 發布工具

### 支援嘅程式語言
- **Swift**（主要推薦）
- **Objective-C**
- **C/C++**
- **JavaScript**（用於網絡視圖）

## 系統需求

### macOS 版本要求
- **最新版本 Xcode 15**：需要 macOS Sonoma 14.0 或更新版本
- **Xcode 14**：需要 macOS Ventura 13.0 或更新版本
- **Xcode 13**：需要 macOS Monterey 12.0 或更新版本

### 硬體需求
- **記憶體**：建議 8GB 或以上（16GB 更佳）
- **存儲空間**：至少 40GB 可用空間
- **處理器**：Intel 或 Apple Silicon (M1/M2/M3) 處理器

## 安裝方法

### 方法一：從 Mac App Store 安裝（推薦）

#### 步驟 1：檢查系統版本
```bash
# 檢查 macOS 版本
sw_vers
```

#### 步驟 2：開啟 Mac App Store
1. 點擊 Dock 中嘅 App Store 圖標
2. 或者使用 Spotlight 搜尋 "App Store"

#### 步驟 3：搜尋 Xcode
1. 在 App Store 搜尋欄輸入 "Xcode"
2. 找到 Apple 官方嘅 Xcode 應用程式

#### 步驟 4：下載並安裝
1. 點擊 "獲取" 按鈕
2. 點擊 "安裝"
3. 輸入 Apple ID 密碼
4. 等待下載完成（檔案大小約 10-12GB）

#### 步驟 5：完成安裝
1. 下載完成後，Xcode 會自動安裝
2. 安裝完成後，可以從 Applications 資料夾或 Launchpad 啟動

### 方法二：從 Apple 開發者網站下載

#### 步驟 1：訪問 Apple 開發者網站
1. 打開瀏覽器，訪問 [https://developer.apple.com/xcode/](https://developer.apple.com/xcode/)
2. 登入 Apple ID（免費帳號即可）

#### 步驟 2：下載 Xcode
1. 找到 "Download" 區域
2. 選擇最新版本嘅 Xcode
3. 點擊下載連結

#### 步驟 3：安裝 Xcode
1. 下載完成後，打開 Downloads 資料夾
2. 雙擊 Xcode.xip 檔案
3. 系統會自動解壓縮
4. 將解壓後嘅 Xcode.app 拖拽到 Applications 資料夾

### 方法三：使用命令行工具安裝

#### 步驟 1：安裝 Homebrew（如果未安裝）
```bash
# 安裝 Homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

#### 步驟 2：安裝 Xcode（透過 Mas CLI）
```bash
# 安裝 Mas CLI
brew install mas

# 安裝 Xcode
mas install 497799835  # Xcode 的 App Store ID
```

## 初次設置

### 1. 啟動 Xcode
```bash
# 從命令行啟動
open /Applications/Xcode.app

# 或者從 Applications 資料夾雙擊 Xcode 圖標
```

### 2. 同意使用條款
首次啟動時，Xcode 會顯示使用條款：
1. 點擊 "Agree" 按鈕
2. 輸入系統密碼確認

### 3. 安裝額外組件
Xcode 會自動安裝所需組件：
- iOS 模擬器
- 命令行工具
- 系統支持檔案

### 4. 驗證安裝
```bash
# 檢查 Xcode 版本
xcodebuild -version

# 檢查 SDK 版本
xcodebuild -showsdks

# 檢查安裝路徑
xcode-select -p
```

## 常見問題解決

### 1. "Xcode is damaged" 錯誤
```bash
# 解決方法
sudo xcode-select --reset
xcode-select --install
```

### 2. 存儲空間不足
```bash
# 檢查存儲空間
df -h

# 清理系統（可選）
sudo rm -rf ~/Library/Developer/Xcode/DerivedData/
```

### 3. 下載速度慢
- 嘗試切換到更穩定嘅網絡
- 使用有線網絡連接
- 避免在網絡高峰期下載

### 4. 安裝失敗
```bash
# 重置安裝
sudo rm -rf /Applications/Xcode.app
# 重新下載安裝
```

## Xcode 基本操作

### 1. 創建新專案
1. 啟動 Xcode
2. 選擇 "Create a new Xcode project"
3. 選擇應用程式類型（iOS App）
4. 設置專案選項
5. 選擇保存位置

### 2. 界面介紹
- **導航區域**：顯示專案文件結構
- **編輯區域**：編寫程式碼嘅主要區域
- **工具區域**：屬性檢查器和庫
- **調試區域**：顯示調試信息

### 3. 構建與運行
- 點擊 "Run" 按鈕（▶️）
- 或者使用快捷鍵 `Cmd + R`
- 選擇目標設備（模擬器或真機）

### 4. 測試應用程式
```bash
# 在模擬器中運行
Cmd + R

# 在真機上運行
連接 iPhone → 選擇設備 → Cmd + R
```

## NFC 應用程式開發準備

### 1. 啟用 NFC 功能
1. 在專案設置中添加 Core NFC 框架
2. 配置 Info.plist 文件
3. 設置權利文件

### 2. 測試環境設置
1. 確保 iPhone 支持 NFC
2. 準備 NFC 標籤用於測試
3. 配置開發者帳號

## 學習資源

### 官方資源
- [Apple 開發者網站](https://developer.apple.com/)
- [Xcode 文檔](https://developer.apple.com/xcode/)
- [Swift 學習資源](https://developer.apple.com/swift/)

### 推薦教程
- Apple 官方 Swift 教程
- Xcode 使用指南
- iOS 開發入門課程

## 總結

Xcode 係開發 iOS 應用程式嘅必備工具，佢提供咗完整嘅開發環境。安裝 Xcode 係開發你 NFC 應用程式嘅第一步，跟住就可以開始編寫程式碼同測試喇。

記住要確保你嘅 Mac 符合系統需求，並且有足夠嘅存儲空間。安裝完成後，就可以開始你嘅 NFC 應用程式開發之旅啦！