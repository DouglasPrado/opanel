---
title: "ADR-0005 — The Swarm Executor stays in the Control Plane process for M01"
status: "accepted"
date: "2026-09-10"
---

# ADR-0005 — The Swarm Executor stays in the Control Plane process for M01

## Context

`docs/architecture/07-internal-control-plane.md` §2.2 draws the privileged Docker
boundary as a **separate process**:

```text
API / Workers --[internal authenticated RPC]--> Swarm Executor --[docker.sock]--> Docker Engine
Public API ---X---> docker.sock
```

with §21 adding "RPC interno autenticado e autorizado por identidade de serviço"
and replicas of the executor for availability.

`M01-09` delivered the executor as a Ruby module in `app/executors/`, inside the
single Rails process that also serves `app/controllers/**`. There is no second
process, no Procfile entry, no RPC. That is the shape the Story's own §Scope
asked for, and it is not the shape the architecture draws — recorded as
**SC-19** in `docs/implementation/SPEC_CONFLICTS.md` rather than decided
silently, which is why `M01-09` sat in `BLOCKED_FOR_PRODUCT_DECISION` and why
every Story from `M01-10` to `M01-23` was unreachable behind it.

The independent review's Critical finding is accurate and is the reason this
record exists: **remote code execution anywhere in the Control Plane process
reaches `SwarmExecutor` and `EngineClient` with no RPC hop to defeat.** A
separate process does not remove that risk; it forces an attacker to also forge
a service identity and cross a network boundary to reach the socket.

## Decision

For **M01 only**, the Swarm Executor is a module inside the Control Plane
process. `docs/architecture/07-internal-control-plane.md` §2.2 remains the target
architecture and is not edited to match the implementation.

### What M01 relies on instead of the process boundary

These are the compensating controls. They exist and are tested; they are not
promises:

- **No route reaches it.** No controller in `app/executors/`, no executor in
  `app/controllers/`, no route whose path or controller names one, and no
  published port in any compose or stack file — `spec/security/executor_isolation_spec.rb` (AC10).
- **No generic execution primitive.** No `exec`, `system`, `spawn`, backticks or
  `public_send` anywhere under `app/executors/`, asserted against a control that
  proves the search recognises what it forbids (AC3).
- **A closed allowlist of eleven typed operations**, pinned by name, so a twelfth
  is a reviewed diff and not a call site.
- **One transport, three verbs.** `EngineClient#get/post/delete` over a unix
  socket resolved from the daemon's own context, refused unless local
  (`DAEMON_NOT_LOCAL`).
- **AF-01 and AF-02**, evaluated against a planted violation in a fixture tree
  rather than against the absence of violations in a clean one.
- **Redaction** of `X-Registry-Auth` and `SWMTKN` at every log and error
  boundary, with the "what did not change" control.

### The risk this accepts, stated plainly

A vulnerability in any part of the Control Plane process — a deserialization
bug, a template injection, a compromised gem — reaches the Docker socket through
the executor's typed operations. Those operations cannot run an arbitrary
command, but they can create, update and remove Services and Networks, which is
sufficient to run arbitrary containers on the cluster. This is a Tier-0 exposure
(Annex C §8, T01) accepted for a single-node development Milestone and for no
other reason.

### When it stops being acceptable

The extraction happens **before whichever of these comes first**:

1. the platform accepts a second node — the point at which the executor's blast
   radius stops being one machine the operator already controls;
2. the public API (`MCP`, CLI, integrations) is served from the same process as
   the executor to any caller outside the operator's own network;
3. the first workload not authored by the operator runs on the cluster.

None of the three is inside M01's scope. The Story that performs the extraction
is **`M02-EXEC-SPLIT`**, to be written when M02 is planned, and it carries: a
second process with its own minimal image, RPC authenticated by service
identity, a private network, supervision and restart policy, and the removal of
`app/executors/` from the Control Plane image.

### The first trigger is a check, not a sentence

A deadline written only in prose is a deadline nobody trips over, and that is
how a temporary exception becomes a permanent one. Trigger 1 is mechanical:
**`M01-10` (node registration) carries a fitness function that fails when more
than one node is registered while `app/executors/` is still loaded in the
Control Plane process.** The Story that makes a second node possible is the
Story that makes this ADR expire, and the gate says so.

Triggers 2 and 3 have no equivalent check today — they are decisions a human
makes, not states the repository can observe — so they stay as review
obligations, named here so a reviewer can hold them.

## Consequences

- `M01-09` closes with SC-19 resolved by this record. `M01-10` through `M01-23`
  become reachable.
- `docs/decisions/pending-documentation-updates.md` carries the divergence: doc
  07 §2.2 describes the target, not the M01 implementation.
- A reviewer who finds the executor in-process during M01 should find this ADR
  first; a reviewer who finds it in-process after any of the three triggers above
  has a Critical finding, and this record is the evidence that it was always a
  deadline and never a permanent exception.
- This ADR does **not** license any further privilege inside the process: the
  allowlist, the absence of an exec primitive and the fitness functions remain
  the boundary, and widening any of them needs its own decision.
