# M04-03 — ServicePort model and internal service discovery

## Objective
Modelar as portas internas de um Service como recurso explícito e garantir um alias de DNS interno estável para comunicação entre serviços do mesmo Environment.

## Outcome
Um Service declara suas portas com nome e protocolo; outros Services do mesmo Environment o alcançam por um alias previsível; nenhum IP de Task é persistido.

## References
- `docs/architecture/08-networking-domains-edge.md` §6 (service discovery interno), §9.2 (múltiplas portas), §26 (modelo de dados)
- `docs/architecture/09-data-model-apis-contracts.md` §5.3

## Preconditions
M03 aceito.

## Scope
- `ServicePort`: id, serviceId, name, targetPort, protocol.
- Alias de DNS interno previsível por Service dentro da overlay do Environment.
- Suporte a múltiplas portas por Service, cada uma referenciável por um `DomainBinding` distinto.
- Documentação, na UI, de como um Service alcança outro dentro do mesmo Environment.
- Regra: **não persistir IP de container/Task** no banco (doc 08 §6).

## Out of Scope
- `DomainBinding` (`M04-04`).
- Exposição TCP/UDP arbitrária (backlog).
- Egress policy por Environment (doc 08 §21 marca como fase posterior).

## Domain Impact
**Entidade:** `ServicePort`. A unidade estável é o Service e seu alias, nunca a Task.

## Application Layer
- **Commands:** `UpsertServicePort`, `RemoveServicePort`.
- **Queries:** `ServicePorts`, incluída em `ServiceRuntimeView`.

## Security Requirements
- Declarar uma porta **não** a expõe publicamente; exposição exige `DomainBinding` (`M04-04`).
- O alias interno é resolvível apenas dentro da overlay do Environment — o isolamento de `M01-17` continua valendo.
- Remover uma porta com binding ativo é bloqueado, para não deixar rota apontando para porta inexistente.

## Observability Requirements
A UI mostra as portas internas e o alias de DNS na aba Networking do Service (doc 10 §14.1).

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Porta duplicada no mesmo Service | Rejeitada por validação. |
| Remover porta com binding ativo | Bloqueado com a lista de bindings. |
| Porta fora do intervalo válido | Rejeitada. |
| Alias colidindo com outro Service | Impossível por construção; teste guarda a propriedade. |
| Aplicação escutando em porta diferente da declarada | O binding fica `DEGRADED` com diagnóstico de conexão ao origin (doc 08 §25). |

## Acceptance Criteria
1. Um Service declara múltiplas portas com nome, `targetPort` e protocolo.
2. Porta duplicada ou fora do intervalo válido é rejeitada.
3. Um Service alcança outro do mesmo Environment pelo alias interno, provado contra Swarm real.
4. O alias **não** é resolvível a partir de outro Environment.
5. Nenhum IP de container ou Task é persistido no banco, verificado por teste.
6. Declarar uma porta não a expõe publicamente.
7. Remover porta com binding ativo é bloqueado com a lista de bindings.
8. Colisão de alias entre Services é impossível por construção.
9. A UI mostra portas internas e alias na aba Networking.

## Required Tests
- **unit**: validação de porta; geração de alias.
- **Docker/Swarm**: resolução do alias dentro da overlay; ausência de resolução cruzada entre Environments.
- **integration**: bloqueio de remoção com binding ativo; ausência de IP persistido.
- **policy**: negativo cross-team.

## Quality Gates
Local Quality Gate + suíte Docker/Swarm.

## Definition of Done
Os 9 Acceptance Criteria satisfeitos, isolamento de discovery provado, nenhum IP persistido, Critical/High = 0.
