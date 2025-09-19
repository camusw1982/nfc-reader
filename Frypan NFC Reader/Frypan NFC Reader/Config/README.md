# MiniMax 配置指南

## 設置方法

### 方法 1: Xcode Build Settings (推薦)

1. 打開 Xcode project
2. 選擇 project 根目錄
3. 選擇 "Build Settings"
4. 搜索 "User-Defined"
5. 點擊 "+" 添加以下設置：
   - `MINIMAX_API_KEY`: 你的 API key
   - `MINIMAX_GROUP_ID`: `1920866061935186857`

### 方法 2: 環境變數

喺終端機設置環境變數：

```bash
export MINIMAX_API_KEY="your_api_key_here"
export MINIMAX_GROUP_ID="1920866061935186857"
```

### 方法 3: xcconfig 檔案

直接編輯 `Config/MiniMax.xcconfig` 檔案，取消註解並填入你嘅值：

```xcconfig
MINIMAX_API_KEY = your_api_key_here
MINIMAX_GROUP_ID = 1920866061935186857
```

## 配置檔案結構

- `MiniMax.xcconfig`: 通用配置
- `Debug.xcconfig`: Debug 環境配置
- `Release.xcconfig`: Release 環境配置

## 安全注意事項

- 請勿將真實嘅 API key 提交到版本控制
- 建議使用 `.gitignore` 排除包含敏感信息嘅檔案
- 生產環境建議使用更安全嘅配置管理方式