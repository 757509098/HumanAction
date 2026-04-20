# HumanAction - AI Jump Rope Counter 🏃‍♂️💪

**HumanAction** 是一款基于 iOS 原生开发的智能跳绳计数 App。它通过手机摄像头实时追踪人体姿态，利用 Apple 的 **Vision** 框架提取骨骼点，并结合 **CoreML** 动作分类模型，实现高精度的跳绳动作识别与自动计数。

---

## ✨ 核心特性

- 🤖 **AI 动作识别**：集成自定义训练的 CoreML 模型，精准区分“跳绳”与“普通跳跃”或“日常动作”。
- 🦴 **实时姿态追踪**：利用 Vision Framework 实时绘制人体 18 个关键点骨骼图。
- 📏 **自适应基准算法**：动态追踪用户站立地面高度，自动适配不同身高与摄像头角度。
- 🎚️ **实时灵敏度调节**：内置调试面板，支持实时微调起跳阈值，适配“小碎跳”到“高抬腿”各种风格。
- 🔵 **可视化调试层**：直观显示蓝色地面基准线与黄色起跳触发线，让算法判断过程透明化。
- 📳 **触觉反馈**：每次有效跳跃均伴随轻微震动反馈，提升运动节奏感。

---

## 🛠️ 技术栈

- **语言**: Swift 5.10+
- **框架**: SwiftUI, AVFoundation, Vision, Combine, CoreML
- **AI 引擎**: Apple Vision (VNDetectHumanBodyPoseRequest), Create ML (Action Classification)
- **要求**: iOS 17.0+ / Xcode 15.0+ (需真机运行以支持 AI 加速)

---

## 📐 核心算法原理

项目采用 **“AI 门控 + 物理状态机”** 的双重校验机制：

1. **AI 门控 (CoreML)**：
   系统连续收集 30 帧（约 1 秒）的身体动作序列。只有当 `JumpRopeClassifier` 模型确认当前动作为 `JumpRope` 且信心度大于 60% 时，计数引擎才会激活。

2. **物理状态机 (Height Logic)**：
   - **Baseline (蓝色实线)**：通过脖子 (Neck) 点的 Y 轴坐标，结合 EMA 滤波平滑算法，动态锁定“地面”高度。
   - **Threshold (黄色虚线)**：用户设置的起跳触发线。
   - **状态切换**：
     - `Standing -> Jumping`: 脖子点穿过黄色虚线。
     - `Jumping -> Standing`: 脖子点回落至蓝色基准线附近，此时触发 `Count + 1`。

---

## 🚀 快速开始

### 1. 克隆项目
```bash
git clone https://github.com/757509098/HumanAction.git
cd HumanAction
```

### 2. 配置权限
确保 `Info.plist` 中已包含摄像头使用权限说明：
- `Privacy - Camera Usage Description`: "我们需要使用摄像头来识别您的跳绳动作并进行计数。"

### 3. 准备 AI 模型
由于 `.mlmodel` 文件体积较大，本项目可能未包含预训练模型。请：
1. 使用 **Create ML** 训练一个 `Action Classification` 模型。
2. 将导出的 `JumpRopeClassifier.mlmodel` 拖入项目。
3. 确保 Target Membership 已勾选。

### 4. 运行
将 iPhone 连接至电脑，选择你的设备并点击 **Run**。
> **注意**: 模拟器不支持摄像头和部分 Vision 特性，请务必使用真机测试。

---

## 📷 调试指南

- **绿点**: AI 识别出的身体关节点。
- **红圈**: 算法追踪的核心参考点（脖子）。
- **蓝色实线**: 自动计算的地面高度。如果线偏离身体过远，请站定 1 秒让其自动校准。
- **黄色虚线**: 调节滑动条，使其略高于红圈起跳后的最高点以下。

---

## 🤝 贡献与反馈

欢迎提交 Issue 或 Pull Request！
如果你有更好的动作分类数据集或优化建议，请随时联系。

---

## 📄 开源协议

[MIT License](LICENSE)
