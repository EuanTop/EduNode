# EduNode

[English](README.md) | [中文](README.zh-Hans.md)

面对复杂的教学任务，教师往往需要在教案、课件与教学流程之间反复切换。EduNode 将这些工作统一到一个结构化画布中，并由 Agent 架构贯穿课程设计、内容生成与课堂执行全流程。

在 EduNode 中，课程被拆解为知识点、教学工具与评价节点等最小单元，所有教学流程都可被清晰组织、连接与推演。

在前期，AI 不替代教师，而是辅助思考：系统会基于课程信息推荐合适的教育模型，并生成课程结构模板，让教师不再从空白开始。

在中期，AI 加速产出：通过风格迁移与结构复用，教师可以快速生成统一结构的教案与 PPT，实现从节点画布到教学材料的一体化生产。

在后期，EduNode 进入课堂：课程进度、幻灯片与节点实时同步，支持过程性评价与记录，让课堂执行可追踪、可回溯。

这套持续优化的 Agent 系统结合了多轮迭代，并引入多学科教育专家测试与反馈。EduNode 的目标是减少重复劳动、释放教师精力，让教学回归本质：围绕知识，服务学生。


[![EduNode Demo Video](https://vumbnail.com/1184658322.jpg)](https://vimeo.com/1184658322)

> 点击预览图跳转到 Vimeo 观看完整演示。

### 目录结构

- `EduNode/`: App 主代码。
- `EduNodeTests/`: 单元与集成测试。
- `EduNodeUITests/`: UI 测试。
- `Scripts/`: 冒烟脚本与辅助脚本。
- `GNodeKit`: 通过远程 Swift Package 依赖获取（GitHub）。

### 环境要求

- macOS + Xcode 16 或更高（iOS SDK 17+）。
- 能正常解析 Swift Package 依赖。

### 快速开始

1. 用 Xcode 打开 `EduNode.xcodeproj`。
2. 选择 `EduNode` scheme。
3. Build and Run。

### 环境变量配置

App 与部分冒烟测试可从 `EduNode/.env` 读取配置。

1. 复制 `EduNode/.env.example` 为 `EduNode/.env`。
2. 按需填写变量。

关键变量：

- `EDUNODE_LLM_BASE_URL`
- `EDUNODE_LLM_MODEL`
- `EDUNODE_LLM_API_KEY`
- `EDUNODE_REFERENCE_TEMPLATE_PATH`（可选，本地参考 PDF 的绝对路径）
- `MINERU_API_TOKEN`（可选，MinerU 解析能力）

### 运行测试

Xcode 中：Product -> Test

命令行：

```bash
xcodebuild -project EduNode.xcodeproj -scheme EduNode -destination 'platform=iOS Simulator,name=iPhone 16' test
```

### 运行冒烟脚本

```bash
cd Scripts
./run_agent_logic_smoke.sh
```

如需使用真实本地模板：

```bash
export EDUNODE_REFERENCE_TEMPLATE_PATH='/absolute/path/to/reference-template.pdf'
```

### GNodeKit 依赖策略

本仓库仅支持远程依赖模式：`EduNode` 通过 Swift Package Manager 从 GitHub 拉取 `GNodeKit`。

- 依赖仓库：`https://github.com/EuanTop/GNodeKit.git`
- 当前版本规则：跟踪 `main` 分支（待你发布稳定 tag 后可切回语义化版本）
- 用户在 clone 本项目后，Xcode 可自动解析并下载依赖

### 安全注意事项

- 不要提交 `EduNode/.env`。
- 如果真实 API Key 曾在不可信环境出现，务必轮换。
- `EduNode/.env.example` 只保留占位符。

### Push 前检查

- `git status` 不应包含敏感信息文件。
- 确认 `EduNode/.env` 始终被忽略。
- 执行你依赖的测试/冒烟流程。