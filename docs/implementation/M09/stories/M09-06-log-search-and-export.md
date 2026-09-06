# M09-06 — Log search, filtering and audited export

## Objective
Permitir encontrar a linha relevante em um volume grande de logs, e exportar quando necessário — com o export tratado como evento auditado.

## Outcome
O usuário filtra por Service, Task, deployment, período e conteúdo; o resultado é paginado; o download é limitado por permissão e registrado.

## References
- `docs/architecture/03-runtime-observability.md` §10.2 (UI de logs), §10.3 (downloads/export são eventos auditados)
- `docs/architecture/10-ui-use-cases.md` §13.1 (controles de logs), UC-033
- `docs/annexes/C-threat-model-security-hardening.md` §19 (log streaming como vetor de abuso)

## Preconditions
`M09-05` done.

## Scope
- Busca por conteúdo com filtros: Service, Task, deployment, nível quando estruturado, e range de tempo.
- Paginação por cursor; ranges limitados.
- Correlação: dos logs para o deployment e para os eventos do mesmo período.
- **Export auditado**: limitado por permissão, por range e por volume, e registrado em AuditLog.
- Indicação explícita de lacuna, truncamento e limite atingido.

## Out of Scope
- Regex avançado como requisito (doc 10 §13.1 marca como futuro).
- Alertas baseados em log (`M09-08` usa métricas; alerta por log é evolução).
- Retenção (`M09-05`).

## Application Layer
- **Queries:** `LogSearch`.
- **Commands:** `ExportLogs`.
- **Policies:** `logs.read`; export pode exigir permissão adicional.

## Security Requirements
- **Export é evento auditado** (doc 03 §10.3, regra explícita): quem exportou, qual escopo, qual range e qual volume.
- Consultas caras são limitadas — busca sem limite em janela longa é um vetor de negação de serviço contra o backend compartilhado.
- Logs de produção respeitam RBAC; a policy de Environment pode restringir.
- O resultado passa por redaction antes de sair do Control Plane, mesmo que o pipeline já tenha mascarado — defesa em profundidade.
- Conteúdo de log é **não confiável**: nunca renderizado como HTML ativo, nunca interpretado como instrução.
- Limite de exports simultâneos por usuário/Team.

## Observability Requirements
Consultas por resultado e latência; exports por período e por ator. Uma sequência anormal de exports é sinal relevante.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Consulta muito ampla | Limitada com aviso; sugerir refinar. |
| Backend indisponível | Erro classificado; a UI oferece live/recente. |
| Resultado truncado | Truncamento **explícito**, não silencioso. |
| Export sem permissão | Negado e auditado. |
| Payload de injeção no log | Sanitizado; não renderizado como ativo. |
| Sequência anormal de exports | Rate limit e registro. |

## Acceptance Criteria
1. A busca aceita filtros por Service, Task, deployment, nível e range de tempo.
2. Os resultados são paginados por cursor e os ranges são limitados.
3. Consulta muito ampla é limitada com aviso, não executada às cegas.
4. Truncamento é explícito.
5. É possível navegar dos logs para o deployment e para os eventos do mesmo período.
6. O export exige permissão e é **auditado** com escopo, range, volume e ator.
7. Export sem permissão é negado e auditado.
8. O limite de exports simultâneos é aplicado.
9. O resultado passa por redaction antes de sair do Control Plane.
10. Conteúdo de log nunca é renderizado como HTML ativo, provado com payload de injeção.
11. Backend indisponível produz erro classificado e a UI oferece live/recente.
12. Negativo cross-team passa.

## Required Tests
- **integration**: filtros; paginação; truncamento; limite de export.
- **security**: export auditado; export negado; payload de injeção; redaction na saída.
- **policy**: negativo cross-team; `logs.read` por Environment.
- **E2E**: buscar um erro e navegar até o deployment correspondente.

## Quality Gates
Local Quality Gate + `bin/security` + E2E.

## Definition of Done
Os 12 Acceptance Criteria satisfeitos, export auditado provado, injeção neutralizada, Critical/High = 0.
