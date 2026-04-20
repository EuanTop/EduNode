# EduNode

[English](README.md) | [中文](README.zh-Hans.md)

Teachers often have to switch repeatedly between lesson plans, slides, and classroom flow management. EduNode unifies this work in a single structured canvas, with an Agent architecture that supports the full workflow from planning to delivery.

In EduNode, a course is decomposed into atomic units such as knowledge points, teaching tools, and assessment nodes. Teaching flow can then be clearly organized, connected, and iterated.

In the early stage, AI does not replace teachers; it supports thinking. Based on course context, EduNode recommends suitable educational models and generates structural templates so teachers do not start from a blank page.

In the middle stage, AI accelerates production. With style transfer and structure reuse, teachers can quickly generate consistent lesson plans and slides, moving from node canvas to teaching materials in one flow.

In the classroom stage, EduNode synchronizes progress, slides, and nodes in real time, making formative assessment executable and trackable.

Behind this experience is a continuously optimized Agent system, iterated across cycles and informed by multidisciplinary education experts. EduNode aims to reduce repetitive workload and return teaching to its essence: knowledge-centered, student-serving practice.

[![EduNode Demo Video](https://vumbnail.com/1184658322.jpg)](https://vimeo.com/1184658322)

> Click the preview image to watch the full demo on Vimeo.

### Repository Layout

- `EduNode/`: App source code.
- `EduNodeTests/`: Unit and integration tests.
- `EduNodeUITests/`: UI tests.
- `Scripts/`: Smoke and helper scripts.
- `GNodeKit`: Fetched as a remote Swift Package dependency from GitHub.

### Requirements

- macOS with Xcode 16+ (iOS SDK 17+).
- Swift Package dependency resolution enabled in Xcode.

### Quick Start

1. Open `EduNode.xcodeproj` in Xcode.
2. Select the `EduNode` scheme.
3. Build and run.

### Environment Configuration

The app and smoke tests can load runtime configuration from `EduNode/.env`.

1. Copy `EduNode/.env.example` to `EduNode/.env`.
2. Fill the required values.

Key variables:

- `EDUNODE_LLM_BASE_URL`
- `EDUNODE_LLM_MODEL`
- `EDUNODE_LLM_API_KEY`
- `EDUNODE_REFERENCE_TEMPLATE_PATH` (optional absolute path to a local reference PDF)
- `MINERU_API_TOKEN` (optional, for MinerU-based parsing)

### Running Tests

In Xcode: Product -> Test

From CLI:

```bash
xcodebuild -project EduNode.xcodeproj -scheme EduNode -destination 'platform=iOS Simulator,name=iPhone 16' test
```

### Running Smoke Scripts

```bash
cd Scripts
./run_agent_logic_smoke.sh
```

To run smoke flows with a real local template:

```bash
export EDUNODE_REFERENCE_TEMPLATE_PATH='/absolute/path/to/reference-template.pdf'
```

### GNodeKit Dependency Strategy

This repository uses remote dependency mode only: `EduNode` fetches `GNodeKit` via Swift Package Manager from GitHub.

- Repository URL: `https://github.com/EuanTop/GNodeKit.git`
- Current rule: track `main` branch (switch back to semantic version once stable tags are published)
- After cloning, users can resolve and download dependencies directly in Xcode

### Security Notes

- Do not commit `EduNode/.env`.
- Rotate any real API key that may have been exposed.
- Keep placeholders only in `EduNode/.env.example`.

### Pre-Push Checklist

- Ensure `git status` has no secret-bearing files.
- Ensure `EduNode/.env` is ignored.
- Run the tests/smokes you rely on before pushing.
