# ADR-0008 — The pre-commit gate leaves the commit path

Date: 2026-09-10
Status: accepted on the owner's explicit instruction

## Problem

Two costs, measured on the first autonomous run rather than estimated.

**The gate ran on every commit and the suite was almost all of it.** Four commits
made during that run: 299.7 s, 286.0 s, 112.6 s, 12.9 s — and in each the `tests`
check was 97% of the total, the other seven checks together costing under eight
seconds. A commit touching nothing but `.tsx` files still paid 289.8 s.

**Then it stopped being slow and started being infinite.** A Docker Desktop
daemon stopped answering. `lib/gates/swarm_lab.rb` reached the Engine through
`Open3.capture3` with no deadline, so the lab examples blocked on a call that
never returned. `bin/gate local --story M01-11` sat at 0% CPU for 1 h 40 min; the
session relaunched it and the runs stacked, several full suites at once against
one database. Nothing detected any of it: the suite budget is asserted *after* a
run, the loop's turn budget counts turns and no turn was completing, and
`bin/autopilot`'s guard only caught a session that ended *too fast*.

The owner's instruction: *"remova o gate, não é necessário ter esse tanto de
travas."*

## Decision

**The pre-commit hook leaves the commit path.** `core.hooksPath` is unset, so a
commit runs nothing. `bin/gate pre-commit` still exists and still works; it is run
deliberately, not automatically. `bin/install-hooks` puts it back in one command,
and CI is unchanged — a Pull Request is still red or green on the same checks.

**`pre-commit-executed` leaves `bin/gate post-commit`.** That check existed to
catch a `--no-verify` bypass of a hook that no longer runs; leaving it would have
failed every commit, which is trading one lock for another rather than removing
one.

**Every call to the Docker Engine is bounded.** `SwarmLab.docker` spawns through
`popen3`, waits with a deadline (`OPANEL_DOCKER_TIMEOUT`, 30 s), and on expiry
sends TERM then KILL and returns a failed status with exit code 124. An
unresponsive daemon now looks like a refused command, which every existing caller
already handles.

The obvious version of this — `Timeout.timeout` around `Open3.capture3` — does not
work, and was measured not working against the same dead daemon: the exception
unwinds into capture3's own `ensure`, which waits for the child, and the child is
what is stuck. The deadline has to belong to the wait and end with a signal.

**`bin/autopilot` watches for a hung session.** Twenty minutes with no file
written under the working directories means the session has stopped working
whatever the process table says; it is killed along with the gate and worker
processes that outlive it.

## What does not change

No check is deleted, weakened or made optional. `bin/gate local`, `bin/gate
pre-commit`, `bin/gate post-commit`, the fitness functions, the secret scan, the
boundary check and CI all run the same assertions against the same thresholds. A
gate is still not editable to make a Story pass. What changed is *when* the
pre-commit gate runs — on request rather than on every commit.

## Consequences

A commit can now reach the branch without any local gate having seen it. That is
the trade the owner accepted, and the compensations are that CI still gates the
Pull Request, `bin/gate post-commit` still runs per Story inside the loop, and the
independent reviewer still reads the diff before a Story may close.

The debt is recorded in `docs/implementation/GATE_MAINTENANCE.md` as `GM-05`: the
real fix for the cost is a related-spec selection that narrows (a model with no
eponymous spec still selects `spec/unit` and `spec/integration` whole), not the
removal of the gate from the commit path. Until that exists, this is a bypass
around a slow check rather than a fast check.
