# M00-14 — Autonomous Development Loop scaffolding

## Objective
Dar ao loop autônomo do Anexo H um estado persistente confiável e um Stop Gate determinístico, para que progresso e conclusão não dependam da memória da conversa.

## Outcome
`bin/pack validate` valida todos os `tasks.json` contra um schema; `bin/stop-gate` executa checks determinísticos e devolve `ok:false` com razão objetiva; os diretórios de evidence, review e report existem com contrato definido.

## References
- `docs/annexes/H-autonomous-development-loop.md` §4 (Stop Gates), §5 (estado persistente), §6 (state machine da Story), §9 (Milestone Loop), §16 (failure modes)
- `docs/annexes/I-engineering-playbook-quality-gates.md` §21 (gates por estado da Story)
- `docs/annexes/G-agent-oriented-development.md` §22 (padrão de relatório)
- `CLAUDE.md` — “Autonomous Work”

## Preconditions
`M00-12` done.

## Scope
- **Schema de `tasks.json`**: milestone, name, status, dependencies, stories[{id, file, status, dependsOn, attempts, required, commit?, blockedReason?}]. Estados permitidos exatamente: `pending`, `ready`, `in_progress`, `review`, `fix_required`, `done`, `blocked`.
- `bin/pack validate`: valida schema, verifica que todo `file` existe, que todo `dependsOn` referencia Story existente do mesmo Milestone, que não há ciclo entre Stories, e que toda Story `done` tem `commit`.
- `bin/stop-gate`: executa a checklist do Anexo H §4.2 e emite JSON `{ok, reason, checks[]}`.
- Diretórios com contrato: `M<XX>/review/<story>.md`, `M<XX>/evidence/<story>/`, `M<XX>/MILESTONE_REPORT.md`, `M<XX>/BLOCKERS.md`.
- Política de tentativas: 3 tentativas sem progresso → trocar estratégia uma vez → `blocked` com diagnóstico reproduzível.
- Qualificadores de bloqueio válidos: `BLOCKED_FOR_PRODUCT_DECISION`, `BLOCKED_FOR_HUMAN_APPROVAL`, `BLOCKED_EXTERNAL_DEPENDENCY`.
- `bin/pack next`: dado um Milestone, imprime a próxima Story elegível (não bloqueada por dependência), para reconstruir estado sem depender da conversa.

## Out of Scope
- Orquestrador headless (`Dev Orchestrator`, Anexo H §14.2) — fora deste roadmap.
- Métricas de autonomia (Anexo H §15) — nascem aqui como log, viram dashboard só se houver Story própria.

## Security Requirements
- O Stop Gate não pode ser satisfeito por afirmação do agente: cada check executa um comando e usa o exit code (Anexo H §4.1).
- Nenhuma credencial de produção pode existir no workspace; `bin/stop-gate` verifica isso e reprova se encontrar.
- O agente não pode editar o próprio Stop Gate para destravar Milestone; alteração é detectada pelo post-commit.

## Observability Requirements
Log mínimo por Story, conforme Anexo H §15.2: milestone, story, tentativas, comandos de teste e resultado, findings do reviewer, commit produzido, motivo de bloqueio.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Agente declara `done` cedo | Stop Gate falha com razão objetiva e o loop continua trabalhando. |
| Sessão perdida ou compactada | `bin/pack next` + `git log` reconstroem o estado sem a conversa. |
| Ciclo entre Stories | `bin/pack validate` detecta e reprova. |
| Story `done` sem commit | `bin/pack validate` reprova. |
| Loop preso repetindo a mesma correção | Contador de tentativas força troca de estratégia e depois `blocked`. |
| Stop hook em ciclo infinito | Teto de execuções registrado; ao atingir, registra diagnóstico e para de reafirmar. |

## Acceptance Criteria
1. Existe schema de `tasks.json` e `bin/pack validate` valida os 15 Milestones deste pack com exit code 0.
2. `bin/pack validate` reprova: estado inválido, `file` inexistente, `dependsOn` inválido, ciclo entre Stories e Story `done` sem commit — um caso negativo por regra.
3. `bin/stop-gate` executa os checks do Anexo H §4.2 e emite JSON com `ok`, `reason` e resultado por check.
4. `bin/stop-gate` devolve `ok:false` com razão objetiva quando um teste falha, provado por caso negativo.
5. `bin/stop-gate` reprova se encontrar credencial de produção no workspace.
6. `bin/pack next M00` imprime a próxima Story elegível respeitando `dependsOn`.
7. Os diretórios de review, evidence, report e blockers têm contrato documentado.
8. A política de tentativas e os três qualificadores de bloqueio estão documentados e refletidos no schema.
9. Nenhum check do Stop Gate depende de afirmação do agente; todos executam comando e usam exit code.

## Required Tests
- **unit**: validador de schema; detector de ciclo; seletor de próxima Story.
- **integration**: `bin/pack validate` sobre o pack real; cinco casos negativos; `bin/stop-gate` verde e vermelho.
- **security**: detecção de credencial de produção no workspace.

## Quality Gates
Local Quality Gate + `bin/fitness`. A partir desta Story, o fechamento de qualquer Milestone passa por `bin/stop-gate`.

## Definition of Done
Os 9 Acceptance Criteria satisfeitos, `bin/pack validate` verde para M00–M14, casos negativos provados, Critical/High = 0.
