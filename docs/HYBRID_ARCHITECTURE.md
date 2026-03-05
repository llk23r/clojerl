# Hybrid Clojerl + Elixir Architecture for BEAM Agent Systems

## Executive Summary

This document proposes a polyglot BEAM architecture for building AI
agent systems that combines Clojerl's REPL-driven development and
macro system with Elixir's production ecosystem. Both languages
compile to BEAM bytecode and interoperate natively — no FFI, no
serialization, no network boundary.

## Part 1: The Clojerl REPL — How It Actually Works

### It's a Real Clojure REPL, Not a Look-Alike

The clojerl REPL implements the full Clojure compilation pipeline on
every evaluation:

```
Input → Reader → Analyzer → Emitter → Core Erlang → BEAM Bytecode → Execute
```

This is **not interpretation**. Every expression you type in the REPL
gets compiled to actual BEAM bytecode through the same path as `make`
compilation. The difference from Clojure JVM is the backend (BEAM
bytecode instead of JVM bytecode), not the architecture.

### Compilation Pipeline Detail

```
┌──────────────────────────────────────────────────────────────┐
│                    clj_compiler:eval/1                        │
│                                                              │
│  1. clj_reader:read/1          ← Full Clojure reader        │
│     - Reads from binary or PushbackReader                    │
│     - Handles all syntax: #(), #"", #{}, #?, #:ns{}, ##Inf  │
│     - Tracks line/column for error reporting                 │
│     - Reader conditionals with :clje feature tag             │
│                                                              │
│  2. clj_analyzer:analyze/1     ← Semantic analysis           │
│     - Symbol resolution (namespaces, vars, locals)           │
│     - Macro expansion                                        │
│     - Special form handling                                  │
│     - Type inference where possible                          │
│                                                              │
│  3. clj_emitter:emit/1         ← Core Erlang generation     │
│     - Generates Core Erlang AST (cerl)                       │
│     - Handles def, fn, protocols, records                    │
│     - Module generation with proper exports                  │
│                                                              │
│  4. core_eval:exprs/1          ← BEAM bytecode execution     │
│     - Compiles Core Erlang to BEAM bytecode                  │
│     - Loads into VM                                          │
│     - Executes and returns result                            │
│                                                              │
│  Each eval spawns in a monitored process for isolation.      │
└──────────────────────────────────────────────────────────────┘
```

### REPL Features

| Feature | Status | Implementation |
|---------|--------|----------------|
| `*1`, `*2`, `*3` (result history) | Yes | Defined in core.clje, bound per-session |
| `*e` (last exception) | Yes | Bound in `with-bindings` |
| `*stacktrace*` | Yes | BEAM stacktrace capture |
| Multi-line input | Yes | Via `PushbackReader` buffering |
| `doc`, `source`, `dir` | Yes | In `clojure.repl` namespace |
| `find-doc`, `apropos` | Yes | Pattern-based search |
| Socket REPL | Yes | `clojure.core.server/start-server` — TCP REPL |
| Tab completion | No | Relies on external `rlwrap` |
| Command history | No | Relies on external `rlwrap` |
| nREPL protocol | No | Only raw socket REPL |
| Middleware system | No | No pluggable middleware hooks |

### What This Means for Agent Development

The REPL compiles to real BEAM bytecode, which means:

1. **Redefine functions in a running system** — `defn` replaces the
   module function in the BEAM code server. All processes calling that
   function immediately see the new version.

2. **Inspect live process state** — since clojerl shares the BEAM,
   you can call `erlang/process_info` on any process, inspect ETS
   tables, query supervisors.

3. **Hot-swap agent behavior** — redefine a tool function, and the
   next time an agent calls it, it gets the new version. No restart,
   no redeploy.

4. **Connect to remote nodes** — the socket REPL lets you connect to
   a running production node and inspect/modify agent behavior live.

## Part 2: BEAM Polyglot Interop

### How It Works

All BEAM languages compile to `.beam` files containing bytecode for
the BEAM virtual machine. The VM doesn't know or care which language
produced the file. Function calls between modules are the same
regardless of source language.

```
Clojerl (.clje) ──compile──→ .beam ──┐
                                     ├──→ Same BEAM VM
Elixir  (.ex)   ──compile──→ .beam ──┤    Same process space
                                     │    Same message passing
Erlang  (.erl)  ──compile──→ .beam ──┘    Zero-cost interop
```

### Calling Conventions

**Clojerl calling Erlang** (native):
```clojure
;; Module/function syntax — same as Erlang calls
(lists/reverse #erl(1 2 3))
(ets/new :my_table #erl(:set :public))
(gen_server/call pid :get_state)
```

**Clojerl calling Elixir** (prefix with `Elixir.`):
```clojure
;; Elixir modules have an implicit Elixir. prefix on BEAM
(Elixir.Jason/encode {:hello "world"})
(Elixir.Req/get "https://api.example.com/data")
(Elixir.MyApp.AgentSupervisor/start_agent agent-spec)
```

**Elixir calling Clojerl** (standard module call):
```elixir
# Clojerl modules are standard BEAM modules
:clojure.core.eval(some_form)
:"agents.core".define_agent(spec)
:"agents.tools".register_tool(:web_search, &MyApp.Tools.web_search/1)
```

### Proven Precedent

- **Gleam + Elixir**: The `mix_gleam` plugin compiles `.gleam` files
  inside Mix projects. Real projects use this (e.g., Gleam inside
  Phoenix). Same pattern needed for Clojerl.
- **EMQX**: Major MQTT broker builds its Erlang multi-application
  system with Mix managing rebar3 dependencies.
- **Clojerl on Hex.pm**: Published as `clojerl` v0.9.0. Mix projects
  can already depend on it — Mix uses rebar3 to compile it
  automatically.

### What Doesn't Exist Yet

- **`mix_clojerl` compiler plugin** — analogous to `mix_gleam`. Would
  let Mix compile `.clje` files alongside `.ex` files. Needs to be
  built (estimated 2-3 days based on `mix_gleam` as template).
- **No known hybrid Clojerl+Elixir project** — this would be the
  first. The mechanics are proven, the integration is not.

## Part 3: Proposed Architecture

### Directory Structure

```
agent_framework/
├── mix.exs                          # Mix manages the project
├── config/
│   └── config.exs                   # Standard Elixir config
├── lib/
│   ├── agent_framework/
│   │   ├── application.ex           # OTP application
│   │   ├── supervisor.ex            # Top-level supervisor
│   │   ├── agent_supervisor.ex      # DynamicSupervisor for agents
│   │   ├── web/                     # Phoenix LiveView dashboard
│   │   │   ├── router.ex
│   │   │   ├── agent_live.ex        # Live agent monitoring
│   │   │   └── repl_live.ex         # Web-based REPL
│   │   ├── http.ex                  # HTTP client (Req)
│   │   ├── llm.ex                   # LLM API client
│   │   └── store.ex                 # ETS/Mnesia state store
│   └── agent_framework.ex           # Public API
├── clje/
│   ├── agents/
│   │   ├── core.clje                # Agent definition DSL
│   │   ├── tools.clje               # Tool protocol and registry
│   │   ├── loop.clje                # Agent execution loop
│   │   └── inspect.clje             # REPL inspection utilities
│   └── dsl/
│       ├── defagent.clje            # defagent macro
│       └── deftool.clje             # deftool macro
├── test/
│   ├── elixir/                      # ExUnit tests
│   └── clje/                        # clojure.test tests
└── rel/
    └── env.sh.eex                   # Release configuration
```

### Layer Responsibilities

```
┌─────────────────────────────────────────────────────────┐
│                    Developer Interface                    │
│                                                         │
│  Clojerl REPL ←──── Interactive agent development       │
│  Phoenix UI  ←──── Dashboard, monitoring, web REPL      │
├─────────────────────────────────────────────────────────┤
│                    Agent Layer (Clojerl)                  │
│                                                         │
│  defagent macro    ← Declarative agent definitions      │
│  deftool macro     ← Tool definitions as data           │
│  Agent loop        ← Think → Act → Observe cycle        │
│  Code-as-data      ← Agents can inspect/modify behavior │
├─────────────────────────────────────────────────────────┤
│                 Infrastructure (Elixir)                   │
│                                                         │
│  DynamicSupervisor ← Agent process lifecycle            │
│  Req / Finch       ← HTTP for LLM APIs                  │
│  Jason             ← JSON encoding/decoding              │
│  Phoenix PubSub    ← Agent-to-agent communication        │
│  ETS / Mnesia      ← State persistence                   │
│  Telemetry         ← Metrics and tracing                 │
├─────────────────────────────────────────────────────────┤
│                      BEAM VM                             │
│                                                         │
│  Processes, schedulers, distribution, hot code loading   │
└─────────────────────────────────────────────────────────┘
```

### Data Flow Example: Agent Executing a Tool

```
1. User defines agent in REPL (Clojerl):
   (defagent researcher
     :model "claude-sonnet-4-20250514"
     :tools [(web-search) (summarize)])

2. Agent process spawned (Elixir supervisor manages it):
   AgentSupervisor.start_child(:"agents.core", :start, [spec])

3. Agent receives task (BEAM message passing):
   (receive* [[:task query] (think-and-act query)])

4. Agent decides to call web-search tool (Clojerl):
   (invoke-tool :web-search {:query "BEAM polyglot"})

5. Tool calls HTTP API (Elixir infrastructure):
   (Elixir.AgentFramework.Http/search query)
   → Req.get!("https://api.search.com/...", ...)

6. Result flows back through Clojerl agent loop.

7. Developer inspects in REPL:
   clje.user=> (agent-messages :researcher)
   [{:role :user :content "Research BEAM..."}
    {:role :assistant :tool_calls [...]}
    {:role :tool :content "Results: ..."}]
```

### What the Clojerl Macros Enable

This is the part Elixir cannot replicate:

```clojure
;; Agent definition is DATA, not just code
(defagent researcher
  :model "claude-sonnet-4-20250514"
  :system "You are a research assistant."
  :tools [(web-search {:max-results 5})
          (summarize {:max-length 500})]
  :on-error :retry
  :max-retries 3)

;; This macro expands to:
;; 1. A gen_server module for the agent process
;; 2. A data structure describing the agent (inspectable)
;; 3. Registration in the agent registry
;; 4. Tool binding and validation

;; Because it's data, you can do this at runtime:
(def new-agent
  (assoc (agent-spec :researcher)
         :tools (conj (:tools (agent-spec :researcher))
                      (code-interpreter))))

;; Or this in the REPL (live, no restart):
(redefine-tool :researcher :summarize
  (fn [text opts]
    (let [result (Elixir.AgentFramework.LLM/complete
                   {:prompt (str "Summarize: " text)
                    :max-tokens (:max-length opts)})]
      (:content result))))
```

In Elixir, you'd need to restart the process or build a complex
callback replacement system. In Clojerl, `defn` just replaces the
function in the code server — every process sees the new version
immediately.

## Part 4: Implementation Roadmap

### Phase 0: Foundation (1-2 weeks)

- [ ] Build `mix_clojerl` compiler plugin (based on `mix_gleam`)
- [ ] Verify bidirectional Elixir ↔ Clojerl calls in a test project
- [ ] Establish data conversion conventions (when to use `#erl()`)

### Phase 1: Core Agent Loop (2-3 weeks)

- [ ] `defagent` macro — agent definition DSL
- [ ] `deftool` macro — tool definition protocol
- [ ] Agent gen_server process (Clojerl, supervised by Elixir)
- [ ] LLM client (Elixir side, calling Claude/OpenAI APIs)
- [ ] Basic think → act → observe loop

### Phase 2: REPL Tooling (1-2 weeks)

- [ ] `agent-state`, `agent-messages` inspection functions
- [ ] `redefine-tool` for live tool replacement
- [ ] Socket REPL with agent-aware helpers
- [ ] Connect-to-running-node workflow

### Phase 3: Observability (2-3 weeks)

- [ ] Phoenix LiveView dashboard
- [ ] Real-time agent message stream
- [ ] Tool call visualization
- [ ] Web-based REPL (LiveView terminal)
- [ ] Telemetry integration for metrics

### Phase 4: Distribution (2-3 weeks)

- [ ] Multi-node agent deployment
- [ ] Agent migration between nodes
- [ ] Distributed tool registry
- [ ] Cluster-aware supervision

## Part 5: Risk Assessment

### Technical Risks

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| `mix_clojerl` plugin is harder than expected | Medium | Fallback: pre-compile clojerl with rebar3, include .beam files |
| Data conversion overhead (Clojerl maps ↔ Elixir maps) | Low | Both use Erlang maps internally; conversion is zero-cost for most types |
| Clojerl compilation speed for large agent definitions | Medium | Pre-compile stable code; use REPL only for development |
| Clojerl bugs block agent development | Medium | Can always drop to Erlang/Elixir for specific modules |
| Community/maintenance risk (single maintainer) | High | Fork already established; we maintain our own |

### What Could Kill This

1. **Clojerl compiler bugs in edge cases** — we're deep in the
   compiler now and can fix these, but they could be time sinks.
2. **Performance** — if Clojerl-compiled code is significantly slower
   than Elixir for hot paths, agents would suffer. Needs benchmarking.
3. **Developer onboarding** — requiring knowledge of both Clojure and
   Elixir is a high bar. The REPL needs to be good enough that the
   Elixir layer is invisible to agent developers.

### What Makes This Worth It

The REPL changes the development loop from:

```
Traditional:  Write code → Compile → Deploy → Test → Check logs → Repeat
REPL-driven:  Connect to system → Inspect state → Modify behavior → See result
```

For AI agents, where behavior is emergent and unpredictable, the
ability to observe and modify a running agent interactively is not a
nice-to-have — it's a fundamental development paradigm shift.
