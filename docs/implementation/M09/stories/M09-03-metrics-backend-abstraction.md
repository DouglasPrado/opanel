# M09-03 — MetricProvider abstraction and query layer

## Objective
Desacoplar a plataforma do backend de métricas, para que o autoscaler e a UI não dependam de um fornecedor específico — e registrar a escolha concreta por ADR.

## Outcome
Existe um `MetricProvider` com consultas pré-definidas; o backend concreto é escolhido por ADR e pode ser substituído sem alterar coletores nem consumidores.

## References
- `docs/architecture/03-runtime-observability.md` §8.3 (abstrair MetricProvider para o autoscaler não depender de Prometheus), §9 (backend substituível)
- `docs/implementation/SPEC_CONFLICTS.md` SC-11 (backend não faz parte da stack congelada; exige ADR)
- `docs/annexes/D-test-strategy.md` §6.3 (provider contracts)

## Preconditions
`M09-02` done. **Esta Story exige um ADR aceito** para o backend concreto (SC-11).

## Scope
- Contrato `MetricProvider` com consultas **pré-definidas ou DSL limitada**, nunca expressão arbitrária do usuário.
- Limites de range e de cardinalidade nas consultas.
- Adapter concreto para o backend escolhido no ADR.
- Normalização de erros e comportamento sob indisponibilidade.
- `ObservabilityProvider` no modelo, com configuração por Team/Cluster.
- Contract tests do provider.

## Out of Scope
- UI (`M09-04`).
- Alertas (`M09-08`).
- Autoscaling (`M09-12`) — que **consome** esta abstração.

## Application Layer
- **Providers:** `MetricProvider`.
- **Queries:** `ServiceMetrics`, `ClusterMetrics`, `IngressMetrics`.

## Security Requirements
- **Consultas pré-definidas ou DSL limitada** (Anexo F §10 e doc 03 §8.3): expressão arbitrária vira um vetor de custo — uma consulta mal formada derruba o backend e afeta todos os tenants.
- Limites de range e de cardinalidade aplicados no boundary, não confiados ao backend.
- Consultas respeitam tenancy: um Team não alcança séries de outro, garantido por filtro obrigatório no boundary.
- Credencial do backend no Vault, com escopo mínimo.
- A URL do backend passa pela política de SSRF.

## Observability Requirements
Latência e taxa de erro das consultas ao backend. Backend indisponível é **degradação visível**, não silêncio.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Backend indisponível | Estado degradado explícito; o autoscaler entra em modo seguro (`M09-13`); a UI diz que os dados não estão disponíveis. |
| Consulta muito cara | Rejeitada pelos limites antes de chegar ao backend. |
| Série inexistente | Resposta vazia distinguível de erro. |
| Backend lento | Timeout com causa; não travar a UI. |
| Filtro de tenancy ausente na consulta | Erro de programação detectado por teste. |
| ADR não aceito | Story `BLOCKED_FOR_PRODUCT_DECISION`. |

## Acceptance Criteria
1. O ADR do backend de observabilidade está **aceito** antes da implementação do adapter.
2. `MetricProvider` existe com consultas pré-definidas ou DSL limitada; **nenhuma** expressão arbitrária do usuário.
3. Limites de range e de cardinalidade são aplicados no boundary da plataforma.
4. Toda consulta carrega filtro de tenancy obrigatório; a ausência é detectada por teste.
5. Um Team não alcança séries de outro, provado por teste cross-team.
6. A credencial do backend vive no Vault, com escopo mínimo.
7. A URL do backend passa pela política de SSRF.
8. Backend indisponível produz degradação **visível**, não silêncio.
9. Série inexistente é distinguível de erro.
10. Consulta cara é rejeitada antes de chegar ao backend.
11. Trocar o backend exige apenas um novo adapter, sem alterar coletores nem consumidores.
12. Contract tests do provider passam.

## Required Tests
- **contract**: consultas suportadas; série inexistente; backend indisponível; timeout.
- **security**: SSRF; credencial protegida; filtro de tenancy; consulta cara rejeitada.
- **policy**: negativo cross-team.

## Quality Gates
Local Quality Gate + contract tests + `bin/security`. **Bloqueada pelo ADR de SC-11.**

## Definition of Done
ADR aceito, os 12 Acceptance Criteria satisfeitos, isolamento de tenancy e limites de consulta provados, Critical/High = 0.
