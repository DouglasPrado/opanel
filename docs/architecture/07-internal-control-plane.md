---
document: "07"
title: "Control Plane Interno"
type: "architecture"
status: "approved"
source: "docx"
---

**PLATAFORMA PAAS  
CLUSTER-FIRST**

**Documento técnico consolidado - Parte 7**

Control Plane interno, reconciliadores, jobs e consistência operacional

| **Campo**       | **Definição**                                                                                                                                                                                             |
|-----------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Status          | Documento vivo - v0.7                                                                                                                                                                                     |
| Data            | 05 de setembro de 2026                                                                                                                                                                                    |
| Escopo          | Backend operacional, desired state, actual state, filas, state machines, eventos, locks, retries, idempotência, reconciliação e execução privilegiada no Docker Swarm.                                    |
| Premissas       | Cluster-first; Services do Swarm como primitive de runtime; API pública sem docker.sock; aplicações stateless; dados externos; Vault próprio; build via Railpack/BuildKit.                                |
| Decisão central | A UI nunca executa infraestrutura diretamente. Toda mutação vira Desired State + Operation durável; um executor privilegiado nos Manager nodes aplica a mudança e reconciliadores verificam convergência. |

## Resumo executivo

O Control Plane é o cérebro operacional da plataforma. PostgreSQL guarda o estado desejado e o histórico do produto; Docker Swarm representa o estado efetivamente executado. A plataforma não assume que uma chamada à Docker API é suficiente para declarar sucesso: cada alteração gera uma Operation durável, passa por filas e state machines, é aplicada por um executor privilegiado e somente termina quando o estado observado converge para o desejado.

| **Princípio:** A regra principal é: request HTTP registra intenção; workers executam; reconciliadores confirmam realidade. Nunca manter uma requisição HTTP aberta enquanto um deploy, scale, drain ou certificado é aplicado. |
|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|

# 1. Responsabilidades do Control Plane

| **Responsabilidade** | **Descrição**                                                                                       |
|----------------------|-----------------------------------------------------------------------------------------------------|
| API de produto       | Autenticação, RBAC, validação, CRUD de Teams/Projects/Environments/Services e criação de operações. |
| Desired State Store  | Representação persistente do que a plataforma quer que exista.                                      |
| Operation Engine     | Executa mudanças assíncronas, com estado, retry, timeout e auditoria.                               |
| Reconciliation       | Compara desired state com actual state e corrige divergências.                                      |
| Swarm Executor       | Único componente autorizado a mutar Docker/Swarm.                                                   |
| Event Pipeline       | Propaga alterações de domínio de forma durável e idempotente.                                       |
| Schedulers           | Jobs periódicos: reconcile, health, certificate renewal, autoscaling, cleanup.                      |
| Audit/Observability  | Registra quem pediu, o que mudou, resultado, duração e erros.                                       |

# 2. Componentes internos

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>PUBLIC / PRODUCT PLANE<br />
<br />
Browser / CLI / API token<br />
|<br />
v<br />
API Service<br />
|<br />
+----------------------+<br />
| |<br />
v v<br />
PostgreSQL Audit Log<br />
Desired State + Ops<br />
|<br />
v<br />
Durable Queue<br />
|<br />
+-----+----------------------------+<br />
| |<br />
v v<br />
Operation Workers Reconcilers<br />
| |<br />
+----------------+-----------------+<br />
|<br />
v<br />
Swarm Executor<br />
(Manager nodes only)<br />
|<br />
/var/run/docker.sock<br />
|<br />
v<br />
Docker Swarm</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 2.1 API Service

- Não possui acesso ao docker.sock.

- Valida autenticação, Team, role, quotas e ownership do recurso.

- Faz validação sintática e semântica da alteração solicitada.

- Persiste Desired State e cria Operation na mesma transação sempre que a ação exigir infraestrutura.

- Retorna rapidamente operationId/deploymentId para acompanhamento assíncrono.

- Nunca considera um recurso HEALTHY apenas porque o registro no banco foi atualizado.

## 2.2 Swarm Executor privilegiado

Para reduzir a superfície de privilégio, o acesso ao Docker Socket fica isolado em um serviço interno. Ele roda exclusivamente em Manager nodes, não possui rota pública e só aceita comandos tipados produzidos pelo Control Plane.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>API / Workers<br />
|<br />
| internal authenticated RPC<br />
v<br />
Swarm Executor<br />
|<br />
| /var/run/docker.sock<br />
v<br />
Docker Engine / Swarm API<br />
<br />
NOT allowed:<br />
Browser --------X--------&gt; Docker API<br />
Public API -----X--------&gt; docker.sock<br />
Worker node ----X--------&gt; manager socket</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

| **Decisão:** O Swarm Executor não é um Agent instalado em todos os nodes. É um componente do próprio Control Plane, restrito aos Managers, para encapsular acesso privilegiado ao Docker. |
|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|

## 2.3 Execução ativa e redundância

Podem existir múltiplas réplicas do Swarm Executor para disponibilidade, mas uma mesma mutação sobre um recurso precisa ser serializada. A plataforma usa locks/leases para garantir que duas réplicas não atualizem simultaneamente o mesmo Service.

| **Caso**                | **Política**                                              |
|-------------------------|-----------------------------------------------------------|
| Leituras                | Podem ser concorrentes.                                   |
| Mutação de um Service   | Uma operação ativa por serviceId.                         |
| Mutação de um Node      | Uma operação ativa por nodeId.                            |
| Mutação cluster-wide    | Lock exclusivo por clusterId.                             |
| Executor cai            | Lease expira; outro executor retoma operação idempotente. |
| Resposta Docker perdida | Reconcile do actual state decide se precisa repetir.      |

# 3. Desired State e Actual State

## 3.1 Desired State

Desired State pertence ao PostgreSQL da plataforma. Ele descreve a configuração que o usuário aprovou, independentemente do que o Swarm está executando naquele instante.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>ServiceDesiredState<br />
<br />
imageDigest sha256:abc...<br />
replicas 6<br />
cpuLimit 1.0<br />
memoryLimit 1024 MB<br />
network project-prod<br />
secrets [sv_12, sv_31]<br />
domains [api.example.com]<br />
placement role=worker<br />
revision 42</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 3.2 Actual State

Actual State é observado no Docker/Swarm e em subsistemas relacionados. Ele pode ser mantido em cache no banco para UX e histórico, mas nunca deve substituir a leitura/reconciliação do runtime quando uma decisão crítica precisa ser tomada.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>ServiceActualState<br />
<br />
swarmServiceId q1w2e3...<br />
imageDigest sha256:abc...<br />
desiredTasks 6<br />
runningTasks 5<br />
healthyTasks 5<br />
failedTasks 1<br />
nodes [w1,w2,w3]<br />
observedAt 22:10:41<br />
runtimeVersion Docker Version.Index</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 3.3 Convergência

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>DESIRED ACTUAL<br />
replicas = 6 replicas = 5<br />
image = sha256:abc image = sha256:abc<br />
| |<br />
+---------------+---------------+<br />
|<br />
v<br />
Reconciler<br />
|<br />
v<br />
scale service to 6<br />
|<br />
v<br />
observe 6 / 6<br />
|<br />
v<br />
CONVERGED</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

| **Consistência:** O estado do banco e o runtime podem divergir temporariamente; isso é esperado. O sistema é projetado para convergência, não para fingir transações distribuídas entre PostgreSQL e Docker. |
|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|

# 4. Resource Revision e concorrência

Todo recurso mutável recebe uma revisão monotônica. Cada alteração do usuário incrementa a revisão desejada; Operations registram exatamente qual revisão estão tentando aplicar.

| **Campo**            | **Exemplo** | **Uso**                                                  |
|----------------------|-------------|----------------------------------------------------------|
| desiredRevision      | 42          | Última configuração aprovada no PostgreSQL.              |
| appliedRevision      | 41          | Última revisão confirmada no runtime.                    |
| operationRevision    | 42          | Revisão que uma Operation específica pretende aplicar.   |
| Docker Version.Index | 187         | Controle otimista do próprio Swarm ao atualizar Service. |

Se o usuário salvar v43 enquanto a v42 ainda está em execução, o worker não precisa necessariamente completar a configuração obsoleta. Ele pode marcar v42 como SUPERSEDED e reconciliar diretamente para v43 quando for seguro.

# 5. Operation Engine

## 5.1 Operation como unidade durável

Toda ação de infraestrutura é representada por uma Operation persistente. Isso vale para deploy, scale, restart, rollback, rotate secret, attach domain, drain node e outras mudanças que não são CRUD puramente local.

| **Campo**              | **Descrição**                                                  |
|------------------------|----------------------------------------------------------------|
| id                     | Identificador global da operação.                              |
| type                   | DEPLOY, SCALE, UPDATE_SERVICE, DRAIN_NODE, ROTATE_SECRET, etc. |
| scopeType/scopeId      | Recurso serializado pela operação.                             |
| requestedBy            | Usuário, sistema, webhook ou autoscaler.                       |
| desiredRevision        | Revisão que deve ser aplicada.                                 |
| status                 | Estado atual da state machine.                                 |
| attempt                | Número da tentativa.                                           |
| idempotencyKey         | Deduplicação de requests/retries.                              |
| startedAt/finishedAt   | Tempos operacionais.                                           |
| errorCode/errorDetails | Falha normalizada e detalhes internos protegidos.              |

## 5.2 State machine genérica

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>PENDING<br />
|<br />
v<br />
QUEUED<br />
|<br />
v<br />
RUNNING<br />
|<br />
+---------&gt; WAITING_RUNTIME<br />
| |<br />
| v<br />
| VERIFYING<br />
| |<br />
+-----------------+<br />
|<br />
+----+----+<br />
| |<br />
v v<br />
SUCCEEDED RETRYABLE<br />
|<br />
v<br />
QUEUED<br />
<br />
Terminal alternatives:<br />
FAILED / CANCELED / SUPERSEDED / TIMED_OUT</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 5.3 Tipos de erro

| **Classe**        | **Exemplo**                                               | **Comportamento**                                        |
|-------------------|-----------------------------------------------------------|----------------------------------------------------------|
| Validation        | Porta inválida, domínio duplicado, quota excedida.        | Falha antes de enfileirar.                               |
| Conflict          | Outra operação mutante está ativa no mesmo recurso.       | Serializa, espera ou supersede.                          |
| Transient         | Registry timeout, manager temporariamente indisponível.   | Retry com backoff + jitter.                              |
| Runtime rejection | Imagem inexistente, secret ausente, placement impossível. | Falha contextual; pode exigir ação humana.               |
| Timeout           | Tasks não ficam healthy no limite.                        | Rollback/failed conforme política.                       |
| Unknown outcome   | Docker aplicou, mas resposta foi perdida.                 | Nunca repetir cegamente: observar actual state primeiro. |

# 6. Idempotência

## 6.1 API idempotente

Endpoints que podem ser repetidos por timeout de cliente aceitam uma Idempotency-Key. O par Team + endpoint semântico + key só pode produzir uma operação lógica.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Client<br />
POST /services/svc/deploy<br />
Idempotency-Key: 9cb...<br />
|<br />
v<br />
API transaction<br />
|<br />
+-- key already exists? --&gt; return original Operation<br />
|<br />
+-- new key -------------&gt; create Operation once</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 6.2 Idempotência no executor

- Create deve procurar primeiro recursos já marcados com IDs/labels da plataforma.

- Update aplica a revisão desejada, não uma sequência imperativa cega.

- Delete de recurso já ausente deve ser tratado como convergido quando apropriado.

- Uma operação retomada após crash sempre começa observando estado atual.

- Identificadores Docker nunca são a única identidade do recurso; labels persistentes ligam runtime ao serviceId/releaseId da plataforma.

# 7. Labels de ownership no Swarm

Todo recurso criado pela plataforma deve possuir metadados suficientes para ser identificado e reconciliado mesmo após restart completo do Control Plane.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>com.platform.managed=true<br />
com.platform.team_id=team_01...<br />
com.platform.project_id=prj_01...<br />
com.platform.environment_id=env_01...<br />
com.platform.service_id=svc_01...<br />
com.platform.release_id=rel_01...<br />
com.platform.desired_revision=42</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

| **Boundary:** O usuário pode executar workloads externos no mesmo Swarm, mas a plataforma só reconcilia recursos com ownership explícito. Não apagar nem “adotar” automaticamente Services desconhecidos. |
|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|

# 8. Drift detection

## 8.1 Alteração manual no Docker CLI

Mesmo em uma plataforma fechada, um administrador pode alterar um Service manualmente. Isso cria drift entre desired e actual state.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Platform DB<br />
replicas = 6<br />
|<br />
| manual CLI<br />
| docker service scale api=2<br />
| |<br />
v v<br />
Reconciler &lt;---- Swarm replicas = 2<br />
|<br />
v<br />
Drift detected<br />
|<br />
+-- default: restore to 6<br />
+-- audit event<br />
+-- optional admin action: adopt runtime state</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

Para recursos gerenciados, a política padrão é Platform Wins. Uma operação explícita de Adopt Current State pode existir para Instance Admin, nunca de forma automática.

# 9. Filas e serialização

## 9.1 Filas lógicas

| **Fila**     | **Exemplos**                                        | **Concorrência**                         |
|--------------|-----------------------------------------------------|------------------------------------------|
| deployments  | Build concluído -\> release -\> Swarm update.       | Alta entre Services; serial por Service. |
| runtime      | Scale, restart, resource update, secret binding.    | Serial por recurso.                      |
| cluster      | Node drain, promote/demote, cluster maintenance.    | Baixa; alguns jobs cluster-exclusive.    |
| certificates | Issue, renew, distribute.                           | Paralela por certificado/domínio.        |
| backup-dr    | Snapshots e verificações de recovery.               | Limitada por cluster/storage.            |
| system       | Cleanup, reconciliation sweeps, garbage collection. | Controlada por scheduler.                |

## 9.2 Implementação da fila

A camada de fila deve ser abstraída do domínio. A implementação inicial pode usar BullMQ + Redis gerenciado, alinhada ao ecossistema Node/TypeScript, desde que operações continuem persistidas em PostgreSQL. A fila é mecanismo de entrega; PostgreSQL continua sendo a fonte de verdade sobre a Operation.

| **Regra:** Se Redis perder uma mensagem, um sweep periódico encontra Operations QUEUED/RUNNING sem lease válido e as reenfileira. A durabilidade do produto não pode depender exclusivamente do broker. |
|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|

# 10. Transactional Outbox

## 10.1 Problema

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>BAD<br />
<br />
1. UPDATE service desired state in PostgreSQL OK<br />
2. publish deployment event to queue FAIL<br />
<br />
Result: DB changed but nobody executes it.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 10.2 Solução

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>ONE POSTGRES TRANSACTION<br />
<br />
UPDATE service desired state<br />
INSERT operation<br />
INSERT outbox_event<br />
|<br />
COMMIT<br />
|<br />
v<br />
Outbox Dispatcher<br />
|<br />
v<br />
Queue / consumers<br />
|<br />
v<br />
mark event delivered</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

A Outbox elimina a janela entre “salvei a intenção” e “publiquei o trabalho”. Consumidores também precisam de Inbox/Dedup quando recebem webhooks ou eventos que podem ser entregues mais de uma vez.

# 11. Reconcilers

## 11.1 Conceito

Reconciler é um loop que observa desired state + actual state e executa apenas as ações necessárias para aproximá-los. Ele não depende de ter visto todos os eventos anteriores.

| **Reconciler**         | **Responsabilidade**                                                    |
|------------------------|-------------------------------------------------------------------------|
| Service Reconciler     | Imagem, replicas, resources, placement, networks, configs, labels.      |
| Deployment Reconciler  | Confirma rollout, health, timeout e rollback.                           |
| Secret Reconciler      | Materializa SecretVersion como Swarm Secret e mantém bindings corretos. |
| Ingress Reconciler     | Labels/rotas do Traefik e associação do Service ao ingress.             |
| Certificate Reconciler | Versão ativa do certificado distribuída para os ingress nodes.          |
| Node Reconciler        | Status, labels, availability, drain e readiness.                        |
| Cluster Reconciler     | Quorum, managers, ingress capacity e readiness geral.                   |
| Autoscaling Reconciler | Converte decisão do autoscaler em desired replicas.                     |
| Garbage Collector      | Remove imagens/secrets/releases sem referência conforme política.       |

## 11.2 Event-driven + periodic

Eventos aceleram a reação, mas sweeps periódicos garantem correção. Docker Events pode disparar rechecks rápidos; ele não é usado como ledger definitivo.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Docker Events -----&gt; fast reconcile trigger<br />
|<br />
v<br />
Reconciler<br />
^<br />
|<br />
Periodic sweep ----------+<br />
(e.g. every N seconds/minutes)<br />
<br />
Correctness comes from re-reading state,<br />
not from trusting an uninterrupted event stream.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 11.3 Algoritmo de reconcile

Cada execução de reconcile deve ser pequena, determinística e retomável. O loop não assume que é o primeiro a tocar o recurso e não usa memória de processo como fonte de verdade.

1.  Adquirir lock/lease do recurso com fencing token.

2.  Carregar Desired State e desiredRevision mais recentes.

3.  Inspecionar Actual State diretamente no runtime.

4.  Calcular diff sem executar efeitos colaterais.

5.  Se não houver diff, confirmar convergência/appliedRevision e encerrar.

6.  Se houver diff, construir um plano ordenado de ações tipadas.

7.  Aplicar a menor mutação segura necessária via Swarm Executor.

8.  Re-inspecionar runtime; nunca assumir que a chamada anterior definiu o estado final.

9.  Persistir ReconciliationRun, eventos e próxima verificação quando ainda não convergiu.

10. Liberar lease somente após persistir o resultado da tentativa.

## 11.4 Classes de diff

| **Classe**  | **Exemplo**                                                              | **Ação**                                                                     |
|-------------|--------------------------------------------------------------------------|------------------------------------------------------------------------------|
| NOOP        | Desired e Actual equivalentes.                                           | Nenhuma mutação; atualizar observedAt/appliedRevision.                       |
| CREATE      | Service esperado não existe.                                             | Criar recurso com labels de ownership e revisão.                             |
| UPDATE_SAFE | Label, limite ou configuração atualizável sem troca completa.            | Atualizar Service Spec conforme política.                                    |
| ROLLOUT     | Novo image digest, secret/config ou mudança que recria Tasks.            | Iniciar rollout e acompanhar health.                                         |
| DELETE      | Desired State remove recurso ainda existente.                            | Remover somente após checar dependências/policy.                             |
| BLOCKED     | Placement impossível, quota, secret ausente ou dependência indisponível. | Não repetir agressivamente; registrar razão e aguardar condição/ação humana. |
| DRIFT       | Runtime foi alterado fora da plataforma.                                 | Platform Wins por padrão ou Adopt explícito por admin.                       |

# 12. Fluxo completo: scale

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>USER<br />
Scale API 3 -&gt; 8<br />
|<br />
v<br />
POST /services/:id/scale<br />
|<br />
v<br />
Auth + RBAC + quota<br />
|<br />
v<br />
PostgreSQL transaction<br />
desiredReplicas = 8<br />
desiredRevision = 57<br />
Operation(SCALE,57)<br />
OutboxEvent<br />
|<br />
v<br />
Queue<br />
|<br />
v<br />
Runtime Worker<br />
|<br />
acquire service lock<br />
|<br />
v<br />
Swarm Executor<br />
|<br />
Docker Service Update<br />
|<br />
v<br />
Swarm scheduler<br />
|<br />
tasks converge 8/8<br />
|<br />
v<br />
Reconciler verifies<br />
|<br />
appliedRevision = 57<br />
Operation = SUCCEEDED<br />
|<br />
v<br />
UI receives event / polling update</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

# 13. Fluxo completo: deploy

A Parte 2 definiu Git -\> Railpack/BuildKit -\> OCI image -\> Registry. A partir do artifact, o Control Plane assume o deploy.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Artifact<br />
image@sha256:NEW<br />
|<br />
v<br />
Create Release<br />
|<br />
v<br />
Environment/Service desiredRevision++<br />
|<br />
v<br />
DEPLOY Operation<br />
|<br />
v<br />
Swarm Executor<br />
|<br />
Update Service Spec<br />
image digest<br />
secrets/configs<br />
labels/release id<br />
update policy<br />
|<br />
v<br />
Rolling update<br />
|<br />
+--&gt; task failed ------&gt; policy / rollback<br />
|<br />
v<br />
Health verification<br />
|<br />
v<br />
Release = ACTIVE<br />
previous = SUPERSEDED<br />
Operation = SUCCEEDED</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 13.1 Release imutável

- Release referencia image digest, nunca apenas uma tag mutável.

- Release registra exatamente as SecretVersions e configurações usadas no deploy.

- Rollback seleciona uma Release anterior; não executa novo build.

- Promoção HML -\> Production pode reaproveitar o mesmo artifact digest e mudar apenas bindings/configuração específica do Environment.

# 14. Locks e leases

## 14.1 Tipos

| **Lock**        | **Escopo**                         | **Exemplo**                                              |
|-----------------|------------------------------------|----------------------------------------------------------|
| Resource Lock   | serviceId / nodeId / certificateId | Impede dois updates concorrentes no mesmo Service.       |
| Cluster Lock    | clusterId                          | Promote/demote manager, restore Raft, operações globais. |
| Build Slot      | builder/Team                       | Controla saturação de BuildKit.                          |
| Deployment Slot | Environment/Service                | Impede deploys sobrepostos incompatíveis.                |
| Lease           | worker execution                   | Permite retomada se processo morre sem liberar lock.     |

Locks devem possuir TTL/lease e owner token. O worker renova heartbeat durante a execução. Um novo worker só assume após expiração e sempre revalida actual state antes de agir.

# 15. Retry, backoff e timeout

Retry deve ser política explícita por tipo de operação. Repetir tudo indiscriminadamente é perigoso em infraestrutura.

| **Operação**                    | **Retry sugerido**                                   | **Timeout / observação**                         |
|---------------------------------|------------------------------------------------------|--------------------------------------------------|
| Registry pull/transient network | Exponencial + jitter                                 | Curto/médio.                                     |
| Docker service update           | Retry somente após observar Version/actual state     | Evita update duplicado/conflito.                 |
| Rolling health                  | Polling/reconcile                                    | Timeout definido pelo deploy policy.             |
| Certificate distribution        | Retry por ingress target                             | Cert só vira ACTIVE após quorum/política.        |
| Node drain                      | Reconcile até Tasks migrarem                         | Pode exigir intervenção se placement impossível. |
| Delete                          | Idempotente; recurso ausente pode significar sucesso | Respeitar dependências.                          |

# 16. Cancelamento e supersession

## 16.1 Cancelamento

PENDING/QUEUED pode ser cancelado diretamente. RUNNING só pode ser cancelado quando a operação define um ponto seguro de interrupção. Depois de uma mutação no Swarm, muitas operações precisam completar ou reconciliar para um estado consistente antes de aceitar outra intenção.

## 16.2 Supersession

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>desired revision 10 -&gt; deploy A queued<br />
|<br />
user saves revision 11 before A applies<br />
|<br />
v<br />
A = SUPERSEDED<br />
B = QUEUED(revision 11)<br />
|<br />
v<br />
executor reconciles directly toward revision 11</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

# 17. Estado e UX

## 17.1 Status de Service

O status apresentado na UI deve ser derivado, não um booleano salvo manualmente.

| **Status** | **Condição resumida**                                             |
|------------|-------------------------------------------------------------------|
| PENDING    | Desired State existe, mas ainda não aplicado.                     |
| DEPLOYING  | Operation mutante/rollout em progresso.                           |
| HEALTHY    | Applied revision = desired revision e health policy satisfeita.   |
| DEGRADED   | Parcialmente funcional; tasks/metrics fora do esperado.           |
| FAILED     | Última tentativa terminou em falha e desired state não convergiu. |
| DRIFTED    | Runtime foi alterado fora do Control Plane.                       |
| PAUSED     | Usuário/sistema suspendeu reconciliação de mutações específicas.  |

## 17.2 Timeline de operação

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Deployment #2184<br />
<br />
22:10:01 Requested by Douglas<br />
22:10:01 Revision 57 created<br />
22:10:02 Artifact resolved sha256:...<br />
22:10:03 Swarm update accepted<br />
22:10:08 2/6 tasks updated<br />
22:10:14 6/6 tasks running<br />
22:10:18 Health policy satisfied<br />
22:10:18 Release activated<br />
22:10:18 SUCCEEDED (17.2s)</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

# 18. WebSocket/SSE e atualizações da UI

A interface não deve fazer polling agressivo de Docker. Ela recebe eventos derivados do Control Plane, por SSE ou WebSocket, e pode usar polling de baixa frequência como fallback.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Swarm / Reconciler<br />
|<br />
v<br />
Platform Event<br />
|<br />
+--&gt; PostgreSQL history<br />
|<br />
+--&gt; Realtime Gateway<br />
|<br />
v<br />
Browser<br />
<br />
The browser receives sanitized product events,<br />
not raw Docker event payloads.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

# 19. Modelo de dados sugerido

| **Entidade**          | **Campos centrais**                                                                                    |
|-----------------------|--------------------------------------------------------------------------------------------------------|
| services              | id, environmentId, desiredRevision, appliedRevision, desiredSpec, statusDerivedAt                      |
| service_runtime_state | serviceId, swarmServiceId, observedSpec, taskSummary, dockerVersionIndex, observedAt                   |
| operations            | id, type, scopeType, scopeId, desiredRevision, status, attempt, idempotencyKey, leaseOwner, timestamps |
| operation_steps       | operationId, step, status, startedAt, finishedAt, metadataSafe                                         |
| outbox_events         | id, aggregateType, aggregateId, type, payload, createdAt, deliveredAt                                  |
| inbox_events          | source, externalId, processedAt, resultRef                                                             |
| reconciliation_runs   | resourceType, resourceId, trigger, diff, actions, result, timestamps                                   |
| resource_locks        | scopeKey, owner, leaseUntil, fencingToken                                                              |
| releases              | serviceId, artifactDigest, configSnapshot, secretBindingsSnapshot, status                              |
| audit_events          | actor, action, target, requestId, operationId, result, timestamp                                       |

# 20. Contratos internos

## 20.1 Command

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Command {<br />
id<br />
type<br />
clusterId<br />
resourceType<br />
resourceId<br />
desiredRevision<br />
requestedBy<br />
correlationId<br />
idempotencyKey<br />
payload<br />
}</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 20.2 Executor result

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>ExecutionResult {<br />
commandId<br />
outcome: APPLIED | NOOP | CONFLICT | RETRYABLE | FAILED<br />
observedRuntimeVersion<br />
runtimeResourceIds<br />
safeMetadata<br />
errorCode?<br />
}</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 20.3 Reconcile result

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>ReconcileResult {<br />
resourceId<br />
desiredRevision<br />
observedRevision<br />
converged<br />
driftDetected<br />
actions[]<br />
nextCheckAt?<br />
}</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

# 21. Segurança interna

- API pública nunca recebe docker.sock nem credenciais de manager.

- Swarm Executor fica em overlay network privada e sem published port.

- RPC interno autenticado e autorizado por identidade de serviço; comandos não aceitam shell arbitrário.

- Exec/terminal é um caminho separado, permissionado e auditado conforme Parte 3/4.

- Payloads de Operation não armazenam plaintext de secrets; somente SecretVersion IDs.

- Logs removem tokens, headers sensíveis, registry credentials e material criptográfico.

- Toda ação privilegiada possui requestId, operationId e actor para correlação forense.

| **Proibido:** Não criar um endpoint interno “exec(command: string)”. O executor deve expor operações tipadas como UpdateServiceSpec, InspectService, DrainNode, CreateSecret e RemoveSecret. |
|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|

# 22. Falhas que o desenho precisa tolerar

| **Falha**                                | **Comportamento esperado**                                                         |
|------------------------------------------|------------------------------------------------------------------------------------|
| API reinicia após salvar Desired State   | Outbox/Operation permanece; execução continua.                                     |
| Queue perde mensagem                     | Sweep detecta Operation sem progresso e reenfileira.                               |
| Worker morre no meio da operação         | Lease expira; sucessor observa runtime e retoma idempotentemente.                  |
| Executor perde resposta do Docker        | Não assume falha; re-inspeciona actual state.                                      |
| Manager indisponível                     | Operation entra em retry/backoff; nenhuma configuração é inventada localmente.     |
| Alteração manual no Swarm                | Reconciler detecta drift e restaura desired state por padrão.                      |
| Dois usuários alteram o mesmo Service    | Revision/optimistic concurrency + serialização por Service.                        |
| Webhook Git duplicado                    | Inbox/dedup evita dois deploys lógicos para o mesmo evento quando política exigir. |
| Deploy novo chega durante rollout antigo | Política de cancel/supersede/queue determina a ordem sem concorrência cega.        |

# 23. Reconciliation cadence

Nem tudo precisa do mesmo intervalo. O scheduler deve escolher frequência conforme criticidade e custo.

| **Objeto**         | **Trigger rápido**             | **Sweep periódico**                                              |
|--------------------|--------------------------------|------------------------------------------------------------------|
| Service            | Operation + Docker Events      | Segundos/dezenas de segundos em rollout; minutos quando estável. |
| Node               | Docker node/task events        | Curto durante manutenção; regular para readiness.                |
| Certificate        | Domain/cert events             | Horas/dias para renovação; mais rápido perto de expiry.          |
| Cluster            | Node/manager changes           | Regular + após alteração administrativa.                         |
| Garbage collection | Release/image lifecycle events | Janela periódica controlada.                                     |
| Autoscaler         | Metrics window                 | Cadência da Parte 3 com cooldown.                                |

# 24. API operacional

| **Endpoint conceitual**          | **Comportamento**                                                             |
|----------------------------------|-------------------------------------------------------------------------------|
| PATCH /services/:id              | Atualiza desired spec + revision; gera Operation se mudança afeta runtime.    |
| POST /services/:id/deployments   | Cria Release/Deployment apontando para artifact imutável.                     |
| POST /services/:id/scale         | Muda desired replicas e cria Operation.                                       |
| POST /services/:id/restart       | Cria Operation sem alterar configuração funcional.                            |
| POST /operations/:id/cancel      | Solicita cancelamento quando a state machine permite.                         |
| GET /operations/:id              | Estado, steps, erro normalizado e timestamps.                                 |
| GET /services/:id/runtime        | Actual state observado e diferenças para desired.                             |
| POST /services/:id/adopt-runtime | Instance Admin transforma runtime atual em novo desired state, com auditoria. |
| POST /clusters/:id/reconcile     | Dispara sweep administrativo; não bypassa locks/regras.                       |

# 25. Ordem de implementação

1\. Criar Operation + desiredRevision/appliedRevision no modelo de Service.

2\. Implementar API assíncrona que salva Desired State e retorna operationId.

3\. Criar Outbox + dispatcher e fila durável.

4\. Criar Swarm Executor interno com operações tipadas e acesso isolado ao docker.sock.

5\. Implementar resource locks/leases e fencing token.

6\. Implementar Service Reconciler: inspect -\> diff -\> apply -\> verify.

7\. Implementar Deployment state machine e convergência de rolling update.

8\. Adicionar Docker Events apenas como acelerador de reconcile.

9\. Adicionar sweeps periódicos para recuperação após perda de mensagens/processos.

10\. Adicionar drift detection, audit trail e status derivados para UI.

11\. Adicionar reconciliadores de secrets, ingress, certificates e nodes.

12\. Integrar autoscaler e demais controllers das Partes 3-6.

# 26. Decisões registradas nesta parte

| **Decisão**                                         | **Resultado**                                                                    |
|-----------------------------------------------------|----------------------------------------------------------------------------------|
| PostgreSQL é source of truth do produto             | Desired State, Operations e histórico sobrevivem a restart de workers/queue.     |
| Docker/Swarm é source of truth do runtime observado | Actual State é lido/reconciliado, não inferido apenas pelo banco.                |
| API não chama Docker diretamente                    | Toda mutação de infra é assíncrona e durável.                                    |
| docker.sock isolado                                 | Somente Swarm Executor interno em Manager nodes possui acesso.                   |
| Sem agent por node                                  | Não existe daemon proprietário obrigatório em cada worker/ingress/builder.       |
| Desired vs Actual + reconcile                       | Falhas parciais e drift são tratados como condição normal do sistema.            |
| Outbox + Operations                                 | Nenhuma intenção depende de publish não transacional para existir.               |
| Idempotência + locks + revisions                    | Retries e concorrência não podem produzir mutações duplicadas/desordenadas.      |
| Fila não é source of truth                          | Mensagens podem ser reconstruídas a partir do PostgreSQL.                        |
| Platform Wins em recursos gerenciados               | Mudanças manuais são revertidas, salvo operação explícita de adopt.              |
| Release imutável                                    | Deploy/rollback trabalham com image digest e snapshots de configuração/bindings. |

## Próxima parte sugerida

| **Continuação:** Parte 8: Networking, domínio e Edge em profundidade - overlay networks, isolamento entre Environments, Traefik routing model, Load Balancer L4, DNS automation, Certificate Manager, wildcard domains, IPv4/IPv6, rate limiting e fluxos de request ponta a ponta. |
|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
