# M08-12 — Cluster Readiness and the honest HA claim

## Objective
Derivar o estado de prontidão do cluster da redundância **realmente verificada**, e distinguir explicitamente “cluster funcional” de “HA Ready”.

## Outcome
A UI mostra, por check, o que está pronto e o que falta; um cluster single-node aparece como operacional e **não** como HA.

## References
- `docs/architecture/06-infrastructure-provisioning.md` §14 (cluster readiness), §14.2 (indicadores de UI)
- `docs/architecture/01-foundation.md` §12 (o que significa HA real), §12.1
- `docs/annexes/B-nfr-slos.md` §2 (classes de topologia e elegibilidade a SLO)
- `docs/annexes/A-implementation-roadmap.md` §5 M10 (UI diferencia “cluster funcional” de “HA Ready”)

## Preconditions
`M08-05` e `M08-11` done.

## Scope
- `ClusterReadinessView` derivada dos checks do doc 06 §14.1: quorum do Swarm, topologia de managers (ímpar e ≥ 3), workers com capacidade para remanejar após perda de um node, ingress ≥ 2 saudáveis no LB, overlay reachability e MTU, registry testado por pull a partir de um worker, capacidade de build, disco, relógio, dependências externas.
- Classificação por classe de topologia do Anexo B §2: `DEV/SINGLE`, `PROD-HA`, `PROD-HA-ZONAL`.
- Indicadores separados: `Operational`, `Compute HA`, `Ingress HA`, `Overall readiness`.
- Cada check com **motivo** e o que fazer para satisfazê-lo.
- Regra: a plataforma **não** declara HA por existir cluster; a redundância precisa ser verificada.

## Out of Scope
- Elegibilidade a SLO formal e error budget (`M13-13`).
- Protection readiness (`M03-13`, `M10-17`) — entra como check quando existir.
- Multi-zona real (depende de provider; a classe existe, a validação é de M13/M14).

## Application Layer
- **Queries:** `ClusterReadinessView`.
- Derivação a partir de `ClusterObservation`, `NodeObservation`, `IngressObservation` e do estado do LB.

## Security Requirements
- **Honestidade é o requisito de segurança aqui.** Declarar HA sem redundância verificada leva o operador a confiar em uma tolerância a falhas que não existe — e a descobrir isso durante um incidente.
- “Replicas > 1” **não** conta como HA (Anexo B §2, regra explícita).
- Um check que não pôde ser executado é `indisponível`, nunca `ok`.
- A view respeita tenancy; detalhes de infraestrutura exigem permissão adequada.

## Observability Requirements
Cada check com resultado, motivo, evidência e data. Evento quando a readiness muda de classe. Métrica de tempo em cada estado.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Cluster single-node | `Operational: sim`, `HA: não`, com o que falta listado. |
| 2 managers | Quorum frágil: avisado; ímpar é recomendado. |
| 1 ingress | `Ingress HA: não`. |
| Workers sem capacidade para remanejar após perda de um | `Compute HA: não`, com o cálculo. |
| Registry não testado a partir de um worker | Check pendente, não `ok`. |
| Check não executável | `indisponível` com causa. |
| Readiness degradando | Evento emitido; a UI destaca a mudança. |

## Acceptance Criteria
1. `ClusterReadinessView` é **derivada** dos checks reais, nunca de coluna gravada.
2. Todos os checks do doc 06 §14.1 são avaliados e reportados individualmente com motivo.
3. A UI distingue `Operational` de `Compute HA`, `Ingress HA` e `Overall readiness`.
4. Um cluster single-node aparece como operacional e **não** como HA, provado por teste.
5. “Replicas > 1” não influencia a classificação de HA.
6. Número par de managers gera aviso; ímpar ≥ 3 é o alvo.
7. `Compute HA` exige capacidade para remanejar workloads após a perda de um node, com o cálculo exibido.
8. `Ingress HA` exige ≥ 2 ingress saudáveis no LB.
9. O pull do registry a partir de um worker é um check; não testado significa pendente, não `ok`.
10. Check não executável é `indisponível` com causa, nunca `ok`.
11. A classe de topologia (`DEV/SINGLE`, `PROD-HA`, `PROD-HA-ZONAL`) é derivada e exibida.
12. Mudança de readiness emite evento; a view respeita tenancy.

## Required Tests
- **unit**: derivação de cada check; classificação de topologia; caso indisponível.
- **Docker/Swarm**: readiness em cluster single-node × multi-node; degradação após perda de node.
- **integration**: evento de mudança de readiness.
- **policy**: tenancy da view.

## Quality Gates
Local Quality Gate + suíte Docker/Swarm.

## Definition of Done
Os 12 Acceptance Criteria satisfeitos, distinção entre funcional e HA provada em ambas as topologias, Critical/High = 0.
