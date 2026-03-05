# Kapsicum Collective Intelligence Architecture

## Vision

Kapsicum evolves from a personal memory app (capture + search) into a
**personal AI with collective consciousness** — thousands of micro-agents
that each understand one aspect of your life, communicate with each
other, and collectively form a living model of YOU.

Every person, project, topic, pattern, and document gets its own agent.
They learn continuously, communicate via message passing, and anticipate
your needs — all running locally, all private, all free (local LLMs).

**Tagline**: "Kapsicum doesn't just remember. It understands."

## Why BEAM is Non-Negotiable for This

This architecture requires properties that only BEAM provides together:

| Property | Why Required | BEAM Mechanism |
|----------|-------------|----------------|
| Thousands of concurrent agents | Each entity = one process | Lightweight processes (~2KB each) |
| Crash isolation | User-defined agents can't kill the system | Per-process heap, no shared state |
| Self-healing | Crashed agents restart automatically | OTP supervisors with backoff |
| Live inspection | "Why did you suggest this?" answered in real-time | REPL + process introspection |
| Hot reload | Tweak agent behavior without restart, state preserved | BEAM code server hot swap |
| Zero-cost messaging | Agents communicate by sending messages | Erlang message passing |
| Graph-native storage | Knowledge graph with concurrent access | ETS (in-memory) + Mnesia (persistent) |
| Server portability | Same code runs locally or on a VPS | BEAM release is platform-independent |
| Multi-device distribution | Mac + iPhone + server in one cluster | BEAM node clustering + Mnesia replication |
| Built-in observability | No Datadog needed for local dev | :observer, :recon, :dbg, LiveDashboard |

**Why clojerl specifically (not just Elixir):**
- Agent definitions are DATA (homoiconicity) — inspectable, composable, LLM-generatable
- Macros for agent DSL (`defagent`, `defmicro-agent`, `deftool`)
- REPL-first development culture — the right mindset for tuning a live system
- LLMs can generate valid Clojure agent definitions at runtime

## Architecture Overview

### Two-Process Model

```
┌────────────────────────────────────────────────────────┐
│               Kapsicum (Swift)                          │
│                                                        │
│  Responsibilities:                                     │
│  - Text capture (CGEvent taps, Accessibility API)      │
│  - Audio capture (ProcessTap, WhisperKit)              │
│  - Clipboard monitoring                                │
│  - UI (SwiftUI + AppKit)                               │
│  - Encrypted storage (SQLite + SQLCipher)              │
│  - Agent lifecycle management (start/stop BEAM)        │
│  - Display insights from agent swarm                   │
│                                                        │
│  Writes to: archive.db (encrypted, raw captures)       │
│  Reads from: insights.db (agent outputs)               │
└────────────────────────────────────────────────────────┘
         │ SQLite (read)              ▲ SQLite (read)
         ▼                            │
┌────────────────────────────────────────────────────────┐
│            Agent Runtime (BEAM)                         │
│                                                        │
│  Responsibilities:                                     │
│  - Run agent swarm (OTP supervised)                    │
│  - Maintain knowledge graph (ETS + Mnesia)             │
│  - Call local LLMs (Ollama)                            │
│  - Publish insights for Swift to display               │
│  - Provide REPL for inspection/debugging               │
│                                                        │
│  Reads from: archive.db (captures, via SQLCipher key)  │
│  Writes to: insights.db (agent outputs for Swift)      │
│  Internal: ETS (hot state) + Mnesia (persistent graph) │
└────────────────────────────────────────────────────────┘
```

### Communication: DB as Interface

Swift and BEAM communicate exclusively through SQLite. No custom IPC
protocol, no RPC, no socket API (for data flow). The database IS the
contract.

```
Swift writes:  archive_entries (captured text, audio, clipboard)
BEAM reads:    archive_entries (polls for new entries)
BEAM writes:   insights.db (entities, relationships, briefings, alerts)
Swift reads:   insights.db (GRDB ValueObservation, reactive)
```

**Security**: Both processes share an encryption key for archive.db.
The key is passed to BEAM at launch (via stdin or environment variable).
For insights.db, a separate shared key is generated at first launch and
stored encrypted on disk — both processes derive it from the user's
master password.

**Why not IPC?** Simplicity and portability. If BEAM is ever replaced,
the contract is just "read these SQLite tables, write those SQLite
tables." Any language can implement that.

**When IPC is needed (Phase 2+):** Agent wants to use the microphone,
paste into an app, or trigger a macOS notification that requires Swift
APIs. These rare cases use a Unix domain socket with a simple JSON-RPC
protocol. But for data flow, it's always the DB.

### SQLite vs ETS/Mnesia: Different Jobs

```
SQLite (archive.db)              ETS                  Mnesia
───────────────────              ───                  ──────
Raw captured entries             Agent hot state      Knowledge graph
User settings                   Message routing      Entity profiles
Chat history                    Cache/indexes        Relationships
Audio transcripts               Ephemeral counters   Patterns
                                                     Agent definitions

Written by: Swift               Written by: Agents   Written by: Agents
Read by: BEAM                   Read by: Agents      Read by: Agents + Swift*

Encrypted (SQLCipher)            In-memory only       Persisted to disk
Single-writer                   Concurrent r/w       Transactional
Good for: durable capture       Good for: speed      Good for: graph queries
Bad for: graph queries          Bad for: persistence Bad for: nothing relevant
Bad for: concurrent writes

* Swift reads Mnesia data indirectly via insights.db export
```

**Why not just SQLite for everything?**
- SQLite is single-writer. 50 agents writing concurrently = bottleneck.
- Graph queries (entities related within N hops) require self-joins in SQL.
  In Mnesia, it's a direct graph traversal: ~1ms vs ~200ms.
- ETS does millions of ops/sec. SQLite does hundreds of writes/sec.
- Agent state changes rapidly. Persisting every state change to SQLite
  would be wasteful. ETS is in-memory — zero disk I/O for hot state.

## The Agent Swarm

### Micro-Agent Concept

Each micro-agent is a BEAM process (~2KB memory) responsible for
understanding ONE entity in your life. It:

- Maintains a small state (summary, relationships, patterns, sentiment)
- Wakes when a message arrives (new mention, query, update from another agent)
- Optionally calls a local LLM for understanding extraction
- Sends messages to related agents when its understanding changes
- Goes idle when no messages arrive (zero CPU when sleeping)

```clojure
(defmicro-agent "entity:sarah-chen"
  :state {:type :person
          :summary "Product manager, Project Atlas. Reports to David."
          :last-seen "2026-03-05T14:00 (Slack)"
          :sentiment :positive
          :open-threads ["Q3 roadmap review" "design system migration"]
          :interaction-frequency :daily
          :relationship-strength 0.89
          :mention-count 47}

  :on-mention (fn [entry state]
    ;; New entry mentions Sarah — extract what's new
    (let [delta (local-llm/extract-delta (:text entry) (:summary state))]
      ;; Update own state
      (-> state
          (merge-delta delta)
          (update :mention-count inc)
          (assoc :last-seen (now)))
      ;; Notify related entity agents
      (when (:mentions-project delta)
        (send! (entity-agent (:project delta))
               {:linked-by "sarah-chen" :entry entry :delta delta}))))

  :on-query (fn [question state]
    ;; Another agent or user asks about Sarah
    ;; Answer from local state — no LLM needed for simple queries
    (match-answer question state))

  :on-related-update (fn [msg state]
    ;; Another entity agent notified us of a change
    ;; e.g., Project Atlas agent says "deadline changed"
    (update-relationship state (:from msg) (:delta msg))))
```

### Agent Types

```
SYSTEM AGENTS (always running, 5-10 processes)
──────────────────────────────────────────────
Entry Watcher
  - Polls SQLite for new archive_entries
  - Dispatches entries to relevant entity agents
  - Manages the entry→entity routing table

Entity Spawner
  - Detects new entities (people, projects, topics) from extractor output
  - Creates new micro-agents for previously unseen entities
  - Persists agent definitions to Mnesia

Decay Manager
  - Periodically reduces relationship strength for dormant connections
  - Garbage-collects entity agents with zero activity for 30+ days
  - Persists decay state to Mnesia

Anticipation Engine
  - Reads calendar/schedule (from captured data patterns)
  - Queries entity agents for relevant context
  - Publishes briefings to insights.db before events

Insight Publisher
  - Subscribes to high-confidence insights from all agents
  - Writes to insights.db for Swift to display
  - Rate-limits to avoid flooding the UI

REPL Server
  - Socket REPL for developer inspection
  - Web REPL (optional, via Phoenix LiveView)

ENTITY MICRO-AGENTS (one per entity, 100-100,000+ processes)
──────────────────────────────────────────────────────────────
Person agents      — one per person you interact with
Project agents     — one per project you work on
Topic agents       — one per recurring topic
Document agents    — one per significant document
Meeting agents     — one per recurring meeting
App agents         — one per app you use heavily

Each maintains local state, communicates via messages.

USER-DEFINED AGENTS (0-N, created by user or LLM)
──────────────────────────────────────────────────
Custom automations defined via:
  - Visual builder in Swift UI
  - Natural language ("watch for X, do Y")
  - Clojerl REPL (power users)
  - LLM-generated code

Examples:
  "Summarize every meeting transcript automatically"
  "Alert me when deadline pressure increases across projects"
  "Draft a weekly digest of Project Atlas activity"
  "When I'm emailing Sarah, show recent context"

EPHEMERAL AGENTS (short-lived, spawned per-task)
────────────────────────────────────────────────
Batch processors  — "re-extract entities from last 1000 entries"
Research agents   — "deep-dive on this topic across all my data"
Analysis agents   — "compare my interaction patterns this month vs last"
```

### Message Flow Example

```
You type in Slack: "Sarah mentioned the Atlas deadline might slip"

1. Swift captures → writes to archive.db

2. Entry Watcher (polls every 1-2s) → finds new entry
   → Calls local LLM: "Extract entities from this text"
   → Result: [sarah-chen, project-atlas, topic:deadlines]
   → Dispatches to each entity agent

3. entity:sarah-chen receives {:new-mention entry}
   → Calls local LLM: "What's new vs my current summary?"
   → Delta: {concern about Atlas deadline}
   → Updates own state: adds "deadline concern" to open-threads
   → Sends to entity:project-atlas: {:risk-signal :deadline-slip :source "sarah-chen"}

4. entity:project-atlas receives {:risk-signal ...}
   → Updates risk assessment: deadline_risk = 0.7 (was 0.3)
   → Sends to entity:q3-roadmap: {:dependency-risk "atlas" 0.7}
   → Sends to entity:david-kim: {:heads-up "atlas deadline" :flagged-by "sarah-chen"}

5. entity:q3-roadmap receives {:dependency-risk ...}
   → Now 2 of 4 projects have elevated risk
   → Sends to Anticipation Engine: {:pattern :multi-project-risk :confidence 0.8}

6. Anticipation Engine evaluates:
   → Multi-project deadline pressure + upcoming planning meeting
   → Generates briefing: "Atlas and API Redesign have deadline pressure.
      Key people: Sarah (Atlas), Mike (API). You have planning Thursday."
   → Writes to insights.db

7. Swift observes insights.db change → shows notification:
   "Heads up: deadline pressure on 2 projects before Thursday's planning."

Total elapsed: ~5-15 seconds (mostly local LLM inference time)
Total BEAM processes involved: 6 agents + supervisors
Total LLM calls: 2-3 (entity extraction + delta extraction + briefing)
Cost: $0 (all local)
```

### Collective Intelligence Properties

The swarm exhibits emergent intelligence that no single agent has:

**Transitive knowledge**: You never told the system that Q3 roadmap
depends on Atlas. But entity:project-atlas told entity:q3-roadmap about
the dependency because they were frequently mentioned together. The
relationship was LEARNED, not programmed.

**Multi-hop reasoning**: Sarah → Atlas → Q3 → Thursday planning. No
single agent made this full connection. Each agent handled one hop.
The intelligence emerged from communication.

**Pattern detection across silos**: Deadline pressure in Slack + budget
discussion in email + calendar crunch = the system detects organizational
stress before you consciously notice it.

**Temporal awareness**: Agents track not just WHAT but WHEN. "Sarah
mentions Atlas every standup, but the deadline concern is new as of
today." Temporal novelty drives alerting.

## Resource Budget (Local Mac)

### Memory

```
Component                          Memory
──────────────────────────────────────────
BEAM runtime                       ~40MB
System agents (10)                 ~1MB
Entity micro-agents (1,000)        ~2MB  (2KB each)
Entity micro-agents (10,000)       ~20MB
Entity micro-agents (100,000)      ~200MB
ETS tables (hot state + caches)    ~50-200MB
Mnesia tables (knowledge graph)    ~100-500MB
──────────────────────────────────────────
Total (1,000 entities):            ~200MB
Total (10,000 entities):           ~400MB
Total (100,000 entities):          ~800MB

For context: a Mac with 16GB RAM has plenty of headroom.
Kapsicum Swift app itself uses ~100-300MB.
```

### CPU

```
Micro-agents when idle: 0 CPU (BEAM scheduler doesn't poll idle processes)
Agent processing one message: ~1ms (state update) to ~15s (LLM call)

Typical day:
  New entries captured: ~500-2000
  Entity extractions (LLM): ~500-2000 calls
  At ~500 tokens each, ~17s per call on M2 Pro (7B model)
  Total LLM time: ~2.5-9.5 hours spread across 16 waking hours
  GPU utilization: ~15-60% (intermittent, not continuous)

  Non-LLM processing (message routing, state updates, graph ops):
  Negligible — microseconds per operation
```

### Disk

```
Mnesia persistence: ~10-100MB (knowledge graph)
insights.db: ~1-10MB (current insights for Swift)
BEAM release: ~50-80MB (one-time, bundled in app)
```

## Restart / Crash Recovery

### What Happens When the Mac Restarts

```
Mac restarts
  → macOS launches Kapsicum (login item)
    → Swift app starts, user enters password
    → Swift launches BEAM process, passes SQLCipher key
      → BEAM starts OTP application
        → Top supervisor starts
          → Mnesia starts, loads tables from disk
            → Agent definitions restored
            → Knowledge graph restored
            → Entity states restored
          → Agent Supervisor starts
            → Reads agent definitions from Mnesia
            → Spawns each micro-agent
            → Each agent loads its state from Mnesia
            → Entry Watcher starts polling for entries since last checkpoint
          → System agents start
            → Resume from last known state

Time to full recovery: 2-10 seconds
Data lost: zero (Mnesia persists to disk)
In-flight messages lost: yes, but new data will arrive and re-trigger
Agent state: fully preserved
Knowledge graph: fully preserved
```

### What Happens When an Agent Crashes

```
entity:project-atlas crashes (bug in user-customized logic)
  → Supervisor detects crash
  → Logs crash reason + stacktrace
  → Waits 1 second (backoff)
  → Restarts entity:project-atlas
  → Agent loads state from Mnesia (last persisted state)
  → Resumes processing

If it crashes 5 times in 60 seconds:
  → Supervisor gives up on THIS agent only
  → Marks it as :stopped in Mnesia
  → All other agents continue unaffected
  → Swift UI shows: "Agent 'project-atlas' stopped (recurring error)"
  → User can inspect via REPL, fix the issue, restart manually

Impact on other agents: ZERO
Impact on Swift app: ZERO
Impact on data capture: ZERO
```

### What Happens When the BEAM Process Crashes

```
BEAM process crashes entirely (rare but possible)
  → Swift detects BEAM process exit
  → Waits 2 seconds
  → Restarts BEAM process
  → Full recovery as described in "Mac Restarts" above
  → Swift shows brief notification: "Agent runtime restarted"

Data during downtime:
  → Swift continues capturing to SQLite (unaffected)
  → When BEAM recovers, Entry Watcher processes missed entries
  → No data lost, just a brief gap in agent processing
```

### Mnesia Persistence Strategy

```
What persists to disk (survives restart):
  - Agent definitions (which agents exist, their config)
  - Entity state (summaries, relationships, patterns)
  - Knowledge graph (entities + relationships + strengths)
  - User-defined agent code
  - Pattern history

What stays in-memory only (rebuilt on restart):
  - ETS caches (rebuilt from Mnesia on demand)
  - Message routing tables (rebuilt from agent registry)
  - Active LLM requests (re-triggered by new data)

Persistence frequency:
  - Mnesia disc_copies: writes on every transaction (durable)
  - Checkpoint: every 5 minutes, save "last processed entry ID"
  - On clean shutdown: flush all pending state to Mnesia
```

## Server Portability

The same BEAM release runs locally or on a server with zero code changes:

```
LOCAL DEPLOYMENT                    SERVER DEPLOYMENT
──────────────                      ─────────────────
Bundled in Kapsicum.app             Deployed to VPS/cloud
Reads local SQLite                  Reads Postgres (swap adapter)
Local Ollama                        Cloud LLMs or GPU server Ollama
Mnesia on one node                  Mnesia replicated across nodes
REPL via localhost socket           REPL via SSH tunnel
Single user                         Multi-user (each user = namespace)
```

### Multi-Device (Future)

BEAM's built-in distribution enables:

```
┌──────────────┐      BEAM clustering      ┌──────────────┐
│  Mac (local)  │◄────────────────────────►│   iPhone      │
│              │                           │ (mobile-BEAM) │
│ Private data  │                           │ Phone data    │
│ Full swarm   │                           │ Light swarm   │
└──────────────┘                           └──────────────┘
        ▲                                          ▲
        │            BEAM clustering               │
        ▼                                          ▼
┌──────────────────────────────────────────────────────┐
│                    Server (optional)                   │
│                                                      │
│  Shared agents (team features, if desired)            │
│  Heavy computation (large model inference)            │
│  Mnesia replication for backup                       │
└──────────────────────────────────────────────────────┘

Mnesia handles replication natively:
  - Private tables: stay on device, never sync
  - Shared tables: replicated across nodes
  - Agent migration: move an agent from Mac to server with one call
```

## REPL: The Debugging Superpower

### For Development (Claude Code / Developer)

```clojure
;; Connect to running agent swarm
clje.user=> (agent-count)
{:system 8 :entity 1847 :user-defined 12 :ephemeral 3 :total 1870}

;; Find the busiest agents
clje.user=> (top-agents :message-throughput 5)
[{:id "entity:sarah-chen" :msgs-today 23}
 {:id "entity:project-atlas" :msgs-today 19}
 {:id :entry-watcher :msgs-today 1204}
 {:id "entity:david-kim" :msgs-today 14}
 {:id "topic:q3-planning" :msgs-today 11}]

;; Inspect an agent's understanding
clje.user=> (agent-state "entity:sarah-chen")
{:summary "Product manager on Atlas. Concerned about deadline..."
 :relationships {"project-atlas" 0.94
                 "david-kim" 0.67
                 "design-system" 0.45}
 :open-threads ["Q3 roadmap review" "deadline risk"]
 :last-seen "14:23 today (Slack)"
 :mention-count 47}

;; Ask why the system generated a specific insight
clje.user=> (explain-insight :latest)
{:insight "Deadline pressure on 2 projects before Thursday planning"
 :reasoning-chain
 [{:agent "entity:sarah-chen"
   :observation "Mentioned Atlas deadline might slip"
   :source {:app "Slack" :time "14:00"}}
  {:agent "entity:project-atlas"
   :inference "Deadline risk elevated to 0.7"
   :trigger "sarah-chen risk signal"}
  {:agent "entity:q3-roadmap"
   :inference "2/4 dependent projects at risk"
   :trigger "atlas risk propagation"}
  {:agent :anticipation-engine
   :decision "Thursday planning meeting is relevant context"
   :confidence 0.87}]}

;; Tune an agent live
clje.user=> (update-config! :anticipation-engine
              {:min-confidence 0.85  ;; was 0.80
               :briefing-lead-time-minutes 45})  ;; was 30
;; Immediately active. No restart.

;; Trace all messages to/from an agent (like tcpdump for agents)
clje.user=> (trace-agent "entity:project-atlas" :duration-seconds 60)
;; ... watch messages flow in real-time ...

;; Hot-reload an agent's logic without losing state
clje.user=> (redefine-handler "entity:sarah-chen" :on-mention
              (fn [entry state]
                ;; New logic: also track sentiment
                (let [delta (local-llm/extract-delta (:text entry) (:summary state))
                      sentiment (local-llm/sentiment (:text entry))]
                  (-> state
                      (merge-delta delta)
                      (assoc :sentiment sentiment)))))
;; Sarah agent now tracks sentiment. State preserved. No restart.
```

### For Users (Natural Language via Swift UI)

```
User: "What do you know about Project Atlas?"
  → Swift sends query to BEAM
  → BEAM queries entity:project-atlas agent directly
  → Agent responds from its state (no LLM needed)
  → "Project Atlas: 4-person team led by Sarah Chen.
     Active since January. Current risk: deadline pressure.
     Related: Q3 Roadmap, Design System Migration.
     47 mentions in the last 30 days, mostly in Slack and email."

User: "Why do you think there's deadline pressure?"
  → Explain-insight traces the reasoning chain
  → "Sarah mentioned 'deadline might slip' in Slack today.
     This follows 3 other deadline-related discussions this week.
     Combined with the Q3 dependency, confidence is 87%."

User: "Watch for any budget discussions about Atlas"
  → LLM generates a user-defined agent:
    (defmicro-agent "user:atlas-budget-watch"
      :trigger {:entity "project-atlas" :topic-match "budget|cost|spend"}
      :action (fn [entry state]
                (notify! {:title "Atlas budget mention"
                          :body (summarize (:text entry))
                          :source (:app entry)})))
  → Agent spawned, supervised, persistent.
```

## Implementation Roadmap

### Phase 0: Foundation (2 weeks)

```
Goal: BEAM process running inside Kapsicum, reading data, one working agent.

Tasks:
[ ] Bundle BEAM release in Kapsicum.app/Contents/MacOS/
[ ] Swift launches BEAM on app start, passes SQLCipher key via stdin
[ ] BEAM opens archive.db (read-only) via exqlite + SQLCipher NIF
[ ] Entry Watcher agent: polls for new entries every 2 seconds
[ ] Entity Extractor agent: calls Ollama to extract entities from text
[ ] Writes extracted entities to insights.db (unencrypted, local-only)
[ ] Swift reads insights.db via GRDB ValueObservation
[ ] Minimal "Entities" view in Swift UI showing extracted people/projects
[ ] Socket REPL accessible via `rlwrap nc localhost 9876`

Deliverable: Open Kapsicum, type things, see entities appear automatically.
```

### Phase 1: Knowledge Graph (3 weeks)

```
Goal: Entity micro-agents with relationships, Mnesia persistence.

Tasks:
[ ] Mnesia schema: entities, relationships, patterns
[ ] Entity Spawner: creates micro-agent per entity
[ ] Micro-agent gen_server: state management, message handling
[ ] Relationship Linker: connects entities mentioned together
[ ] Decay Manager: relationship strength decay over time
[ ] Graph queries: "related within N hops"
[ ] Insight Publisher: writes entity profiles + relationships to insights.db
[ ] Swift UI: "People", "Projects", "Topics" views with relationship graph
[ ] Crash recovery: full Mnesia restore on restart

Deliverable: Kapsicum automatically builds a knowledge graph of your world.
```

### Phase 2: Anticipation + Patterns (3 weeks)

```
Goal: Proactive intelligence — the system surfaces insights before you ask.

Tasks:
[ ] Pattern Detector: recurring behaviors, temporal patterns
[ ] Anticipation Engine: pre-meeting briefings, context suggestions
[ ] Notification integration: BEAM writes alerts, Swift shows them
[ ] Temporal awareness: "this is new" vs "this is routine"
[ ] Confidence calibration: tune thresholds via REPL
[ ] User feedback loop: "this was helpful" / "not relevant" → adjust

Deliverable: Kapsicum tells you things you need to know before you ask.
```

### Phase 3: User-Defined Agents (3 weeks)

```
Goal: Users create their own agents via UI, natural language, or REPL.

Tasks:
[ ] Clojerl defagent/defmicro-agent macros
[ ] Agent definition storage in Mnesia
[ ] Visual agent builder in Swift UI (trigger → condition → action)
[ ] Natural language → LLM generates agent code → eval in clojerl
[ ] Agent marketplace: export/import agent definitions as EDN/JSON
[ ] Safety: sandboxed execution, resource limits per agent
[ ] REPL: full agent development workflow

Deliverable: "Describe what you want" → working agent in seconds.
```

### Phase 4: Multi-Device + Server (4 weeks)

```
Goal: Agent swarm spans Mac + iPhone + optional server.

Tasks:
[ ] mobile-BEAM-OTP integration for iOS
[ ] Mnesia table replication policies (private vs shared)
[ ] Agent migration between nodes
[ ] Server deployment (same release, different config)
[ ] Sync protocol: which data crosses device boundaries
[ ] Conflict resolution for concurrent entity updates

Deliverable: Your personal AI follows you across devices.
```

## Risk Assessment

### Technical Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| SQLCipher key sharing across processes | Low | High | Pass via stdin at launch, never write to disk |
| Mnesia corruption on hard crash | Low | High | WAL mode + periodic backup to SQLite |
| Local LLM too slow for real-time | Medium | Medium | Queue + prioritize; batch non-urgent work |
| BEAM binary size too large | Low | Low | Strip debug info; ~50MB is acceptable |
| Clojerl compiler bugs | Medium | Medium | Can drop to Erlang/Elixir for specific modules |
| Entity count grows unbounded | Medium | Low | Decay Manager GCs inactive entities |
| SQLite polling latency (1-2s) | Low | Low | Acceptable; could add filesystem notify later |

### What Could Kill This

1. **Local LLM quality insufficient** — if 7B models can't reliably extract
   entities and relationships, the knowledge graph is garbage. Mitigation:
   test with multiple models, allow cloud LLM fallback.

2. **Noise ratio too high** — if every keystroke generates entities, the
   graph drowns in noise. Mitigation: aggressive filtering, confidence
   thresholds, user feedback loop.

3. **User doesn't see value from entity extraction alone** — Phase 0 must
   demonstrate clear value. If "here are the people you interact with"
   isn't compelling, the rest won't matter. Mitigation: focus Phase 0
   on the "wow" moment.

### What Makes This Defensible

No one else has:
- A local-first personal data platform (Kapsicum's capture moat)
- With a BEAM agent runtime (fault-tolerant, concurrent, distributed)
- With a Clojure REPL for live agent development
- Running AI agents on personal data
- All completely offline-capable
- With a path to multi-device via BEAM clustering

The closest competitors (Rewind, Recall, Limitless) capture and search.
They don't have a living intelligence layer. They don't have agents that
understand relationships and anticipate needs. They don't have a REPL.
They definitely don't have a path to "users build their own AI apps on
their data."
