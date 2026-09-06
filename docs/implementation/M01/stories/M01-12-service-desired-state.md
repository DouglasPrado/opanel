# M01-12 — Service desired state and revisions

## Objective
Persistir a intenção do usuário sobre um workload — imagem, réplicas, portas, recursos e health — como Desired State versionado, **sem tocar no Docker**.

## Outcome
Um Service existe no PostgreSQL com `desiredRevision` que incrementa a cada alteração aprovada; nada é aplicado ao runtime nesta Story.

## References
- `docs/architecture/09-data-model-apis-contracts.md` §5.3 (Service), §17 (state machines), §18 (constraints), §27 (validações essenciais)
- `docs/architecture/07-internal-control-plane.md` §3.1 (Desired State), §4 (revisions e concorrência)
- `docs/annexes/G-agent-oriented-development.md` §9 (template de Story M01-06, “Create Service”)
- `docs/architecture/10-ui-use-cases.md` UC-013

## Preconditions
`M01-11` done.

## Scope
- `Service`: id, environmentId, name, slug, serviceType, imageRef/digest, replicas, command?, args?, ports, healthcheck, cpuReservation/cpuLimit, memoryReservation/memoryLimit, placement básico, desiredRevision, appliedRevision, status, timestamps, archivedAt/deletedAt.
- Constraint `UNIQUE(environmentId, slug) WHERE deletedAt IS NULL`.
- Criação a partir de **imagem OCI existente** com resolução para digest quando a tag for mutável (doc 10 UC-013: “tag mutável → resolver digest e armazenar release por digest”). Em M01 a resolução é registrada no Service; `Release` formal chega em M06.
- Optimistic concurrency: `expectedRevision` em mutações sensíveis; conflito retorna `REVISION_CONFLICT`.
- Validações do doc 09 §27 aplicáveis: Environment e Cluster ativos, slug livre, porta válida, recursos coerentes.

## Out of Scope
- Qualquer chamada ao Docker (`M01-18` reconcilia).
- Operation e Outbox (`M01-13`).
- Secret bindings (`M03-06`).
- Build a partir de Git (`M05`).
- Domínio e exposição pública (`M04`).
- Autoscaling (`M09-12`).

## Domain Impact
**Entidade:** `Service`.
**Relacionamentos:** `Environment 1—N Service`.
**Transições:** `DRAFT/PROVISIONING → RUNNING ↔ DEGRADED | STOPPED → DELETING` (doc 09 §17). Transição inválida é **rejeitada** com `INVALID_STATE_TRANSITION`, nunca corrigida em silêncio.
**Nome técnico:** determinístico e derivado de IDs (SC-09); o produto nunca depende dele como identificador primário.

## Application Layer
- **Commands:** `CreateService`, `UpdateServiceDesiredState`.
- **Queries:** `ServicesForEnvironment`, `ServiceRuntimeView` (parte desired; a parte actual chega em `M01-19`).
- **Policies:** `ServicePolicy` — criar/alterar exige ADMIN ou DEVELOPER conforme escopo.

## API Impact
Mutação retorna o recurso e, quando afeta runtime, o `operationId` — que passa a existir em `M01-13`. `expectedRevision` aceito para compare-and-swap; conflito retorna `REVISION_CONFLICT` do doc 09 §28.

## UI Impact
Formulário de criação de Service por imagem: nome, imagem, réplicas, porta interna, recursos e health check. Progressive disclosure: placement e política de rollout ficam em “avançado”.

## Security Requirements
- Validação de entrada em todo campo que cruza a borda: imagem, porta, comando, recursos.
- `imageRef` é validada; não aceitar referência que permita escapar do registry pretendido.
- Nenhum campo de Service aceita valor sensível — variáveis sensíveis são Vault (M03), e a UI deixa isso explícito.
- Criar e alterar geram AuditLog; negativo cross-team obrigatório.
- Recursos sem limite explícito são sinalizados (Anexo B §10 exige alerta para service sem limites em produção).

## Observability Requirements
Logs com `service_id`, `environment_id`, `project_id`, `team_id`, `actor_id`, `request_id` e a `desiredRevision` resultante.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Slug duplicado no Environment | Validação inline. |
| Environment ou Cluster inativo | Criação bloqueada com causa. |
| `expectedRevision` desatualizada | `REVISION_CONFLICT`; a UI mostra o que mudou. |
| Transição de estado inválida | `INVALID_STATE_TRANSITION`; nunca “corrigir” silenciosamente. |
| Imagem com tag mutável | Resolver e registrar o digest; a tag fica como alias. |
| Recursos sem limite | Permitido com aviso explícito, registrado. |

## Acceptance Criteria
1. Um Service é criado dentro de um Environment com imagem, réplicas, porta e recursos, **sem nenhuma chamada ao Docker**.
2. `UNIQUE(environmentId, slug) WHERE deletedAt IS NULL` existe e é provado por caso negativo.
3. `desiredRevision` incrementa a cada alteração relevante do desired state.
4. `expectedRevision` desatualizada produz `REVISION_CONFLICT`, provado por teste concorrente.
5. Transição de estado inválida é rejeitada com `INVALID_STATE_TRANSITION`.
6. Criação com Environment ou Cluster inativo é bloqueada com causa explícita.
7. Uma imagem com tag mutável tem o digest resolvido e persistido.
8. O nome técnico do Swarm é derivado de IDs, e renomear o Service **não** altera esse nome.
9. Service sem limite de recursos é aceito com aviso explícito registrado.
10. Nenhum campo de Service aceita ou persiste valor sensível.
11. Criar e alterar geram AuditLog e passam por Policy, com negativo cross-team.

## Required Tests
- **unit**: state machine; incremento de revisão; derivação do nome técnico; validação de `imageRef`, porta e recursos.
- **integration**: constraint de slug; `REVISION_CONFLICT` em teste concorrente com barreira; bloqueio por Environment inativo.
- **policy**: matriz de roles + negativo cross-team.
- **security**: nenhum valor sensível aceito; `imageRef` maliciosa rejeitada.

## Quality Gates
Local Quality Gate (Ruby/Rails, Database, React/TypeScript) + suíte cross-team.

## Definition of Done
Os 11 Acceptance Criteria satisfeitos, conflito de revisão provado por teste concorrente, nenhuma chamada Docker nesta Story (verificado por AF-01/AF-02), Critical/High = 0.
