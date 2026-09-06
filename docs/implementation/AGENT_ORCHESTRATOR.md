# Milestone Agent Orchestrator

O orquestrador é uma máquina de estados local para o handoff entre dois papéis
fixos:

```text
Claude IMPLEMENTER
  -> ready_for_review
Codex REVIEWER (read-only)
  -> human_acceptance
  -> fix_required -> Claude FIX -> ready_for_review -> Codex REVIEW
  -> blocked após o limite
```

Ele não implementa Stories, não revisa por heurística própria e nunca inicia o
próximo Milestone.

## Estado

Cada Milestone que participa do fluxo possui `review-state.json`. Os estados são:

| Estado | Dono da transição seguinte |
|---|---|
| `implementing` | Claude |
| `ready_for_review` | Orquestrador |
| `reviewing` | Orquestrador executa Codex |
| `fix_required` | Orquestrador |
| `fixing` | Claude |
| `accepted` | Orquestrador (estado transitório) |
| `human_acceptance` | Humano |
| `blocked` | Humano |

Claude pode solicitar review, mas não pode declarar `accepted`. Codex produz um
verdict, mas roda com sandbox read-only e não altera o repositório. O orquestrador
é o único processo que persiste verdict e transições finais.

## Gatilho

`.claude/settings.json` executa `scripts/agent-orchestrator.sh dispatch` em todo
Stop hook. `dispatch` só inicia trabalho quando encontra um estado elegível; em
`implementing`, `human_acceptance` ou `blocked`, ele encerra sem efeito.

O worker usa lock atômico por repositório/Milestone. Assim, Stop hooks recursivos
disparados pelo Claude da fase de fix não criam uma segunda execução.

## Review

`scripts/run-codex-review.sh` exige antes de chamar o Codex:

- todas as Stories obrigatórias `done` e nenhuma bloqueada;
- `MILESTONE_REPORT.md` com `Status: READY_FOR_REVIEW`;
- estado `reviewing`.

O comando usa `codex exec --sandbox read-only`, política de aprovação `never`,
sessão efêmera e JSON Schema. O wrapper valida a coerência entre verdict, counts
e findings e então grava `CODEX_REVIEW_<NN>.md`.

## Correção

Um `NOT_ACCEPTED` válido precisa conter ao menos um finding Critical ou High. O
orquestrador chama `scripts/run-claude-fix.sh`; Claude segue
`docs/goals/FIX_REVIEW_FINDINGS.md`, corrige apenas findings bloqueantes, gera
`FIX_REPORT_<NN>.md` e solicita novo review.

Claude usa `acceptEdits` por padrão e prompts de permissão interativos são
desativados no modo não interativo. Nenhum bypass irrestrito de permissões é
usado.

## Limites e falhas

`maxReviewAttempts` e `maxFixAttempts` são obrigatórios. O terceiro review
rejeitado com o limite padrão move o estado para `blocked`. Falha de CLI, saída
estruturada inconsistente, fase interrompida ou ausência de relatório também
falha fechado com `blockedReason` objetivo; o sistema não tenta indefinidamente.

## Operação manual

```sh
scripts/agent-orchestrator.sh status M00
scripts/agent-orchestrator.sh dispatch
scripts/agent-orchestrator.sh run M00
scripts/tests/agent-orchestrator-test.sh
```

Pré-requisitos: Bash, `jq`, `claude` autenticado e `codex` autenticado. Logs do
worker assíncrono ficam em `${TMPDIR:-/tmp}/opanel-agent-orchestrator/`.

Chegar a `human_acceptance` encerra a automação. Somente uma ação humana pode
liberar trabalho posterior.
