# EduNode

[English](README.md) | [中文](README.zh-Hans.md)

EduNode is a native pedagogical-graph workspace for teachers. It turns lesson planning into a structured canvas where course intent, instructional moves, assessment evidence, and delivery artifacts can be designed in one place instead of being scattered across disconnected documents.

Rather than positioning AI as a detached chat layer, EduNode keeps teachers in control of structure and judgment. Agents help recommend graph changes, fill gaps, align lesson plans to reference templates, and refine delivery materials, while the instructional logic remains explicit and reviewable.

[![EduNode Demo Video](https://vumbnail.com/1184658322.jpg)](https://vimeo.com/1184658322)

> Click the preview image to watch the full demo on Vimeo.

## Why EduNode

- Structure before generation: courses are modeled as a pedagogical graph of knowledge nodes, toolkit or activity nodes, evaluation nodes, and live state.
- Teacher-governed AI: agent actions are proposed, reviewable, and reversible instead of silently rewriting the course.
- One workspace across the teaching lifecycle: planning, materialization, presentation, and classroom execution stay connected.
- Native app, not a web dashboard: EduNode is built as a SwiftUI + SwiftData application for iPad and Mac Catalyst workflows.

## Current Product Surface

- Structured course intake with grade range, goals, learner profile, teaching team, resource constraints, and pedagogical-model selection.
- A graph canvas built on GNodeKit, where knowledge, toolkit, and evaluation nodes can be connected as a directed instructional flow.
- Agent-assisted canvas co-building with visual change review, apply or dismiss controls, and undo support.
- A Lesson Plan Workbench that can parse a reference PDF, detect missing instructional information, ask follow-up questions, generate an aligned lesson plan, and export Markdown or PDF.
- A presentation pipeline that derives courseware slides from the pedagogical graph, supports styling and AI-assisted slide-copy refinement, and exports HTML or PDF.
- Classroom-facing flow tracking and evaluation support, including progress state, presentation mode, and fine-grained assessment indicators.
- Onboarding and guided tutorial flows for first-time users.

## Architecture at a Glance

- App architecture: single native SwiftUI application with SwiftData persistence.
- Graph engine: GNodeKit via Swift Package Manager.
- LLM integration: direct OpenAI-compatible API calls configured inside the app.
- Reference-template parsing: MinerU, loaded from runtime `.env` settings for parser access.
- Artifact outputs: graph-grounded lesson plans and presentation decks rendered as Markdown, HTML, and PDF.
- Phase-1 delivery strategy - service-oriented monolith: to control early development cost and keep iteration speed high, the current Agent backend is implemented directly in Swift inside the application. In the next phase, these boundaries can be lifted into independent API services and the current in-process calls can be replaced with network requests.

EduNode does not require a custom backend to run locally. External services are used only when you enable remote LLM calls or reference-PDF parsing.

## Requirements

- macOS with Xcode 16 or newer.
- iOS 17.6+ SDK support for the app target.
- macOS 15+ if you use the Mac Catalyst workflow.
- Network access if you want remote LLM calls or MinerU parsing.
- Swift Package resolution enabled in Xcode.

## Getting Started

1. Clone the repository.
2. Open `EduNode.xcodeproj` in Xcode.
3. Let Xcode resolve the `GNodeKit` Swift Package dependency.
4. Select the `EduNode` scheme.
5. Build and run on iPad Simulator, a connected iPad, or Mac Catalyst.

## Runtime Configuration

### In-app model settings

LLM settings for the application are configured inside EduNode's Model Settings UI, not from `EduNode/.env`.

Configure:

- provider base URL
- model name
- API key
- temperature
- max tokens
- timeout
- optional extra system prompt

API keys configured in the app are stored through Keychain-backed settings.

### `.env` for reference parsing and smoke scripts

For reference-template parsing and CLI smoke workflows, copy:

```bash
cp EduNode/.env.example EduNode/.env
```

Important variables include:

- `MINERU_API_TOKEN`
- `MINERU_API_BASE_URL`
- `MINERU_APPLY_UPLOAD_URL`
- `MINERU_BATCH_RESULT_URL_PREFIX`
- `EDUNODE_LLM_BASE_URL`
- `EDUNODE_LLM_MODEL`
- `EDUNODE_LLM_API_KEY`
- `EDUNODE_REFERENCE_TEMPLATE_PATH`

Notes:

- The app-side reference parser looks for `.env` in the app's Documents directory or bundled resources.
- The CLI smoke scripts read `EduNode/.env` directly from the repository.

## Local Verification

Run tests in Xcode:

- `Product -> Test`

Command-line example:

```bash
xcodebuild -project EduNode.xcodeproj -scheme EduNode -destination 'platform=iOS Simulator,name=iPhone 16' test
```

Focused local verification scripts are also included under `Scripts/`, primarily for parser inspection, agent-logic smoke checks, and running the core test target.

Current automated coverage is strongest around agent logic, template parsing, compliance checking, and lesson-plan materialization.

## Dependency Notes

EduNode resolves `GNodeKit` as a remote Swift Package:

- Repository: `https://github.com/EuanTop/GNodeKit.git`
- Integration mode: Swift Package Manager

## License

This repository is released under the PolyForm Noncommercial 1.0.0 license. See [LICENSE](LICENSE) and [NOTICE](NOTICE) for details.
