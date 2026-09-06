---
document: "03"
title: "Runtime, Observabilidade e Operações"
type: "architecture"
status: "approved"
source: "docx"
---

**PLATAFORMA PAAS  
CLUSTER-FIRST**

**Documento técnico consolidado - Parte 3**

Runtime, health, observabilidade, autoscaling, operação de cluster e resposta a falhas

| **Campo**       | **Definição**                                                                                                                                |
|-----------------|----------------------------------------------------------------------------------------------------------------------------------------------|
| Status          | Documento vivo - v0.3                                                                                                                        |
| Data            | 05 de setembro de 2026                                                                                                                       |
| Escopo          | Definir como workloads são operados depois do deployment e como a plataforma detecta, explica e reage a falhas                               |
| Premissas       | Cluster-first com Docker Swarm; aplicações stateless; Postgres, Redis e object storage inicialmente gerenciados por terceiros                |
| Decisão central | Swarm reconcilia o estado do runtime; nossa plataforma agrega observabilidade, políticas operacionais, autoscaling e experiência de operação |

## Resumo executivo

Depois que a Parte 2 transforma código em uma imagem OCI e publica uma Release, a Parte 3 define como essa Release vive no cluster. O objetivo não é substituir o Swarm: o Swarm continua responsável por Services, Tasks, placement, restart e reconciliação. A plataforma acrescenta o contexto de produto que o Swarm não possui: Team, Project, Environment, histórico, políticas, métricas, alertas, autoscaling, auditoria e uma interface operacional coerente.

| **Princípio:** O runtime deve ser operável sem SSH na rotina normal. SSH continua existindo como ferramenta de emergência do operador da infraestrutura, não como fluxo padrão para deploy, restart, logs ou troubleshooting. |
|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|

# 1. Objetivo e limites desta parte

## 1.1 Resultados esperados

- Um modelo claro para diferenciar Service, Task, Container e estado desejado/estado atual.

- Health model que combine Docker HEALTHCHECK, estado das Tasks e probes da própria plataforma.

- Restart e self-healing nativos do Swarm, configuráveis pela plataforma.

- CPU e memória com limits e reservations explícitos por Service.

- Placement por labels, zonas, roles de node e requisitos de capacidade.

- Scaling manual e autoscaling construído pela plataforma sobre métricas.

- Logs ao vivo e histórico pesquisável com contexto de Team/Project/Environment/Service/Deployment.

- Métricas de host, container, Service, ingress e cluster.

- Alertas, incidentes e timeline operacional.

- Operações de manutenção de node usando Active, Pause e Drain.

- Terminal/exec e ações sensíveis sempre auditados e protegidos por RBAC.

## 1.2 Fora do escopo imediato

- HA de Postgres, Redis ou object storage dentro do cluster; estes serviços serão terceirizados inicialmente.

- Service mesh ou mTLS aplicação-a-aplicação como requisito inicial.

- Tracing distribuído obrigatório na primeira fase.

- Autoscaling baseado em modelos preditivos; a primeira versão será reativa e determinística.

- Kubernetes HPA/VPA ou outro scheduler além do Docker Swarm.

# 2. Modelo de runtime do Swarm

A entidade operacional da plataforma deve ser o Service. O usuário não administra containers diretamente como unidade persistente. Containers são consequência temporária de Tasks criadas pelo Swarm para satisfazer a especificação do Service.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Service: albert-production-api<br />
Desired replicas: 3<br />
Image: registry/app@sha256:abc...<br />
|<br />
v<br />
Docker Swarm<br />
|<br />
+----+----+<br />
| | |<br />
Task1 Task2 Task3<br />
| | |<br />
v v v<br />
Container Container Container</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

| **Objeto** | **Responsabilidade**                                                                                                         |
|------------|------------------------------------------------------------------------------------------------------------------------------|
| Service    | Especificação persistente: image, replicas, env/config, secrets, networks, recursos, healthcheck, update policy e placement. |
| Task       | Unidade agendada pelo Swarm para satisfazer um slot do Service. Possui estado e histórico próprios.                          |
| Container  | Processo Linux criado para executar uma Task. É descartável e não deve ser tratado como identidade da aplicação.             |
| Node       | Máquina membro do Swarm que pode atuar como manager, worker ou ambos.                                                        |
| Release    | Objeto da nossa plataforma que aponta para um artifact imutável e configurações versionadas.                                 |
| Deployment | Tentativa de fazer um Environment convergir para uma Release.                                                                |

## 2.1 Desired state x actual state

O Swarm trabalha declarativamente. A plataforma informa o estado desejado; o cluster tenta convergir para ele. A UI deve sempre mostrar os dois lados, em vez de esconder discrepâncias.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>DESIRED STATE ACTUAL STATE<br />
api replicas = 6 running = 5<br />
image = sha256:abc healthy = 5<br />
pending = 1<br />
<br />
DIFF<br />
|<br />
v<br />
Swarm reconciles<br />
|<br />
v<br />
running = 6 / 6</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 2.2 Estado operacional que a UI deve expor

| **Status de produto** | **Interpretação**                                                                         |
|-----------------------|-------------------------------------------------------------------------------------------|
| HEALTHY               | Todas as réplicas desejadas estão running e saudáveis; nenhuma operação crítica pendente. |
| CONVERGING            | Deployment, scale ou restart em andamento; cluster ainda converge para o desired state.   |
| DEGRADED              | Parte das réplicas atende, mas desired e actual divergem ou há falhas de health.          |
| UNHEALTHY             | Nenhuma réplica saudável ou taxa de falha excede política definida.                       |
| PAUSED                | Rollout/ação operacional foi pausada por política ou usuário.                             |
| STOPPED               | Service deliberadamente escalado para zero ou desativado pela plataforma.                 |

# 3. Health model

Health não deve ser um booleano obtido de uma única fonte. A plataforma precisa combinar o health do container, o estado das Tasks, disponibilidade do Service no ingress e, opcionalmente, uma probe HTTP/TCP definida pelo usuário.

## 3.1 Camadas de health

| **Camada**          | **Sinal**                                        | **Uso**                                                            |
|---------------------|--------------------------------------------------|--------------------------------------------------------------------|
| Process             | Container/Task running, exit code, restart count | Detecta crash e falhas imediatas.                                  |
| Container health    | Docker HEALTHCHECK                               | Permite que a imagem declare uma verificação interna recorrente.   |
| Service convergence | Desired replicas x Tasks running                 | Mede se o Swarm conseguiu materializar a especificação.            |
| Application probe   | HTTP/TCP probe opcional da plataforma            | Valida que a aplicação realmente responde no endpoint esperado.    |
| Ingress             | Traefik router/service metrics e health          | Valida que o tráfego consegue chegar ao backend.                   |
| External probe      | Probe fora do cluster, opcional                  | Detecta problemas de DNS/LB/TLS/rota que probes internas não veem. |

## 3.2 Configuração por Service

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Health Check<br />
<br />
Type: HTTP<br />
Path: /health<br />
Port: 3000<br />
Interval: 10s<br />
Timeout: 3s<br />
Start period: 30s<br />
Retries: 3<br />
Expected status: 200-399</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

A plataforma deve respeitar o HEALTHCHECK da imagem quando existir, mas também permitir uma health policy declarada no Service. Para aplicações web, uma probe HTTP externa ao processo oferece uma visão mais próxima da experiência real do usuário.

## 3.3 Readiness e liveness

Docker possui um conceito único de health por container, portanto não há a mesma separação nativa de readiness/liveness encontrada em Kubernetes. Na nossa plataforma, podemos criar essa distinção no nível de produto:

- Liveness: o processo está funcional ou precisa ser substituído/reiniciado?

- Readiness: esta réplica já deve receber tráfego?

- Startup: a aplicação ainda está dentro da janela normal de inicialização?

| **Regra:** A plataforma não deve declarar uma aplicação saudável apenas porque o processo está running. Running e Healthy são estados diferentes. |
|---------------------------------------------------------------------------------------------------------------------------------------------------|

# 4. Restart, self-healing e convergência

O Swarm já possui restart policy e reconciliação. A nossa plataforma deve expor isso como política de Service e registrar os eventos, em vez de implementar um supervisor paralelo que concorra com o scheduler.

## 4.1 Restart policy

| **Campo**       | **Exemplo** | **Significado**                                         |
|-----------------|-------------|---------------------------------------------------------|
| condition       | on-failure  | Reiniciar quando a Task termina com falha.              |
| delay           | 5s          | Esperar antes da nova tentativa.                        |
| maxAttempts     | 5           | Limitar tentativas dentro da janela.                    |
| window          | 60s         | Janela usada para avaliar falhas sucessivas.            |
| stopGracePeriod | 30s         | Tempo para encerramento gracioso antes de kill forçado. |

## 4.2 Restart manual

Em Swarm, um restart operacional pode ser implementado como update forçado do Service, fazendo as Tasks serem recriadas sem alteração do artifact. A UI deve tratar isso como uma operação auditável:

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>[ Restart Service ]<br />
|<br />
v<br />
Operation: FORCE_ROLLOUT<br />
|<br />
v<br />
Swarm Service Update<br />
|<br />
v<br />
Tasks recreated according to update policy</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 4.3 Crash loop

A plataforma deve detectar padrões de crash loop e destacar causa provável, última saída, exit code, OOMKilled quando disponível e deployment que introduziu a alteração. O objetivo é evitar que o usuário precise correlacionar manualmente dezenas de Tasks antigas.

# 5. CPU, memória e capacidade

## 5.1 Limits e reservations

Cada Service deve possuir configuração explícita de recursos. Reservations ajudam o scheduler a evitar nodes sem capacidade suficiente; limits evitam que um workload consuma recursos ilimitados do host.

| **Configuração**      | **Exemplo** | **Uso**                                                         |
|-----------------------|-------------|-----------------------------------------------------------------|
| CPU reservation       | 0.25 CPU    | Capacidade mínima considerada pelo scheduler.                   |
| CPU limit             | 1 CPU       | Teto de CPU permitido para a Task.                              |
| Memory reservation    | 256 MiB     | Memória reservada para decisão de placement.                    |
| Memory limit          | 512 MiB     | Teto de memória; ultrapassar pode resultar em OOM/terminação.   |
| Replicas max per node | 1 ou 2      | Evita concentrar todas as réplicas de um Service no mesmo host. |

## 5.2 Presets de UI

A UI pode oferecer presets para reduzir fricção, sem esconder valores técnicos:

| **Preset** | **CPU** | **RAM** | **Uso típico**                          |
|------------|---------|---------|-----------------------------------------|
| Nano       | 0.1     | 128 MiB | Jobs muito leves e serviços auxiliares. |
| Small      | 0.25    | 256 MiB | APIs pequenas e workers leves.          |
| Medium     | 0.5     | 512 MiB | Aplicações web comuns.                  |
| Large      | 1       | 1 GiB   | Aplicações com maior processamento.     |
| Custom     | livre   | livre   | Configuração explícita do usuário.      |

## 5.3 Proteção contra saturação

Além de limits por Service, a plataforma deve observar headroom do cluster. Autoscaling não deve aumentar réplicas se não existe capacidade real para agendá-las. A UI deve distinguir falta de capacidade de falha da aplicação.

# 6. Placement e topologia de nodes

Node labels transformam infraestrutura física em regras de agendamento. A plataforma deve administrar labels estruturadas, não strings arbitrárias espalhadas pela UI.

| **Label sugerida**   | **Exemplo**                          | **Uso**                                            |
|----------------------|--------------------------------------|----------------------------------------------------|
| platform.role        | manager / ingress / worker / builder | Separar funções do node.                           |
| platform.zone        | az-a / az-b / az-c                   | Distribuir réplicas por domínio de falha.          |
| platform.region      | br-sp / us-east                      | Classificação geográfica futura.                   |
| platform.class       | general / cpu / memory               | Agrupar capacidade.                                |
| platform.environment | production / homolog                 | Isolamento físico opcional entre environments.     |
| platform.tenant      | shared / dedicated                   | Suportar clusters com nodes dedicados a um tenant. |

## 6.1 Constraints x preferences

Constraints são requisitos obrigatórios; se nenhum node cumprir, a Task fica pendente. Preferences são desejos de distribuição; o Swarm tenta espalhar Tasks usando a estratégia suportada.

| **Tipo**     | **Exemplo**                                    | **Resultado**                                                            |
|--------------|------------------------------------------------|--------------------------------------------------------------------------|
| Constraint   | node.labels.platform.environment == production | A Task só pode executar em nodes de produção.                            |
| Constraint   | node.labels.platform.role == worker            | Evita workloads comuns em managers/ingress.                              |
| Preference   | spread=node.labels.platform.zone               | Tenta espalhar réplicas entre zonas.                                     |
| Max per node | 1                                              | Evita duas réplicas do mesmo Service no mesmo host quando há capacidade. |

## 6.2 Managers dedicados

Clusters de produção devem poder marcar managers como Drain para que participem do Raft sem receber workloads comuns. Isso reduz interferência de aplicações na função de gerenciamento do cluster.

# 7. Scaling manual

O primeiro mecanismo de scale é simples e explícito: alterar desired replicas do Service. A UI nunca deve vender escala como número de visitas; ela deve operar em réplicas e métricas observáveis.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Service: api<br />
<br />
Replicas<br />
[-] 6 [+]<br />
<br />
Running: 6 / 6<br />
Healthy: 6<br />
<br />
[Apply]</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 7.1 Scale to zero

Services não essenciais podem ser escalados para zero sem excluir configuração, Release, domains ou bindings. Isso permite pausar environments de teste e economizar capacidade.

# 8. Autoscaling da plataforma

Docker Swarm fornece o primitive de replicas, mas não entrega um controlador de autoscaling equivalente a um HPA completo. Portanto o autoscaler será um componente nosso, responsável apenas por alterar desired replicas conforme políticas e métricas.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Metrics Backend<br />
|<br />
v<br />
Autoscaling Controller<br />
|<br />
evaluate policy<br />
|<br />
v<br />
Desired replicas: 6 -&gt; 10<br />
|<br />
v<br />
Docker Service Update<br />
|<br />
v<br />
Swarm Scheduler</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 8.1 Política inicial

| **Campo**            | **Exemplo**                                         |
|----------------------|-----------------------------------------------------|
| Enabled              | true                                                |
| Min replicas         | 3                                                   |
| Max replicas         | 30                                                  |
| Metric               | CPU utilization                                     |
| Scale up threshold   | \> 70% por 2 minutos                                |
| Scale down threshold | \< 30% por 10 minutos                               |
| Scale up step        | +50% ou +2 réplicas                                 |
| Scale down step      | -1 réplica por ciclo                                |
| Cooldown             | 3 minutos após scale up; 10 minutos após scale down |

## 8.2 Regras de segurança do autoscaler

- Nunca escalar acima da capacidade disponível do cluster sem avisar claramente que existem Tasks Pending.

- Scale down deve ser mais conservador que scale up para evitar oscilação.

- Sempre respeitar min/max replicas.

- Não tomar decisão durante deployment incompleto, incidentes graves ou ausência de métricas confiáveis.

- Registrar cada decisão com métrica observada, política, valor anterior e novo desired replicas.

- Permitir modo MANUAL, AUTO e PAUSED por Service.

## 8.3 Métricas futuras

Depois de CPU/memória, o controlador pode aceitar métricas de negócio e tráfego: requests/s, concurrent requests, queue depth, latency p95 ou métricas customizadas exportadas pela aplicação. A implementação deve abstrair MetricProvider para que o autoscaler não dependa de Prometheus diretamente.

# 9. Observabilidade: arquitetura

A plataforma precisa separar coleta de telemetria do armazenamento histórico. Coletores rodam próximos aos workloads; o backend central recebe e consulta dados. Como o projeto delegará stateful services inicialmente, o backend de observabilidade pode começar gerenciado/externo e ser substituído depois sem mudar os agentes de coleta.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>EVERY NODE<br />
+------------------------------+<br />
| Node Exporter -&gt; host |<br />
| cAdvisor -&gt; containers |<br />
| Alloy -&gt; logs |<br />
+--------------+---------------+<br />
|<br />
v<br />
Observability Backend<br />
+---------+---------+<br />
| |<br />
Metrics Store Loki/Logs<br />
| |<br />
+---------+---------+<br />
|<br />
v<br />
Platform API/UI</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 9.1 Fontes de métricas

| **Fonte**        | **Métricas principais**                                                          |
|------------------|----------------------------------------------------------------------------------|
| Docker/Swarm API | estado de nodes, Services, Tasks, desired/running replicas, failures e eventos.  |
| Node Exporter    | CPU, RAM, disk, filesystem, load, network e métricas do host Linux.              |
| cAdvisor         | CPU, memória, network e filesystem por container.                                |
| Traefik          | requests, status codes, latency, open connections, retries e saúde dos backends. |
| Aplicação        | métricas customizadas opcionais via Prometheus/OpenTelemetry.                    |
| Load Balancer    | health dos ingress targets e métricas externas quando o provider disponibilizar. |

## 9.2 Identidade de telemetria

Todo dado deve ser enriquecido com labels estáveis da plataforma. Não podemos depender apenas de container ID, porque containers são efêmeros.

| **Label**      | **Exemplo**    |
|----------------|----------------|
| team_id        | team_01        |
| project_id     | prj_albert     |
| environment_id | env_prod       |
| service_id     | svc_api        |
| deployment_id  | dep_918        |
| release_id     | rel_221        |
| node_id        | node_worker_03 |
| task_id        | swarm task id  |

# 10. Logs

## 10.1 Dois modos de acesso

A experiência de logs terá dois caminhos complementares:

| **Modo**   | **Fonte**                               | **Objetivo**                                                 |
|------------|-----------------------------------------|--------------------------------------------------------------|
| Live       | Docker Service/Task logs via Engine API | Acompanhar deployment, startup e troubleshooting imediato.   |
| Historical | Alloy -\> Loki ou backend compatível    | Pesquisar logs depois que Task/container já foi substituído. |

## 10.2 UI de logs

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Albert / Production / API / Logs<br />
<br />
Time Level Task Message<br />
20:41:02.115 INFO api.7 server listening :3000<br />
20:41:03.229 INFO api.2 GET /users 200 31ms<br />
20:41:04.118 ERROR api.5 upstream timeout<br />
<br />
Search: [ upstream timeout ]<br />
Task: All Deployment: #918 Follow: ON</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 10.3 Segurança de logs

- Nunca logar valores de SecretVersion na plataforma.

- Aplicar redaction para padrões conhecidos em logs do próprio sistema quando possível.

- Acesso a logs de Produção deve respeitar RBAC e gerar audit trail em operações sensíveis.

- Downloads/export de logs devem ser eventos auditados.

- Retention deve ser configurável por Team/Environment ou plano.

# 11. Eventos de runtime

Além de métricas e logs, a plataforma deve consumir eventos do Docker/Swarm para construir uma timeline causal. Eventos são úteis porque respondem “o que aconteceu?” sem depender de polling agressivo.

| **Evento de produto** | **Exemplos de origem**                                     |
|-----------------------|------------------------------------------------------------|
| TASK_STARTED          | Task entrou em running.                                    |
| TASK_FAILED           | Task terminou/foi rejeitada.                               |
| SERVICE_CONVERGED     | desired replicas == healthy/running conforme política.     |
| NODE_DOWN             | node passou a indisponível.                                |
| NODE_DRAINED          | operador colocou node em Drain.                            |
| OOM_DETECTED          | container terminou por falta de memória quando detectável. |
| AUTOSCALE_APPLIED     | controlador alterou replicas.                              |
| HEALTH_DEGRADED       | health agregado cruzou limite da política.                 |
| RECOVERED             | condição que abriu incidente voltou ao normal.             |

# 12. Alertas e incidentes

Alertas devem ser derivados de regras e convertidos em incidentes quando exigem ação. O sistema precisa evitar notificar repetidamente o mesmo problema a cada coleta.

## 12.1 Regras iniciais

| **Regra**           | **Condição sugerida**                                | **Severidade**                    |
|---------------------|------------------------------------------------------|-----------------------------------|
| ServiceUnavailable  | 0 réplicas healthy por 60s                           | Critical                          |
| ReplicaMismatch     | running \< desired por 5 min                         | Warning                           |
| NodeDown            | node worker unreachable                              | Critical quando reduz redundância |
| IngressTargetDown   | Traefik/ingress fora do LB                           | Warning/Critical conforme quorum  |
| HighCPU             | \> 85% por 10 min                                    | Warning                           |
| HighMemory          | \> 90% por 5 min                                     | Warning                           |
| OOMLoop             | 2+ OOMs em janela curta                              | Critical                          |
| DeploymentFailed    | rollout pausado/rollback disparado                   | Critical                          |
| CertificateExpiring | certificado abaixo do threshold sem renovação válida | Critical                          |

## 12.2 Lifecycle do incidente

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Signal<br />
|<br />
v<br />
Alert FIRING<br />
|<br />
v<br />
Incident OPEN<br />
|---- events / logs / metrics / deployment context<br />
|<br />
condition recovers<br />
|<br />
v<br />
Incident RESOLVED</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 12.3 NotificationProvider

Notificações devem ser desacopladas por provider. A plataforma pode começar com e-mail/webhook e depois adicionar Slack, Discord, WhatsApp ou PagerDuty sem alterar o motor de regras.

# 13. Operação de nodes

## 13.1 Active, Pause e Drain

| **Estado** | **Comportamento**                                                                           | **Uso**                                    |
|------------|---------------------------------------------------------------------------------------------|--------------------------------------------|
| Active     | Pode receber novas Tasks e continua executando as existentes.                               | Operação normal.                           |
| Pause      | Não recebe novas Tasks; Tasks existentes continuam.                                         | Bloqueio temporário sem evacuar workloads. |
| Drain      | Não recebe novas Tasks; Swarm encerra Tasks de Services e tenta recriá-las em nodes Active. | Manutenção, remoção ou isolamento do node. |

## 13.2 Fluxo de manutenção

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Node worker-04<br />
Status: Active<br />
|<br />
[Drain] requested<br />
|<br />
v<br />
Stop scheduling new Tasks<br />
|<br />
Evacuate replicated Services<br />
|<br />
Wait cluster convergence<br />
|<br />
v<br />
SAFE FOR MAINTENANCE</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

A plataforma deve bloquear a indicação “safe for maintenance” enquanto houver Tasks de workloads gerenciados ainda presas ao node, salvo quando explicitamente ignoradas pelo operador.

## 13.3 Remoção de node

- Drain antes de remover sempre que o node ainda estiver acessível.

- Validar que a remoção não reduz managers abaixo do quorum desejado.

- Validar capacidade restante de workers e ingress.

- Remover target do Load Balancer antes de desligar um ingress node.

- Registrar quem removeu, motivo e impacto previsto.

# 14. Terminal e exec

O terminal web é útil, mas é uma das capacidades de maior risco. Ele deve ser tratado como acesso privilegiado temporário a uma Task específica, não como recurso casual.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Browser Terminal<br />
| WebSocket<br />
v<br />
Platform API<br />
RBAC + Audit<br />
|<br />
v<br />
Docker Exec API<br />
|<br />
v<br />
Specific Task Container</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 14.1 Regras

- Usuário escolhe Service e Task explicitamente; a plataforma não promete que o mesmo container existirá depois.

- Produção pode exigir role específica e reautenticação.

- Toda sessão registra usuário, Team, Environment, Service, Task, início, fim e origem.

- Não armazenar conteúdo completo do terminal por padrão; registrar metadata e comandos apenas se a política de segurança do produto exigir e estiver claramente documentada.

- Nunca expor shell do host através dessa funcionalidade.

# 15. Dashboard operacional

## 15.1 Service overview

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Albert / Production / API<br />
<br />
Status HEALTHY<br />
Release rel_221 sha256:abc...<br />
Replicas 6 / 6<br />
CPU 42% avg<br />
Memory 318 MiB / 512 MiB<br />
Traffic 2.8k req/s<br />
Latency p95 82 ms<br />
Errors 5xx 0.18%<br />
Autoscaling 3..30 AUTO<br />
Last deploy 18 min ago<br />
<br />
[Logs] [Metrics] [Restart] [Scale] [Terminal]</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 15.2 Cluster overview

| **Bloco**   | **Informação**                                              |
|-------------|-------------------------------------------------------------|
| Managers    | quorum, leader, reachable/unavailable, versão Docker.       |
| Workers     | Ready/Down, Active/Pause/Drain, CPU/RAM, Tasks.             |
| Ingress     | Traefik instances, LB target health, open connections, TLS. |
| Capacity    | CPU/RAM total, reservado, utilizado e headroom.             |
| Services    | healthy/degraded/unhealthy/converging.                      |
| Incidents   | abertos por severidade e impacto.                           |
| Deployments | em andamento, falhos e concluídos recentemente.             |

# 16. SLI e SLO

Para aplicações grandes, “está online” é insuficiente. A plataforma deve ser capaz de medir indicadores objetivos, mesmo que a primeira versão apenas exiba os dados e não ofereça um produto completo de SRE.

| **SLI**           | **Exemplo**                                                |
|-------------------|------------------------------------------------------------|
| Availability      | proporção de requests consideradas bem-sucedidas.          |
| Latency           | p50, p95 e p99 por router/Service.                         |
| Error rate        | proporção de 5xx e falhas de upstream.                     |
| Saturation        | CPU, memória, connections ou queue depth perto do limite.  |
| Deployment health | taxa de deployments bem-sucedidos e tempo de convergência. |

| **Importante:** SLO é uma meta do produto, não uma consequência automática de ter múltiplas réplicas. A plataforma deve medir disponibilidade; não prometer disponibilidade sem considerar LB, ingress, app e dependências externas. |
|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|

# 17. Cenários de falha e reação esperada

| **Falha**                    | **Quem detecta**            | **Reação**                                                                                |
|------------------------------|-----------------------------|-------------------------------------------------------------------------------------------|
| Container crash              | Swarm + events              | Swarm cria nova Task conforme restart policy; plataforma registra e correlaciona.         |
| Healthcheck falha            | Docker/Swarm + probe        | Task pode ser substituída; UI marca DEGRADED e abre alerta conforme janela.               |
| Worker cai                   | Swarm managers              | Tasks são reagendadas em nodes elegíveis; plataforma mede perda de capacidade.            |
| Ingress cai                  | LB health check             | LB para de enviar tráfego ao target; incidente se redundância ficar abaixo do mínimo.     |
| Deploy ruim                  | Swarm update policy         | Pause ou rollback automático conforme política definida na Parte 2.                       |
| OOM recorrente               | Runtime metrics/events      | Alerta; não aumentar limit automaticamente sem política explícita.                        |
| Cluster sem capacidade       | Scheduler + metrics         | Tasks Pending; autoscaler de replicas deve parar scale-up e sinalizar Capacity Exhausted. |
| Metrics backend indisponível | Collector/controller        | Autoscaler entra em modo seguro; não escala com dados desconhecidos.                      |
| Dependency externa fora      | Application/Traefik metrics | Erro aparece como SLI degradado; plataforma não tenta “corrigir” serviço externo.         |

# 18. Segurança operacional

- Managers e Docker Engine API são recursos altamente privilegiados; acesso deve ser restrito ao backend da plataforma e operadores autorizados.

- Não expor Docker daemon sem TLS/autenticação em rede pública.

- Terminal, restart, scale, drain, delete e mudança de resources geram AuditEvent.

- Secrets nunca aparecem em logs, métricas, eventos ou payloads de observabilidade.

- Permissões devem ser avaliadas no nível Team/Project/Environment e operação.

- Collectors de observabilidade que precisam de acesso ao Docker devem ser tratados como componentes privilegiados e hardenizados.

- A UI de Produção deve diferenciar operações reversíveis de destrutivas e exigir intenção explícita para as últimas.

# 19. Modelo de dados adicional

| **Entidade**          | **Responsabilidade**                                                         |
|-----------------------|------------------------------------------------------------------------------|
| ServiceRuntimePolicy  | restart policy, health policy, limits, reservations e placement.             |
| AutoscalingPolicy     | min/max replicas, metric, thresholds, cooldowns e estado manual/auto/paused. |
| RuntimeOperation      | restart, scale, drain, terminal session e outras operações auditáveis.       |
| MetricBinding         | mapeia Service/Environment para séries/labels do backend de métricas.        |
| AlertRule             | condição, janela, severidade e escopo.                                       |
| AlertInstance         | estado atual de uma regra para um recurso específico.                        |
| Incident              | agregação de alertas/eventos com lifecycle open/resolved.                    |
| AuditEvent            | ator, ação, recurso, timestamp e metadata de segurança.                      |
| NodeMetadata          | labels, role lógica, zone, capacidade e política de scheduling.              |
| ObservabilityProvider | configuração do backend de métricas/logs utilizado pelo Team/Cluster.        |

# 20. Sequência de implementação da Parte 3

1.  Runtime inventory: ler nodes, Services e Tasks via Docker Engine API e mapear para entidades da plataforma.

2.  Service status agregado: desired/running/healthy/pending/failed.

3.  Health policy e restart policy configuráveis.

4.  Limits/reservations e placement labels.

5.  Logs live via Docker Service/Task logs.

6.  Node Exporter + cAdvisor + métricas de Traefik.

7.  Backend histórico de métricas e dashboards nativos.

8.  Alloy + Loki/backend de logs para histórico e busca.

9.  Docker/Swarm event ingestion e timeline.

10. Alert rules + incident lifecycle + notifications.

11. Manual scaling.

12. Autoscaling CPU/memory com min/max/cooldown.

13. Node maintenance: Pause/Drain/Remove.

14. Terminal/exec com RBAC e audit.

15. SLI/SLO e métricas avançadas por aplicação.

# 21. Decisões registradas nesta parte

| **Decisão**                         | **Resultado**                                                                               |
|-------------------------------------|---------------------------------------------------------------------------------------------|
| Swarm é o reconciliador             | Não construir supervisor concorrente para restart/scheduling.                               |
| Service é a unidade persistente     | Containers são efêmeros e não aparecem como objeto principal do produto.                    |
| Autoscaling é nosso                 | Controller próprio altera replicas via Docker API.                                          |
| Health é agregado                   | Running não implica Healthy.                                                                |
| Managers podem ser dedicados        | Produção suporta managers em Drain para evitar workloads comuns.                            |
| Observabilidade desacoplada         | Collectors no cluster; backend histórico substituível/externo inicialmente.                 |
| Logs têm live + historical          | Docker API para tempo real; Alloy/Loki ou provider para histórico.                          |
| Stateful de negócio segue externo   | Postgres, Redis e object storage não entram no escopo do runtime HA agora.                  |
| Operação é auditável                | Terminal, restart, scale e manutenção de nodes geram audit trail.                           |
| Capacidade é métrica, não marketing | A UI trabalha com req/s, latência, CPU, RAM, replicas e headroom, não “visitas suportadas”. |

# 22. Referências técnicas

| **Fonte**                      | **URL**                                                                                    |
|--------------------------------|--------------------------------------------------------------------------------------------|
| Docker Swarm services          | https://docs.docker.com/engine/swarm/services/                                             |
| docker service update          | https://docs.docker.com/reference/cli/docker/service/update/                               |
| Manage nodes in a swarm        | https://docs.docker.com/engine/swarm/manage-nodes/                                         |
| Drain a node                   | https://docs.docker.com/engine/swarm/swarm-tutorial/drain-node/                            |
| Docker Prometheus metrics      | https://docs.docker.com/engine/daemon/prometheus/                                          |
| Prometheus cAdvisor guide      | https://prometheus.io/docs/guides/cadvisor/                                                |
| Prometheus Node Exporter guide | https://prometheus.io/docs/guides/node-exporter/                                           |
| Traefik metrics                | https://doc.traefik.io/traefik/v3.5/reference/install-configuration/observability/metrics/ |
| Grafana Alloy -\> Loki         | https://grafana.com/docs/loki/latest/send-data/alloy/                                      |
| Alloy Docker log source        | https://grafana.com/docs/alloy/latest/reference/components/loki/loki.source.docker/        |

# 23. Próxima parte sugerida

A Parte 4 deve fechar a camada de produto e governança em torno da infraestrutura: autenticação, Teams, RBAC detalhado, Audit Log, Vault/Recovery Key em profundidade, billing/quotas, onboarding de clusters, providers externos e experiência de administração. Depois disso, uma parte específica pode tratar Disaster Recovery, backups da plataforma, snapshots e runbooks de recuperação.

| **Marco:** Ao final das Partes 1, 2 e 3, a plataforma já está conceitualmente definida do domínio do usuário até o runtime: Team/Project/Environment/Service -\> source/build/artifact/release/deployment -\> Service/Task/health/metrics/logs/autoscaling. |
|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
