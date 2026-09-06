# `spec/contracts` — external contracts

The shape of what Opanel promises to something outside itself: the public API,
event payloads, provider adapters and the schemas they exchange.

A contract test fails when the *shape* changes, which is the point — the caller
cannot be asked to re-read the code. Annex I §15.1 requires this suite green
whenever an endpoint, an event or a provider changed.

Empty until the first contract exists (M02 for the public API, M05 for events).
Declared now because `lib/gates/suite_types.rb` names `contract` as a suite type
and the CI pipeline schedules it: a type with nowhere to live fails the job that
runs it.
