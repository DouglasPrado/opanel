# M09-04 — Metrics UI for cluster, environment, service and ingress

## Objective
Apresentar métricas no contexto do produto — por Service, Environment, Cluster e ingress — respondendo perguntas operacionais, sem virar um substituto de ferramenta de observabilidade genérica.

## Outcome
A página do Service mostra CPU, memória, réplicas, restarts, tráfego e latência; a do Cluster mostra capacidade e headroom; a de ingress mostra requisições, erros e TLS.

## References
- `docs/architecture/10-ui-use-cases.md` §18.1 (metrics por nível), §6 (dashboard não vira Grafana)
- `docs/architecture/03-runtime-observability.md` §15.1 (service overview), §15.2 (cluster overview)
- `docs/annexes/B-nfr-slos.md` §4 (latência de leitura da UI)

## Preconditions
`M09-03` done.

## Scope
- Métricas por nível do doc 10 §18.1: cluster, environment, service, task, ingress.
- Painel do Service com o conteúdo do doc 03 §15.1: status, release, réplicas, CPU, memória, tráfego, latência, erros, autoscaling, último deploy.
- Painel do Cluster com o conteúdo do doc 03 §15.2: managers, workers, ingress, capacidade, services, incidentes, deployments.
- Ranges de tempo pré-definidos, com limites.
- Correlação: da métrica para o deployment, os logs e os eventos do mesmo período.

## Out of Scope
- Dashboards customizáveis pelo usuário — o doc 10 §6 é explícito: “o dashboard não vira Grafana”.
- Métricas de negócio da aplicação.
- Alertas (`M09-08`).

## UI Impact
O painel responde quatro perguntas (doc 10 §6): está tudo saudável? o que mudou? o que precisa de atenção? onde entro para agir?

## Security Requirements
- Consultas respeitam tenancy pelo boundary de `M09-03`.
- Ranges e cardinalidade limitados na UI, para que um usuário não construa uma consulta destrutiva por acidente.
- Nenhuma métrica exibida contém valor sensível.
- Métricas de infraestrutura detalhadas exigem permissão adequada.

## Observability Requirements
Latência das consultas dentro das metas do Anexo B §4. Ausência de dado é **explícita**: “sem dados no período” difere de “zero”.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Backend indisponível | Painel mostra indisponibilidade com causa; não exibe zeros. |
| Sem dados no período | “Sem dados” explícito, diferente de zero. |
| Consulta lenta | Timeout com causa; o resto da página continua utilizável. |
| Lacuna de coleta | Sinalizada no gráfico, não interpolada silenciosamente. |
| Range muito grande | Limitado com aviso. |

## Acceptance Criteria
1. As métricas são apresentadas por cluster, environment, service, task e ingress.
2. O painel do Service traz status, release, réplicas, CPU, memória, tráfego, latência, erros e último deploy.
3. O painel do Cluster traz managers, workers, ingress, capacidade e headroom.
4. Backend indisponível mostra indisponibilidade com causa; **nunca** zeros.
5. “Sem dados no período” é visualmente distinto de “zero”.
6. Lacuna de coleta é sinalizada, não interpolada silenciosamente.
7. Ranges são limitados, com aviso quando o pedido excede o limite.
8. A partir de um gráfico é possível navegar para o deployment, os logs e os eventos do mesmo período.
9. As consultas respeitam tenancy; negativo cross-team passa.
10. Métricas de cluster e de nó exigem `INSTANCE_ADMIN` ou `OPERATOR`; métricas de Service exigem papel com leitura no Environment, com negativo cross-team verde.
11. A latência das consultas fica dentro da meta do Anexo B §4.
12. Nenhum componente novo foi criado onde o inventário resolvia; Reuse Gate documentado; acessibilidade AA verificada.

## Required Tests
- **unit (frontend)**: distinção “sem dados” × zero; sinalização de lacuna; limite de range.
- **integration**: backend indisponível; timeout de consulta.
- **E2E**: navegar da métrica para o deployment e para os logs.
- **policy**: negativo cross-team; permissão de infraestrutura.

## Quality Gates
Local Quality Gate + Reuse Gate + E2E.

## Definition of Done
Os 12 Acceptance Criteria satisfeitos, distinção entre ausência e zero provada, correlação navegável, Critical/High = 0.
