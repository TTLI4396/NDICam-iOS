# NDICam — iOS NDI 发送/接收

基于 NDI SDK for Apple (v6.3.2) 的 iOS 应用：

- **发送**：摄像头 720p 采集 → BGRA → NDI 广播（`NDICam/Sender/`）
- **接收**：局域网 NDI 源发现 → 连接 → 实时显示（`NDICam/Receiver/`）
- `NDICam/Bridge/NDIBridge.mm` 是 NDI C API 的 Objective-C++ 封装

## 重要前提

**Windows 无法构建 iOS IPA**，必须用 macOS + Xcode。两种途径：

## 途径 A：本地 Mac 构建

```bash
./scripts/build_ipa.sh
```

脚本会自动：下载/解包 NDI SDK（若 `NDI SDK for Apple/` 不存在）→ `xcodegen generate` 生成工程 → 无签名归档 → 打包 `build/NDICam.ipa`。

## 途径 B：GitHub Actions 云端构建（无需 Mac）

1. 把本目录推送到 GitHub 仓库（SDK 已被 .gitignore 排除，CI 会自行下载）
2. Actions → **Build iOS IPA** → Run workflow
3. 完成后在 Artifacts 下载 `NDICam-unsigned-ipa`

## 安装到设备

产出的是**未签名 IPA**，需重签名后安装：

- **免费 Apple ID**：用 [AltStore](https://altstore.io) / Sideloadly 侧载（7 天有效）
- **付费开发者账号**：在 Xcode 中打开生成的 `NDICam.xcodeproj`，填入 Development Team 直接真机运行；或 `xcodebuild -exportArchive` 导出签名 IPA

## 真机注意

- 首次启动需授予**相机**与**本地网络**权限（Info.plist 已声明）
- 收发双方须处于**同一局域网**（NDI 走 mDNS 发现 `_ndi._tcp`）
- 建议 5GHz Wi-Fi，720p NDI 高带宽流约 100+ Mbps
