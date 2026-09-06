# M05-14 — Build log streaming, persistence and sanitization

## Objective
Dar visibilidade em tempo real do build e preservar o histórico, tratando a saída do builder como **conteúdo não confiável**.

## Outcome
O usuário acompanha o build ao vivo em segundos; após reload, o histórico é reconstruído; nenhum valor sensível aparece; a saída não é renderizada como conteúdo ativo.

## References
- `docs/architecture/02-build-deploy.md` §18 (eventos, logs e auditoria), §18.1 (streaming para UI)
- `docs/annexes/C-threat-model-security-hardening.md` §17 (build logs como não confiáveis)
- `docs/annexes/B-nfr-slos.md` §7 (streaming em ≤ 2 s), §12 (retenção de build logs: 30 dias)
- `docs/architecture/10-ui-use-cases.md` §11.2 (build logs separados de runtime events)

## Preconditions
`M05-06` done.

## Scope
- Streaming do log do builder para a UI em tempo quase real, reutilizando o transporte de `M02-11`.
- Persistência dos logs com `logRef` no `Build`; o blob não vive na linha do banco (doc 09 §8.1).
- **Sanitização** antes de sair do Control Plane, com os valores conhecidos (build secrets, tokens) registrados no scanner de `M03-10`.
- Limite de tamanho por build e truncamento explícito quando excedido.
- Retenção configurável (default 30 dias, Anexo B §12); metadados do Build permanecem além do log bruto.
- **Separação visual** entre build logs e runtime events (doc 10 §11.2).

## Out of Scope
- Busca em logs históricos (`M09-06`).
- Export com audit (`M09-06`).
- Logs de runtime (`M01-20`).

## Application Layer
- **Queries:** `BuildLogStream`, `BuildLogHistory`.
- **Policies:** leitura conforme escopo do Service.

## Security Requirements
- **Build log é conteúdo não confiável** (Anexo C §17): sanitizado na UI, nunca renderizado como HTML ativo, nunca interpretado como instrução por agente (Anexo F §17.1).
- Valores conhecidos de secret e token são mascarados antes de sair do Control Plane.
- Limite de tamanho e retenção evitam que um build hostil encha o storage (Anexo C §19).
- Backpressure: cliente lento não derruba o worker.
- Acesso respeita RBAC; negativo cross-team obrigatório.
- Download/export de log é auditado quando existir (`M09-06`).

## Observability Requirements
- Latência entre a primeira saída do builder e a disponibilidade na UI (meta ≤ 2 s, Anexo B §7).
- Tamanho do log e se houve truncamento.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Conexão cai durante o stream | Reconexão com continuidade; lacuna sinalizada. |
| Log excede o limite | Truncado com aviso explícito, não silenciosamente. |
| Saída com sequência de escape/HTML | Sanitizada; nunca renderizada como ativo. |
| Valor de secret ecoado pelo build | Mascarado; a garantia real de não vazar na imagem é de `M05-10`. |
| Cliente lento | Backpressure. |
| Log perdido após retenção | Metadados do Build permanecem; a UI explica que o log expirou. |

## Acceptance Criteria
1. Os logs são streamados para a UI em ≤ 2 s após a primeira saída do builder.
2. Após reload, o histórico é reconstruído do log persistido.
3. O blob do log não vive na linha do `Build`; existe `logRef`.
4. Valores conhecidos de secret e token são mascarados antes de sair do Control Plane, provado com valor plantado.
5. A saída **não** é renderizada como HTML ativo, provado com payload de injeção.
6. Log acima do limite é truncado com aviso explícito.
7. Cliente lento não derruba o worker, provado por teste de backpressure.
8. A retenção é aplicada e os metadados do Build permanecem além do log.
9. Build logs e runtime events são visualmente separados.
10. O acesso respeita RBAC; negativo cross-team passa.
11. Conexão caída é sinalizada com lacuna explícita.

## Required Tests
- **unit**: sanitização; truncamento.
- **integration**: reconstrução após reload; retenção; backpressure.
- **security**: valor plantado mascarado; payload de injeção não renderizado; negativo cross-team.
- **Build Lab**: stream real durante um build.

## Quality Gates
Local Quality Gate + Build Lab + `bin/security`.

## Definition of Done
Os 11 Acceptance Criteria satisfeitos, sanitização e injeção cobertas, backpressure provado, Critical/High = 0.
