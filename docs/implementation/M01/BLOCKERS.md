---
title: "M01 — Blockers"
milestone: "M01"
type: "blockers"
---

# M01 — Blockers

Two blocks, both needing the same person: whoever may commit outside a loop run.
Neither is a Story that failed to converge — both are the loop refusing to let the
implementer touch the machinery that judges it, which is the rule working, not a
bug in the Story.

Per `docs/goals/G02-run-m01.md` the run stops here rather than starting a domain
Story: the Goal orders the gate change committed **on its own, before any domain
Story**, and that commit is exactly what is blocked.

---

## M01 — milestone-wide: `run-start` writes a key the pack contract rejects

- **Qualificador:** `BLOCKED_FOR_HUMAN_APPROVAL`
- **Data:** `2026-09-09`
- **Tentativas:** 1 (no second strategy exists that the implementer may take —
  see "Why this is a block")

### Diagnóstico reproduzível

```text
$ tools/opanel-loop/scripts/tasks.sh docs/implementation/M01 run-start
run started 2026-09-09T02:47:04Z

$ bin/pack validate
docs/implementation/M01/tasks.json
  SCHEMA             (root) carries the unknown property `run`
                     config/pack/tasks.schema.json is the contract, and this is it being applied

pack: FAIL (1 violation(s) in 15 milestone(s))
exit 1
```

Root cause, located in the commit that introduced it:

`9806315` (`feat(loop): gate the handoff…`, Story `M01-90`) added `cmd_run_start`
and `cmd_turns` to `tools/opanel-loop/scripts/tasks.sh`, which write a root-level
object:

```
tasks.sh:169   '.run = {startedAt: $now, turns: 0,
tasks.sh:170              doneAtStart: ([.stories[] | select(.status == "done")] | length)}'
tasks.sh:179   '.run.turns = ((.run.turns // 0) + 1)'
```

The same commit extended `config/pack/tasks.schema.json` — it added the per-Story
`review` and `reason` properties — but not a root-level `run`. The root object is
`"additionalProperties": false` with exactly five properties: `milestone`, `name`,
`status`, `dependencies`, `stories`.

`M00/tasks.json` has no `run` key, so nothing exercised this before: `run-start`
is called once, at the start of a run, and this is the first run since `9806315`.

### Why this is a block and not a bug to fix

The two ways to fix it are both closed to the implementer:

1. **Change `tools/opanel-loop/scripts/tasks.sh`.** `CLAUDE.md` §Fixed Role
   forbids modifying the loop — "its scripts, schemas, hooks, agents or skills" —
   while executing a Milestone. Outside a run, on human instruction, it is
   ordinary work in its own commit.
2. **Add `run` to `config/pack/tasks.schema.json`.** That is the pack contract a
   gate enforces. Widening a contract so a red check goes green is what
   `AGENT_RULES` §Quality Gates forbids without its own Story or ADR — and here
   the red check is telling the truth.

Deleting `.run` from `tasks.json` is not a third option: the Stop hook calls
`tasks.sh turns increment` on **every** turn (`stop-gate.sh:47`), and
`.run.turns = ((.run.turns // 0) + 1)` recreates the key. The violation returns at
the end of whatever turn removed it.

### Blast radius

- `GOAL.md` completion condition 4 — `bin/pack validate` exit 0 — cannot be met
  while a run is active.
- `spec/gates/pack_spec.rb` ("validates every Milestone of this repository") is
  red, which makes the `tests` check of `bin/gate local` red for **any** Story on
  this branch. `main` is at `219e16c` and holds only a README, so `bin/test
  --changed` resolves against a merge base of the initial commit and selects
  essentially the whole suite — `pack_spec.rb` included, for every Story.
- Therefore no Story can be closed with a green local gate, and
  `bin/stop-gate M01` cannot reach `ok`.

### O que destravaria

- One decision, by the repository owner, in its own commit outside this run:
  either add a `run` object to `config/pack/tasks.schema.json`, or move the
  loop's run state out of `tasks.json` into a file the pack contract does not
  govern (e.g. `review-state.json`, which already holds run-scoped state such as
  `reviewAttempt` and the budgets).
- The second is the better shape — `tasks.json` is the Implementation Pack's
  durable record and `run` is per-run bookkeeping — but it is a contract change
  either way, so it is the owner's call, not the implementer's.

### Trabalho independente que continuou

None, deliberately. `G02` requires the gate/loop change to be committed alone
before any domain Story, and both available gate commits are blocked. Starting
`M01-01` ahead of them would violate the Goal's stated order and would close
Stories against a gate that is red for a reason unrelated to them.

---

## M01-91 — Bring the local gate back inside its budget

- **Qualificador:** `BLOCKED_FOR_HUMAN_APPROVAL`
- **Data:** `2026-09-09`
- **Tentativas:** 2

### Diagnóstico reproduzível

The Story's remaining scope is two lines in `bin/gate`'s `local` case. Every
attempt to edit that file is refused by the loop's own PreToolUse guard:

```text
$ echo '{"tool_input":{"file_path":"'"$PWD"'/bin/gate"}}' \
    | CLAUDE_PROJECT_DIR="$PWD" tools/opanel-loop/hooks/scripts/guard-edit.sh
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny",
 "permissionDecisionReason":"This is a quality gate. Failing a gate means fixing
 the implementation — a gate edited to pass protects nothing."}}
```

The builder attempted the edit twice through the `Edit` tool and received that
message verbatim both times. `guard-edit.sh:40` matches
`^bin/(gate|stop-gate|merge-gate)` and denies unconditionally — it has no notion
of a Story, so it cannot distinguish the Story that **declares** `bin/gate` in
`boundaries.yml` from any other Story trying to edit its way past a red check.

### Why this is a block and not a bug to fix

`docs/goals/G02-run-m01.md` authorises this Story by name to edit `bin/gate`, and
`M01-91` declares it in `docs/implementation/M01/boundaries.yml`. The guard is
nonetheless correct to be unconditional today, and the instruction was explicit:
do not look for a way around it. No workaround was attempted — no `Write`, no
`sed`/`perl` rewrite, no hook edit, no `--no-verify`, no sandbox override.

This is the same reason the first half of this Story was delivered
**interactively** by the repository owner, in `70c7f7e` and `3d05b73`, rather
than by the loop. The Story file records that; it did not record that the second
half has the same obstacle.

### What was delivered anyway

The defect the Story exists to fix — the suite not being parallel-safe — is
fixed and evidenced, inside the declared boundary. The root cause was not the one
the Story's text predicted: the five red examples are not four logging examples
plus a scan, they are two shared-working-tree races. See
`reports/M01-91.md` for the reproduction, the fix
(`spec/support/repository_lock.rb`), and the repeated `--parallel` runs.

Blocked criteria: **AC1** (under 90 s) and **AC5** (`bin/gate local` runs
`bin/test --changed --parallel`), plus the `local`-specific half of Scope item 3
(diff-scoping the secret scan).

### What the independent review found — `review/M01-91.md`, `COUNTS 1 2 2 0`

`Critical = 1`, `High = 2`. The Story cannot be `done`, and one of those findings
is the reason this block is not merely about a denied edit.

- **F-1, Critical — AC1 is not reachable even once the edit is unblocked.** The
  reviewer reproduced the timing independently, twice: `bin/test --parallel` over
  the five affected files finished in **145.4 s** and **142.9 s** (169 examples,
  0 failures both runs). The Story's own "Já entregue" section projected 88 s,
  measured *before* the five collisions were root-caused. With the mutual
  exclusion correctness now requires, `security_scan_spec.rb`'s ~85 s whole-tree
  scan sits on the critical path and can no longer overlap a planted probe — so
  the `tests` check alone exceeds the 90 s **total** gate budget before
  `format`/`lint`/`typecheck`/`security` add their ~11 s. **The 90 s ceiling is a
  property of the Story that the measurement has disproved**, not something the
  implementation failed to reach.
- **F-2, High — the AC7 budget spec asserts only against synthetic hashes**, so it
  cannot fail on a real regression; today's actual state (`--parallel` missing
  from `bin/gate`) produces no red anywhere. This is *also* waiting on the same
  human decision as F-1: a spec that asserts the live gate "under its ceiling"
  cannot be written until the ceiling has a defensible number.
- **F-3, High — the Required Test "one rspec process per gate run" has no
  automated check**, only a one-off `ps aux` observation. This one is independent
  of the ceiling and is straightforwardly fixable.
- **F-4, Medium** — the report marks AC1 `[x]` while its own sentence says "Not
  met; blocked". Left uncorrected deliberately: the implementer's report is its
  own artifact, and the review already records the contradiction.
- **F-5, Medium** — the single global `flock` is correct today (verified twice,
  no deadlock path) but is now the serialization bottleneck working against the
  Story's own goal.

What held: the `RepositoryLock` fix is sound, no assertion in any touched spec was
weakened, narrowed, skipped or removed (the reviewer compared every diff hunk —
strictly wrap-in-lock), and nothing fell outside the declared boundary.

### Why no third attempt was spent

Attempt 2 of 3. A third builder run could close F-3 and F-4, but not F-1 or F-2 —
both wait on the same decision only the owner can make, and that decision may
change the ceiling F-2's spec is supposed to assert. Building a live-budget
assertion against a number that is about to move is work thrown away. The Story
stops here with `Critical = 1` and a diagnosis, rather than converging on
appearance.

### The work is uncommitted, and deliberately so

`git status` is dirty. These files carry the parallel-safety fix and are **not**
committed:

```text
 M spec/gates/ci_pipeline_spec.rb
 M spec/gates/gate_scripts_spec.rb
 M spec/security/production_logging_spec.rb
 M spec/security/security_scan_spec.rb
?? spec/support/repository_lock.rb
?? spec/gates/gate_budget_spec.rb
?? docs/implementation/M01/boundaries.yml
?? docs/implementation/M01/reports/M01-91.md
```

Two reasons, both of them rules rather than caution:

1. `tasks.sh set M01-91 done` is refused with `Critical = 1`, and the commit step
   of the loop follows `done`. A Story with an open Critical finding is not a
   checkpoint.
2. `bin/gate pre-commit` cannot be green. It runs `bin/test --changed --fast`;
   `gate_files` (`bin/_gate_lib.sh:286`) resolves `changed` against
   `git merge-base HEAD main`, `main` is `219e16c` — a README — so the changed set
   is effectively the whole repository, `spec/gates/pack_spec.rb` included, and
   that spec is red for the milestone-wide reason above. `pack_spec.rb` is not
   tagged `:slow`, so `--fast` does not drop it.

`OPANEL_GATE_BASE` would narrow the gate's base commit and make it green. That is
narrowing a gate to pass it, so it was not used.

Nothing here is lost — the tree is intact and the diff is reviewed. It needs a
commit by someone who may make one over a gate that is red for a cause outside
the Story, or the milestone-wide block cleared first, which makes the gate green
on its own.

### O que destravaria

- The repository owner applies the two-line change in `bin/gate`'s `local` case
  interactively — `bin/test --changed` → `bin/test --changed --parallel`, and the
  adjoining comment, which currently says the parallel-safety fix is still owed;
- **or** teaches `guard-edit.sh` to allow a path a Story declares in its
  `boundaries.yml` (a loop change, its own commit, outside a run — and a change
  that weakens a deliberate guard, so it deserves the thought an ADR gives it);
- **and** decides what to do about AC1's 90 s ceiling given the measurement
  above: relax it with a reason, or accept a follow-up Story for the deeper fix
  (scan a git worktree snapshot instead of the live checkout, which removes the
  need for mutual exclusion).

---

## Ambiente — o Swarm lab não tem daemon descartável (não bloqueia M01-01)

**Descoberto em:** fechamento de `M01-01`, 2026-09-09. **Estado:** aberto.
**Não é regressão desta Story:** a baseline em `c8dc53a`, medida antes de
qualquer edição, já era `730 examples, 0 failures, **9 pending**`.

### O sintoma

`bin/gate post-commit --story M01-01` fica vermelho num único check:

```text
tests   FAIL
        the recorded run skipped 9 example(s). A skipped example is not a
        passing one, and the run reports `pass` either way — make the
        dependency they need available (bin/swarm-lab up, bin/setup) and run
        bin/test again
```

Os nove são `spec/integration/swarm_lab_spec.rb`. O gate está certo: um exemplo
pulado não é um exemplo verde, e essa é exatamente a categoria de falso verde que
o Anexo D §7 manda não aceitar.

### Por que continua vermelho mesmo com o Docker no ar

O daemon foi iniciado (Docker Desktop 29.7.2, `Swarm.LocalNodeState: active`) e o
skip mudou de razão em vez de sumir:

```text
antes:  the Docker daemon is not reachable — run `bin/swarm-lab up`
depois: this Docker daemon is not the Opanel lab — run `bin/swarm-lab up`
```

E `bin/swarm-lab up` recusa:

```text
This daemon already runs a Swarm that is not the Opanel lab.
It carries no `opanel.lab=true` node label, so it may be a real cluster.
Refusing to touch it. Point DOCKER_HOST at a disposable daemon.
```

A recusa é o comportamento correto — a proteção existe para não deixar a suíte
reinicializar um Swarm que pode ser de verdade — e **não foi contornada**: nenhuma
saída forçada do Swarm existente, nenhum `DOCKER_HOST` apontado para o daemon do
desenvolvedor.

### O que destravaria

Um daemon descartável para o lab, sem tocar no Swarm que já roda no Docker
Desktop. Duas formas, ambas decisão do dono da máquina:

1. um segundo daemon (`colima start --profile opanel-lab`, ou equivalente), com
   `DOCKER_HOST` apontado para ele ao rodar a suíte; **ou**
2. confirmar que o Swarm atual do Docker Desktop é descartável e liberá-lo
   (`docker swarm leave --force`) para que `bin/swarm-lab up` possa criar o lab com o
   label `opanel.lab=true`.

A opção 2 destrói o Swarm existente. Nenhuma das duas foi executada: qual delas é
segura é informação que só o dono da máquina tem.

### Impacto no Milestone

- **`M01-01` não está bloqueada.** Está `done`, commit `70134b3`, review
  independente `COUNTS 0 0 4 3`, `bin/gate local --story M01-01` PASS e
  `bin/gate pre-commit` PASS no commit. Nenhum dos seus 11 Acceptance Criteria
  depende de Swarm — a Story é identidade e autenticação.
- **As Stories de runtime dependem.** `M01-08` em diante (bootstrap de Cluster,
  Swarm Executor, reconcilers, E2E do slice) exigem Swarm real, e o Exit Gate do
  Milestone exige "a suíte Docker/Swarm roda contra Swarm real e termina verde".
  Sem o lab, elas são `BLOCKED_EXTERNAL_DEPENDENCY` conforme a Block policy do
  `GOAL.md`.
- Até `M01-07` o trabalho é domínio, autorização, audit e UI, e segue sem Docker.

---

## M01-07 — o AC5 exige `Environment`, e a `M01-11` exige a `M01-07` fechada

**Estado:** `BLOCKED_FOR_PRODUCT_DECISION`. Oito dos nove Acceptance Criteria
satisfeitos; o gate local passa; a revisão independente devolveu `COUNTS 1 1 0 0`
e o High já foi fechado. O que resta é o Critical, e ele não está no alcance do
implementer.

**Diagnóstico reproduzível:**

```
$ git grep -l "class Environment\|create_table :environments" -- app lib db
(nenhum resultado)

$ grep -A2 '## Preconditions' docs/implementation/M01/stories/M01-07-project-entity.md
`M01-04` e `M01-05` done.

$ grep -A2 '## Preconditions' docs/implementation/M01/stories/M01-11-environment-entity.md
`M01-07` e `M01-08` done.
```

O AC5 da `M01-07` pede que arquivar um Project com Environments ativos seja
bloqueado. `Environment` só nasce na `M01-11`, cujo precondition é a `M01-07`
`done`. As duas Stories são precondition uma da outra para este critério. Está
registrado como **SC-18** em `docs/implementation/SPEC_CONFLICTS.md`.

Hoje a regra é vacuamente verdadeira — sem Environments, nenhum Project pode ter
um ativo — mas não é **provável**, e um critério que não pode falhar não é um
critério satisfeito.

**O que o implementer não vai fazer**, e por quê:

- criar a tabela `environments` aqui: está em Out of Scope da própria `M01-07` e
  colidiria com o boundary da `M01-11`;
- introduzir um registry de bloqueadores com uma implementação vazia: abstração
  especulativa, proibida pelo `AGENT_RULES`, e um guarda que nada dispara nunca se
  vê falhando;
- marcar `done` com `Critical = 1`.

**Decisão que falta ao dono do repositório.** Duas saídas, ambas legítimas:

1. **Aceitar o diferimento**: `M01-07` fecha com oito de nove, e o AC5 vira
   obrigação nomeada da `M01-11` — que já a carrega em `SC-18` e no relatório.
   Isso exige uma decisão explícita contra a Definition of Done desta Story, que
   pede os nove.
2. **Reordenar o pack**: mover o AC5 para a `M01-11` no arquivo da Story,
   deixando a `M01-07` com oito critérios próprios. Editar uma Story do pack é
   mudança de plano, não de implementação, e não é do implementer.

Enquanto nenhuma das duas for tomada, a `M01-07` fica `blocked` e o run segue
pelas Stories independentes — a `M01-08` (Cluster e bootstrap do Swarm) não
depende de Project.

---

## M01-92 — metade da Story vive em arquivos que o hook nega ao implementer

**Estado:** `BLOCKED_FOR_HUMAN_APPROVAL`. Feito e verde tudo que
`guard-edit.sh` permite: `bin/test-metadata` grava `tree`; `gate_warn` em
`bin/_gate_lib.sh`; checklist no agente `reviewer`; `spec/gates` 308/0; gate local
PASS; revisão rodada 2 `COUNTS 1 0 0 0`. O Critical restante são os ACs 2, 5, 6, 7
e 9, que só existem como patch para `lib/gates/post_commit.rb` e `bin/gate` —
caminhos que o hook nega incondicionalmente, e que o `AGENT_RULES` manda não
contornar.

**Ação que só o operador pode fazer** (patch validado com `git apply --check`,
`ruby -c` e `bash -n`; reproduzido inteiro no fim de `reports/M01-92.md`):

```
git apply docs/implementation/M01/evidence/M01-92-gated-files.patch   # ou salve o bloco do relatório
bundle exec rspec spec/gates && bin/gate local --story M01-92
bin/test && git commit  ...  && bin/gate post-commit --story M01-92   # sem rodar a suíte de novo: é a prova do AC2/AC5
```

Depois disso a Story fecha com os cinco critérios provados, ou não fecha com
evidência do porquê.


---

## M01-09 — o executor vive no processo do Control Plane, e a arquitetura desenha outro processo

**Estado:** `BLOCKED_FOR_PRODUCT_DECISION`. Implementado, testado contra o Engine
real (7 exemplos), gate local verde, revisão rodada 1 `COUNTS 1 1 1 1` com High,
Medium e Low fechados na rodada 2. O Critical restante é **SC-19**: o doc 07
§2.2 põe o Swarm Executor num processo separado atrás de RPC autenticado, e a
Story pediu — e recebeu — um módulo dentro do processo Rails. Não há ADR, e a
Story não pode vencer a arquitetura.

**O que não vai ser feito sem decisão:** um segundo processo com RPC por
identidade de serviço, imagem mínima e rede privada. É topologia que nenhuma
Story do M01 declara; construir isso "para fechar" seria o padrão inventado que
o `AGENT_RULES` proíbe em conflito de segurança.

**Decisão que só o dono pode tomar:** ADR aceitando o módulo in-process em M01
(nomeando quando ele vira serviço), ou ADR exigindo o serviço agora com a Story
que o entrega. As duas opções estão em `docs/implementation/SPEC_CONFLICTS.md`
SC-19. Até lá `M01-17`/`M01-18` podem consumir o módulo — ele é o que o AF-02
permite — mas a M01-09 não fecha.
