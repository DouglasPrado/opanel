# M09-01 — Telemetry identity and stable platform labels

## Objective
Enriquecer todo dado de telemetria com a identidade da plataforma, porque containers são efêmeros e container ID não serve como chave de diagnóstico.

## Outcome
Métrica, log e evento carregam `team_id`, `project_id`, `environment_id`, `service_id`, `deployment_id`, `release_id`, `node_id` e `task_id`.

## References
- `docs/architecture/03-runtime-observability.md` §9.2 (identidade de telemetria)
- `docs/annexes/I-engineering-playbook-quality-gates.md` §19.2 (observabilidade mínima por operação)
- `docs/annexes/C-threat-model-security-hardening.md` §17 (métricas: evitar alta cardinalidade e valores sensíveis)

## Preconditions
M06 aceito.

## Scope
- Conjunto canônico de labels de telemetria, derivado das labels de ownership de `M01-16`.
- Enriquecimento no ponto de coleta: o coletor obtém a identidade a partir das labels do Service/Task.
- Contrato único de enriquecimento, consumido por métricas, logs e eventos.
- **Política de cardinalidade**: quais labels podem virar dimensão de métrica e quais só existem em log — `task_id` e `deployment_id` são alta cardinalidade e não viram dimensão de série temporal por padrão.
- Regra: nenhum label carrega valor sensível.

## Out of Scope
- Coletores em si (`M09-02`).
- Backend (`M09-03`).
- Tracing distribuído (não é requisito da primeira fase).

## Application Layer
Módulo único de identidade de telemetria, reutilizado por coletores e pelo pipeline de logs.

## Security Requirements
- **Alta cardinalidade é um risco operacional real**: `task_id` como dimensão de série temporal derruba o backend de métricas. A política é explícita e verificada.
- Nenhum label carrega nome de secret, valor de variável ou dado do usuário.
- A identidade não expõe informação entre tenants: um dashboard só consulta séries do próprio Team.

## Observability Requirements
Esta Story é a **fundação** da correlação: a partir de um `service_id` deve ser possível cruzar métrica, log, evento, deployment e operação.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Task sem labels de ownership | Telemetria marcada como não atribuída; não descartada, mas sinalizada. |
| Label de alta cardinalidade usada como dimensão | Reprovado por verificação automatizada. |
| Recurso renomeado | IDs não mudam; a série temporal permanece contínua. |
| Workload externo no mesmo Swarm | Não recebe identidade da plataforma; fica fora do escopo de tenancy. |

## Acceptance Criteria
1. O conjunto canônico de labels existe e é derivado das labels de ownership.
2. Métricas, logs e eventos usam o **mesmo** contrato de enriquecimento.
3. A partir de um `service_id`, é possível cruzar métrica, log, evento, deployment e operação.
4. Labels de alta cardinalidade (`task_id`, `deployment_id`) **não** viram dimensão de série temporal por padrão, verificado automaticamente.
5. Nenhum label carrega valor sensível, provado com valor plantado.
6. Renomear um recurso **não** quebra a continuidade da série, porque a identidade são os IDs.
7. Task sem labels de ownership é sinalizada como não atribuída, não descartada silenciosamente.
8. Workload externo no mesmo Swarm não recebe identidade da plataforma.
9. Consultas respeitam tenancy; um Team não alcança séries de outro.

## Required Tests
- **unit**: contrato de enriquecimento; política de cardinalidade.
- **integration**: correlação a partir de `service_id`; renomeação preservando a série.
- **security**: valor plantado ausente dos labels; isolamento de tenancy.

## Quality Gates
Local Quality Gate + `bin/security`.

## Definition of Done
Os 9 Acceptance Criteria satisfeitos, correlação provada, política de cardinalidade verificada, Critical/High = 0.
