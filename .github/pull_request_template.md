## What this changes

<!-- The Story or ADR this implements, and what a reviewer should look at first. -->

Story / ADR:

## Merge Gate — Annex I §15.2

`bin/merge-gate` runs every one of these and uses the exit code. The boxes are
here so a human reads the list; **ticking one proves nothing** and the gate does
not read them.

- [ ] base branch current
- [ ] CI green — every required job, by name
- [ ] Critical = 0
- [ ] High = 0
- [ ] migration rollout safe
- [ ] rollback / forward-fix known
- [ ] Story / Milestone status consistent
- [ ] documentation or ADR updated if a contract changed
- [ ] required approvals satisfied

## Evidence

<!-- Commands run and their exit codes. "Tests pass" is a claim; the output is
     evidence (AGENT_RULES, "Evidence over confidence"). -->

```
```
