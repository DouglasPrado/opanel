# M01-08 — Cluster entity and single-node Swarm bootstrap

## Objective
Registrar o Cluster como recurso de produto e inicializar (ou detectar) um Docker Swarm de um único node, com preflight checks — sem expor a Docker API.

## Outcome
Uma instalação vazia executa preflight, inicializa o Swarm, persiste `swarmId` e mostra o Cluster como `READY` ou `DEGRADED` **com diagnóstico**, nunca como sucesso vago.

## References
- `docs/architecture/06-infrastructure-provisioning.md` §3 (primeiro bootstrap), §3.2 (preflight), §4 (portas e Docker API), §14 (cluster readiness)
- `docs/architecture/09-data-model-apis-contracts.md` §4.1 (Cluster)
- `docs/architecture/10-ui-use-cases.md` UC-003
- `docs/implementation/SPEC_CONFLICTS.md` SC-12

## Preconditions
`M01-04` e `M01-05` done. Docker Engine acessível ao Control Plane.

## Scope
- `Cluster`: id, **teamId NOT NULL** (SC-12), name, slug, status (`PROVISIONING`, `READY`, `DEGRADED`, `MAINTENANCE`, `UNREACHABLE`, `DELETING`), swarmId (UNIQUE quando conhecido), desiredRevision/appliedRevision, timestamps.
- Preflight checks do doc 06 §3.2 aplicáveis a um bootstrap local: SO/arquitetura suportados, acesso ao daemon, hostname resolvível, relógio sincronizado, disco e inodes mínimos, portas necessárias livres, interface/IP de advertise.
- Inicialização do Swarm com `advertise address` **explícito** quando houver múltiplas interfaces; detecção e adoção de Swarm já existente **somente** se compatível e autorizado.
- Persistência de `swarmId` e status derivado.
- Tela de inicialização mostrando os checks, o que passou e o que falhou.

## Out of Scope
- Swarm Executor (`M01-09`) — esta Story usa o caminho mínimo de bootstrap; toda operação posterior passa pelo Executor.
- Enrollment de nodes adicionais e multi-node (`M08`).
- Networks de Environment (`M01-17`).
- Cluster Readiness completo com HA (`M08-12`); aqui readiness é `Operational` sem `HA`.
- Provisionamento cloud (backlog/M08).

## Domain Impact
**Entidade:** `Cluster`.
**Regra de tenancy (SC-12):** `teamId` é `NOT NULL`. Cluster de sistema **não** é modelado; se vier a ser necessário, exige ADR próprio.
**Transições:** `PROVISIONING → READY | DEGRADED`; `READY ↔ DEGRADED ↔ UNREACHABLE`.

## Application Layer
- **Commands:** `BootstrapCluster`, `RefreshClusterStatus`.
- **Queries:** `ClusterReadinessView` (versão mínima: operacional sim/não, com a lista de checks).
- **Policies:** bootstrap exige `INSTANCE_ADMIN`; leitura exige membership no Team.

## Async / Control Plane
O bootstrap é uma operação de infraestrutura e por isso é **assíncrona e durável**: a requisição registra a intenção e retorna `operationId`; a execução acontece em worker. Como `M01-13` (Operation) ainda não existe quando esta Story começa, a implementação usa o caminho de Operation assim que ele existir — a ordem de `dependsOn` garante que `M01-13` venha depois, portanto esta Story entrega o **comando síncrono de preflight + init** e a Story `M01-18` reconecta o Cluster ao ciclo de reconciliação. Qualquer chamada ao Docker é feita fora de transação de banco.

## UI Impact
Tela de inicialização de Cluster com: checks de readiness, IPs detectados, sugestão de advertise address, confirmação explícita, e resultado com diagnóstico por check.

## Security Requirements
- **Nunca** expor `tcp://0.0.0.0:2375` nem publicar a Docker API (doc 04 §15, doc 06 §4.2).
- O navegador nunca fala com o Docker.
- O join token do Swarm **não** é exibido nesta Story e nunca é gravado em log ou AuditLog (doc 04 §14.2).
- Bootstrap exige `INSTANCE_ADMIN` e é auditado.
- Portas internas do Swarm restritas à rede confiável; o preflight verifica e reporta.

## Observability Requirements
- Status do Cluster é **derivado** de observação, com `observedAt`.
- Falha do daemon aparece como `UNREACHABLE`/`DEGRADED` **com causa classificada**, não como timeout genérico (critério explícito do Anexo A §5 M2).
- Cada check de preflight registra resultado individual.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Docker daemon indisponível | Cluster `UNREACHABLE` com causa; não trava a UI nem derruba a aplicação. |
| Swarm já existe | Detectar; adotar **somente** se compatível e explicitamente autorizado; caso contrário, bloquear com diagnóstico. |
| Múltiplas interfaces de rede | Exigir escolha explícita do advertise address; não adivinhar. |
| Relógio fora de sincronia | Preflight falha — TLS, tokens e consenso dependem disso. |
| Porta ocupada | Preflight falha nomeando a porta e o processo. |
| Versão de Engine incompatível | Falha explícita nomeando versão encontrada e suportada. |

## Acceptance Criteria
1. Uma instalação vazia inicializa um Swarm e registra o `Cluster` com `swarmId`.
2. `Cluster.teamId` é `NOT NULL` no banco.
3. O preflight executa todos os checks aplicáveis e reporta cada um individualmente.
4. Relógio fora de sincronia, porta ocupada ou versão incompatível **bloqueiam** o bootstrap com diagnóstico específico.
5. Com múltiplas interfaces, o advertise address precisa ser escolhido explicitamente.
6. Um Swarm preexistente é detectado e só é adotado se compatível e autorizado.
7. Docker daemon indisponível resulta em `UNREACHABLE`/`DEGRADED` com causa classificada, não timeout genérico.
8. A Docker API não é exposta em rede; nenhuma porta 2375 é aberta, verificado por teste.
9. Bootstrap exige `INSTANCE_ADMIN` e gera AuditLog.
10. Nenhum join token aparece em log, AuditLog ou resposta.
11. O status do Cluster é derivado de observação com `observedAt`, nunca de booleano salvo.

## Required Tests
- **unit**: avaliação de preflight; derivação de status.
- **integration**: bootstrap contra Docker real do Swarm Lab; daemon indisponível; Swarm preexistente.
- **Docker/Swarm**: init e leitura de `swarmId`; versão incompatível.
- **policy**: bootstrap negado a não-`INSTANCE_ADMIN`; negativo cross-team na leitura.
- **security**: ausência de porta 2375; join token fora de log.

## Quality Gates
Local Quality Gate (Ruby/Rails, Database, Infrastructure) + suíte Docker/Swarm contra Swarm Lab.

## Definition of Done
Os 11 Acceptance Criteria satisfeitos contra Swarm real, falha de daemon classificada, ausência de Docker API exposta comprovada, Critical/High = 0.
