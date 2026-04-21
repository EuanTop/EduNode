# EduNode

[English](README.md) | [中文](README.zh-Hans.md)

EduNode 是一个面向教师的原生 pedagogical-graph workspace。它把课程设计、教学推进、评价证据与产出物统一到同一块结构化画布里，避免教师在零散文档之间反复切换。

EduNode 并不把 AI 仅仅当作一个脱离教学结构的聊天入口，而是把它嵌入教师可审阅、可修改、可追踪的教学结构之中。教师负责教学判断与课程结构，Agent 负责协助推荐图谱调整、补齐缺失信息、对齐参考教案结构，并支持后续产出与优化。

<video src="https://github.com/user-attachments/assets/798fb6d6-a0b0-4691-b222-eb1e468beb5b" controls playsinline width="100%"></video>

> [Watch on Vimeo](https://vimeo.com/1184658322)

## EduNode 的核心定位

- 先结构、后生成：课程首先被建模为 pedagogical graph，而不是直接丢给模型输出整份文档。
- 教师主导、Agent 辅助：AI 的改动是可提议、可审查、可撤销的，而不是黑箱式代写。
- 同一工作台贯穿全流程：从建课、搭图、生成教案到展示与课堂执行，保持同一套语义结构。
- 原生应用而非网页拼装：EduNode 采用 SwiftUI + SwiftData 构建，面向 iPad 与 Mac Catalyst 工作流。

## 当前已实现的产品能力

- 结构化建课表单，覆盖年级范围、课程目标、学情、教师团队、资源约束与教学模型选择。
- 基于 GNodeKit 的节点画布，以知识节点、Toolkit 或活动节点、评价节点构成有向教学流程。
- Agent 辅助搭图，支持可视化改动审查、应用或拒绝、以及撤销。
- 教案工作台，可读取参考 PDF、识别缺失教学信息、进行补问、生成对齐模板结构的教案，并导出 Markdown 或 PDF。
- 课件链路，可由节点图生成课件幻灯片，支持样式调整与 AI 辅助优化讲稿文案，并导出 HTML 或 PDF。
- 面向课堂执行的流程追踪与评价支持，包括状态推进、展示模式与细粒度评价指标。
- 面向首次使用者的 onboarding 与 tutorial 流程。

## 架构概览

- 应用架构：SwiftUI 单体原生应用，使用 SwiftData 持久化。
- 图谱引擎：通过 Swift Package Manager 集成 GNodeKit。
- LLM 接入：在应用内直接配置并调用 OpenAI-compatible 接口。
- 参考教案解析：通过 MinerU 完成，依赖运行时 `.env` 配置。
- 产出链路：从节点图生成教案与展示材料，支持 Markdown、HTML、PDF 等格式。
- 第一阶段交付策略 - service-oriented monolith：考虑到早期开发成本与迭代速度，当前 Agent 后端直接以 Swift 形式内嵌在应用中。在下一阶段进入前后端分离时，能快速把上述边界提升为独立 API 服务，并把当前的进程内调用替换为网络请求。

## 环境要求

- macOS + Xcode 16 或更高版本。
- App 目标要求 iOS 17.6 及以上 SDK。
- 若走 Mac Catalyst 工作流，建议 macOS 15 及以上。
- 若使用远程 LLM 或 MinerU，需要可用网络。
- Xcode 可正常解析 Swift Package 依赖。

## 快速开始

1. Clone 本仓库。
2. 使用 Xcode 打开 `EduNode.xcodeproj`。
3. 让 Xcode 自动解析 `GNodeKit` 依赖。
4. 选择 `EduNode` scheme。
5. 在 iPad Simulator、真机 iPad 或 Mac Catalyst 上构建运行。

## 运行时配置

### 应用内模型配置

应用本身的 LLM 配置不是从 `EduNode/.env` 读取的，而是在 EduNode 的 Model Settings 界面中完成。

可配置项包括：

- provider base URL
- model name
- API key
- temperature
- max tokens
- timeout
- optional extra system prompt

应用内配置的密钥通过 Keychain 相关机制存储。

### 用于参考解析与 smoke 的 `.env`

如果你需要参考教案解析或 CLI smoke 工作流，请先复制：

```bash
cp EduNode/.env.example EduNode/.env
```

关键变量包括：

- `MINERU_API_TOKEN`
- `MINERU_API_BASE_URL`
- `MINERU_APPLY_UPLOAD_URL`
- `MINERU_BATCH_RESULT_URL_PREFIX`
- `EDUNODE_LLM_BASE_URL`
- `EDUNODE_LLM_MODEL`
- `EDUNODE_LLM_API_KEY`
- `EDUNODE_REFERENCE_TEMPLATE_PATH`

说明：

- App 侧的参考解析器会在应用 Documents 目录或打包资源目录中查找 `.env`。
- CLI smoke 脚本会直接读取仓库中的 `EduNode/.env`。

## 本地验证

在 Xcode 中运行测试：

- `Product -> Test`

命令行运行：

```bash
xcodebuild -project EduNode.xcodeproj -scheme EduNode -destination 'platform=iOS Simulator,name=iPhone 16' test
```

`Scripts/` 目录中保留了一组聚焦本地验证的小型脚本，主要用于模板解析检查、Agent 逻辑 smoke 与核心测试入口。

当前自动化覆盖的重点在于 Agent 逻辑、模板解析、模板合规性检查与教案物化链路。

## 依赖说明

EduNode 当前通过远程 Swift Package 方式集成 `GNodeKit`：

- 仓库地址：`https://github.com/EuanTop/GNodeKit.git`
- 集成方式：Swift Package Manager

## 许可协议

本仓库采用 PolyForm Noncommercial 1.0.0 许可。详情见 [LICENSE](LICENSE) 与 [NOTICE](NOTICE)。
