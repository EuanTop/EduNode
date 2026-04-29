# EduNode

[English](README.md) | [中文](README.zh-Hans.md)

EduNode is a native pedagogical-graph workspace for teachers. It turns lesson planning into a structured canvas where course intent, instructional moves, assessment evidence, and delivery artifacts can be designed in one place instead of being scattered across disconnected documents.

Rather than positioning AI as a detached chat layer, EduNode keeps teachers in control of structure and judgment. Agents help recommend graph changes, fill gaps, align lesson plans to reference templates, and refine delivery materials, while the instructional logic remains explicit and reviewable.

<video src="https://github.com/user-attachments/assets/798fb6d6-a0b0-4691-b222-eb1e468beb5b" controls playsinline width="100%"></video>

> [Watch on Vimeo](https://vimeo.com/1184658322)

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
- Backend service: Python/FastAPI `EduNodeServer` under `Server/`, preserving the app-facing API contract while enabling lighter multi-provider LLM routing.
- Graph engine: GNodeKit via Swift Package Manager.
- LLM integration: the workspace-agent path is driven by `EduNodeServer`, with LiteLLM SDK handling provider normalization, multi-model fallback, token usage, and Langfuse tracing.
- Reference-template parsing: MinerU, called only by the backend and configured in `Server/.env`.
- Artifact outputs: graph-grounded lesson plans and presentation decks rendered as Markdown, HTML, and PDF.
- Phase-1 delivery strategy - service-oriented monolith: to control cloud cost and keep deployment simple, auth, Agent orchestration, LiteLLM-based routing, Langfuse observability hooks, local usage logging, and reference parsing live in one Python backend service. The internal boundaries remain explicit enough to split later if traffic grows.

EduNode can still render and edit the pedagogical graph locally, but the workspace-agent path now expects `EduNodeServer` whenever you want live LLM-backed assistance.

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

### App-side backend connection

The client only needs the EduNode backend base URL:

```bash
cp EduNode/.env.example EduNode/.env
```

- `EDUNODE_BACKEND_BASE_URL`

For local development and deployment switching, use the checked-in templates:

```bash
cp EduNode/.env.dev.example EduNode/.env
cp EduNode/.env.production.example EduNode/.env
```

The app now signs in only through `EduNodeServer`. Supabase stays behind the Python backend, so the client no longer carries Supabase URL or publishable-key configuration.
Do not place Supabase, LLM, or MinerU secrets in `EduNode/.env`; those stay backend-only in `Server/.env`.
### Backend-side model configuration

Copy:

```bash
cp Server/.env.example Server/.env
```

For server deployment, keep real values in ignored files such as `Server/.env.dev` or `Server/.env.production`, then set `EDUNODE_ENV=dev` or `EDUNODE_ENV=production` in the runtime environment.

Key backend variables include:

- `EDUNODE_SUPABASE_URL`
- `EDUNODE_SUPABASE_PUBLISHABLE_KEY`
- `EDUNODE_LLM_MODELS_FILE`
- `EDUNODE_USAGE_LOG_PATH`
- `EDUNODE_LITELLM_ENABLE_LANGFUSE`
- `LANGFUSE_PUBLIC_KEY`
- `LANGFUSE_SECRET_KEY`
- `LANGFUSE_OTEL_HOST`
- `EDUNODE_LLM_PROVIDER_NAME`
- `EDUNODE_LLM_BASE_URL`
- `EDUNODE_LLM_MODEL`
- `EDUNODE_LLM_API_KEY`
- `EDUNODE_LLM_TEMPERATURE`
- `EDUNODE_LLM_MAX_TOKENS`
- `EDUNODE_LLM_TIMEOUT_SECONDS`
- `EDUNODE_LLM_ADDITIONAL_SYSTEM_PROMPT`
- `MINERU_API_TOKEN`

For multiple LLM providers, copy `Server/llm_models.example.json` to `Server/llm_models.json` and add provider entries by priority. The backend uses LiteLLM SDK to try enabled models in priority order, normalize provider responses, and append JSONL usage records to `EDUNODE_USAGE_LOG_PATH`. If Langfuse keys are configured, LiteLLM also emits traces through the `langfuse_otel` callback.

The app no longer reads provider/model/API-key values from the UI. Users now sign in through EduNode backend endpoints, and the backend brokers Supabase Auth before running any protected agent or parsing workload. For the official MinerU cloud service, `MINERU_API_TOKEN` is enough; the backend falls back to the official default endpoint automatically.

## Local Backend

From the repository root:

```bash
cd Server
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python run.py
```

Default runtime:

- host: `127.0.0.1`
- port: `8080`

Optional environment variables:

- `PORT`
- `EDUNODE_SERVER_HOST`
- `EDUNODE_SERVER_AGENT_MODE`

## Local Verification

Run tests in Xcode:

- `Product -> Test`

Command-line example:

```bash
xcodebuild -project EduNode.xcodeproj -scheme EduNode -destination 'platform=iOS Simulator,name=iPhone 16' test
```

Focused local verification scripts are also included under `Scripts/`, primarily for parser inspection, agent-logic smoke checks, and running the core test target.

Current automated coverage is strongest around agent logic, template parsing, compliance checking, and lesson-plan materialization.

If you run backend integration tests against protected routes, seed a valid Supabase session first through either:

- `EDUNODE_TEST_SUPABASE_ACCESS_TOKEN` with optional refresh and user metadata
- `EDUNODE_TEST_SUPABASE_EMAIL` plus `EDUNODE_TEST_SUPABASE_PASSWORD`

## Dependency Notes

EduNode resolves `GNodeKit` as a remote Swift Package:

- Repository: `https://github.com/EuanTop/GNodeKit.git`
- Integration mode: Swift Package Manager

## License

This repository is released under the PolyForm Noncommercial 1.0.0 license. See [LICENSE](LICENSE) and [NOTICE](NOTICE) for details.
