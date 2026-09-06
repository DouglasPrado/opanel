# `spec/policies` — authorization

Authorization is server-side, contextual, and evaluated with Team / Project /
Environment explicitly loaded. It is never enforced by the UI, so it is never
tested through the UI either.

**Every new mutation needs a test here, and it needs the negative direction:**
the actor who must be refused, including a cross-team attempt. A policy spec
that only proves the owner can act proves nothing about the boundary — the
interesting case is the one that has to be denied (Annex C §7.3, AGENT_RULES
"Policies").

Empty until M01 brings the first entity with an owner. Declared now because
`lib/gates/suite_types.rb` names `policy` as a suite type and the CI pipeline
schedules it: a type with nowhere to live fails the job that runs it.
