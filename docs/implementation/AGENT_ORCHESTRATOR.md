# Milestone Agent Orchestrator

O Milestone inteiro roda dentro do Claude Code, através do plugin
`tools/opanel-loop`. Não há mais processo externo, nem uma CLI de outro
fornecedor no caminho crítico.

A separação de papéis continua sendo a razão de tudo isto existir:

```text
lead (skill backlog)          decide o que vem a seguir; não escreve código
  -> builder agent            implementa UMA Story, em contexto novo
  -> reviewer agent           revisa a Story, em contexto novo, read-only
  -> milestone-reviewer       julga o Milestone inteiro, read-only, adversarial
```

Quem implementa nunca aprova. O reviewer roda em contexto novo — não vê o
raciocínio de quem construiu — e o verdict é gravado por um script, não por
prosa de agente.

## Estado

Dois arquivos por Milestone, cada um com **uma** porta de escrita:

| Arquivo | Porta de escrita | Guarda |
|---|---|---|
| `tasks.json` | `tools/opanel-loop/scripts/tasks.sh` | `done` é recusado sem `review/<id>.md` e sem `Critical = 0`, `High = 0`. |
| `review-state.json` | `tools/opanel-loop/scripts/review-state.sh` | `ACCEPTED` exige `C = H = 0`; `NOT_ACCEPTED` exige ao menos um bloqueante. |

Os estados de `review-state.json` seguem `scripts/schemas/review-state.schema.json`:

| Estado | Quem age em seguida |
|---|---|
| `implementing` | lead — próxima Story |
| `ready_for_review` | `/review-milestone` |
| `reviewing` | milestone-reviewer |
| `fix_required` | `/fix-milestone` |
| `fixing` | builder |
| `human_acceptance` | **humano** |
| `blocked` | **humano** |

`accepted` existe no schema por compatibilidade; o caminho de sucesso vai direto
de `verdict ACCEPTED` para `human_acceptance`.

## Gatilho

Não há dispatcher em background. O **Stop hook** é a máquina de estados: a cada
turno ele lê o estado gravado e ou bloqueia a parada com a próxima ação
concreta, ou deixa o loop parar.

Ele só age quando existe `.backlog-active` na raiz — um arquivo com o caminho do
Milestone, criado por `/backlog` e removido quando o loop termina. Sem ele,
nenhum hook deste plugin interfere numa sessão comum.

A decisão de parar não é do agente. "Um agente perguntado se o próprio trabalho
acabou responde que sim"; por isso quem responde é o hook, a partir do que está
gravado, e no fechamento a palavra final é de `bin/stop-gate <Mxx>`.

## Review

`/review-milestone <dir>` abre a tentativa (`review-start`), despacha o
`milestone-reviewer` em contexto novo e read-only, e valida a **coerência** do
que volta antes de gravar: counts batendo com os findings, `NOT_ACCEPTED` com ao
menos um bloqueante, cada finding com arquivo e evidência localizáveis.

Resultado incoerente vira `error REVIEW_OUTPUT_INCONSISTENT` e mais uma rodada;
persistiu, `block`. A lead **não conserta os números do reviewer** — corrigir o
verdict é escrevê-lo.

O relatório é gravado em `MILESTONE_REVIEW_<NN>.md`, com o papel, a tentativa, o
`HEAD` e a branch no cabeçalho.

## Correção

`/fix-milestone <dir>` abre `fix-start` e segue `docs/goals/FIX_REVIEW_FINDINGS.md`:
somente `Critical` e `High`, dentro dos boundaries declarados, com testes
afetados, `bin/gate local` e `bin/stop-gate` executados e registrados com exit
code em `FIX_REPORT_<NN>.md`.

Verde: commit e `fix-done`, que devolve o Milestone a `ready_for_review` e limpa
o verdict respondido. Não verde: `block` com motivo reproduzível.

## Limites

`maxReviewAttempts` e `maxFixAttempts` param o ciclo review↔fix. Um deles
esgotado bloqueia o Milestone para decisão humana.

Uma **falha de execução não é um verdict** e não consome tentativa: ela vai para
`executionFailures` através de `review-state.sh error`. O orçamento existe para
impedir um loop de correção, não para punir uma ferramenta que morreu.

Há ainda um teto de turnos — `stories × 6 + 30` — como rede para um loop que só
aparenta progredir. Atingi-lo é defeito a ler, não limiar a aumentar.

## Guardas

- `guard-bash.sh` nega as Dangerous Actions do `CLAUDE.md` e pergunta antes de
  infraestrutura real ou de sinal de gate enfraquecido (`rubocop:disable`,
  `--no-verify`, `xit(`, `.skip(`).
- `guard-edit.sh` nega edição de `docs/architecture/**`, dos anexos,
  `AGENT_RULES.md`, `bin/gate*`, `bin/stop-gate`, `lib/gates/**` e credenciais.
  Um gate editável para passar não protege nada.
- `task-gate.sh` impede fechar a tarefa de uma Story que ainda não está `done`
  nem `blocked` em `tasks.json`.

## Operação

```sh
/backlog docs/implementation/M01
/review-milestone docs/implementation/M01
/fix-milestone docs/implementation/M01

tools/opanel-loop/scripts/tasks.sh docs/implementation/M01 next
tools/opanel-loop/scripts/review-state.sh docs/implementation/M01 status
tools/opanel-loop/scripts/smoke-test.sh
```

Chegar a `human_acceptance` encerra a automação. Somente uma ação humana libera
o Milestone seguinte.

Os runners externos anteriores estão em `scripts/legacy/`, preservados para
leitura do histórico dos Milestones revisados antes desta troca.
