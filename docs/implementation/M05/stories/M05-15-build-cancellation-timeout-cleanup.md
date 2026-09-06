# M05-15 — Build cancellation, timeout and workspace cleanup

## Objective
Garantir que um build possa ser interrompido, que ele não rode indefinidamente, e que nada sobre no builder depois — em qualquer desfecho.

## Outcome
Cancelar propaga ao builder em segundos; um build que excede o deadline é morto; o workspace é destruído em sucesso, falha, cancelamento e crash.

## References
- `docs/architecture/02-build-deploy.md` §7.1 (workspace eliminado após sucesso/falha), §16 (cancel é best-effort e registrado)
- `docs/annexes/B-nfr-slos.md` §7 (cancelamento propagado em ≤ 10 s)
- `docs/annexes/E-operational-runbooks.md` RB-14 (builder preso ou saturado)
- `docs/annexes/C-threat-model-security-hardening.md` §10 (builder persistence, cryptomining/DoS)

## Preconditions
`M05-07` done.

## Scope
- Cancelamento pelo Operations Center e pela tela do build, propagado ao builder.
- Deadline por build, configurável, com corte efetivo — não apenas marcação de status.
- Limpeza do workspace e dos recursos do builder em **todos** os desfechos, incluindo crash do worker.
- Job de varredura removendo workspaces e processos órfãos.
- Cancelamento é **best-effort e registrado**: se o ponto atual não for interrompível, a intenção fica registrada e o corte acontece no ponto seguro.

## Out of Scope
- Cancelamento de deployment (`M06-10`).
- Quotas de concorrência por Team (`M11-10`).

## Application Layer
- **Commands:** `CancelBuild`.
- **Jobs:** watchdog de deadline; varredura de órfãos.

## Security Requirements
- O deadline é um controle contra **cryptomining e DoS** (Anexo C §10): sem ele, um repositório hostil consome o builder indefinidamente.
- A limpeza do workspace impede **builder persistence**: nada do build anterior sobrevive para o próximo.
- Processos órfãos deixados por um build hostil são detectados e mortos pela varredura.
- O cancelamento não pode ser usado para deixar o builder em estado inconsistente: a limpeza roda de qualquer forma.
- Cancelamento gera AuditLog.

## Observability Requirements
- Tempo entre o pedido de cancelamento e a parada efetiva (meta ≤ 10 s).
- Contagem de builds mortos por deadline e de órfãos removidos — órfãos recorrentes indicam problema real.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Cancelamento em etapa não interrompível | Intenção registrada; corte no ponto seguro; status final coerente. |
| Build excede o deadline | Morto; `TIMED_OUT`; workspace limpo. |
| Worker do build morre | Watchdog detecta; workspace é limpo pela varredura. |
| Processo órfão no builder | Detectado e morto; registrado. |
| Limpeza falha | Registrada e repetida; o builder é marcado como degradado se persistir (RB-14). |
| Cancelamento de build já terminal | Rejeitado com erro claro. |

## Acceptance Criteria
1. Cancelar um build propaga ao builder em ≤ 10 s.
2. Cancelamento em etapa não interrompível registra a intenção e corta no ponto seguro.
3. Cancelar build já terminal é rejeitado com erro claro.
4. Um build que excede o deadline é **efetivamente morto**, não apenas marcado.
5. O workspace é destruído em sucesso, falha, cancelamento e crash do worker.
6. Processos órfãos no builder são detectados e mortos pela varredura.
7. A varredura é idempotente e roda de novo sem erro após crash.
8. Falha persistente de limpeza marca o builder como degradado.
9. Cancelamento gera AuditLog.
10. Métricas de tempo até parada, builds mortos por deadline e órfãos removidos estão disponíveis.
11. Nenhum resíduo do build anterior está acessível ao build seguinte, provado por teste.

## Required Tests
- **Build Lab**: cancelamento durante build; deadline excedido; crash do worker; resíduo entre builds.
- **integration**: varredura idempotente; builder degradado por falha de limpeza.
- **security**: ausência de persistência entre builds; processos órfãos mortos.
- **unit**: elegibilidade de cancelamento por estado.

## Quality Gates
Local Quality Gate + Build Lab + `bin/security`.

## Definition of Done
Os 11 Acceptance Criteria satisfeitos, ausência de resíduo entre builds provada, corte efetivo por deadline verificado, Critical/High = 0.
