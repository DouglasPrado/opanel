# M08-14 — Cluster, Nodes and maintenance UI

## Objective
Entregar a interface de infraestrutura: visão do cluster, inventário de nodes, adição guiada e fluxos de manutenção que mostram o impacto antes de executar.

## Outcome
O operador enxerga quorum, capacidade e readiness em uma tela; adiciona um node com comando de validade curta; e conduz manutenção sabendo o que será afetado.

## References
- `docs/architecture/10-ui-use-cases.md` §16 (Clusters), §16.2 (Cluster Overview), §16.3 (Nodes), §16.4 (Add Node), §17 (Cluster Maintenance), §26 (ações destrutivas)
- `docs/architecture/06-infrastructure-provisioning.md` §20 (UX principal)
- `docs/annexes/I-engineering-playbook-quality-gates.md` §6.3 (Reuse Gate)

## Preconditions
`M08-12` e `M08-13` done.

## Scope
- **Cluster list**: nome, status, managers, workers, ingress, capacidade, projetos e atenção.
- **Cluster Overview**: quorum, contagens por papel, capacidade, e os checks de readiness com motivo.
- **Nodes**: hostname, role, capabilities, availability, status, capacidade, tasks, labels e ações.
- **Node detail**: endereços, versão da Engine, histórico de operações, elegibilidade de placement.
- **Add Node**: escolha de role e capabilities, geração do comando com contagem regressiva e ação de revogar.
- **Maintenance**: drain guiado mostrando tasks movíveis e bloqueadas com o motivo; “drain anyway” desabilitado quando o impacto é inaceitável.
- Confirmações proporcionais ao risco para promote, demote, remove e force remove.

## Out of Scope
- Provisionamento por cloud provider (backlog).
- Dashboards de métricas históricas (`M09-04`).
- Instance administration global (`M11-12`).

## UI Impact
Consolida a área de infraestrutura como paralela ao produto: Clusters não são pais de Projects (doc 10 §4.2).

## Security Requirements
- O comando de enrollment é exibido **uma vez**, com contagem regressiva e ação de revogar; o token não é recuperável depois.
- Ações privilegiadas (promote, force remove) exigem confirmação reforçada e, quando aplicável, step-up.
- A UI **não** mostra join token do Swarm em nenhuma circunstância.
- Endereços internos e inventário completo exigem permissão de infraestrutura.
- A UI não esconde constraints que bloqueiam a evacuação (doc 10 §17, regra explícita).

## Observability Requirements
Cada tela mostra a idade da observação. Readiness com motivo por check. Histórico de operações por node.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Cluster inalcançável | Última leitura com timestamp; mutações bloqueadas. |
| Node com dado velho | Badge de observação antiga; não exibido como saudável. |
| Drain bloqueado | Lista dos workloads bloqueados e do que precisa mudar. |
| Operação em andamento | Ação conflitante desabilitada, com link para o progresso. |
| Sem permissão de infraestrutura | Tela explicativa sem vazar inventário. |
| Muitos nodes | Paginação por cursor. |

## Acceptance Criteria
1. A lista de clusters mostra status, contagens por papel, capacidade e atenção.
2. O Cluster Overview mostra quorum, capacidade e **cada check de readiness com o motivo**.
3. A lista de nodes mostra role, capabilities, availability, status, capacidade, tasks e labels.
4. O Node detail mostra endereços, versão da Engine e histórico de operações.
5. Add Node gera o comando com contagem regressiva e ação de revogar; o token não é recuperável depois.
6. O fluxo de drain mostra tasks movíveis e **bloqueadas com o motivo**.
7. “Drain anyway” é desabilitado quando o impacto é inaceitável.
8. Promote, demote, remove e force remove usam confirmação proporcional ao risco.
9. O join token do Swarm **não** aparece em nenhuma tela.
10. Dado velho é sinalizado; nenhum node é exibido como saudável sem observação recente.
11. Cluster inalcançável preserva a última leitura com timestamp e bloqueia mutações.
12. Sem permissão de infraestrutura, a tela explica sem vazar inventário.
13. Listas usam paginação por cursor; acessibilidade AA verificada.
14. Nenhum componente novo foi criado onde o inventário resolvia; Reuse Gate documentado.

## Required Tests
- **unit (frontend)**: readiness por check; badge de dado velho; drain bloqueado.
- **E2E**: adicionar node pela UI até `READY`; drain guiado; promote com confirmação.
- **security**: join token ausente das telas; permissão de infraestrutura; token não recuperável.
- **policy**: negativo cross-team.

## Quality Gates
Local Quality Gate classe React/TypeScript + Reuse Gate + E2E + `bin/security`.

## Definition of Done
Os 14 Acceptance Criteria satisfeitos, constraints de evacuação visíveis, token protegido, Critical/High = 0.
