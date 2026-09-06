---
document: "E"
title: "Runbooks Operacionais"
type: "annex"
status: "approved"
source: "docx"
---

**PLATAFORMA PAAS  
CLUSTER-FIRST**

**Anexo E — Runbooks Operacionais**

*Procedimentos de resposta, recuperação, validação e manutenção para Control Plane, Docker Swarm, Edge, Build, Vault, Backup e dependências críticas*

## Resumo executivo

Este anexo converte a arquitetura, os SLOs, o Threat Model e a estratégia de testes em procedimentos operacionais executáveis. Cada runbook parte de um sintoma observável, estabelece contenção e diagnóstico antes de qualquer ação destrutiva, define a sequência de recuperação e termina com validações objetivas para evitar o falso positivo de “voltou”.

Os runbooks são deliberadamente independentes da linguagem do Control Plane. API, Operation Engine, workers, Executor e reconcilers são nomes lógicos; a implementação pode ser Rails, Rust ou outra tecnologia sem alterar o procedimento operacional.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th><p><strong>Princípio operacional</strong></p>
<p>Em incidentes de infraestrutura, restaurar disponibilidade rapidamente é importante, mas preservar consistência é mais importante. Nunca “conserte” o Swarm, o banco ou o Vault apagando estado sem antes capturar evidências e confirmar o caminho de recuperação.</p></th>
</tr>
</thead>
<tbody>
</tbody>
</table>

# 1. Modelo operacional e comando de incidente

## 1.1 Ciclo padrão de resposta

| **Etapa**        | **Ação obrigatória**                                                                            |
|------------------|-------------------------------------------------------------------------------------------------|
| 1\. Detectar     | Confirmar alerta/sintoma e impacto real ao usuário.                                             |
| 2\. Classificar  | Definir severidade, blast radius e componentes afetados.                                        |
| 3\. Conter       | Interromper ações que ampliem o incidente: deploys, autoscaling, GC, rotações ou upgrades.      |
| 4\. Preservar    | Salvar correlationIds, OperationIds, logs, métricas, estado do cluster e timestamps.            |
| 5\. Diagnosticar | Identificar camada causal: Control Plane, DB, queue, Docker, Swarm, Edge, provider ou workload. |
| 6\. Recuperar    | Aplicar a menor mudança reversível capaz de restaurar o serviço.                                |
| 7\. Validar      | Testar dataplane e control plane, consistência e sinais de observabilidade.                     |
| 8\. Encerrar     | Remover mitigação temporária, registrar timeline e abrir follow-up/postmortem quando aplicável. |

## 1.2 Severidade operacional

| **Sev** | **Definição**                                                                  | **Exemplos**                                                                                             |
|---------|--------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------|
| SEV-1   | Indisponibilidade ampla, perda/risco de perda de dados ou controle do cluster. | Quorum perdido; DB irrecuperável; edge indisponível em múltiplos apps; comprometimento de Manager/Vault. |
| SEV-2   | Degradação material ou função crítica indisponível com workaround limitado.    | Deploys parados; Registry indisponível; emissão TLS falhando; um cluster degradado.                      |
| SEV-3   | Impacto restrito a serviço/tenant, sem risco sistêmico.                        | Um workload crash-loop; domain custom incorreto; build individual preso.                                 |
| SEV-4   | Problema operacional sem impacto imediato.                                     | Capacidade baixa, certificado futuro, disco crescendo, réplica desalinhada.                              |

## 1.3 Freeze automático em incidentes

• SEV-1: bloquear deploys, upgrades, rotations, cluster topology changes e garbage collection até liberação explícita.

• SEV-2: congelar apenas operações que toquem o subsistema afetado.

• Autoscaling pode ser colocado em HOLD se estiver amplificando pressão ou mascarando o diagnóstico.

• Nenhuma automação de “healing” pode usar operações destrutivas como force-new-cluster ou restore de banco automaticamente.

# 2. Kit universal de triagem

## 2.1 Estado do cluster

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>docker info<br />
docker node ls<br />
docker service ls<br />
docker stack services &lt;stack&gt;<br />
docker service ps &lt;service&gt; --no-trunc<br />
docker service inspect &lt;service&gt; --pretty<br />
docker events --since 30m</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 2.2 Estado do host

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>uptime<br />
free -h<br />
df -h<br />
df -i<br />
systemctl status docker --no-pager<br />
journalctl -u docker --since "30 min ago" --no-pager<br />
ss -lntup</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 2.3 Estado da plataforma

| **Sinal**     | **Coletar**                                                                       |
|---------------|-----------------------------------------------------------------------------------|
| Control Plane | health/readiness, p95/p99, error rate, saturation, versão/commit.                 |
| Operations    | operations QUEUED/RUNNING/FAILED, attempts, lock owner, deadlines, correlationId. |
| Reconciler    | lag desiredRevision-appliedRevision, queue depth, last successful sweep.          |
| Executor      | heartbeat, Docker API latency/errors, event stream connectivity.                  |
| Edge          | LB health, Traefik instances, 4xx/5xx, cert status, target health.                |
| Build         | builder capacity, BuildKit workers, queue depth, registry push/pull errors.       |
| Storage       | DB connection pool, replication/provider health, backup freshness.                |

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th><p><strong>Captura mínima antes de reiniciar</strong></p>
<p>Timestamp UTC/local, node/service IDs, OperationId/DeploymentId, `docker node ls`, `docker service ps`, últimos eventos Docker, métricas do período e logs do componente. Reiniciar antes disso pode apagar a evidência que explica a causa.</p></th>
</tr>
</thead>
<tbody>
</tbody>
</table>

# 3. Control Plane e persistência

## RB-01 — Control Plane API indisponível

| **Campo**          | **Definição**                                                                           |
|--------------------|-----------------------------------------------------------------------------------------|
| Severidade típica  | SEV-1/2                                                                                 |
| Gatilho / sintomas | UI/API com timeout/5xx; health/readiness falhando; dataplane pode continuar servindo.   |
| Objetivo           | Conter impacto, recuperar serviço e preservar evidências antes de mudanças destrutivas. |

### Ação imediata

• Declarar freeze de mutações enquanto a causa não estiver clara.

• Confirmar se o dataplane das aplicações continua saudável; não reiniciar Swarm se apenas o Control Plane caiu.

### Diagnóstico

• Checar processo/containers do Control Plane, readiness, CPU/RAM e pool de DB.

• Verificar PostgreSQL, fila/worker e dependências externas.

• Comparar início dos 5xx com deploy/upgrade/config change recente.

### Recuperação

• Se regressão de versão: rollback do Control Plane para release anterior compatível.

• Se saturação: restaurar capacidade do componente sem aumentar concorrência contra DB já degradado.

• Após retorno, executar reconcile sweep e liberar operações gradualmente.

### Validação pós-recuperação

• GETs e mutações básicas respondem dentro do SLO.

• Operations pendentes progridem sem duplicidade.

• desiredRevision converge para appliedRevision.

• Dataplane permanece/volta saudável.

Escalar quando: API não recupera após rollback/restart controlado ou houver inconsistência entre DB e runtime.

## RB-02 — PostgreSQL indisponível ou degradado

| **Campo**          | **Definição**                                                                           |
|--------------------|-----------------------------------------------------------------------------------------|
| Severidade típica  | SEV-1                                                                                   |
| Gatilho / sintomas | timeouts de DB; pool esgotado; transações falhando; Control Plane/readiness degradado.  |
| Objetivo           | Conter impacto, recuperar serviço e preservar evidências antes de mudanças destrutivas. |

### Ação imediata

• Bloquear novas mutações e jobs que dependam de persistência.

• Manter dataplane intacto; não “recriar” recursos no Swarm a partir de memória/cache.

### Diagnóstico

• Verificar status do provider, conexões, locks, CPU/IO, storage e latência.

• Checar pool do Control Plane e queries dominantes.

• Confirmar backup/PITR mais recente antes de qualquer ação de restore.

### Recuperação

• Se provider gerenciado: seguir failover oficial.

• Se overload: reduzir concorrência/consumidores e remover query patológica.

• Somente restaurar/PITR quando corrupção/perda estiver comprovada.

### Validação pós-recuperação

• Transações e health checks estáveis.

• Outbox volta a drenar.

• Operations não foram duplicadas.

• Reconcile sweep corrige drift residual.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th><p><strong>Cuidado</strong></p>
<p>Restore de banco altera a fonte de verdade. Nunca execute PITR como primeira tentativa para resolver simples indisponibilidade.</p></th>
</tr>
</thead>
<tbody>
</tbody>
</table>

Escalar quando: houver suspeita de corrupção, necessidade de PITR ou RPO ameaçado.

## RB-03 — Fila/Operation Engine parado

| **Campo**          | **Definição**                                                                           |
|--------------------|-----------------------------------------------------------------------------------------|
| Severidade típica  | SEV-2                                                                                   |
| Gatilho / sintomas | Operations permanecem QUEUED; queue depth cresce; workers sem heartbeat.                |
| Objetivo           | Conter impacto, recuperar serviço e preservar evidências antes de mudanças destrutivas. |

### Ação imediata

• Pausar criação de operações não essenciais se a fila crescer continuamente.

• Não executar comandos Docker manualmente para “substituir” operações sem registro.

### Diagnóstico

• Checar backend da fila, workers, leases e dead-letter/retry state.

• Identificar Operation mais antiga e se existe lock órfão.

• Verificar se um provider externo lento está bloqueando todo o pool.

### Recuperação

• Restaurar backend/worker.

• Expirar/reclamar leases apenas conforme fencing policy.

• Reprocessar operações idempotentes; FAILED exige nova tentativa auditada, não UPDATE manual de status.

### Validação pós-recuperação

• Queue lag retorna ao normal.

• Nenhuma Operation executou duas vezes logicamente.

• Outbox e reconcile sem backlog crescente.

# 4. Docker Swarm e nodes

## RB-04 — Worker indisponível

| **Campo**          | **Definição**                                                                           |
|--------------------|-----------------------------------------------------------------------------------------|
| Severidade típica  | SEV-2/3                                                                                 |
| Gatilho / sintomas | Node Down/Unknown; tasks sendo reprogramadas; perda parcial de capacidade.              |
| Objetivo           | Conter impacto, recuperar serviço e preservar evidências antes de mudanças destrutivas. |

### Ação imediata

• Confirmar se replicas foram realocadas e se há capacidade restante.

• Se node está intermitente, marcar Drain antes de manutenção quando ele voltar acessível.

### Diagnóstico

• \`docker node ls\`; \`docker node inspect \<node\>\`; serviços com tasks no node.

• Checar host, Docker daemon, rede privada e portas Swarm.

### Recuperação

• Recuperar host/Docker ou substituir node.

• Para manutenção planejada: \`docker node update --availability drain \<node\>\`.

• Remover node somente após tasks migradas e decisão de substituir/descartar.

### Validação pós-recuperação

• Serviços atingem replicas desejadas.

• Node novo/recuperado fica Ready/Active quando apropriado.

• Sem erros persistentes de placement.

## RB-05 — Manager indisponível com quorum preservado

| **Campo**          | **Definição**                                                                                    |
|--------------------|--------------------------------------------------------------------------------------------------|
| Severidade típica  | SEV-2                                                                                            |
| Gatilho / sintomas | Um Manager Down/Unavailable, mas \`docker node ls\` funciona e managers restantes mantêm quorum. |
| Objetivo           | Conter impacto, recuperar serviço e preservar evidências antes de mudanças destrutivas.          |

### Ação imediata

• Não promover novo manager imediatamente se o outage for transitório e o quorum estiver saudável.

• Evitar mudanças de topologia simultâneas.

### Diagnóstico

• Confirmar número total de managers e quorum atual.

• Verificar host/Docker/rede do manager afetado.

• Checar se ele também tinha função Ingress/Builder não redundante.

### Recuperação

• Recuperar/recriar manager conforme bootstrap documentado.

• Se substituição for permanente, adicionar novo manager primeiro e remover o antigo depois quando possível.

### Validação pós-recuperação

• Quorum saudável; managers esperados Reachable.

• Operações de control plane e scheduling funcionam.

• Autolock/unlock key continua disponível e testada.

## RB-06 — Perda de quorum dos Managers

| **Campo**          | **Definição**                                                                              |
|--------------------|--------------------------------------------------------------------------------------------|
| Severidade típica  | SEV-1                                                                                      |
| Gatilho / sintomas | Comandos de gestão falham; swarm não aceita updates; managers insuficientes para consenso. |
| Objetivo           | Conter impacto, recuperar serviço e preservar evidências antes de mudanças destrutivas.    |

### Ação imediata

• Congelar qualquer tentativa de reconfigurar serviços/nodes.

• Preservar discos/estado dos managers; não inicializar outro Swarm com os mesmos workloads.

• Identificar quais managers originais ainda têm estado mais recente.

### Diagnóstico

• Determinar se quorum pode ser restaurado recuperando managers existentes.

• Verificar conectividade privada e Docker daemon antes de assumir perda de estado.

• Localizar backup consistente de \`/var/lib/docker/swarm\` e unlock key, se necessário.

### Recuperação

• Preferência 1: recuperar managers suficientes para restabelecer quorum.

• Somente se quorum for irrecuperável: escolher o manager com estado válido mais recente e seguir procedimento de disaster recovery/force-new-cluster aprovado; depois reconciliar/recriar managers.

• Executar full reconcile após retorno do controle.

### Validação pós-recuperação

• \`docker node ls\` e updates de service funcionam.

• Raft/quorum estável com topologia ímpar planejada.

• Todos os serviços convergem; nenhum recurso duplicado.

• Backup imediato do novo estado de Swarm realizado.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th><p><strong>Cuidado</strong></p>
<p>`docker swarm init --force-new-cluster` é operação de desastre, não um comando de troubleshooting. Usá-lo com quorum recuperável ou no manager errado pode consolidar estado antigo e causar perda lógica.</p></th>
</tr>
</thead>
<tbody>
</tbody>
</table>

Escalar quando: for necessário usar force-new-cluster, houver dúvida sobre qual manager possui estado mais recente ou o unlock key estiver indisponível.

### Procedimento controlado de force-new-cluster (somente DR aprovado)

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th># 1) confirmar que quorum original é irrecuperável e escolher manager sobrevivente correto<br />
# 2) preservar backup/snapshot do estado atual antes da mudança<br />
docker swarm init --force-new-cluster --advertise-addr &lt;MANAGER_PRIVATE_IP&gt;<br />
# 3) validar services/nodes/secrets/configs antes de admitir novos managers<br />
docker node ls<br />
docker service ls</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## RB-07 — Overlay network ou service discovery degradado

| **Campo**          | **Definição**                                                                                  |
|--------------------|------------------------------------------------------------------------------------------------|
| Severidade típica  | SEV-2                                                                                          |
| Gatilho / sintomas | tasks Running mas conexões internas falham; DNS interno inconsistente; timeout entre services. |
| Objetivo           | Conter impacto, recuperar serviço e preservar evidências antes de mudanças destrutivas.        |

### Ação imediata

• Evitar recriar networks em massa.

• Identificar se falha é por node, network específica ou cluster inteiro.

### Diagnóstico

• Verificar 7946/tcp+udp e 4789/udp entre nodes na rede privada.

• Inspecionar network e tasks anexadas.

• Comparar falhas com firewall/MTU/VPN/provider network change.

### Recuperação

• Corrigir conectividade/MTU/firewall.

• Reagendar tasks do node defeituoso via drain se necessário.

• Recriar network somente com plano explícito de reanexar services.

### Validação pós-recuperação

• DNS/service discovery resolvem.

• Conectividade east-west restaurada.

• Sem packet loss/timeout anormal e sem tasks órfãs.

## RB-08 — Docker daemon travado em node

| **Campo**          | **Definição**                                                                              |
|--------------------|--------------------------------------------------------------------------------------------|
| Severidade típica  | SEV-2/3                                                                                    |
| Gatilho / sintomas | Docker API timeout; node Unknown; comandos locais travam ou daemon reinicia repetidamente. |
| Objetivo           | Conter impacto, recuperar serviço e preservar evidências antes de mudanças destrutivas.    |

### Ação imediata

• Se possível, Drain o node a partir de manager saudável.

• Capturar \`journalctl\` e estado de disco/memória antes do restart.

### Diagnóstico

• Checar disk/inodes, OOM, storage driver e erros kernel.

• Verificar processos Docker/containerd e filesystem.

### Recuperação

• Corrigir pressão de recurso.

• Reiniciar Docker de forma controlada somente após tasks estarem protegidas/redundantes.

• Se recorrente, substituir node em vez de insistir em reparos em produção.

### Validação pós-recuperação

• Node Ready.

• Tasks reconciliadas.

• Sem novos erros de daemon/storage por janela de observação.

# 5. Edge, Traefik, Load Balancer, DNS e TLS

## RB-09 — Traefik/Ingress indisponível

| **Campo**          | **Definição**                                                                           |
|--------------------|-----------------------------------------------------------------------------------------|
| Severidade típica  | SEV-1/2                                                                                 |
| Gatilho / sintomas | LB marca targets unhealthy; 502/503/timeout em múltiplos domains.                       |
| Objetivo           | Conter impacto, recuperar serviço e preservar evidências antes de mudanças destrutivas. |

### Ação imediata

• Confirmar se problema atinge uma instância ou todas.

• Retirar target unhealthy do LB se o provider não o fizer automaticamente.

### Diagnóstico

• Checar Traefik services/tasks, logs, labels/config file provider, portas 80/443 e conectividade overlay.

• Verificar se mudança recente de dynamic config/cert causou reload inválido.

### Recuperação

• Rollback da config/release de Traefik se necessário.

• Restaurar replicas ingress em nodes saudáveis.

• Recolocar target no LB somente após health estável.

### Validação pós-recuperação

• HTTP/HTTPS de domínio padrão e custom respondem.

• WebSocket/SSE de teste funciona.

• 5xx e LB unhealthy voltam ao baseline.

## RB-10 — Load Balancer externo degradado

| **Campo**          | **Definição**                                                                              |
|--------------------|--------------------------------------------------------------------------------------------|
| Severidade típica  | SEV-1/2                                                                                    |
| Gatilho / sintomas | targets saudáveis localmente, mas tráfego externo falha; health do provider inconsistente. |
| Objetivo           | Conter impacto, recuperar serviço e preservar evidências antes de mudanças destrutivas.    |

### Ação imediata

• Validar Traefik diretamente pela rede/test endpoint antes de culpar ingress.

• Evitar trocar DNS para IPs individuais sem considerar TTL/TLS/firewall.

### Diagnóstico

• Provider status; listener 80/443; target group; health check; firewall/security group.

• Comparar IPs/targets esperados com provider actual state.

### Recuperação

• Reconciliar targets via provider abstraction.

• Se provider indisponível e plano de contingência existir, ativar LB alternativo/DNS failover conforme procedimento específico.

### Validação pós-recuperação

• Health checks verdes em múltiplos targets.

• Tráfego público distribuído e TLS íntegro.

## RB-11 — Certificado não emite, não renova ou está perto de expirar

| **Campo**          | **Definição**                                                                            |
|--------------------|------------------------------------------------------------------------------------------|
| Severidade típica  | SEV-2/3                                                                                  |
| Gatilho / sintomas | Certificate Pending/Failed; alerta de validade; browser reporta cert incorreto/expirado. |
| Objetivo           | Conter impacto, recuperar serviço e preservar evidências antes de mudanças destrutivas.  |

### Ação imediata

• Não apagar a versão ACTIVE válida enquanto investiga.

• Se renovação falhou mas certificado ainda é válido, manter serving com a versão atual.

### Diagnóstico

• Checar DNS-01 TXT, credencial/scopes do DNS provider, ACME rate limits, clock e logs do Certificate Manager.

• Verificar CertificateVersion ACTIVE e ACKs dos ingress.

### Recuperação

• Corrigir provider/challenge.

• Emitir nova versão, distribuir e aguardar ACK/quorum antes de ativar.

• Rollback para versão anterior se reload falhar.

### Validação pós-recuperação

• Cert correto apresentado em todos os ingress.

• Validade/chain/SAN corretos.

• Certificate status ACTIVE e próxima renovação agendada.

Escalar quando: certificado expira dentro da janela crítica e nova emissão continua falhando.

## RB-12 — Domain custom não resolve ou aponta incorretamente

| **Campo**          | **Definição**                                                                           |
|--------------------|-----------------------------------------------------------------------------------------|
| Severidade típica  | SEV-3                                                                                   |
| Gatilho / sintomas | onboarding de domain preso; NXDOMAIN; CNAME/A incorreto; validação ownership falha.     |
| Objetivo           | Conter impacto, recuperar serviço e preservar evidências antes de mudanças destrutivas. |

### Ação imediata

• Preservar binding e cert existentes se o domínio já estava ativo.

• Não assumir controle de domínio apenas porque DNS mudou.

### Diagnóstico

• Resolver DNS de múltiplos vantage points.

• Checar ownership challenge, TTL, CAA e target esperado.

• Verificar se proxy/CDN externo modifica comportamento.

### Recuperação

• Orientar/corrigir registros via DNS provider.

• Reexecutar validação e emissão TLS após propagation.

### Validação pós-recuperação

• DNS converge; ownership validado; HTTPS serve o Service correto.

# 6. Build, Registry e Deploy

## RB-13 — Registry indisponível

| **Campo**          | **Definição**                                                                           |
|--------------------|-----------------------------------------------------------------------------------------|
| Severidade típica  | SEV-2                                                                                   |
| Gatilho / sintomas | pull/push timeout/5xx; novos tasks não iniciam; builds falham no push.                  |
| Objetivo           | Conter impacto, recuperar serviço e preservar evidências antes de mudanças destrutivas. |

### Ação imediata

• Pausar deploys/rollouts que exigem imagens não cacheadas.

• Não remover tasks saudáveis existentes enquanto Registry estiver fora.

### Diagnóstico

• Provider status; auth; quota/storage; network/DNS; manifest/digest específico.

• Testar pull de imagem conhecida a partir de node de runtime.

### Recuperação

• Restaurar provider/credencial.

• Reprocessar push/pull de forma idempotente.

• Se digest não existir mais, reconstruir do source revision somente se reprodutibilidade estiver garantida e registrar novo artifact.

### Validação pós-recuperação

• Push/pull funcionam de builder e workers.

• Rollout de teste por digest conclui.

• Nenhuma release aponta para artifact inexistente.

## RB-14 — Builder/BuildKit preso ou saturado

| **Campo**          | **Definição**                                                                           |
|--------------------|-----------------------------------------------------------------------------------------|
| Severidade típica  | SEV-2/3                                                                                 |
| Gatilho / sintomas | build RUNNING além do deadline; queue crescente; BuildKit worker unhealthy.             |
| Objetivo           | Conter impacto, recuperar serviço e preservar evidências antes de mudanças destrutivas. |

### Ação imediata

• Bloquear entrada de builds acima da capacidade; preservar runtime.

• Isolar build individual suspeito antes de reiniciar todo pool.

### Diagnóstico

• CPU/RAM/disk do builder; BuildKit status/logs; cache; network para Git/Registry.

• Identificar Dockerfile/comando que excede timeout ou gera consumo anormal.

### Recuperação

• Cancelar build pelo mecanismo de Operation/cancellation.

• Reciclar builder efêmero ou daemon BuildKit isolado.

• Escalar pool somente se storage/registry não forem o gargalo.

### Validação pós-recuperação

• Builds pequenos de canário concluem.

• Queue lag volta ao SLO.

• Builder não possui acesso indevido ao Control Plane/cluster.

## RB-15 — Deployment preso ou falhando

| **Campo**          | **Definição**                                                                           |
|--------------------|-----------------------------------------------------------------------------------------|
| Severidade típica  | SEV-2/3                                                                                 |
| Gatilho / sintomas | Deployment permanece DEPLOYING; tasks Reject/Failed; rollout não converge.              |
| Objetivo           | Conter impacto, recuperar serviço e preservar evidências antes de mudanças destrutivas. |

### Ação imediata

• Congelar novos deploys do mesmo Service.

• Manter release anterior servindo quando rolling update permitir.

### Diagnóstico

• \`docker service ps --no-trunc\`; pull errors; healthcheck; placement; resources; secrets/configs; port conflicts.

• Comparar desired release com última release saudável.

### Recuperação

• Se artefato/config inválido: executar rollback formal para release anterior.

• Se infra/capacidade: corrigir node/registry/resources e permitir reconcile.

• Nunca editar o Docker Service manualmente como solução permanente; qualquer mitigação manual deve ser reconciliada de volta ao Desired State.

### Validação pós-recuperação

• Deployment termina SUCCEEDED/ROLLED_BACK.

• Service atinge replicas saudáveis.

• Release/Operation/Audit refletem o ocorrido.

## RB-16 — Service em crash loop ou unhealthy

| **Campo**          | **Definição**                                                                           |
|--------------------|-----------------------------------------------------------------------------------------|
| Severidade típica  | SEV-3/2                                                                                 |
| Gatilho / sintomas | replicas reiniciando; healthcheck falha; erro rate do app sobe.                         |
| Objetivo           | Conter impacto, recuperar serviço e preservar evidências antes de mudanças destrutivas. |

### Ação imediata

• Determinar se é problema do workload ou plataforma.

• Se rollout recente, considerar rollback antes de investigar profundamente em produção.

### Diagnóstico

• Logs da task; exit code; healthcheck; secrets; env/config; memória/CPU; dependências externas.

• Comparar múltiplas replicas/nodes para descartar host específico.

### Recuperação

• Rollback/redeploy de release saudável ou corrigir configuração.

• Se dependência externa, degradar/limitar workload conforme estratégia do app.

### Validação pós-recuperação

• Replicas estáveis por janela definida.

• Latência/erro retornam ao baseline.

• Nenhum restart contínuo.

# 7. Capacidade e saúde do host

## RB-17 — Disco ou inodes próximos de esgotar

| **Campo**          | **Definição**                                                                           |
|--------------------|-----------------------------------------------------------------------------------------|
| Severidade típica  | SEV-2/3                                                                                 |
| Gatilho / sintomas | disk \> threshold; ENOSPC; Docker/build/logs falham.                                    |
| Objetivo           | Conter impacto, recuperar serviço e preservar evidências antes de mudanças destrutivas. |

### Ação imediata

• Bloquear novos builds no node e evitar pulls grandes.

• Identificar filesystem afetado antes de apagar qualquer coisa.

### Diagnóstico

• \`df -h\`; \`df -i\`; \`docker system df\`; logs; build cache; imagens/volumes.

• Distinguir runtime data, logs, BuildKit cache e volumes persistentes.

### Recuperação

• Rotacionar/limpar logs conforme retention.

• Executar GC seguro de artifacts/cache não referenciados.

• Expandir disco/substituir node quando crescimento é estrutural.

### Validação pós-recuperação

• Espaço e inodes abaixo dos thresholds.

• Docker/BuildKit funcionam.

• GC não removeu artifacts/releases referenciados.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th><p><strong>Cuidado</strong></p>
<p>Nunca use `docker system prune -a --volumes` como resposta genérica em produção. Pode remover imagens, caches e volumes necessários e destruir dados locais.</p></th>
</tr>
</thead>
<tbody>
</tbody>
</table>

Escalar quando: filesystem contém dados não classificados ou volume persistente de aplicação.

## RB-18 — Pressão de memória/CPU no node

| **Campo**          | **Definição**                                                                           |
|--------------------|-----------------------------------------------------------------------------------------|
| Severidade típica  | SEV-2/3                                                                                 |
| Gatilho / sintomas | OOM kills; load alto; latência; tasks throttled/restarted.                              |
| Objetivo           | Conter impacto, recuperar serviço e preservar evidências antes de mudanças destrutivas. |

### Ação imediata

• Identificar workloads dominantes.

• Drain node se a pressão ameaça Docker/Traefik/manager.

### Diagnóstico

• \`free -h\`; load; cgroup/container stats; OOM logs; service resource limits.

• Checar autoscaling loop e se ele está amplificando a pressão.

### Recuperação

• Reduzir/redistribuir workload; aplicar limits/reservations corretos.

• Adicionar capacidade ou corrigir leak do workload.

### Validação pós-recuperação

• Sem OOM/restarts; headroom restabelecido; placement distribuído.

# 8. Vault, credenciais e incidentes de segurança

## RB-19 — Recovery Key perdida ou suspeita de exposição

| **Campo**          | **Definição**                                                                           |
|--------------------|-----------------------------------------------------------------------------------------|
| Severidade típica  | SEV-1/2                                                                                 |
| Gatilho / sintomas | usuário reporta perda/exposição; chave encontrada em local indevido.                    |
| Objetivo           | Conter impacto, recuperar serviço e preservar evidências antes de mudanças destrutivas. |

### Ação imediata

• Se exposição: tratar como incidente de segurança e restringir acesso administrativo.

• Não rotacionar Master Key inteira automaticamente.

### Diagnóstico

• Confirmar se outra cópia válida existe e quem acessou.

• Revisar AuditLog e operações de decrypt/secret management.

### Recuperação

• Se Recovery Key exposta mas Master Key íntegra: gerar nova Recovery Key e rewrap do Master Encryption Key conforme design.

• Revogar cópias antigas e atualizar procedimento de custódia.

• Se houver evidência de acesso aos secrets, rotacionar credenciais afetadas nos providers/workloads.

### Validação pós-recuperação

• Nova Recovery Key verificada por procedimento de restore/unwrap controlado.

• Antiga não desbloqueia material.

• Audit trail completo.

Escalar quando: não existir cópia válida ou houver suspeita de comprometimento da Master Encryption Key.

## RB-20 — Token/API credential/provider credential comprometido

| **Campo**          | **Definição**                                                                           |
|--------------------|-----------------------------------------------------------------------------------------|
| Severidade típica  | SEV-1/2                                                                                 |
| Gatilho / sintomas | vazamento confirmado, uso anômalo ou secret scanner detecta credential.                 |
| Objetivo           | Conter impacto, recuperar serviço e preservar evidências antes de mudanças destrutivas. |

### Ação imediata

• Revogar/rotacionar imediatamente a credencial no sistema de origem.

• Suspender automações que dependem dela se necessário para impedir abuso.

### Diagnóstico

• Determinar escopo, permissões, período e chamadas realizadas.

• Consultar AuditLog, provider logs e operations relacionadas.

### Recuperação

• Emitir credencial de menor privilégio, atualizar SecretVersion/binding e redeploy somente dos serviços dependentes.

• Invalidar sessões/tokens derivados quando aplicável.

### Validação pós-recuperação

• Credencial antiga rejeitada.

• Nova funciona apenas no escopo previsto.

• Sem atividade suspeita após rotação.

## RB-21 — Suspeita de comprometimento de Manager/Executor

| **Campo**          | **Definição**                                                                                     |
|--------------------|---------------------------------------------------------------------------------------------------|
| Severidade típica  | SEV-1                                                                                             |
| Gatilho / sintomas | root compromise, acesso indevido ao docker.sock, binário alterado ou comportamento não explicado. |
| Objetivo           | Conter impacto, recuperar serviço e preservar evidências antes de mudanças destrutivas.           |

### Ação imediata

• Isolar host da rede sem destruir disco.

• Congelar deploys e topology changes.

• Preservar logs/imagem do host e acionar resposta de segurança.

### Diagnóstico

• Avaliar tokens Swarm, secrets potencialmente acessíveis, node certificates e actions no Docker API.

• Determinar se outros nodes foram alcançados.

### Recuperação

• Substituir host em vez de “limpar”.

• Rotacionar join tokens/credenciais administrativas/provider secrets conforme exposição.

• Reconstituir topologia a partir de hosts confiáveis e executar reconcile.

### Validação pós-recuperação

• Cluster saudável somente com nodes confiáveis.

• Credenciais comprometidas revogadas.

• Security review confirma blast radius encerrado.

Escalar quando: houver qualquer incerteza sobre integridade do Raft/Vault/DB ou movimento lateral.

# 9. Backup, Restore e Disaster Recovery

## RB-22 — Backup falhando ou fora do RPO

| **Campo**          | **Definição**                                                                           |
|--------------------|-----------------------------------------------------------------------------------------|
| Severidade típica  | SEV-2                                                                                   |
| Gatilho / sintomas | último backup válido ultrapassa RPO; checksum/upload/retention falha.                   |
| Objetivo           | Conter impacto, recuperar serviço e preservar evidências antes de mudanças destrutivas. |

### Ação imediata

• Impedir GC de backups anteriores.

• Classificar se falha é fonte, criptografia, storage ou scheduler.

### Diagnóstico

• Job logs; storage provider; credentials; quota; checksum; DB/Swarm snapshot source.

• Validar se alertas de freshness estão corretos.

### Recuperação

• Corrigir causa e executar backup manual controlado.

• Validar checksum e restore de amostra antes de considerar incidente encerrado.

### Validação pós-recuperação

• Backup novo VERIFIED; freshness dentro do RPO.

• Cópias anteriores preservadas conforme retention.

## RB-23 — Restore do banco da plataforma

| **Campo**          | **Definição**                                                                           |
|--------------------|-----------------------------------------------------------------------------------------|
| Severidade típica  | SEV-1                                                                                   |
| Gatilho / sintomas | corrupção/perda confirmada ou necessidade de PITR.                                      |
| Objetivo           | Conter impacto, recuperar serviço e preservar evidências antes de mudanças destrutivas. |

### Ação imediata

• Congelar writes e workers.

• Registrar ponto de recuperação escolhido e impacto de RPO.

• Preservar banco/volume original para investigação.

### Diagnóstico

• Confirmar backup/PITR válido e Recovery Key disponível para conteúdo cifrado.

• Mapear operations/deployments posteriores ao ponto de restore que poderão existir no runtime mas não no DB restaurado.

### Recuperação

• Restaurar DB em instância isolada e validar integridade/schema primeiro.

• Promover DB restaurado.

• Executar reconcile em modo DR: detectar resources existentes no Swarm antes de CREATE; usar IDs/labels para adoção segura.

### Validação pós-recuperação

• Login/Teams/Projects/Services consistentes.

• Vault decryption test passa.

• Operations/outbox sem duplicidade.

• Runtime converge sem recriar serviços existentes.

Escalar quando: RPO implica perda material de operações ou reconcile detecta recursos ambíguos.

## RB-24 — Clean Rebuild completo da plataforma

| **Campo**          | **Definição**                                                                           |
|--------------------|-----------------------------------------------------------------------------------------|
| Severidade típica  | SEV-1                                                                                   |
| Gatilho / sintomas | infra de Control Plane/cluster perdida ou opção mais segura que restaurar Swarm antigo. |
| Objetivo           | Conter impacto, recuperar serviço e preservar evidências antes de mudanças destrutivas. |

### Ação imediata

• Declarar DR e congelar mudanças externas de DNS/LB/Registry.

• Inventariar ativos sobreviventes: DB backup, Vault/Recovery Key, Registry artifacts, certs, provider configs.

### Diagnóstico

• Validar integridade dos backups e digests de artifacts.

• Definir novo cluster/topologia e rede privada.

### Recuperação

• Provisionar Control Plane e novo Swarm.

• Restaurar DB/Vault/config; conectar Registry/providers.

• Reconstruir networks/secrets/configs/services a partir do Desired State e releases por digest.

• Restaurar Edge/LB/Traefik e só então direcionar tráfego.

### Validação pós-recuperação

• Todos os recursos críticos reconciliados.

• TLS/domains válidos.

• Smoke/E2E passa.

• RPO/RTO medidos e registrados.

• Novo backup completo realizado.

Escalar quando: algum componente essencial (DB backup, Recovery Key ou artifacts) não estiver disponível.

## RB-25 — Restore do estado do Swarm

| **Campo**          | **Definição**                                                                               |
|--------------------|---------------------------------------------------------------------------------------------|
| Severidade típica  | SEV-1                                                                                       |
| Gatilho / sintomas | Clean Rebuild não é desejado e existe necessidade explícita de recuperar Raft/state antigo. |
| Objetivo           | Conter impacto, recuperar serviço e preservar evidências antes de mudanças destrutivas.     |

### Ação imediata

• Usar somente backup consistente de manager e preservar o original.

• Confirmar unlock key se autolock estiver habilitado.

### Diagnóstico

• Verificar versão Docker compatível e documentação de restore testada no DR Lab.

• Confirmar que nenhum cluster concorrente está usando a mesma identidade/estado.

### Recuperação

• Seguir procedimento de restore validado pelo laboratório, inicialmente isolado da rede de produção.

• Após boot, validar services/secrets/configs/nodes e então reconstruir managers/workers necessários.

### Validação pós-recuperação

• Raft saudável.

• Services íntegros.

• Reconcile com DB sem conflitos.

• Backup do estado restaurado executado.

Escalar quando: restore não tiver sido testado na versão atual ou houver dúvida entre Fast Swarm Restore e Clean Rebuild.

# 10. Manutenção, mudanças de topologia e upgrades

## RB-26 — Adicionar Worker

| **Campo**          | **Definição**                                                                           |
|--------------------|-----------------------------------------------------------------------------------------|
| Severidade típica  | Mudança planejada                                                                       |
| Gatilho / sintomas | necessidade de capacidade ou substituição.                                              |
| Objetivo           | Conter impacto, recuperar serviço e preservar evidências antes de mudanças destrutivas. |

### Ação imediata

• Validar rede privada, firewall, Docker version e capacidade do host.

### Diagnóstico

• Gerar Enrollment Token temporário da plataforma; verificar clusterId/role/labels pretendidos.

### Recuperação

• Executar bootstrap; join como worker; aplicar labels; validar heartbeat; somente depois habilitar placement.

### Validação pós-recuperação

• Node Ready/Active.

• Task canário agenda e comunica pela overlay.

• Métricas/logs/health disponíveis.

## RB-27 — Adicionar ou substituir Manager

| **Campo**          | **Definição**                                                                           |
|--------------------|-----------------------------------------------------------------------------------------|
| Severidade típica  | Mudança planejada / SEV-2                                                               |
| Gatilho / sintomas | expansão para topologia HA ou substituição.                                             |
| Objetivo           | Conter impacto, recuperar serviço e preservar evidências antes de mudanças destrutivas. |

### Ação imediata

• Confirmar quorum saudável antes da mudança.

• Manter número ímpar de managers quando possível.

### Diagnóstico

• Checar latência/rede entre managers e versão Docker compatível.

### Recuperação

• Adicionar novo manager e esperar Reachable antes de remover/demover o antigo.

• Uma mudança de membership por vez.

### Validação pós-recuperação

• Quorum esperado; \`docker node ls\` estável.

• Scheduling/updates funcionam.

• Backup recente do Swarm após mudança.

Escalar quando: quorum já estiver degradado; nesse caso tratar como incidente, não manutenção.

## RB-28 — Remover ou drenar Node

| **Campo**          | **Definição**                                                                           |
|--------------------|-----------------------------------------------------------------------------------------|
| Severidade típica  | Mudança planejada                                                                       |
| Gatilho / sintomas | manutenção, substituição, decomissionamento.                                            |
| Objetivo           | Conter impacto, recuperar serviço e preservar evidências antes de mudanças destrutivas. |

### Ação imediata

• \`docker node update --availability drain \<node\>\` e aguardar tasks saírem.

### Diagnóstico

• Confirmar serviços globais/constraints e dados locais que impedem remoção.

### Recuperação

• Após zero workload relevante e validação, remover do Swarm; revogar enrollment/join material associado quando aplicável.

### Validação pós-recuperação

• Replicas preservadas.

• Nenhum alert de capacity/placement.

• Inventory/CMDB da plataforma atualizado.

## RB-29 — Upgrade do Control Plane

| **Campo**          | **Definição**                                                                           |
|--------------------|-----------------------------------------------------------------------------------------|
| Severidade típica  | Mudança planejada                                                                       |
| Gatilho / sintomas | nova release da plataforma.                                                             |
| Objetivo           | Conter impacto, recuperar serviço e preservar evidências antes de mudanças destrutivas. |

### Ação imediata

• Confirmar backup, migrations compatíveis, feature flags e rollback artifact.

• Congelar mudanças estruturais durante janela se upgrade alterar schema.

### Diagnóstico

• Executar preflight do RC: migration plan, DB load, version compatibility Executor/API.

### Recuperação

• Aplicar expand migration; rollout gradual/canário do Control Plane; observar SLOs; expandir.

• Somente contract/cleanup migrations após janela de compatibilidade.

• Rollback aplicação se necessário sem reverter migration destrutiva.

### Validação pós-recuperação

• API, workers, Operations, reconcile e UI saudáveis.

• Sem error budget burn anormal.

• Upgrade evidence registrado.

## RB-30 — Upgrade Docker/Traefik/BuildKit em cluster

| **Campo**          | **Definição**                                                                           |
|--------------------|-----------------------------------------------------------------------------------------|
| Severidade típica  | Mudança planejada                                                                       |
| Gatilho / sintomas | patch/security/feature release de componente de infraestrutura.                         |
| Objetivo           | Conter impacto, recuperar serviço e preservar evidências antes de mudanças destrutivas. |

### Ação imediata

• Validar versão no laboratório e compatibilidade N/N-1 definida.

• Nunca atualizar todos os managers/ingress simultaneamente.

### Diagnóstico

• Checar release notes, config deprecações e rollback package/image.

### Recuperação

• Nodes: drain → upgrade → validate → active, um por vez conforme role/quorum.

• Ingress: retirar do LB → upgrade → health → recolocar.

• Builders: substituir de forma rolling.

### Validação pós-recuperação

• Cluster quorum intacto.

• Dataplane sem interrupção fora do SLO.

• Canários Docker/overlay/TLS/build passam.

# 11. Comunicação, evidência e postmortem

## 11.1 Timeline mínima

| **Campo**     | **Registrar**                                        |
|---------------|------------------------------------------------------|
| Detecção      | timestamp, alerta/sinal, primeiro impacto conhecido. |
| Classificação | SEV, incident commander, blast radius.               |
| Mudanças      | cada comando/config/deploy com autor e timestamp.    |
| Hipóteses     | o que foi testado e evidência a favor/contra.        |
| Mitigação     | momento em que impacto reduziu.                      |
| Recuperação   | quando SLO e consistência foram validados.           |
| Follow-up     | ações preventivas, owner e prazo.                    |

## 11.2 Critério para postmortem obrigatório

• Todo SEV-1.

• SEV-2 que ultrapasse RTO/SLO relevante ou reincida.

• Qualquer incidente com perda de dados, rollback de DB/Swarm, force-new-cluster ou exposição de segredo.

• Qualquer falha que revele runbook ausente/incorreto ou alerta que não detectou o problema.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th><p><strong>Postmortem sem caça ao culpado</strong></p>
<p>O objetivo é identificar condições sistêmicas: desenho, automação, teste, observabilidade, capacidade e processo. A ação corretiva deve reduzir probabilidade ou blast radius, não apenas pedir “mais atenção”.</p></th>
</tr>
</thead>
<tbody>
</tbody>
</table>

# 12. Exercícios e validação dos runbooks

| **Runbook/tema**                | **Cadência mínima de exercício**     | **Ambiente**                |
|---------------------------------|--------------------------------------|-----------------------------|
| Worker/Manager failure          | Mensal                               | Chaos/DR Lab                |
| Quorum loss / force-new-cluster | Trimestral                           | Chaos/DR Lab                |
| Traefik/LB/TLS                  | Mensal                               | Swarm Integration / Staging |
| Registry/Builder outage         | Mensal                               | Build Lab                   |
| DB restore/PITR                 | Trimestral                           | DR Lab                      |
| Clean Rebuild                   | Trimestral ou antes de major release | DR Lab                      |
| Recovery Key procedure          | Trimestral                           | Ambiente isolado            |
| Platform upgrade/rollback       | Cada release candidate               | Staging                     |
| Docker/Traefik upgrade          | Antes de cada rollout de infra       | Lab + canário               |

## 12.1 Evidência de exercício

• Versão dos componentes e commit da plataforma.

• Topologia inicial e falha injetada.

• Timestamps de detecção, contenção, recuperação e validação.

• RTO/RPO observado versus alvo do Anexo B.

• Passos divergentes do runbook e correções necessárias.

• Links para logs, métricas, Operations e relatório de teste.

# 13. Índice rápido de incidentes

| **Sintoma**                           | **Começar por**       |
|---------------------------------------|-----------------------|
| Painel/API fora, apps ainda servem    | RB-01 / RB-02 / RB-03 |
| Apps de vários tenants fora           | RB-09 / RB-10 / RB-06 |
| Um node caiu                          | RB-04 ou RB-05        |
| Não consigo atualizar o Swarm         | RB-06                 |
| Tasks Running sem comunicação interna | RB-07                 |
| Docker não responde em um host        | RB-08                 |
| HTTPS/cert inválido                   | RB-11 / RB-12         |
| Deploys falham no pull                | RB-13                 |
| Builds presos                         | RB-14                 |
| Deployment não converge               | RB-15                 |
| Uma app reinicia continuamente        | RB-16                 |
| Disco/CPU/RAM crítico                 | RB-17 / RB-18         |
| Recovery Key/token vazou              | RB-19 / RB-20         |
| Manager possivelmente comprometido    | RB-21                 |
| Backup fora do RPO                    | RB-22                 |
| Banco precisa voltar no tempo         | RB-23                 |
| Perdemos a infraestrutura             | RB-24                 |
| Precisamos restaurar Raft/Swarm       | RB-25                 |
| Adicionar/remover nodes               | RB-26 / RB-27 / RB-28 |
| Upgrade                               | RB-29 / RB-30         |

# 14. Critérios finais de aceite do Anexo E

| **\#** | **Critério**                                                                                                                 |
|--------|------------------------------------------------------------------------------------------------------------------------------|
| 1      | Existe owner operacional para cada runbook e canal de escalonamento definido.                                                |
| 2      | Nenhum runbook depende de acesso não documentado ou segredo armazenado apenas na memória de uma pessoa.                      |
| 3      | RB-06 (perda de quorum) foi exercitado em laboratório e o procedimento de force-new-cluster é conhecido como último recurso. |
| 4      | RB-23/24/25 foram testados com backups reais do formato atual e Recovery Key válida.                                         |
| 5      | Os procedimentos distinguem claramente Control Plane de Dataplane e evitam reiniciar runtime quando apenas a UI/API falha.   |
| 6      | Drain/maintenance de nodes preserva replicas e respeita constraints.                                                         |
| 7      | Traefik/LB/TLS possuem validação ponta a ponta depois da recuperação.                                                        |
| 8      | Registry outage não causa remoção desnecessária de tasks saudáveis.                                                          |
| 9      | Build incident não expõe builder ao Control Plane/Manager.                                                                   |
| 10     | Deployment rollback é formal e auditado, não edição manual permanente do Docker Service.                                     |
| 11     | Limpeza de disco não usa prune destrutivo genérico e possui GC referencial.                                                  |
| 12     | Rotação de Recovery Key não exige recriptografar todos os SecretVersions.                                                    |
| 13     | Incidente de credential comprometida produz rotação, revogação e auditoria verificáveis.                                     |
| 14     | Upgrade do Control Plane segue expand-contract e possui caminho de rollback.                                                 |
| 15     | Upgrade de infraestrutura é rolling e preserva quorum/ingress.                                                               |
| 16     | Cada exercício mede RTO/RPO e atualiza o runbook se a prática divergir do texto.                                             |
| 17     | SEV-1 produz timeline, evidências e postmortem obrigatório.                                                                  |
| 18     | Após qualquer recuperação, um reconcile sweep e smoke/E2E confirmam consistência entre Desired State e Actual State.         |

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th><p><strong>Conclusão</strong></p>
<p>Com estes runbooks, a plataforma deixa de depender de improvisação durante incidentes. O objetivo não é prever todas as falhas possíveis, mas garantir que os cenários de maior impacto tenham diagnóstico, contenção, recuperação e validação previamente praticados e auditáveis.</p></th>
</tr>
</thead>
<tbody>
</tbody>
</table>

# 15. Referências operacionais

• Docker Docs — Swarm administration, nodes, services, routing mesh e disaster recovery.

• Traefik Docs — Swarm provider, health/entrypoints e TLS configuration.

• PostgreSQL/provider gerenciado — backup, PITR e failover conforme fornecedor adotado.

• Partes 3, 5, 6, 7 e 8 desta especificação — Runtime, DR, Infra, Control Plane e Edge.

• Anexos B, C e D — SLOs, Threat Model e Estratégia de Testes.
