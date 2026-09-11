## Resolvidos em 2026-09-10 pela decisão do dono

**M01-07 — SC-18.** O dono decidiu mover o `AC5` para a `M01-11`, que é onde ele
pode ser provado. O critério está escrito no arquivo daquela Story (Acceptance
Criteria e Preconditions) e o `SPEC_CONFLICTS.md` marca o SC-18 como `resolved`.
A contagem da revisão foi para `0 0 1 1`: o Critical era exatamente este
conflito, e a própria revisão nomeou esta saída — *"accept AC5 as formally owed
to `M01-11` before either is marked done"*. A contagem mudou pela decisão, não
por juízo do implementer; o arquivo de revisão não foi editado.

**M01-09 — SC-19.** Resolvido por
[`ADR-0005`](../../decisions/ADR-0005-swarm-executor-in-process-for-m01.md),
aceito pelo dono: o Swarm Executor fica como módulo do processo do Control Plane
no M01, com os controles compensatórios nomeados, o risco declarado nas palavras
da revisão, e três gatilhos de extração. O primeiro deixou de ser prosa — a
`M01-10` carrega a fitness function que falha com mais de um `Node` registrado
enquanto `app/executors/` viver no Control Plane. Contagem para `0 0 0 1` pelo
mesmo motivo e com a mesma ressalva.

Com os dois fechados, `tasks.sh next` volta a devolver Story: `M01-10`.

---

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

## M01-91 — as duas linhas que fecham a Story vivem no `bin/gate`, que o hook nega

**Estado:** `BLOCKED_FOR_HUMAN_APPROVAL`. Feito e verde tudo que
`guard-edit.sh` permite: `SwarmDaemonLock` torna os `:swarm` paralelo-seguros;
`bin/security --diff` com negativo próprio; `spec/gates/gate_budget_spec.rb`
(orçamento por check, suíte julgada pela evidência, guarda de reentrada). O que
resta são dois argumentos de `gate_run` em `bin/gate` — `--parallel` nos tests e
`--diff` no security — e o comentário que os explica, entregues como patch.

**O AC1 (menos de 90 s) não fecha com o patch, e não fecha sem tirar check.** A
suíte cresceu um terço desde que o alvo foi escrito; o número real está no
relatório, com o teto que a medição sustenta no spec.

**Ação que só o operador pode fazer** (patch validado com `git apply --check` e
`bash -n`; reproduzido inteiro no fim de `reports/M01-91.md`):

```
git apply docs/implementation/M01/evidence/M01-91-gate-parallel-diff.patch   # ou salve o bloco do relatório
bin/gate local --story M01-91     # um rspec, --parallel, scan do diff — e o tempo real na tabela do relatório
```

Depois disso o AC5 fica provado pelo próprio gate; o AC1 fica como está —
registrado, não atingido — a menos que o dono decida rebaixar o alvo por ADR.

**Achado colateral, para decidir junto:** o check `contracts` do `bin/gate` roda
`bin/test --type contract` depois de `tests` e sobrescreve
`tmp/test-results/rspec-metadata.json` com um registro parcial — toda execução
do gate local apaga a evidência `complete` que acabou de gerar, e o post-commit
(e o exemplo de orçamento) pedem a suíte de novo. Correção em `bin/gate` ou
`bin/test-metadata`; nenhum dos dois está na boundary da M01-91.

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

---

## M01-17 — todo nome técnico de network tem 65 caracteres, e o Swarm recusa acima de 63

**Estado:** a rodada limitada autorizada pela arbitragem de 2026-09-11 fechou o
Critical que lhe foi dado — `network_reconciler.rb:183` passa a
`labels_for(network.environment)` e a label `com.opanel.project_id` agora sai no
payload (provado abaixo) — e os cinco exemplos de laboratório continuam vermelhos
por uma causa **diferente**, que nenhuma rodada e nenhuma revisão anterior
nomeou.

**Diagnóstico reproduzível.** `Opanel::Ownership.technical_name_for(Environment)`
devolve `net_<prj_ULID>_<env_ULID>`: `net_` (4) + `prj_` + 26 (30) + `_` (1) +
`env_` + 26 (30) = **65 caracteres, sempre**. O Engine recusa em 63. Não é
intermitência nem anomalia do daemon — é determinístico e vale para *todo*
Environment:

```sh
# o comando que o reconciler monta (probe via bin/rails runner -e test)
payload={"name" => "net_prj_01M27WZAE8P40GW1TEHTV2P5TN_env_01M27WZAES96CG2QR6CZY1FGNY",
         "labels" => {"com.opanel.managed" => "true", "com.opanel.team_id" => "…",
                      "com.opanel.project_id" => "prj_01M27WZAE8P40GW1TEHTV2P5TN",
                      "com.opanel.environment_id" => "env_01M27WZAES96CG2QR6CZY1FGNY",
                      "com.opanel.desired_revision" => "1"}, "attachable" => false}
outcome="FAILED" code="VALIDATION_ERROR" safe_metadata={http_status: 400}

# o mesmo nome, direto no socket do lab (65 caracteres)
$ curl --unix-socket … -X POST …/v1.44/networks/create -d '{"Name":"net_prj_…_env_…", …}'
{"message":"rpc error: code = InvalidArgument desc = name must be 63 characters or fewer"}
HTTP=400

# os mesmos 65 caracteres truncados em 63, nada mais alterado
HTTP=201  {"Id":"jjtozpyk7paac3v6ybm0rtg6c","Warning":""}
```

**Correção do registro.** `docs/implementation/M01/reports/M01-17.md:140,157`
afirma "Docker VALIDATION_ERROR … despite identical curl requests succeeding
(HTTP 201)" e classifica as cinco falhas como "Docker issue, não defeito de
código". A afirmação não se sustenta: o curl que devolveu 201 usava um nome
curto. Com o nome que o reconciler realmente monta, o curl devolve 400 e a
mensagem do Engine diz exatamente o que falta. O defeito é de código, e está em
`lib/opanel/ownership.rb:90-104` — arquivo que a arbitragem de 2026-09-11
proibiu explicitamente esta rodada de editar, de modo que a rodada não poderia
tê-lo fechado nem em princípio.

**Alcance além da M01-17.** O mesmo método gera
`svc_<prj_ULID>_<env_ULID>_<svc_ULID>` = **96 caracteres** para Service, que é o
recurso da `M01-18`. O esquema de nomes não é imposto por nenhum documento
aprovado: `docs/architecture/09-data-model-apis-contracts.md:195` pede apenas que
o nome seja "determinístico e derivado de IDs/slugs sanitizados" e que o produto
nunca dependa dele como identificador primário, e a `M01-16` (`:22,49,55,60`)
pede derivação de IDs, estabilidade sob rename e ausência de colisão por
construção. Um esquema mais curto que preserve as três propriedades satisfaz
igualmente a especificação; qual esquema é decisão de quem arbitra, não desta
sessão.

**Evidência de teste desta rodada:** 26 exemplos declarados, 21 verdes
(`spec/unit/network_reconciler_spec.rb` 3/3 com a nova asserção de
`com.opanel.project_id` no payload; `spec/unit/ownership_predicate_spec.rb`
15/15 migrados para `RuntimeObservation`;
`spec/integration/swarm_ownership_reidentification_spec.rb` 3/3 migrados),
5 vermelhos — os três arquivos de laboratório, todos pela causa acima.

**Segunda correção do registro: o relatório mediu 6 dos 8 arquivos declarados.**
O item (4) da arbitragem pedia "re-run all eight files declared for this Story"
com prestação de contas por arquivo. O comando registrado em
`reports/M01-17.md:20-33` lista **seis** arquivos, e a tabela por arquivo
(`:38-46`) tem seis linhas. Os três ausentes — todos declarados sob `M01-17` em
`boundaries.yml:1071-1073` — medidos nesta sessão, no mesmo working tree da
rodada:

```sh
$ bin/test spec/unit/swarm_executor_spec.rb              # 33 examples, 13 failures
$ bin/test spec/contracts/executor_contract_spec.rb      #  8 examples,  0 failures
$ bin/test spec/integration/swarm_ownership_labels_spec.rb  # 4 examples, 1 failure
```

O total real dos oito arquivos declarados é **71 exemplos, 19 falhas** — não
"26 examples, 21 passing, 5 failing". As 13 falhas de `swarm_executor_spec.rb`
caem em `retry_after_observing` (`:233,244,260`), idempotência de remoção
(`:325`), a linha de log do AC12 (`:381,392,408`) e a classificação de erro do
AC5 (`:174,178,183,200,205,209`) — as asserções da `M01-09` sobre o arquivo que
a ADR-0009 reescreveu. `swarm_ownership_labels_spec.rb:66` ("finds an existing
Service by ownership labels on retry") é o mesmo defeito de nome no caminho de
Service: `svc_<prj>_<env>_<svc>` tem 96 caracteres.

**`bin/gate pre-commit --story M01-17` no fim da rodada:** `tests` FAIL
(1410 exemplos, 29 falhas), `secret-scan` PASS, `migrations` PASS,
`no-stray-files` PASS, `diff-boundary` **PASS** — o diff não saiu do boundary
declarado. Das 29, seis são as falhas pré-existentes de `DECISIONS.md:70,162-166`
e dezenove são as acima; o restante é o resíduo já arbitrado do `bin/gate`.

**Revisão independente da rodada:** `review/M01-17-round-2.md`,
`COUNTS 1 1 0 0`. A revisão da rodada anterior permanece intacta e verbatim em
`review/M01-17.md` (`COUNTS 3 4 3 0`), como a arbitragem exigiu. Registrado
também, porque é a terceira ocorrência da mesma classe no M01 (`DECISIONS.md:232`
e a entrada da própria arbitragem desta rodada): a prosa desta revisão descreve
dois Criticals e dois Highs e a linha `COUNTS` diz `1 1 0 0`. Os counts foram
gravados como vieram — corrigir um veredito é escrevê-lo, e o implementador não
faz isso.

---

## M01-17 — rodada de nomes: 116 exemplos, 3 falhas, e o relatório ainda erra o mapa de ACs

**Estado:** a rodada autorizada pela segunda arbitragem de 2026-09-11 fechou o
defeito de nome. `Ownership.technical_name_for` passa a `net_<environmentId>` e
`svc_<serviceId>` — 34 caracteres cada, contra os 65 e 96 anteriores — e o
arquivo ganhou a propriedade de comprimento que nunca teve
(`spec/unit/ownership_technical_name_spec.rb`, 13 exemplos, 0 falhas, duas delas
novas afirmando `<= 63` para Service e Environment).

**Medição do lead, arquivo por arquivo, em todos os declarados sob `M01-17`:**

```
spec/unit/network_diff_spec.rb                             7 exemplos, 0 falhas   (era 4)
spec/unit/network_reconciler_spec.rb                       3, 0
spec/unit/ownership_predicate_spec.rb                     15, 0
spec/unit/ownership_technical_name_spec.rb                13, 0
spec/unit/swarm_executor_spec.rb                          33, 0   (era 13 falhas)
spec/contracts/executor_contract_spec.rb                   8, 0
spec/integration/swarm_ownership_labels_spec.rb            4, 1 falha  (:66)
spec/integration/swarm_ownership_reidentification_spec.rb  3, 0
spec/integration/network_reconciler_lab_spec.rb            3, 1 falha  (:36, AC4/AC5)
spec/integration/network_isolation_lab_spec.rb             1, 0   (AC8 verde)
spec/integration/network_unowned_blocked_lab_spec.rb       1, 1 falha  (:9, AC6)
spec/integration/environment_network_operation_spec.rb     3, 0
spec/integration/network_applied_revision_spec.rb          3, 0
spec/integration/reconciliation_run_spec.rb                3, 0
spec/security/reconciler_user_intent_spec.rb               1, 0
spec/policies/network_policy_spec.rb                      15, 0
--------------------------------------------------------------------
                                                         116 exemplos, 3 falhas
```

AC1, AC2, AC3, AC8 e AC11 ficaram verdes contra o Swarm real. AC4, AC5 e AC6
seguem vermelhos, e a condição de encerramento da arbitragem exigia exatamente
esses três verdes.

**As três falhas.** O builder classificou todas as três como especificações que
codificam a suposição pré-ADR-0009 de busca por nome. A revisão independente
(`review/M01-17-round-3.md`, `COUNTS 2 2 1 0`) concordou com duas e recusou a
terceira: `network_reconciler_lab_spec.rb:36` e
`network_unowned_blocked_lab_spec.rb:9` criam uma network **sem** labels de
plataforma e esperam, respectivamente, `NOOP` e `BLOCKED` de um reconciler que
agora endereça por label — e sob `AGENT_RULES` ("Reconciliation") um recurso sem
ownership de plataforma nunca é adotado automaticamente, de modo que `CREATE` é
o comportamento correto e a asserção é que está velha; já
`swarm_ownership_labels_spec.rb:66` testa a adoção por label em si e continua sem
diagnóstico — pode ser lacuna real no caminho de `do_create_service`.

**O que a revisão achou além dos testes, e é o que a bloqueia:** o mapa de
Acceptance Criteria do relatório (`reports/M01-17.md:42-51`) atribui descrições
que não são as da Story — AC1, AC3 e AC8 aparecem com o texto de outros
critérios — e quatro dos doze (AC7, AC9, AC10, AC12) não aparecem no mapa, ainda
que `spec/security/reconciler_user_intent_spec.rb` e
`spec/integration/reconciliation_run_spec.rb` estejam verdes. É a terceira
rodada seguida em que o relatório é o artefato que reprova a Story, e a quinta
vez no M01 em que um critério foi dado por satisfeito sem exemplo que o prove.

`tasks.sh attempt` recusou em 3 e bloqueou a Story sozinho.

---

## M01-17 — rodada final: 117 exemplos, 1 falha, e ela é o AC4

**Estado:** os cinco itens da terceira arbitragem de 2026-09-11 foram executados.
AC6 passou pela primeira vez na história desta Story — o exemplo agora cria a
network não-possuída sob o nome exato que o reconciler pede
(`Ownership.technical_name_for(environment)`), de modo que a colisão realmente
acontece, e `network_reconciler.rb` ganhou o ramo `RESOURCE_NAME_CONFLICT` que
registra `BLOCKED` com diagnóstico em vez de `FAILED`/"retry". AC5 passou.
`swarm_ownership_labels_spec.rb` ficou 4/4 com a troca de `service.id` por
`service.external_id`.

**Medição do lead, nos dezesseis arquivos declarados:**

```
network_diff_spec 7/0 · network_reconciler_spec 3/0 · ownership_predicate_spec 15/0
ownership_technical_name_spec 13/0 · swarm_executor_spec 33/0
executor_contract_spec 8/0 · swarm_ownership_labels_spec 4/0
swarm_ownership_reidentification_spec 3/0 · network_reconciler_lab_spec 4/1
network_isolation_lab_spec 1/0 · network_unowned_blocked_lab_spec 1/0
environment_network_operation_spec 3/0 · network_applied_revision_spec 3/0
reconciliation_run_spec 3/0 · reconciler_user_intent_spec 1/0
network_policy_spec 15/0
----------------------------------------------------------------
117 exemplos, 1 falha
```

**A falha, reduzida.** `spec/integration/network_reconciler_lab_spec.rb:36`
(AC4): `expect(run.diff_class).to eq("NOOP")` recebe `"CREATE"` em `:73`. O que
está estabelecido, com evidência, e o que não está:

- A primeira execução **encontra** a network por label. Não é inferência:
  `network_reconciler.rb:199-206` só marca `READY` e só avança
  `applied_revision` quando `inspect_network_in_swarm` devolve uma observação e
  `managed_by_platform?` a aceita, e o exemplo afirma as duas coisas em `:47-48`
  — ambas passam.
- A segunda execução chama o mesmo `inspect_network_in_swarm` e obtém `nil`:
  `NetworkDiff:40-44` só responde `CREATE` quando `actual.nil?`.
- Não há exceção engolida. O `rescue StandardError` de
  `network_reconciler.rb:135-143` registra `network.reconciliation.inspect_failed`,
  e esse evento não aparece na execução do exemplo.
- Não é resíduo no daemon: depois da suíte não resta nenhuma network com label
  `com.opanel.*`.
- Não é o caminho de adoção de `find_by_label`: o AC5, doze linhas abaixo, cria
  a network **com** `labels_for(environment)` e é reconhecida `NOOP` — o mesmo
  filtro `com.opanel.environment_id`, verde.

Ou seja: a mesma chamada, contra o mesmo daemon, no mesmo exemplo, encontra a
network imediatamente após criá-la e não a encontra na execução seguinte. O
builder classificou isso como "requires investigation of `find_by_label`
contract"; a redução acima descarta o contrato de `find_by_label` como causa
única, e a causa restante não está diagnosticada.

**Condição de encerramento da arbitragem:** "If the AC4, AC5 and AC6 examples are
not green at the end of this round, `M01-17` is a `BLOCK` with `Blocks-On:
HUMAN` — no further raise, no further ADR, no further round"
(`DECISIONS.md`, terceira entrada de 2026-09-11). AC5 e AC6 estão verdes; o AC4
não.

---

## M01-17 — rodada da lease: 118 exemplos, 0 falhas, e um High de base

**Estado:** os quatro itens da quarta arbitragem de 2026-09-11 foram executados e
o diagnóstico dela se confirmou na íntegra. `network_reconciler.rb:105` passou a
liberar a lease com `Opanel::WorkerIdentity.current` — a identidade que
`acquire_resource_lock.rb:49` grava — em vez da string `"system"` de
`system_actor`, que nunca casava, caía no `else` vazio de
`release_resource_lock.rb:26-38` e deixava a lease de 30 s presa; a segunda
execução era então recusada em `:50` e voltava antes do Step 2, sem inspecionar
nada e sem gravar `ReconciliationRun`, de modo que o `order(:created_at).last` do
exemplo lia a linha `CREATE` da primeira execução. Era defeito de produção: a
varredura periódica de `reconcile_networks_job.rb` abandonava uma lease por
Environment a cada passagem.

`spec/unit/network_reconciler_spec.rb:22` trocou `worker_identity: anything` pela
identidade real, e o AC12 ganhou seu primeiro exemplo de verdade — lock com dono
estranho e `lease_until` expirado, tomada com `fencing_token` incrementado, e a
afirmação de que o **primeiro** comando que o executor recebe é `inspect_network`,
antes de qualquer `create_network`.

**Medição do lead, nos dezesseis arquivos declarados: 118 exemplos, 0 falhas.**
Os doze Acceptance Criteria têm exemplo verde, incluindo AC4 e AC12, que eram os
dois Criticals da revisão anterior. A condição de encerramento absoluta da
arbitragem não disparou.

**Revisão independente:** `review/M01-17-round-5.md`, `COUNTS 0 1 0 0`. Nenhum
Critical. O único High é escopo: o revisor encontrou `bin/autopilot`,
`bin/next-milestone` e seis arquivos de `tools/opanel-loop/**` no diff da Story e
o classificou como violação de boundary.

**Fato verificado sobre esse High, sem juízo sobre o veredito.** Os quatro commits
desta Story não tocam `bin/` nem `tools/`:

```sh
$ git diff --name-only 888deb0~1 1f24e9c -- bin tools
(vazio)
```

Os arquivos que o revisor lista entram no diff porque a base registrada da Story
é `eafe075` e entre ela e o HEAD existem sete commits de manutenção do loop —
`676d2a4`, `dd23d4d`, `a190608`, `0516320`, `22fdeef`, `81f49ce`, `634ad0d`,
`55cc3b5` — nenhum deles desta Story e todos anteriores às rodadas desta sessão.
É o mesmo defeito de escopo por base velha já arbitrado em
`DECISIONS.md:82-86,150`. Um deles, `634ad0d`, carrega junto a implementação de
ADR-0009 da M01-17, mistura que já estava commitada antes desta sessão começar.

Os counts foram gravados como vieram. Corrigir um veredito é escrevê-lo, e o
implementador não faz isso: quem decide o que a corrente faz com este High é a
arbitragem.

---

## Débito aceito em M01-17 — dois itens para o humano na pilha

Registrado pela arbitragem DEBT de 2026-09-11 (última entrada de `DECISIONS.md`),
que fechou a M01-17 em `1f24e9c` com `review 0 0 1 0` — o Medium sendo a
reclassificação arbitrada do único High da revisão. Os dois itens viajam ao corpo
do `bin/milestone-pr`; nas palavras do revisor:

> **HIGH — Boundary Violation: 8 files outside M01-17's declared scope**
> Files modified or created outside boundaries.yml:1041-1132:
> - `bin/autopilot` (substantive changes to quota handling)
> - `bin/next-milestone` (substantive changes to block reason detection)
> - 6 files under `tools/opanel-loop/**` explicitly forbidden by DECISIONS.md line 315
> Changes outside the boundary block acceptance, per AGENT_RULES and engineering
> playbook.

**1 — Defeito de base velha, terceira aparição** (`DECISIONS.md:82-86,150`).
O achado acima é verdadeiro do *diff* e falso da *Story*. `bin/story-scope` nunca
re-baseia uma Story reaberta, então a base salva (`eafe075`) precede oito commits
de manutenção do loop — `676d2a4`, `dd23d4d`, `a190608`, `0516320`, `22fdeef`,
`81f49ce`, `634ad0d`, `55cc3b5` — e o diff da Story anexa todos eles. Nenhum dos
quatro commits da M01-17 toca `bin/` ou `tools/`:
`git diff --name-only 888deb0~1 1f24e9c -- bin tools` é vazio, e o
`diff-boundary` do `bin/gate` passou. Pertence a `M01-91`/`M01-93`, que são donas
de `lib/gates/**` e `bin/gate`, como manutenção conduzida por humano fora de uma
execução autônoma.

**2 — `634ad0d` mistura duas coisas num commit.** Ele carrega manutenção do loop
junto com a implementação de ADR-0009 da M01-17, contra `AGENT_RULES`
§"Git Discipline". Pré-existente a esta sessão, e não reparável pela execução que
é julgada por esses arquivos.

**Observação de ferramenta, para o mesmo dono.** `bin/milestone-pr:95` monta o
corpo do PR com `grep -E '^(Verdict|Situation|Reason):' DECISIONS.md`. Duas das
arbitragens desta sessão vieram com os campos em negrito (`**Verdict:** FIX`) em
vez de texto simples, e essas não serão capturadas pelo grep. O ledger completo
está no arquivo; apenas o resumo do PR fica incompleto.

**`git stash@{0}`** continua estacionado: é a implementação de uma sessão anterior
escrita contra o contrato ainda não decidido, e a ADR-0009 rejeitou a forma que
ela escolheu. Cabe ao humano descartá-la.
