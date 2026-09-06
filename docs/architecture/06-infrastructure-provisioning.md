---
document: "06"
title: "Infraestrutura e Provisionamento"
type: "architecture"
status: "approved"
source: "docx"
---

**PLATAFORMA PAAS  
CLUSTER-FIRST**

**Documento técnico consolidado - Parte 6**

Infraestrutura, conectividade, provisionamento e lifecycle de nodes

| **Campo**       | **Definição**                                                                                                                                                                  |
|-----------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Status          | Documento vivo - v0.6                                                                                                                                                          |
| Data            | 05 de setembro de 2026                                                                                                                                                         |
| Escopo          | Instalação cluster-first, bootstrap seguro, roles de nodes, rede, firewall, expansão/redução do Swarm e integrações de infraestrutura.                                         |
| Premissas       | Docker Engine + Swarm desde o primeiro node; Traefik em ingress nodes; Load Balancer externo em HA; aplicações stateless; bancos/Redis/Object Storage externos.                |
| Decisão central | A plataforma nasce como cluster, mesmo com um único node. Adicionar capacidade significa conectar nodes ao Swarm, não migrar de Docker standalone para cluster posteriormente. |

## Resumo executivo

A infraestrutura será apresentada ao usuário como um Cluster composto por nodes com papéis explícitos. O primeiro bootstrap cria um Swarm de um único manager; a mesma máquina pode executar workloads no início. A expansão acontece por enrollment temporário: o usuário prepara uma nova máquina, executa um bootstrap script e a plataforma a conecta como Worker, Ingress, Builder ou, em uma operação mais restrita, Manager. O produto deve automatizar a complexidade de Docker, rede e providers sem expor Docker API insegura na internet.

| **Princípio:** Cluster-first não significa obrigar alta disponibilidade desde o primeiro minuto. Significa que a primitive de runtime sempre é Docker Service/Swarm; HA é uma propriedade alcançada conforme nodes e redundância são adicionados. |
|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|

# 1. Modelo de infraestrutura

## 1.1 Hierarquia

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Team<br />
|<br />
+-- Project<br />
| +-- Environment<br />
| +-- Service<br />
|<br />
+-- Cluster<br />
|<br />
+-- Manager Nodes<br />
+-- Worker Nodes<br />
+-- Ingress Nodes<br />
+-- Builder Nodes<br />
|<br />
+-- Load Balancer<br />
+-- Registry Connection<br />
+-- Network / Firewall profile</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

Project e Environment pertencem ao domínio do produto. Cluster pertence ao domínio de infraestrutura. Um Environment referencia o Cluster onde seus Services devem executar, preservando a flexibilidade de colocar produção e homologação em clusters diferentes no futuro.

## 1.2 Papéis lógicos de node

| **Papel** | **Responsabilidade**                                                                          | **Pode acumular?**                                  |
|-----------|-----------------------------------------------------------------------------------------------|-----------------------------------------------------|
| Manager   | Raft, estado do Swarm, scheduling, alterações de Services/Nodes e API de gerenciamento.       | Sim, em clusters pequenos.                          |
| Worker    | Executa Tasks das aplicações e reporta estado ao manager.                                     | Sim.                                                |
| Ingress   | Executa uma instância de Traefik e recebe tráfego do Load Balancer.                           | Sim, mas produção deve preferir nodes dedicados.    |
| Builder   | Executa builds isolados Railpack/BuildKit. Código de repositório é considerado não confiável. | Pode, mas produção deve separar de manager/ingress. |
| System    | Reserva lógica para workloads internos da plataforma quando necessário.                       | Sim, controlado por placement labels.               |

| **Distinção:** Manager é um role nativo do Swarm. Ingress, Builder e System são roles lógicos da nossa plataforma implementados com node labels + placement constraints. |
|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------|

# 2. Topologias suportadas

## 2.1 Bootstrap mínimo

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>NODE 01<br />
+------------------------------------+<br />
| Docker Engine |<br />
| Swarm Manager / Worker |<br />
| Traefik (opcional no início) |<br />
| Platform services |<br />
| User workloads |<br />
+------------------------------------+<br />
<br />
Cluster status: Functional<br />
HA status: Not configured</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

Esse modo serve para início, desenvolvimento e instalações pequenas. O cluster já é Swarm, portanto todos os workloads continuam sendo Services e não containers standalone.

## 2.2 Produção com HA de compute/ingress

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>L4 LOAD BALANCER<br />
|<br />
+-------------+-------------+<br />
| | |<br />
ingress-01 ingress-02 ingress-03<br />
Traefik A Traefik B Traefik C<br />
| | |<br />
+-------------+-------------+<br />
|<br />
SWARM OVERLAY<br />
|<br />
+-------------------+-------------------+<br />
| | |<br />
worker-01 worker-02 worker-03<br />
<br />
Managers: manager-01 / manager-02 / manager-03<br />
External: PostgreSQL / Redis / Object Storage / Registry</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

Para produção séria, o objetivo é separar quorum, entrada e compute. Os dados stateful permanecem em providers externos nesta fase, reduzindo drasticamente o problema de recuperação e mobilidade de workloads.

# 3. Primeiro bootstrap do cluster

## 3.1 Objetivo do instalador

O instalador transforma uma máquina Linux limpa no primeiro node da plataforma. Ele deve ser idempotente sempre que possível e abortar quando detectar condições inseguras ou incompatíveis.

## 3.2 Preflight checks

- Arquitetura e sistema operacional suportados pela versão da plataforma.

- Acesso root/sudo e filesystem gravável.

- Hostname válido e resolução local consistente.

- Relógio sincronizado (NTP/chrony/systemd-timesyncd) para TLS, logs e consenso distribuído.

- Espaço em disco e inodes mínimos.

- Portas necessárias livres no primeiro node.

- Docker Engine presente ou possibilidade de instalação.

- Interface/IP que será usado como advertise address do Swarm.

- Conectividade de saída para registry, Git providers, DNS/ACME e serviços externos necessários.

## 3.3 Sequência de bootstrap

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Install command<br />
|<br />
v<br />
Preflight<br />
|<br />
v<br />
Install / validate Docker Engine<br />
|<br />
v<br />
Choose advertise address<br />
|<br />
v<br />
docker swarm init<br />
|<br />
v<br />
Create platform overlay networks<br />
|<br />
v<br />
Create node labels<br />
|<br />
v<br />
Deploy platform system services<br />
|<br />
v<br />
Deploy Traefik / ingress if enabled<br />
|<br />
v<br />
Initialize platform database + encryption<br />
|<br />
v<br />
Create first User / Team / OWNER<br />
|<br />
v<br />
Cluster READY</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

| **Rede:** O advertise address deve ser um endereço estável e alcançável pelos outros nodes. Em máquinas com múltiplas interfaces, a escolha deve ser explícita. |
|-----------------------------------------------------------------------------------------------------------------------------------------------------------------|

# 4. Portas e firewall do Swarm

## 4.1 Matriz de rede entre nodes

| **Porta/protocolo** | **Origem -\> destino**      | **Uso**                                                 | **Exposição**                                          |
|---------------------|-----------------------------|---------------------------------------------------------|--------------------------------------------------------|
| 2377/TCP            | Nodes/Managers -\> Managers | Control plane e entrada de novos nodes no Swarm.        | Somente rede confiável do cluster.                     |
| 7946/TCP            | Node \<-\> Node             | Descoberta/comunicação entre nodes.                     | Somente rede confiável.                                |
| 7946/UDP            | Node \<-\> Node             | Descoberta/comunicação entre nodes.                     | Somente rede confiável.                                |
| 4789/UDP            | Node \<-\> Node             | VXLAN / overlay data path.                              | Nunca abrir indiscriminadamente na borda pública.      |
| IP protocol 50      | Node \<-\> Node             | IPSec ESP quando overlay encryption é utilizada.        | Somente rede do cluster.                               |
| 80/TCP              | Internet/LB -\> Ingress     | HTTP público / redirects / challenges quando aplicável. | Somente ingress nodes.                                 |
| 443/TCP             | Internet/LB -\> Ingress     | HTTPS/TLS público.                                      | Somente ingress nodes.                                 |
| 22/TCP              | Admin network -\> Node      | SSH de bootstrap/emergência, se adotado.                | Restrito; nunca necessário para tráfego de aplicações. |

| **Segurança:** A porta UDP 4789 é crítica: VXLAN não autentica tráfego por si só. O firewall deve aceitar esse tráfego apenas de IPs/CIDRs pertencentes ao cluster. |
|---------------------------------------------------------------------------------------------------------------------------------------------------------------------|

## 4.2 Docker API

- O socket /var/run/docker.sock permanece local aos componentes administrativos autorizados.

- Não expor Docker daemon em 0.0.0.0:2375 sem TLS.

- A UI/browser nunca fala diretamente com Docker.

- O acesso administrativo ao Swarm ocorre pelo manager/control plane da plataforma.

- Multi-cluster remoto exigirá um mecanismo seguro próprio no futuro; não será resolvido simplesmente abrindo Docker API na internet.

# 5. Rede privada e endereçamento

## 5.1 Modelo recomendado

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>PUBLIC NETWORK<br />
|<br />
+--&gt; Load Balancer public IP<br />
| |<br />
| +--&gt; ingress nodes :80/:443<br />
|<br />
+--&gt; SSH/VPN endpoint (optional)<br />
<br />
PRIVATE / TRUSTED CLUSTER NETWORK<br />
|<br />
+--&gt; managers :2377<br />
+--&gt; all nodes :7946 tcp/udp<br />
+--&gt; all nodes :4789 udp<br />
+--&gt; registry/private services when available</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

Sempre que o provedor oferecer rede privada, ela deve ser a primeira escolha para advertise address e tráfego interno do Swarm. Public IP serve para entrada pública, bootstrap controlado ou fallback, não como substituto de uma rede confiável.

## 5.2 Modelo de IP no banco

| **Campo**          | **Exemplo**    | **Uso**                                                            |
|--------------------|----------------|--------------------------------------------------------------------|
| publicAddress      | 203.0.113.10   | LB target público, SSH ou bootstrap quando necessário.             |
| privateAddress     | 10.20.0.11     | Swarm advertise/data path preferencial.                            |
| advertiseAddress   | 10.20.0.11     | Endereço que o Swarm anuncia aos outros nodes.                     |
| ingressAddress     | 10.20.0.11:443 | Target utilizado pelo Load Balancer.                               |
| providerInstanceId | srv-abc123     | Correlação com cloud provider quando provisionado automaticamente. |

# 6. Enrollment seguro de novos nodes

## 6.1 Não expor o Swarm join token diretamente

O Docker possui join tokens separados para Worker e Manager. Esses tokens permitem a entrada de novos nodes enquanto permanecerem válidos. A plataforma deve escondê-los atrás de um Enrollment Token próprio, de curta duração, evitando que o usuário copie um segredo de cluster de longa duração.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>UI<br />
|<br />
+-- Add Node<br />
|<br />
v<br />
Platform Enrollment Token<br />
TTL: 15 min / one-use<br />
|<br />
v<br />
bootstrap.sh<br />
|<br />
+--&gt; validate host/preflight<br />
+--&gt; authenticate enrollment over HTTPS<br />
+--&gt; receive join material<br />
+--&gt; docker swarm join<br />
+--&gt; verify node appears in cluster<br />
+--&gt; apply labels<br />
+--&gt; invalidate enrollment token<br />
v<br />
Node READY</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 6.2 EnrollmentToken

| **Campo**             | **Descrição**                                     |
|-----------------------|---------------------------------------------------|
| id                    | Identificador interno.                            |
| clusterId             | Cluster que aceitará o novo node.                 |
| requestedRole         | worker \| ingress \| builder \| manager.          |
| tokenHash             | Somente hash do token de enrollment é persistido. |
| expiresAt             | Expiração curta, por exemplo 15 minutos.          |
| maxUses               | 1 por padrão.                                     |
| createdBy             | Usuário que autorizou.                            |
| usedAt / usedByNodeId | Auditoria e prevenção de replay.                  |
| status                | PENDING \| USED \| EXPIRED \| REVOKED.            |

## 6.3 Join token do Swarm

- Worker e Manager possuem join tokens distintos.

- O token de Manager recebe proteção extra e nunca aparece em logs ou UI.

- A plataforma pode rotacionar o join token se houver suspeita de vazamento; nodes já existentes não são expulsos pela rotação.

- Criar Manager é operação de alto risco e exige INSTANCE_ADMIN/OWNER, reautenticação e confirmação explícita.

- Default de Add Node é Worker. Ingress/Builder são Workers com labels adicionais.

# 7. Lifecycle de um Node

## 7.1 Estados da plataforma

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>REQUESTED<br />
|<br />
v<br />
ENROLLING<br />
|<br />
v<br />
JOINED<br />
|<br />
v<br />
READY / ACTIVE<br />
|<br />
+------&gt; DRAINING ------&gt; MAINTENANCE<br />
| |<br />
| v<br />
| ACTIVE<br />
|<br />
+------&gt; UNREACHABLE<br />
| |<br />
| +--&gt; RECOVERED<br />
| +--&gt; REMOVE<br />
v<br />
REMOVED</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 7.2 Ações por estado

| **Ação**     | **Comportamento**                                                                                                  |
|--------------|--------------------------------------------------------------------------------------------------------------------|
| Drain        | Define availability=drain. O Swarm para de colocar novas Tasks e remaneja workloads de Services para nodes Active. |
| Activate     | Retorna o node a availability=active para receber Tasks.                                                           |
| Pause        | Opcionalmente impede novas Tasks sem necessariamente evacuar as atuais, quando aplicável ao fluxo escolhido.       |
| Promote      | Worker -\> Manager, preservando quorum.                                                                            |
| Demote       | Manager -\> Worker antes de manutenção/remoção quando necessário.                                                  |
| Remove       | Remove o node do Swarm após drain/leave e validações.                                                              |
| Force Remove | Somente para node perdido/inacessível; operação privilegiada e auditada.                                           |

# 8. Manutenção sem indisponibilidade

## 8.1 Worker

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Select worker-02<br />
|<br />
v<br />
Drain<br />
|<br />
v<br />
Wait user Tasks = 0<br />
|<br />
v<br />
Patch OS / Docker / reboot<br />
|<br />
v<br />
Health + connectivity checks<br />
|<br />
v<br />
Activate<br />
|<br />
v<br />
READY</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 8.2 Manager

Managers devem ser atualizados sequencialmente, nunca derrubando quorum. Em um cluster de três managers, apenas um pode estar indisponível por vez. Workloads existentes podem continuar rodando se quorum for perdido, mas operações de gerenciamento e reconciliação ficam comprometidas até o quorum voltar.

- Confirmar quorum saudável antes de iniciar.

- Drain se o manager também executar workloads.

- Atualizar/reiniciar um manager por vez.

- Esperar status Reachable/Leader estabilizar antes do próximo.

- Nunca promover/demover em lote sem simular o novo quorum.

## 8.3 Ingress

Ingress nodes devem sair primeiro do target pool do Load Balancer. Depois de o LB confirmar que não envia novas conexões, o node pode ser drainado e atualizado. Ao retornar, Traefik é validado antes de readicionar o target.

# 9. Labels e placement

## 9.1 Labels gerenciadas pela plataforma

| **Label**               | **Exemplo** | **Finalidade**                                                             |
|-------------------------|-------------|----------------------------------------------------------------------------|
| platform.role.manager   | true        | Metadado espelho para UI/policies; role real continua sendo Swarm Manager. |
| platform.role.ingress   | true        | Placement do Traefik.                                                      |
| platform.role.builder   | true        | Placement de builders BuildKit/Railpack.                                   |
| platform.workloads      | true        | Nodes aptos a workloads de usuário.                                        |
| platform.zone           | sa-east-1a  | Distribuição/anti-affinity futura.                                         |
| platform.provider       | hetzner     | Informação operacional/provider.                                           |
| platform.environment    | production  | Separação opcional por política de placement.                              |
| platform.capacity.class | compute     | Classe de capacidade para scheduling/policies futuras.                     |

## 9.2 Constraints

Services internos e de usuário podem receber constraints geradas pela plataforma. A UI não precisa expor sintaxe bruta do Swarm por padrão; oferece políticas compreensíveis e gera as constraints internamente.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>UI policy:<br />
Workload pool = Production<br />
Avoid builders<br />
<br />
Generated constraints:<br />
node.labels.platform.workloads == true<br />
node.labels.platform.environment == production</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

# 10. Load Balancer Provider

## 10.1 Responsabilidade

O Load Balancer público trabalha em L4/TCP nas portas 80/443 e aponta somente para ingress nodes saudáveis. Ele não conhece Projects, domains ou Services; essa decisão continua no Traefik.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Internet<br />
|<br />
v<br />
L4 Load Balancer<br />
|<br />
+--&gt; ingress-01:443<br />
+--&gt; ingress-02:443<br />
+--&gt; ingress-03:443<br />
<br />
Each ingress:<br />
Traefik -&gt; Host rule -&gt; Swarm Service</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 10.2 Interface de provider

| **Operação**         | **Finalidade**                                             |
|----------------------|------------------------------------------------------------|
| createLoadBalancer   | Criar LB quando o provider for gerenciado pela plataforma. |
| getLoadBalancer      | Ler estado/endereço/health.                                |
| addTarget            | Adicionar ingress node depois de health check.             |
| removeTarget         | Retirar node antes de manutenção/remoção.                  |
| configureListener    | Garantir listeners TCP 80/443.                             |
| configureHealthCheck | Configurar TCP/HTTP health check apropriado.               |
| deleteLoadBalancer   | Destruição explícita e protegida.                          |

## 10.3 Modos

- MANAGED: provider conectado; plataforma cria e mantém o LB.

- EXTERNAL: usuário fornece um LB existente e a plataforma exibe targets esperados.

- MANUAL: plataforma mostra IPs dos ingress nodes para configuração fora do produto.

- SINGLE-NODE: sem HA, tráfego pode chegar diretamente ao Traefik do único node.

# 11. DNS Provider

## 11.1 Escopos diferentes

| **Uso**                  | **Responsabilidade**                                                                     |
|--------------------------|------------------------------------------------------------------------------------------|
| Platform wildcard domain | Ex.: \*.apps.platform.example apontando para o LB principal do cluster.                  |
| Custom domains           | Usuário pode configurar DNS manualmente ou conectar provider.                            |
| ACME DNS-01              | Certificate Manager cria registros \_acme-challenge quando houver integração compatível. |
| Failover/migração        | Provider pode atualizar records caso o endpoint público do cluster mude.                 |

## 11.2 Provider credentials

Tokens de Cloudflare, Route53 ou outros providers são secrets do produto. Eles ficam no Vault versionado, recebem scope mínimo e nunca são enviados ao frontend após criação.

# 12. Registry Provider

## 12.1 Por que faz parte da infraestrutura

Em cluster multi-node, o node escolhido pelo scheduler precisa baixar exatamente o mesmo artefato produzido pelo builder. Portanto o Registry é a fronteira entre build e runtime distribuído.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Builder<br />
|<br />
v<br />
OCI Image<br />
|<br />
v<br />
Registry<br />
|<br />
+--&gt; worker-01 pull digest<br />
+--&gt; worker-02 pull digest<br />
+--&gt; worker-03 pull digest<br />
<br />
Swarm Service always references immutable release digest</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 12.2 Modos

- External GHCR / Docker Hub / GitLab Registry ou OCI registry compatível.

- Private registry do cliente conectado por credentials do Vault.

- Registry gerenciado pela própria plataforma pode ser adicionado futuramente.

- Deployments devem preferir digest imutável; tags são metadata/conveniência, não identidade final do release.

# 13. Provisionamento automático de cloud

## 13.1 Bring Your Own Server primeiro

A primeira implementação não depende de APIs de cloud. O usuário cria uma VPS onde quiser, recebe o bootstrap command e conecta a máquina. Isso mantém o produto provider-agnostic e reduz o escopo inicial.

## 13.2 Providers depois

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>UI: Add Node<br />
|<br />
+--&gt; Bring Your Own Server<br />
|<br />
+--&gt; Cloud Provider<br />
|<br />
+--&gt; create instance<br />
+--&gt; private network<br />
+--&gt; firewall rules<br />
+--&gt; bootstrap<br />
+--&gt; wait for enrollment<br />
+--&gt; label node<br />
+--&gt; add to LB if ingress<br />
v<br />
READY</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 13.3 CloudProvider contract

| **Operação**         | **Exemplo**                                         |
|----------------------|-----------------------------------------------------|
| listRegions          | Regiões disponíveis.                                |
| listInstanceTypes    | CPU/RAM/storage/custo metadata.                     |
| createServer         | Provisiona VM/host.                                 |
| deleteServer         | Remove somente com proteção contra perda acidental. |
| createPrivateNetwork | Opcional, quando provider permitir.                 |
| attachPrivateNetwork | Coloca nodes no mesmo segmento confiável.           |
| configureFirewall    | Libera somente as portas necessárias.               |
| getServerStatus      | Provisioning / running / stopped / failed.          |
| rebootServer         | Operação administrativa controlada.                 |
| getConsoleMetadata   | Informações de diagnóstico sem vazar credentials.   |

## 13.4 OpenTofu como opção interna

Quando a plataforma avançar para provisionamento declarativo, OpenTofu pode ser usado internamente como executor de providers, especialmente para infraestrutura mais complexa. Isso não deve vazar para a UX: o usuário escolhe provider, região, tamanho e role; a plataforma cuida da implementação.

# 14. Cluster Readiness

## 14.1 O cluster não é apenas Ready/Not Ready

A UI deve calcular readiness por capacidade e resiliência. Um cluster single-node pode estar operacional sem estar altamente disponível.

| **Check**             | **Exemplo de avaliação**                                              |
|-----------------------|-----------------------------------------------------------------------|
| Swarm quorum          | 3 managers / 3 reachable -\> healthy.                                 |
| Manager topology      | Ímpar e \>=3 para HA.                                                 |
| Workers               | Capacidade suficiente para remanejar workloads após perda de um node. |
| Ingress               | \>=2 ou 3 ingress nodes saudáveis em LB.                              |
| Overlay network       | 7946/4789 reachability e MTU validado.                                |
| Registry              | Pull de digest testado a partir de worker.                            |
| Build capacity        | Builder disponível e não colocado em manager crítico.                 |
| Disk                  | Espaço para images/layers e thresholds de alerta.                     |
| Clock                 | Desvio dentro da tolerância.                                          |
| External dependencies | Platform DB, storage de backup e providers acessíveis.                |

## 14.2 Indicadores de UI

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Cluster: Production<br />
<br />
Operational YES<br />
Compute HA YES<br />
Ingress HA YES<br />
Manager Quorum 3/3<br />
Workers Healthy 6/6<br />
Ingress Healthy 3/3<br />
Builder Capacity 2<br />
Registry HEALTHY<br />
Network HEALTHY<br />
<br />
Overall readiness: PRODUCTION READY</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

# 15. Escala horizontal do cluster

## 15.1 Aumentar compute

Adicionar Worker é a operação de escala de infraestrutura mais simples. Depois que o novo node entra como Active e passa pelos checks, o scheduler já pode receber Tasks nele sem modificar os Services existentes.

## 15.2 Aumentar ingress

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Add ingress node<br />
|<br />
v<br />
Enroll as worker<br />
|<br />
v<br />
label platform.role.ingress=true<br />
|<br />
v<br />
Swarm global Traefik creates instance<br />
|<br />
v<br />
TLS/config sync health<br />
|<br />
v<br />
LoadBalancer.addTarget()<br />
|<br />
v<br />
Ingress HA capacity increased</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 15.3 Aumentar builders

Builders podem funcionar como pool elástico separado. Eles não aumentam capacidade de serving diretamente; aumentam throughput e isolamento de builds. O scheduler de builds da plataforma escolhe um builder saudável com capacidade disponível.

# 16. Remoção segura de node

## 16.1 Worker

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Request remove<br />
|<br />
v<br />
Mark DECOMMISSIONING<br />
|<br />
v<br />
Drain<br />
|<br />
v<br />
Wait Tasks = 0<br />
|<br />
v<br />
Remove special integrations<br />
(LB target / builder pool)<br />
|<br />
v<br />
Swarm node leave/remove<br />
|<br />
v<br />
Revoke enrollment/runtime metadata<br />
|<br />
v<br />
Provider delete (only if managed + confirmed)<br />
|<br />
v<br />
REMOVED</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 16.2 Manager

| **Bloqueio:** Nunca remover um Manager apenas porque a máquina não responde. A plataforma deve calcular o efeito no quorum e exigir demotion/replacement quando necessário. |
|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------|

- Verificar managers Reachable e quorum atual.

- Se necessário, adicionar/promover substituto primeiro.

- Demote do manager a Worker.

- Drain e remover como node normal.

- Atualizar backup/metadata do cluster depois da mudança de membership.

# 17. Segurança de provisionamento

## 17.1 Regras

- Bootstrap scripts devem ser obtidos somente por HTTPS e possuir versão explícita.

- Enrollment token curto, single-use, armazenado apenas como hash.

- Nunca colocar Swarm manager join token em histórico de shell/UI quando puder ser evitado.

- Credentials de cloud/DNS/LB/registry ficam no Vault e usam privilégio mínimo.

- Docker socket não é compartilhado com workloads de usuário.

- Builder executa código não confiável e deve ter isolamento/restrições próprias.

- Managers devem ser hosts estáveis; não usar nodes efêmeros como quorum por padrão.

- Firewall é deny-by-default para portas internas do Swarm.

- Toda operação de promote/demote/remove/force remove gera Audit Log.

## 17.2 SSH

SSH pode ser usado para bootstrap manual e break-glass, mas não precisa ser o protocolo permanente de gerenciamento da plataforma. Em instalações gerenciadas, recomenda-se chave pública, password login desabilitado e restrição por VPN/CIDR quando possível.

# 18. Modelo de dados

| **Entidade**       | **Campos centrais**                                                                                                                            |
|--------------------|------------------------------------------------------------------------------------------------------------------------------------------------|
| Cluster            | id, teamId, name, status, swarmId, networkProfileId, loadBalancerId, registryConnectionId, createdAt.                                          |
| Node               | id, clusterId, swarmNodeId, hostname, role, labels, availability, status, publicAddress, privateAddress, advertiseAddress, providerInstanceId. |
| EnrollmentToken    | id, clusterId, requestedRole, tokenHash, expiresAt, maxUses, createdBy, usedAt, status.                                                        |
| ProviderConnection | id, teamId, providerType, encryptedCredentialRef, capabilities, status.                                                                        |
| LoadBalancer       | id, clusterId, providerConnectionId, mode, publicAddress, status.                                                                              |
| LoadBalancerTarget | id, loadBalancerId, nodeId, address, port, healthStatus, registeredAt.                                                                         |
| DnsConnection      | id, teamId, providerConnectionId, zones, capabilities, status.                                                                                 |
| RegistryConnection | id, teamId, providerType, registryUrl, encryptedCredentialRef, status.                                                                         |
| NetworkProfile     | id, clusterId, advertiseCIDR, dataPathPort, overlayEncrypted, firewallPolicyVersion.                                                           |
| NodeOperation      | id, nodeId, type, requestedBy, status, startedAt, finishedAt, error.                                                                           |

# 19. APIs de produto

## 19.1 Cluster e nodes

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>POST /clusters<br />
GET /clusters/:id<br />
GET /clusters/:id/readiness<br />
<br />
POST /clusters/:id/enrollments<br />
DELETE /clusters/:id/enrollments/:enrollmentId<br />
<br />
GET /clusters/:id/nodes<br />
GET /nodes/:id<br />
POST /nodes/:id/drain<br />
POST /nodes/:id/activate<br />
POST /nodes/:id/promote<br />
POST /nodes/:id/demote<br />
DELETE /nodes/:id</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 19.2 Providers

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>POST /provider-connections<br />
GET /provider-connections<br />
<br />
POST /clusters/:id/provision-node<br />
POST /clusters/:id/load-balancer<br />
POST /clusters/:id/load-balancer/targets<br />
<br />
POST /dns-connections<br />
POST /registry-connections</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

# 20. UX principal

## 20.1 Cluster Overview

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Production Cluster<br />
<br />
Nodes 9<br />
Managers 3/3 healthy<br />
Workers 6/6 healthy<br />
Ingress 3/3 healthy<br />
Builders 2/2 healthy<br />
<br />
Public endpoint<br />
203.0.113.20<br />
<br />
Network HEALTHY<br />
Registry HEALTHY<br />
Compute HA ENABLED<br />
Ingress HA ENABLED<br />
<br />
[ Add Node ] [ Maintenance ] [ Settings ]</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 20.2 Add Node

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Add Node<br />
<br />
How do you want to add capacity?<br />
<br />
( ) Existing server<br />
( ) Cloud provider<br />
<br />
Role<br />
[x] Worker<br />
[ ] Ingress<br />
[ ] Builder<br />
[ ] Manager (privileged)<br />
<br />
Existing server result:<br />
curl -fsSL https://platform/install/node | sudo sh -s -- --token enr_...<br />
<br />
Expires in 14:32<br />
[ Revoke ]</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 20.3 Node Detail

- Status, role, availability, Swarm ID e hostname.

- Public/private/advertise addresses.

- CPU/RAM/disk e workloads atuais.

- Labels e placement eligibility.

- Ingress/LB target health quando aplicável.

- Docker Engine version e plataforma compatibility.

- Operations history: joined, drained, upgraded, promoted, removed.

- Ações protegidas: Drain, Maintenance, Promote/Demote, Remove.

# 21. Cenários de falha

| **Cenário**                         | **Resposta esperada**                                                                                   |
|-------------------------------------|---------------------------------------------------------------------------------------------------------|
| Enrollment expirou                  | Bootstrap falha fechado; usuário gera novo token.                                                       |
| Join token vazou                    | Rotacionar token do role; existing nodes permanecem no cluster.                                         |
| Worker morreu                       | Swarm recria Tasks em Workers Active com capacidade.                                                    |
| Ingress morreu                      | LB retira target; demais ingress continuam atendendo.                                                   |
| Manager morreu em 3-manager cluster | 2 managers mantêm quorum; substituir antes de nova falha.                                               |
| Perda de quorum                     | Workloads existentes podem continuar; bloquear mudanças e seguir runbook de recuperação.                |
| Registry inacessível                | Running Tasks continuam; novos pulls/deploys podem falhar; alertar e bloquear rollout inseguro.         |
| Private network degradada           | Marcar cluster DEGRADED; evitar alterações que dependam de overlay até a rede estabilizar.              |
| Builder comprometido                | Isolar/remove builder, revogar credentials temporárias, preservar audit/build metadata e reprovisionar. |
| LB provider indisponível            | Targets existentes podem continuar; bloquear mudanças de membership até estado poder ser reconciliado.  |

# 22. Ordem de implementação

1.  Bootstrap de primeiro node: Docker + swarm init + preflight.

2.  Cluster/Node model e leitura de docker node ls/inspect pela Engine API.

3.  EnrollmentToken + bootstrap de Worker existente.

4.  Node labels e roles lógicos: ingress/builder/workload.

5.  Drain/activate/remove com checks de segurança.

6.  Firewall/network readiness checks e diagnóstico.

7.  Ingress node lifecycle + integração manual de Load Balancer.

8.  LoadBalancerProvider abstraction.

9.  RegistryConnection e connectivity/pull test por node.

10. DNS Provider + Certificate Manager DNS-01 integration.

11. Provisionamento cloud via ProviderConnection.

12. Manager promote/demote assistido + quorum guardrails.

13. Cluster Readiness dashboard.

14. Node maintenance orchestration e upgrades sequenciais.

15. Multi-cluster remoto/federação somente após definir canal administrativo seguro.

# 23. Decisões consolidadas desta parte

- A plataforma é cluster-first; o primeiro node já executa Docker Swarm.

- Docker Service é a primitive de runtime desde o início.

- O primeiro cluster pode ser single-node sem ser marcado como HA.

- Workers são o default para adicionar capacidade.

- Ingress e Builder são Workers especializados por labels/placement.

- Produção HA usa 3 managers e múltiplos Workers/Ingress.

- Swarm internal ports só são expostas em rede confiável; 4789/UDP nunca deve ficar aberto indiscriminadamente na internet.

- Docker API não será aberta em 2375 para controle remoto.

- Enrollment próprio temporário esconde o join token real do Swarm.

- Não haverá Agent residente apenas para operar Docker no cluster local.

- Traefik roda nos ingress nodes; Load Balancer externo L4 distribui para eles.

- Registry é infraestrutura compartilhada entre builder e todos os Workers.

- Bring Your Own Server vem antes de automação específica por cloud provider.

- Cloud, LB, DNS e Registry entram por contracts/providers desacoplados.

- Node removal sempre tenta drain antes; manager removal é bloqueada se ameaçar quorum.

- Multi-cluster é permitido no modelo de produto, mas controle remoto de outro Swarm fica explicitamente fora desta fase.

| **Resultado:** Com esta parte, a plataforma passa a ter um modelo completo para nascer em uma máquina e crescer gradualmente para um cluster HA sem trocar o runtime, refazer Services ou alterar a experiência de deploy. |
|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|

# 24. Próxima parte sugerida

A Parte 7 pode consolidar o Control Plane interno: serviços do backend, filas/jobs, reconciliadores, eventos, state machine de operações, concorrência/idempotência, WebSockets/SSE, background workers e como a plataforma traduz o estado salvo no PostgreSQL em operações seguras na Docker Engine API.

# Referências técnicas verificadas

- Docker Docs - Swarm tutorial / required ports: https://docs.docker.com/engine/swarm/swarm-tutorial/

- Docker Docs - Run Docker Engine in swarm mode: https://docs.docker.com/engine/swarm/swarm-mode/

- Docker Docs - Join nodes to a swarm: https://docs.docker.com/engine/swarm/join-nodes/

- Docker Docs - docker swarm join-token: https://docs.docker.com/reference/cli/docker/swarm/join-token/

- Docker Docs - Drain a node: https://docs.docker.com/engine/swarm/swarm-tutorial/drain-node/

- Docker Docs - Administer and maintain a swarm: https://docs.docker.com/engine/swarm/admin_guide/

- Docker Docs - Manage nodes in a swarm: https://docs.docker.com/engine/swarm/manage-nodes/

- Docker Docs - Swarm ingress / external load balancer: https://docs.docker.com/engine/swarm/ingress/
