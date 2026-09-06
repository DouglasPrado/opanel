# M09-13 — Autoscaling safety rules

## Objective
Impedir que o autoscaler tome decisões com dado ruim, sem capacidade ou no meio de um rollout — porque um controller que reage a informação incorreta amplifica incidentes.

## Outcome
Sem métricas confiáveis, durante deployment incompleto, em incidente grave ou sem capacidade real, o autoscaler **não escala** — e diz por quê.

## References
- `docs/architecture/03-runtime-observability.md` §8.2 (regras de segurança do autoscaler), §5.3 (não escalar sem capacidade), §17 (metrics backend indisponível → modo seguro)
- `docs/annexes/A-implementation-roadmap.md` §9 (autoscaling depende de métricas confiáveis)
- `docs/annexes/B-nfr-slos.md` §9 (queue saturation, noisy neighbor)

## Preconditions
`M09-12` done.

## Scope
As regras do doc 03 §8.2, implementadas como **bloqueios explícitos**, cada um com motivo registrado:

1. **Nunca escalar acima da capacidade real** sem avisar claramente que haverá Tasks `Pending`.
2. **Scale down mais conservador** que scale up (já em `M09-12`, reafirmado como invariante testada).
3. **Sempre respeitar min/max**.
4. **Não decidir durante deployment incompleto**, incidente grave ou ausência de métricas confiáveis.
5. **Registrar cada decisão** — e cada decisão **suprimida**, com o motivo.
6. Modos `MANUAL`, `AUTO` e `PAUSED` por Service.

Além disso: modo seguro quando o backend de métricas está degradado, e integração com o headroom de `M08-13`.

## Out of Scope
- Autoscaling de nodes.
- Métricas de negócio como sinal.
- Predição.

## Application Layer
- **Queries:** `AutoscalingSuppressionReason`.

## Security Requirements
- Um autoscaler que reage a dado ruim é um **amplificador de incidente**: ele pode escalar durante uma falha e esgotar o cluster. As regras de supressão são controles de disponibilidade, não conveniências.
- Métricas indisponíveis **nunca** são interpretadas como “carga baixa” — isso levaria a scale down durante um apagão de observabilidade.
- Min/max e quota do Team prevalecem sempre.
- Decisões suprimidas são registradas: um autoscaler silenciosamente inativo é indistinguível de um autoscaler quebrado.

## Observability Requirements
- Cada decisão **suprimida** registra o motivo: métricas indisponíveis, rollout em andamento, incidente aberto, sem capacidade, cooldown, min/max, quota.
- Métrica de supressões por motivo — uma taxa alta de supressão por métricas indisponíveis é um problema de observabilidade, não de autoscaling.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Backend de métricas indisponível | **Modo seguro**: não escalar em nenhuma direção; registrar. |
| Métrica com lacuna | Tratada como indisponível, não como zero. |
| Deployment em andamento | Decisão suprimida com motivo. |
| Incidente grave aberto no recurso | Decisão suprimida com motivo. |
| Sem capacidade no cluster | Não escalar acima do que pode ser agendado; avisar `Capacity Exhausted`. |
| Quota do Team no limite | Decisão bloqueada com motivo. |
| Oscilação apesar do cooldown | Medida como flapping e sinalizada; a política precisa de ajuste humano. |

## Acceptance Criteria
1. Com o backend de métricas indisponível, o autoscaler **não escala em nenhuma direção**, provado por teste.
2. Métrica com lacuna é tratada como **indisponível**, nunca como zero, provado por teste.
3. Durante deployment incompleto, a decisão é suprimida com motivo.
4. Com incidente grave aberto no recurso, a decisão é suprimida com motivo.
5. Sem capacidade real no cluster, o autoscaler não escala acima do agendável e sinaliza `Capacity Exhausted`.
6. Min, max e quota do Team são respeitados em todas as decisões.
7. Scale down é comprovadamente mais conservador que scale up.
8. **Toda decisão suprimida é registrada com o motivo**.
9. Os modos `MANUAL`, `AUTO` e `PAUSED` funcionam por Service.
10. Oscilação apesar do cooldown é medida e sinalizada para ajuste humano.
11. A métrica de supressões por motivo está disponível.
12. Nenhuma regra de segurança pode ser desabilitada por configuração de usuário.

## Required Tests
- **unit**: cada regra de supressão isoladamente.
- **integration**: backend indisponível; lacuna de métrica; rollout em andamento; incidente aberto; quota no limite.
- **Docker/Swarm**: sem capacidade para agendar.
- **security**: impossibilidade de desabilitar as regras de segurança.

## Quality Gates
Local Quality Gate + suíte Docker/Swarm.

## Definition of Done
Os 12 Acceptance Criteria satisfeitos, modo seguro provado em três cenários, supressões registradas, Critical/High = 0.
