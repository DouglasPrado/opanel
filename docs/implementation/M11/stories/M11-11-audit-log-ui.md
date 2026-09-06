# M11-11 — Audit Log search and correlation UI

## Objective
Tornar a trilha de auditoria **consultável**: quem fez o quê, quando, sobre qual recurso e com qual resultado — com correlação para a operação correspondente.

## Outcome
O usuário filtra por ator, ação, recurso, período e resultado; o detalhe mostra metadata sanitizada e links para o recurso e para a operação.

## References
- `docs/architecture/04-identity-teams-security.md` §10 (Audit Log), §18.4
- `docs/architecture/10-ui-use-cases.md` §23 (Audit Log e Activity)
- `docs/architecture/09-data-model-apis-contracts.md` §15.1, §18 (índices)
- `docs/annexes/B-nfr-slos.md` §12 (retenção de audit: 365 dias)

## Preconditions
`M01-05` entregou o AuditLog; esta Story entrega a consulta.

## Scope
- Filtros do doc 10 §23: ator, ação, recurso, período, resultado, request/operation ID.
- Paginação por cursor sobre os índices de `M01-05`.
- Detalhe do evento com metadata **sanitizada** e links para recurso e operação.
- Exportação com permissão e auditoria própria.
- Retenção de 365 dias como default (Anexo B §12), não editável pelo usuário comum.
- Acesso por papel: OWNER, ADMIN e `INSTANCE_AUDITOR`.

## Out of Scope
- Detecção de anomalia — explicitamente “sem automação opaca no core” (doc 10 §21.1).
- SIEM externo (integração é evolução).
- Alteração ou remoção de eventos — o log é append-only.

## Application Layer
- **Queries:** `AuditSearch`, `AuditEventDetail`.
- **Policies:** leitura por OWNER/ADMIN/`INSTANCE_AUDITOR`.

## Security Requirements
- O detalhe **nunca** mostra secret plaintext, credencial de provider ou Recovery Key (doc 10 §23, regra explícita).
- O log é append-only: a UI não oferece edição nem remoção.
- Acesso restrito por papel; um DEVELOPER não lê a trilha completa do Team por padrão.
- A exportação é **auditada** — exportar a trilha é, em si, um evento sensível.
- Consultas caras são limitadas; a trilha é grande por natureza (piso de teste de 1.000.000 eventos, Anexo B §9.1).
- A retenção não é reduzível pelo usuário comum.

## Observability Requirements
A consulta precisa responder, em tempo aceitável, sobre o piso de teste do Anexo B §9.1. A latência é medida.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Consulta muito ampla | Limitada com aviso; sugerir refinar. |
| Evento com metadata sensível | Sanitizada; nunca exibida. |
| Usuário sem permissão | Tela explicativa sem vazar dados. |
| Volume grande | Paginação por cursor estável; índices usados. |
| Export sem permissão | Negado e auditado. |
| Retenção expirada | Ausência explicada com a data limite. |

## Acceptance Criteria
1. Os filtros do doc 10 §23 funcionam, incluindo correlação por request/operation ID.
2. A paginação é por cursor e usa os índices de `M01-05`.
3. O detalhe mostra metadata **sanitizada**; nenhum secret, credencial ou Recovery Key aparece, provado com valor plantado.
4. O log é append-only; a UI não oferece edição nem remoção.
5. O acesso é restrito a OWNER, ADMIN e `INSTANCE_AUDITOR`.
6. A exportação exige permissão e é **auditada**.
7. Consultas amplas são limitadas com aviso.
8. A consulta responde em tempo aceitável sobre o piso de teste do Anexo B §9.1.
9. A retenção default é 365 dias e não é reduzível pelo usuário comum.
10. Retenção expirada é explicada com a data limite.
11. É possível navegar do evento para o recurso e para a operação correspondentes.
12. Negativos cross-team passam.

## Required Tests
- **integration**: filtros; paginação sobre dataset grande; limite de consulta ampla.
- **security**: metadata sanitizada; export auditado; permissão por papel.
- **performance**: consulta sobre o piso de 1.000.000 eventos dentro da meta.
- **policy**: negativo cross-team.

## Quality Gates
Local Quality Gate + `bin/security`.

## Definition of Done
Os 12 Acceptance Criteria satisfeitos, ausência de dado sensível no detalhe provada, consulta performática sobre o piso, Critical/High = 0.
