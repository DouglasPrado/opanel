---
milestone: "M01"
name: "First Vertical Slice"
type: "milestone"
status: "pending"
---

# M01 — First Vertical Slice

## Identity

| Campo | Valor |
|---|---|
| **ID** | M01 |
| **Nome** | First Vertical Slice |
| **Objetivo** | Provar a espinha dorsal inteira da arquitetura com uma imagem OCI já existente, atravessando UI → domínio → persistência → Operation Engine → Swarm Executor → Docker Swarm → Actual State → UI. |
| **Resultado observável** | Um usuário autenticado cria Team, Project, Cluster, Environment e Service a partir de `nginx:alpine`; a UI mostra `1/1 Healthy` derivado do runtime real; o usuário lê os logs sem acesso ao host; altera réplicas de 1 para 3 e a UI converge para `3/3 Healthy`. |

## Why

Este é o Milestone que decide se a arquitetura funciona. O Anexo A §6 e o Anexo G §7 são explícitos: se a linha `Desired State → Operation → Reconciler → Swarm` estiver errada, **todo o resto fica caro de corrigir**.

M01 também é o primeiro piloto recomendado do Autonomous Development Loop (Anexo H §17.2), porque é significativo o bastante para exercitar banco, domínio, Operations, Executor e UI, e ainda tem um boundary claro.

Ele desbloqueia todos os Milestones seguintes.

## Scope

**Identidade e governança mínima**
- User, Session e autenticação com senha forte e sessões revogáveis.
- Team, TeamMember e a constraint de **exatamente um OWNER ativo** no banco.
- Bootstrap: primeiro usuário vira TEAM_OWNER do primeiro Team **e** INSTANCE_ADMIN da instalação.
- Autorização server-side: Policies, deny by default, escopo de tenancy em toda query de domínio.
- AuditLog append-only com redaction e correlação.

**Modelo central de produto**
- Project, Environment (apontando para Cluster) e Service com desired state versionado.
- Cluster com bootstrap/detecção de Swarm single-node e Node observado.
- Overlay network por Environment.

**Control Plane**
- Operation + OutboxEvent gravados na **mesma transação** da mudança de Desired State.
- Dispatcher do Outbox e sweep periódico de recuperação.
- Resource locks com lease e fencing token.
- Swarm Executor privilegiado, manager-only, com operações tipadas e allowlistadas.
- Service Reconciler: inspect → diff → apply → verify.
- Actual State observado e status derivado.

**Experiência**
- App shell Inertia com team switcher e navegação.
- Telas de Projects, Environments e Services com status derivado e feedback de operação.
- Logs ao vivo do Service.
- Scale manual 1 → 3.

## Out of Scope

| Deixado para | O quê |
|---|---|
| M02 | Restart, resources/placement editáveis, health policy configurável, drift detection, adopt runtime, deleção com cleanup completo, Operations Center, SSE, Docker Events. |
| M03 | Vault, SecretVersion, Swarm Secrets, step-up authentication. |
| M04 | Traefik, domínios, TLS. O Service de M01 **não** é acessível publicamente. |
| M05 | Git, GitHub App, Railpack, BuildKit, Registry. M01 usa imagem OCI pública já existente. |
| M06 | Release, Deployment, rollback, promoção. |
| M08 | Multi-node, enrollment, HA. |
| M09 | Métricas, logs históricos, alertas, autoscaling, terminal. |
| M11 | Convites, ownership transfer, MFA, API tokens, quotas. |

Explicitamente fora: qualquer container solto (`docker run`), qualquer chamada Docker fora do Executor, e qualquer requisição HTTP mantida aberta esperando convergência do runtime.

## Dependencies

- **Hard:** M00.
- **Bloqueios de decisão:** `ADR-0002` (estratégia de identificadores) precisa estar **aceito** antes de `M01-01`; `ADR-0001` (namespace das labels de ownership) antes de `M01-16`. Ver SC-04 e SC-08.
- **Externas:** Docker Engine com Swarm disponível no ambiente (o Swarm Lab de `M00-17` atende para teste; o desenvolvimento local precisa de um Docker acessível).

## User-visible Outcome

O operador consegue, sem tocar em SSH ou Docker CLI:

1. criar conta, virar OWNER do primeiro Team e INSTANCE_ADMIN;
2. inicializar o primeiro Cluster;
3. criar um Project e um Environment de produção;
4. criar um Service a partir de uma imagem OCI existente;
5. ver o Service convergir para `1/1 Healthy`, com status **derivado do runtime**, não de um booleano salvo;
6. ler os logs ao vivo;
7. escalar para 3 réplicas e acompanhar a convergência até `3/3 Healthy`;
8. ver quem fez o quê no Audit Log.

Um usuário de outro Team não enxerga nem alcança nada disso.

## Technical Outcome

- Schema das entidades das seções 3, 4, 5 e 9 do doc 09, na ordem do §29 itens 1–3.
- `desiredRevision`/`appliedRevision` funcionando em Service e Environment.
- Operation Engine durável com state machine, retry e supersession.
- Transactional Outbox provado por teste de crash entre commit e publish.
- Swarm Executor como **único** componente com acesso ao `docker.sock`, verificado por AF-02.
- Reconciler idempotente com lease e fencing token.
- Labels de ownership em todo recurso criado no Swarm.

## Architecture Impact

| Categoria | Impacto |
|---|---|
| Entities | User, Session, Team, TeamMember, InstanceRole, AuditLog, Project, Cluster, Node, Environment, Network, Service, Operation, OperationAttempt, OutboxEvent, ResourceLock, ServiceObservation, NodeObservation. |
| Commands | CreateProject, CreateEnvironment, CreateService, UpdateServiceDesiredState, ScaleService, BootstrapCluster. |
| Queries | ProjectOverview, EnvironmentOverview, ServiceRuntimeView (versões mínimas do doc 09 §23). |
| Events | `service.desired_state.changed.v1`, `node.joined.v1` e os eventos de identidade correspondentes. |
| Jobs | Dispatcher do Outbox, worker de Operation, sweep de reconciliação. |
| Operations | `CREATE_SERVICE`, `UPDATE_SERVICE`, `SCALE`, `CREATE_NETWORK`. |
| Reconcilers | Service Reconciler, Network Reconciler, Node Reconciler (observação). |
| Executor | Swarm Executor com operações tipadas: `InspectService`, `CreateService`, `UpdateServiceSpec`, `RemoveService`, `CreateNetwork`, `ListNodes`, `InspectNode`, `ServiceLogs`. |
| UI | App shell, auth, Projects, Environments, Services, logs, scale. |
| Infrastructure | Acesso isolado ao Docker socket; nenhuma porta 2375. |

## Security

Controles que **nascem** com a capacidade neste Milestone:

- **Autorização** junto de Team/Project/Environment/Service: deny by default, avaliação server-side com escopo carregado, e teste negativo cross-team para **toda** mutação (`M01-04`).
- **Anti-IDOR**: nenhuma query busca recurso só por ID confiando na rota; o boundary de tenancy entra na query (Anexo C §7.3).
- **Isolamento do Docker**: só o Swarm Executor toca o socket; sem rota pública; sem primitive `exec(command)` (`M01-09`), verificado por AF-02.
- **Audit** junto das ações críticas: criação de recursos, bootstrap de cluster, scale e login (`M01-05`).
- **Senhas** com KDF resistente a GPU (Argon2id) e parâmetros versionados; sessões revogáveis server-side (`M01-01`).
- **Payload de Operation** sem plaintext sensível desde o primeiro dia (`M01-13`).
- **Isolamento de rede**: overlay dedicada por Environment; Service não publica porta pública (`M01-17`).

## Observability

- `request_id`, `operation_id`, `team_id`, `project_id`, `environment_id`, `service_id`, `cluster_id`, `node_id` e `actor_id` nos logs das operações correspondentes.
- Timeline mínima da Operation: criada, enfileirada, executando, verificando, terminal, com duração.
- Status derivado, nunca booleano salvo manualmente (doc 07 §17.1).
- Falha do daemon Docker aparece como `Cluster UNREACHABLE/DEGRADED`, não como timeout genérico.
- `ServiceObservation` com `observedAt`, e a UI marcando “last observed …” quando o dado está velho (doc 10 §25).

## Testing

| Classe | Exigência em M01 |
|---|---|
| Static | Toda Story. |
| Unit | State machine de Operation, cálculo de diff, policies, revisions, supersession. |
| Integration (PostgreSQL real) | Constraint de OWNER único, slugs, transação Desired State + Operation + Outbox, idempotência, locks/leases/fencing, cursor de paginação. |
| Contract | Envelope de erro, mutação assíncrona retornando `operationId`, contratos do Executor. |
| Policy / authorization | Matriz de roles + **negativo cross-team obrigatório em toda mutação**. |
| Docker/Swarm | Ciclo completo contra Swarm real: create, inspect, update, scale, remove, convergência de Tasks, drift básico, restart do executor. |
| E2E | A jornada completa do vertical slice. |
| Security | Ausência de socket fora do executor; secret/credencial fora de log; isolamento entre Teams. |
| Performance / Chaos | Não neste Milestone, exceto o teste de crash do Control Plane durante operação (que é de corretude, não de carga). |

## Acceptance Criteria

1. O primeiro cadastro cria User, Team e TeamMember OWNER em uma operação consistente e concede INSTANCE_ADMIN.
2. O banco impede Team ativo sem OWNER e impede dois OWNER ativos simultâneos.
3. Um usuário sem permissão recebe negação **no backend** mesmo manipulando a requisição diretamente.
4. Um usuário de outro Team não consegue ler nem mutar nenhum recurso, comprovado por teste negativo em todas as rotas de mutação.
5. Uma instalação vazia inicializa um Swarm e registra o primeiro Manager como Node.
6. A API pública **não** possui acesso ao `docker.sock`; apenas o Swarm Executor tem, e AF-02 comprova.
7. Criar um Service com imagem existente resulta em um **Docker Swarm Service real** com labels de ownership.
8. A mudança de Desired State, a Operation e o OutboxEvent são gravados na mesma transação; nenhuma chamada de rede ocorre dentro dela.
9. Um crash entre o commit e o publish não perde a intenção: o sweep recupera e a operação progride.
10. Repetir a mesma operação é idempotente e não duplica recurso no Swarm.
11. Duas operações conflitantes no mesmo Service são serializadas ou marcadas `SUPERSEDED`; nunca aplicadas concorrentemente.
12. Um worker com lease expirado não consegue aplicar resultado após o fencing token ter avançado.
13. Alterar réplicas de 1 para 3 converge para `3/3` **ou** retorna um estado degradado explicável — nunca sucesso falso.
14. O status exibido é derivado de `appliedRevision` + observação de runtime, não de coluna booleana.
15. Falha do Docker daemon aparece como Cluster UNREACHABLE/DEGRADED com causa, não como timeout genérico.
16. Logs ao vivo funcionam com múltiplas Tasks e passam por redaction.
17. Toda operação privilegiada gera AuditLog com actor, recurso, ação, resultado, `requestId` e `operationId`.
18. Nenhum AuditLog, log ou payload de Operation contém valor sensível.
19. A requisição HTTP de mutação retorna rapidamente com `operationId`; nenhuma requisição fica aberta esperando o runtime.
20. O E2E do vertical slice passa de ponta a ponta contra Swarm real.

## Exit Gate

M01 pode assumir `READY_FOR_HUMAN_ACCEPTANCE` quando:

- [ ] todas as Stories `required: true` estão `done` com commit registrado;
- [ ] `ADR-0001` e `ADR-0002` estão **aceitos** (não `Proposed`);
- [ ] os 20 Acceptance Criteria têm evidência objetiva no `MILESTONE_REPORT.md`;
- [ ] a suíte Docker/Swarm roda contra Swarm real e termina verde;
- [ ] o E2E do vertical slice passa;
- [ ] a matriz de autorização, incluindo os negativos cross-team, está verde;
- [ ] `bin/fitness` verde, com AF-02, AF-06, AF-07 e AF-08 já significativas (não mais vacuamente verdes);
- [ ] Critical = 0 e High = 0;
- [ ] nenhuma Story `required` está `blocked`;
- [ ] `MILESTONE_REPORT.md` gerado com a demonstração do slice: create Team → Project → Environment → Service → 1/1 → logs → scale → 3/3.

**Gate humano:** aceitação da espinha dorsal. O humano valida comportamento real e coerência com a especificação antes de qualquer capacidade ser empilhada por cima.
