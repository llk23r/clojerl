# clojerl

![Build](https://github.com/clojerl/clojerl/workflows/Build/badge.svg)
[![Hex.pm](https://img.shields.io/hexpm/v/clojerl.svg)](https://hex.pm/packages/clojerl)

Clojure implemented on the Erlang VM. Includes portable features from
Clojure 1.10, 1.11, and 1.12.

## Building

Building `clojerl` requires *Erlang/OTP 24+* (tested up to OTP 28)
and [*rebar3*][rebar3].

    git clone https://github.com/clojerl/clojerl
    cd clojerl
    make

On Windows:

    git clone https://github.com/clojerl/clojerl
    cd clojerl
    rebar3 clojerl compile

## Getting Started

### Documentation and Resources

There is more information regarding Clojerl in [clojerl.io][clojerl], where you
can find what [features][features] does Clojerl include and [how it differs from
Clojure][diff-with-clojure].

### Online REPL

To try it out and get a sense of what you can do, you can visit
[Try Clojerl][try-clojerl].

## Docker REPL

To quickly try out `clojerl` via docker you can make use of the docker
image like so:

```
docker pull clojerl/clojerl
docker run -it clojerl/clojerl
```

Then you should be able to see the prompt:

```clojure
Clojure 0.9.0
clje.user=>
```


### Local REPL

Running `make repl` (on Windows first run `rebar3 clojerl compile` and
then `bin/clje.bat`) will start the REPL and show its prompt:

    Clojure 0.9.0
    clje.user=>

From the REPL it's possible to start evaluating Clojure expressions:

    clje.user=> (map inc (range 10))
    (1 2 3 4 5 6 7 8 9 10)
    clje.user=> (doc map)
    -------------------------
    clojure.core/map
    ([f] [f coll] [f c1 c2] [f c1 c2 c3] [f c1 c2 c3 & colls])
      Returns a lazy sequence consisting of the result of applying f to
      the set of first items of each coll, followed by applying f to the
      set of second items in each coll, until any one of the colls is
      exhausted.  Any remaining items in other colls are ignored. Function
      f should accept number-of-colls arguments. Returns a transducer when
      no collection is provided.
    nil
    clje.user=> (doc inc)
    -------------------------
    clojure.core/inc
    ([x])
      Returns a number one greater than num.
    nil
    clje.user=>

### Code Examples

There are some very basic examples in the [scripts/examples][examples]
directory. These are meant to be references on how special forms in
Clojure on the BEAM are used and how they sometimes differ from Clojure
JVM.

### Web Application Example

For a very basic example of a web project please check the
[example-web-app][example-web-app] repository.

### Building Your Own App

The build tool for Clojerl is the [`rebar3_clojerl`][rebar3_clojerl]
plugin. [`rebar3`][rebar3] is the official build tool in the Erlang
community.

The plugin provides helpful commands to:

- Build a basic directory scaffolding for a new project
- Compile
- Run tests
- Start a REPL

For more information on how to use this plugin please check the
documentation in [`rebar3_clojerl`][rebar3_clojerl].

## Capability Matrix

Clojerl brings Clojure's expressiveness to the BEAM, but not every
feature from either world maps directly. The tables below show exactly
what works, what doesn't, and what's replaced by a BEAM-native
equivalent.

### Clojerl vs Clojure JVM

#### Concurrency & State

| Feature | Clojure JVM | Clojerl | Notes |
|---------|:-----------:|:-------:|-------|
| Atoms | Yes | **Yes** | Full support |
| Agents | Yes | **Yes** | Backed by gen_server |
| Futures | Yes | **Yes** | |
| Promises | Yes | **Yes** | |
| Delays | Yes | **Yes** | |
| Dynamic vars / binding | Yes | **Yes** | |
| pmap / pcalls / pvalues | Yes | **Yes** | |
| Refs / STM / dosync | Yes | **No** | BEAM uses message-passing, not shared-memory STM |
| volatile! / vswap! / vreset! | Yes | **Replaced** | `process-val!` uses the process dictionary; `vreset!`/`vswap!` operate on ProcessVal |
| locking | Yes | **No** | JVM monitors have no BEAM equivalent |

#### Data Structures

| Feature | Clojure JVM | Clojerl | Notes |
|---------|:-----------:|:-------:|-------|
| Lists, Vectors, Maps, Sets | Yes | **Yes** | |
| Sorted maps / sorted sets | Yes | **Yes** | |
| Records (defrecord) | Yes | **Yes** | |
| Metadata | Yes | **Yes** | |
| Destructuring | Yes | **Yes** | Full support including `:or`, `:keys`, `:as` |
| Transients | Yes | **No** | `persistent!`, `transient`, `conj!`, `assoc!` not implemented |
| Ratios | Yes | **No** | `(/ 1 3)` returns `0.333...` float, not `1/3` |
| BigDecimal | Yes | **No** | `1.0M` parses but produces a regular float |
| BigInt | Yes | **Native** | BEAM has arbitrary-precision integers natively |
| PersistentQueue | Yes | **No** | |
| Java arrays | Yes | **No** | `into-array`, `aclone`, `amap`, etc. — N/A on BEAM |
| Erlang tuples | No | **Yes** | `#erl[...]`, `into-tuple`, `tuple` |
| Erlang native lists | No | **Yes** | `#erl(...)` |
| Erlang native maps | No | **Yes** | `#erl{...}` |
| Erlang binaries | No | **Yes** | `#bin[...]` |

#### Protocols, Types & Polymorphism

| Feature | Clojure JVM | Clojerl | Notes |
|---------|:-----------:|:-------:|-------|
| defprotocol / extend-type / extend-protocol | Yes | **Yes** | |
| defrecord / deftype | Yes | **Yes** | |
| reify | Yes | **Yes** | |
| Multimethods | Yes | **Yes** | |
| Hierarchies (derive/isa?) | Yes | **Yes** | |
| satisfies? | Yes | **Internal only** | Used internally but not exposed as public API |
| proxy / gen-class / gen-interface | Yes | **No** | JVM-specific |

#### Sequences & Transducers

| Feature | Clojure JVM | Clojerl | Notes |
|---------|:-----------:|:-------:|-------|
| Lazy sequences | Yes | **Yes** | Full support |
| Transducers | Yes | **Yes** | `comp`, `map`, `filter`, `into` with xforms |
| Reducers (clojure.core.reducers) | Yes | **Broken** | Namespace loads but reducer results don't implement IFn |
| Regex | Yes | **Yes** | `re-find`, `re-seq`, `re-matches`, `re-pattern` |

#### Namespaces & Libraries

| Feature | Clojure JVM | Clojerl | Notes |
|---------|:-----------:|:-------:|-------|
| clojure.string | Yes | **Yes** | |
| clojure.set | Yes | **Yes** | |
| clojure.walk | Yes | **Yes** | |
| clojure.zip | Yes | **Yes** | |
| clojure.edn | Yes | **Yes** | |
| clojure.data | Yes | **Yes** | |
| clojure.test | Yes | **Yes** | |
| clojure.pprint | Yes | **Yes** | |
| clojure.xml | Yes | **Yes** | |
| clojure.math | Yes | **Yes** | Wraps Erlang's `:math` module |
| clojure.repl | Yes | **Yes** | |
| clojure.spec.alpha | Yes | **Yes** | Via hex dependency |
| clojure.java.io | Yes | **Replaced** | `clojure.erlang.io` provides `copy`, `delete-file`, `file-open`, etc. |
| clojure.java.shell | Yes | **No** | No shell execution namespace |
| clojure.core.async | Yes | **No** | BEAM processes replace channels natively |

#### Reader & Compiler

| Feature | Clojure JVM | Clojerl | Notes |
|---------|:-----------:|:-------:|-------|
| Reader conditionals (`#?` / `#?@`) | Yes | **Yes** | Uses `:clje` feature tag |
| Namespaced maps (`#:ns{}`) | Yes | **Yes** | |
| Tagged literals (`#inst`, `#uuid`) | Yes | **Yes** | |
| `##Inf` / `##-Inf` / `##NaN` | Yes | **Yes** | Represented as atoms on BEAM (no IEEE 754 special values) |
| `:as-alias` in require | Yes | **No** | Needs compiler changes |

### Clojerl vs Elixir / Gleam (BEAM access)

#### OTP Patterns

| Feature | Elixir | Gleam | Clojerl | Notes |
|---------|:------:|:-----:|:-------:|-------|
| Spawn processes | Yes | Yes | **Yes** | `erlang/spawn`, `erlang/spawn_link` |
| Send/receive messages | Yes | Yes | **Yes** | `erlang/send`, `receive*` special form |
| GenServer | Built-in | gleam/otp | **Partial** | Used internally; `behaviours` macro exists but no high-level wrapper |
| Supervisor | Built-in | gleam/otp | **Partial** | Used internally; no declarative Clojure-friendly wrapper |
| Application | Built-in | Yes | **Partial** | `clojerl_app` exists; no user-facing macro |
| Task (supervised async) | Built-in | gleam/otp | **No** | Futures exist but no supervised Task abstraction |
| Registry | Built-in | No | **No** | |
| DynamicSupervisor | Built-in | No | **No** | |

#### Data & Interop

| Feature | Elixir | Gleam | Clojerl | Notes |
|---------|:------:|:-----:|:-------:|-------|
| ETS / DETS / Mnesia | Yes | Yes | **Yes** | Via `ets/`, `dets/`, `mnesia/` module calls |
| Process dictionary | Yes | No | **Yes** | `erlang/put`, `erlang/get` |
| Binary pattern matching | Native | Native | **Limited** | `#bin[...]` for construction; no destructuring in `case`/`let` |
| Ports | Yes | Yes | **Partial** | `erlang.Port` type wrapper; no high-level API |
| NIFs | Yes | Yes | **No** | No NIF integration (write in Erlang/C, call via interop) |
| Distribution | Yes | Yes | **Yes** | `erlang/node`, `net_kernel`, etc. |
| Hot code loading | Yes | Yes | **Partial** | BEAM supports it; no release tooling like `mix release` |
| Comprehensions | `for` | No | **Yes** | Clojure `for` macro |
| Pipe operator | `\|>` | `\|>` | **Yes** | Threading macros `->`, `->>`, `as->`, `cond->`, `some->` |

#### Tooling & Ecosystem

| Feature | Elixir | Gleam | Clojerl | Notes |
|---------|:------:|:-----:|:-------:|-------|
| Build tool | Mix | gleam build | **rebar3** | Via `rebar3_clojerl` plugin |
| Package manager | Hex | Hex | **Hex** | Publishes to hex.pm |
| REPL | IEx | No | **Yes** | `make repl` or `bin/clojerl -r` |
| Test framework | ExUnit | gleeunit | **clojure.test** | Plus Common Test |
| Type system | Dialyzer | Static types | **None** | No dialyzer integration, no type specs |
| LSP | Yes | Yes | **No** | |
| Formatter | mix format | gleam format | **No** | |
| Release packaging | mix release | gleam export | **No** | Must configure rebar3 manually |
| Web framework | Phoenix | Lustre | **No** | |
| Library ecosystem | Large | Growing | **Tiny** | Few clojerl-specific libs; Erlang libs usable via interop |

### What Clojerl Uniquely Enables

Neither JVM Clojure nor Elixir/Gleam alone provide this combination:

- **Clojure macros + BEAM processes** — Clojure's homoiconic macros
  are more powerful than Elixir's. Combined with millions of
  lightweight processes and OTP supervision.
- **Persistent data abstractions + fault tolerance** — Clojure's
  collection protocols (seqs, transducers, protocols) on top of
  BEAM's "let it crash" philosophy.
- **REPL-driven BEAM development** — More interactive than Elixir's
  IEx for exploratory programming.
- **Cross-type protocols** — Extend Clojure protocols to Erlang types
  and vice versa.

## Rationale

Erlang is a great language for building safe, reliable and scalable
systems. It provides immutable, persistent data structures
out of the box and its concurrency semantics are unequalled by any
other language.

Clojure is a Lisp and as such comes with all the goodies Lisps
provide. Apart from these Clojure also introduces powerful
abstractions such as protocols, multimethods and seqs, to name a few.

Clojure was built to simplify the development of concurrent programs
and some of its concurrency abstractions could be adapted to Erlang.
It is fair to say that combining the power of the Erlang VM with the
expressiveness of Clojure could provide an interesting, useful result
to make the lives of many programmers simpler and make the world a
happier place.

## Goals

- Interoperability as smooth as possible, just like Clojure proper and
  ClojureScript do.
- Provide most Clojure abstractions.
- Provide all Erlang abstractions and toolset.
- Include a default OTP library in Clojerl.

### Personal Goal

Learn more about Erlang (and its VM), Clojure and language
implementation.

This project is an experiment that I hope others will find useful.
Regardless of whether it becomes a fully functional implementation of
Clojure or not, I will have learned a lot along the way.

## QAs

### What is Clojerl?

Clojerl is an experimental implementation of Clojure on the Erlang VM.
Its goal is to leverage the features and abstractions of Clojure that
we love (macros, collections, seq, protocols, multimethods, metadata,
etc.), with the robustness the Erlang VM provides for building
(distributed) systems.

### Have you heard about LFE and Joxa?

Yes. LFE and Joxa were each created with very specific and different
goals in mind. LFE was born to provide a LISP syntax for Erlang. Joxa
was mainly created as a platform for creating DSLs that could take
advantage of the Erlang VM. Its syntax was inspired by Clojure but the
creators weren't interested in implementing all of Clojure's features.

### Aren't the language constructs for concurrency very different between Clojure and Erlang?

Yes, they are. On one hand Clojure provides tools to handle mutable
state in a sane way, while making a clear distinction between identity
and state through reference types. On the other, concurrency in the
Erlang VM is implemented through processes and message passing. The
idea in Clojerl is to encourage the Erlang/OTP concurrency model, but
support as many Clojure constructs as possible and as far as they make
sense in the Erlang VM.

### But... but... Rich Hickey lists [here](https://clojure.org/about/state#actors) some of the reasons why he chose not to use the actor model in Clojure.

That is not a question, but I see what you mean :). The points he
makes are of course very good. For example, when no state is shared
between processes there is some communication overhead, but this
isolation is also an advantage under a lot of circumstances. He also
mentions
[here](https://groups.google.com/forum/#!msg/clojure/Kisk_-9dFjE/_2WxSxyd1SoJ) that
building for the distributed case (a.k.a processes and message
passing) is more complex and not always necessary, so he decided to
optimise for the non-distributed case and add distribution to the
parts of the system that need it. Rich Hickey calls Erlang "quite
impressive", so my interpretation of these writings is that they are
more about exposing the rationale behind the decisions and the
trade-offs he made when designing Clojure (on the JVM), than about
disregarding the actor model.

### Will Clojerl support every single Clojure feature?

No. Some of Clojure's features are implemented by relying on the
underlying mutability of the JVM and its object system. The Erlang VM
provides very few mutability constructs and no support for defining
new types. This makes it very hard or nearly impossible to port some
features into Clojerl's implementation.

### Can I reuse existing Clojure(Script) libraries?

Yes, but they will need to be ported, just like for ClojureScript. In
fact, most of Clojure's core namespaces were ported from the original
.clj files in the Clojure JVM repository.

## Discussion

Join the conversation in the [Clojerl][clojerl-mailing-list] mailing
list or in the [`#clojerl` Slack channel][clojerl-slack]!

You can also find news and updates through [@clojerl][clojerl-twitter].
Or if you have any questions you can find me [@jfacorro][jfacorro-twitter] or lurking
on [Clojure](https://groups.google.com/forum/?hl=en#!forum/clojure)'s
and
[Erlang](https://groups.google.com/forum/?hl=en#!forum/erlang-programming)'s
mailing lists.

Any feedback, comment and/or suggestion is welcome!

[rebar3]: https://github.com/erlang/rebar3
[try-clojerl]: http://try.clojerl.io/
[examples]: scripts/examples
[example-web-app]: https://github.com/clojerl/example-web-app/
[rebar3_clojerl]:https://github.com/clojerl/rebar3_clojerl
[clojerl]: http://clojerl.io/
[features]: http://clojerl.io/available-features
[diff-with-clojure]: http://clojerl.io/differences-with-clojure
[clojerl-mailing-list]: https://groups.google.com/forum/#!forum/clojerl
[clojerl-slack]: https://erlanger.slack.com
[clojerl-twitter]: https://twitter.com/clojerl
[jfacorro-twitter]: https://twitter.com/jfacorro
