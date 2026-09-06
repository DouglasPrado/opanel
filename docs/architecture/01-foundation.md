---
document: "01"
title: "Fundamentos da Plataforma e Arquitetura Cluster-First"
type: "architecture"
status: "approved"
source: "docx"
---

**PLATAFORMA PAAS  
CLUSTER-FIRST**

**Documento técnico consolidado — Parte 1**

Fundamentos do produto, Docker/Swarm, alta disponibilidade, ingress, certificados, domínio de produto e Vault versionado de secrets

| **Status**    | Documento vivo — v0.1                                                        |
|---------------|------------------------------------------------------------------------------|
| **Data**      | 05 de setembro de 2026                                                       |
| **Escopo**    | Consolidar as decisões já tomadas e servir como base para implementação      |
| **Princípio** | Cluster por padrão; dados stateful gerenciados externamente na primeira fase |

**Resumo executivo**

A plataforma será um PaaS self-hosted, orientado a times e projetos, que abstrai Docker Swarm, deploy, ingress, TLS, secrets e alta disponibilidade. O produto nasce cluster-first: mesmo uma instalação com um único servidor é um Swarm de um node, e todos os workloads são modelados como Services, não como containers soltos. Na primeira fase, PostgreSQL, Redis e object storage das aplicações serão serviços externos gerenciados, mantendo o cluster de compute essencialmente stateless e simplificando a construção de HA real.

| Decisão central: a plataforma não tenta reinventar Docker, Swarm, Traefik ou BuildKit. Ela transforma primitives de infraestrutura em uma experiência de produto segura, versionada e operável. |
|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|

# 1. Visão do produto

O objetivo é construir uma plataforma no mesmo espaço de Easypanel/Coolify/Dokploy, porém com decisões próprias de produto desde a fundação: cluster como padrão, environments de primeira classe, Vault interno versionado, alta disponibilidade de ingress e um modelo explícito de segurança e recuperação.

## 1.1 O que o produto abstrai

- Provisionamento e ciclo de vida de aplicações executadas como Docker Swarm Services.

- Build de código-fonte para imagens OCI/Docker usando BuildKit/Buildx.

- Distribuição de imagens entre nodes por registry quando o cluster possuir múltiplos nodes.

- Roteamento HTTP/HTTPS, domínios, middlewares e balanceamento através de múltiplos Traefiks.

- Distribuição segura de secrets para workloads usando Docker Swarm Secrets.

- Organização multiusuário por Team → Project → Environment → Service.

- Deployments versionados, rolling update, rollback e promoção entre environments.

- Backup e recuperação do estado da própria plataforma e do cluster.

## 1.2 O que NÃO faz parte da primeira fase

- Operar PostgreSQL HA dentro do cluster.

- Operar Redis HA dentro do cluster.

- Fornecer storage distribuído próprio para dados de aplicações.

- Construir runtime OCI próprio, containerd customizado ou substituto de Docker.

- Substituir o scheduler do Swarm.

PostgreSQL, Redis e object storage das aplicações serão inicialmente consumidos como serviços gerenciados de terceiros. Isso reduz drasticamente o estado local do cluster e permite concentrar o projeto em compute, deploy, ingress, segurança e operação.

# 2. Princípios de arquitetura e produto

| **Princípio**       | **Decisão**                                                                                                |
|---------------------|------------------------------------------------------------------------------------------------------------|
| Cluster-first       | Toda instalação nasce como Docker Swarm. Um servidor é apenas um cluster de um node.                       |
| Service-first       | Aplicações são Docker Services. Containers são consequência do scheduler, não objeto primário da UX.       |
| Environment-first   | Production, homolog, dev e previews são entidades de produto, não convenções de nome.                      |
| Stateless compute   | Estado crítico das aplicações fica fora dos workers na primeira fase.                                      |
| Secrets versionadas | Environment/Service referencia uma versão imutável de uma Secret.                                          |
| HA sem mágica       | Alta disponibilidade só é declarada quando todos os SPOFs relevantes da camada controlada foram removidos. |
| Provider-agnostic   | LB, DNS e registry podem ser abstraídos para vários fornecedores.                                          |
| Recuperabilidade    | Recovery Key, backups e restore fazem parte do produto, não de documentação externa.                       |

# 3. Stack-base e responsabilidade de cada ferramenta

| **Componente**           | **Responsabilidade na plataforma**                                                                                             |
|--------------------------|--------------------------------------------------------------------------------------------------------------------------------|
| Docker Engine API        | Interface programática para images, networks, volumes, Swarm, services, tasks, nodes, secrets, configs, logs e stats.          |
| Docker Swarm             | Scheduler, desired state, replicas, rolling updates, rollback, cluster membership, overlay networking e distribuição de tasks. |
| Traefik                  | Ingress HTTP/HTTPS, descoberta de Services, host/path routing, middlewares e load balancing de workloads.                      |
| BuildKit / Buildx        | Transformar repositório + Dockerfile em imagem OCI/Docker com cache e builds eficientes.                                       |
| Registry OCI             | Disponibilizar a mesma imagem para qualquer node do cluster. Necessário na prática em clusters multi-node.                     |
| Git / GitHub             | Origem do código, commit SHA, branch e eventos de push para auto-deploy.                                                       |
| Load Balancer externo    | Distribuir conexões TCP 80/443 entre os ingress nodes/Traefiks e remover backends não saudáveis.                               |
| ACME / Let's Encrypt     | Emissão e renovação de certificados gerenciada centralmente pela plataforma.                                                   |
| PostgreSQL da plataforma | Persistir usuários, times, projetos, environments, deployments, bindings de secrets e estado de produto.                       |

## 3.1 Fluxo técnico resumido de deploy

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Git push<br />
↓<br />
Webhook / deploy manual<br />
↓<br />
Checkout do commit<br />
↓<br />
BuildKit / Buildx<br />
↓<br />
Imagem versionada por commit<br />
↓<br />
Registry (quando multi-node)<br />
↓<br />
Docker Swarm Service update<br />
↓<br />
Rolling update + health check<br />
↓<br />
Traefik descobre o Service<br />
↓<br />
Domínio continua atendendo sem troca manual de proxy</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

# 4. Cluster-first com Docker Swarm

A plataforma nunca terá um modo conceitual “standalone” diferente de “cluster”. O primeiro node inicializa o Swarm e torna-se Manager. Nodes adicionais entram no mesmo cluster através do mecanismo de join do Swarm.

## 4.1 Instalação mínima

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Cluster: principal<br />
└── node-01<br />
role: manager + worker<br />
status: ready</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

Nesse estágio ainda há pontos únicos de falha, mas a modelagem do produto e dos workloads já é a mesma que será usada em clusters maiores.

## 4.2 Instalação de produção com HA

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Managers<br />
├── manager-01<br />
├── manager-02<br />
└── manager-03<br />
<br />
Ingress<br />
├── ingress-01 → Traefik<br />
├── ingress-02 → Traefik<br />
└── ingress-03 → Traefik<br />
<br />
Workers<br />
├── worker-01<br />
├── worker-02<br />
├── worker-03<br />
└── ...</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

- Três managers permitem manter quorum com a perda de um manager.

- Workers recebem as Tasks das aplicações.

- Ingress nodes são workers especializados por label/placement e executam uma instância de Traefik cada.

- Managers podem ser drenados de workloads de aplicação quando o cluster tiver capacidade suficiente.

## 4.3 Service, Task e Container

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Service: api<br />
Desired replicas: 4<br />
Image: registry/app:sha-a81fc2<br />
<br />
Swarm Scheduler<br />
├── Task api.1 → container em worker-01<br />
├── Task api.2 → container em worker-02<br />
├── Task api.3 → container em worker-03<br />
└── Task api.4 → container em worker-01</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

A UX da plataforma trabalha com o Service. Task e Container são usados principalmente para diagnóstico, logs, status e observabilidade.

## 4.4 Falha de node

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Antes<br />
worker-01: api.1, api.4<br />
worker-02: api.2<br />
worker-03: api.3<br />
<br />
worker-01 falha<br />
↓<br />
Swarm detecta perda das Tasks<br />
↓<br />
recria api.1/api.4 em nodes elegíveis<br />
↓<br />
Desired = 4 / Running = 4</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

# 5. Modelo de produto: usuários, times, projetos e environments

## 5.1 Hierarquia de negócio

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>User<br />
↓ membership<br />
Team<br />
├── Projects<br />
│ └── Project<br />
│ └── Environments<br />
│ └── Services<br />
│<br />
└── Clusters<br />
└── Nodes</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

Project pertence ao domínio do negócio. Cluster pertence ao domínio da infraestrutura. Por isso, o Project não deve ficar hierarquicamente preso a um Cluster. Cada Environment referencia o Cluster onde deve ser executado.

## 5.2 Exemplo

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Team: Empresa X<br />
<br />
Clusters<br />
├── cluster-production<br />
└── cluster-nonprod<br />
<br />
Project: Albert<br />
├── production → cluster-production<br />
│ ├── api<br />
│ ├── web<br />
│ └── worker<br />
└── homolog → cluster-nonprod<br />
├── api<br />
├── web<br />
└── worker</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 5.3 Isolamento de environments

Cada Environment deve possuir sua própria overlay network, evitando comunicação acidental entre homologação e produção.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>network: albert-production<br />
├── albert-production-api<br />
├── albert-production-web<br />
└── albert-production-worker<br />
<br />
network: albert-homolog<br />
├── albert-homolog-api<br />
├── albert-homolog-web<br />
└── albert-homolog-worker</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 5.4 Entidades-base do banco

| **Entidade**           | **Responsabilidade**                                                               |
|------------------------|------------------------------------------------------------------------------------|
| User                   | Identidade de uma pessoa usuária.                                                  |
| Team                   | Tenant/organização e fronteira principal de ownership.                             |
| TeamMember             | Relaciona User e Team com role.                                                    |
| Cluster                | Agrupa nodes de um Swarm e sua configuração de infraestrutura.                     |
| Node                   | Representa manager/worker/ingress e estado observado.                              |
| Project                | Sistema/produto lógico.                                                            |
| Environment            | Instância do projeto: production, homolog, dev, preview etc.; aponta para Cluster. |
| Service                | Workload dentro do Environment.                                                    |
| Deployment             | Versão implantada de um Service, normalmente ligada a image digest/commit SHA.     |
| Domain                 | Hostname e binding com Service/porta/router.                                       |
| Secret / SecretVersion | Biblioteca central de secrets versionadas e imutáveis.                             |
| ServiceSecretBinding   | Liga uma key de runtime a uma versão específica de Secret.                         |

# 6. Ingress altamente disponível com múltiplos Traefiks

Traefik é o gateway HTTP/HTTPS. Em produção, uma única instância seria um SPOF. A plataforma deve executar uma instância por ingress node, preferencialmente como um Service global restrito por label.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Internet<br />
↓<br />
Load Balancer L4/TCP<br />
↓<br />
┌────────────┬────────────┬────────────┐<br />
│ │ │<br />
▼ ▼ ▼<br />
ingress-01 ingress-02 ingress-03<br />
Traefik A Traefik B Traefik C<br />
│ │ │<br />
└────────────┴──────┬─────┘<br />
↓<br />
Docker Swarm<br />
↓<br />
Application Services</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 6.1 Por que usar ingress nodes dedicados

- Permite controlar claramente quais máquinas recebem tráfego público.

- Facilita firewall, observabilidade e integração com Load Balancer externo.

- Permite publicar 80/443 em host mode, evitando uma camada adicional de routing mesh antes do Traefik.

- Scale-out do ingress passa a ser “adicionar node com label de ingress”.

## 6.2 Descoberta de rotas

Todos os Traefiks observam o mesmo Swarm e leem labels dos Services. Por isso, qualquer instância de Traefik pode encaminhar qualquer domínio configurado para qualquer Service elegível.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Service: albert-production-api<br />
labels:<br />
traefik.enable=true<br />
router rule = Host(`api.albert.com.br`)<br />
target port = 3000<br />
<br />
Traefik A/B/C<br />
↓<br />
mesma visão lógica de rotas</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

# 7. Integração com Load Balancer

O desenho preferido é um Load Balancer externo em camada 4 (TCP) distribuindo 80/443 entre ingress nodes. O TLS termina nos Traefiks. Isso mantém a gestão de certificados independente do provedor do Load Balancer.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>LB frontend<br />
├── TCP :80<br />
└── TCP :443<br />
<br />
Targets<br />
├── 10.0.0.11:80/443 ingress-01<br />
├── 10.0.0.12:80/443 ingress-02<br />
└── 10.0.0.13:80/443 ingress-03</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 7.1 Health checks

- Cada ingress expõe um endpoint de health da camada de proxy.

- O LB remove automaticamente um ingress unhealthy do pool.

- Ao adicionar um novo ingress, a plataforma aguarda Traefik healthy antes de registrá-lo no LB.

- Ao remover um ingress, primeiro drena/remove do LB e só então encerra o workload.

## 7.2 Abstração de provider

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>LoadBalancerProvider<br />
├── create()<br />
├── addTarget(node)<br />
├── removeTarget(node)<br />
├── health()<br />
└── delete()<br />
<br />
Implementações futuras:<br />
Hetzner / AWS / DigitalOcean / Cloudflare / Manual</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

# 8. Certificate Manager centralizado

Com múltiplos Traefiks, a emissão de certificados não deve depender de cada instância executando ACME de forma independente. A plataforma deve ter um Certificate Manager central que emite, versiona, renova e distribui certificados para todos os ingress nodes.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Domain criado<br />
↓<br />
Certificate Manager<br />
↓<br />
ACME challenge (preferência: DNS-01)<br />
↓<br />
Let's Encrypt<br />
↓<br />
CertificateVersion vN<br />
↓<br />
Distribuição para ingress-01/02/03<br />
↓<br />
Traefik file provider recarrega<br />
↓<br />
CertificateVersion = ACTIVE</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 8.1 Preferência por DNS-01

- A validação não depende de qual Traefik recebeu uma requisição HTTP.

- Facilita wildcard certificates quando desejado.

- Permite automatizar emissão via providers de DNS como Cloudflare/Route53.

## 8.2 Distribuição segura

A chave privada do certificado deve permanecer criptografada no armazenamento da plataforma. Durante a distribuição, somente o processo autorizado nos ingress nodes recebe o material necessário. Cada node confirma qual CertificateVersion está carregada.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>CertificateVersion v13<br />
├── ingress-01: loaded ✓<br />
├── ingress-02: loaded ✓<br />
└── ingress-03: loaded ✓<br />
<br />
Somente após confirmação:<br />
v13 → ACTIVE<br />
v12 → RETIRED (após janela de segurança)</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

# 9. Vault próprio de secrets versionadas

O Vault será uma funcionalidade nativa do produto. Não haverá dependência de OpenBao/Vault externo para o modelo principal. O objetivo é ter uma biblioteca central de secrets por Team, com versões imutáveis e bindings explícitos por Environment/Service.

## 9.1 Modelo conceitual

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Team Vault<br />
├── DATABASE_PASSWORD<br />
│ ├── v1<br />
│ ├── v2<br />
│ └── v3<br />
├── STRIPE_SECRET_KEY<br />
│ ├── v1<br />
│ └── v2<br />
└── JWT_SECRET<br />
└── v1</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 9.2 Secret e SecretVersion

| **Campo**     | **Secret**            | **SecretVersion**                                |
|---------------|-----------------------|--------------------------------------------------|
| Identidade    | Nome lógico da secret | Versão imutável                                  |
| Valor         | Não contém plaintext  | encryptedValue                                   |
| Versionamento | Possui N versões      | v1, v2, v3...                                    |
| Edição        | Metadados podem mudar | Nunca é editada; nova alteração cria nova versão |
| Auditoria     | Owner/descrição       | createdBy, createdAt, reason/hash opcional       |

## 9.3 Bindings por Service

O Environment define o contexto, mas a distribuição deve seguir least privilege: cada Service recebe somente as secrets de que precisa.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Albert / Production<br />
<br />
api<br />
├── DATABASE_PASSWORD → SecretVersion v7<br />
├── JWT_SECRET → SecretVersion v4<br />
└── STRIPE_KEY → SecretVersion v3<br />
<br />
worker<br />
├── DATABASE_PASSWORD → SecretVersion v7<br />
└── QUEUE_SECRET → SecretVersion v2<br />
<br />
web<br />
└── PUBLIC_API_URL → variável comum (não secret)</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 9.4 Pinned por padrão

Production deve sempre referenciar uma versão específica. Criar SecretVersion v8 não altera automaticamente o Service que usa v7. A atualização vira uma ação explícita e auditável.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>DATABASE_PASSWORD<br />
latest = v8<br />
<br />
Production API → pinned:v7<br />
Homolog API → pinned:v8<br />
<br />
Após validação:<br />
Promote v8 to Production</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

# 10. Segurança e distribuição das secrets

## 10.1 Não usar Env do Service para segredos sensíveis por padrão

Variáveis não sensíveis podem ser injetadas como environment variables normais. Secrets sensíveis devem, por padrão, ser materializadas como Docker Swarm Secrets, que são distribuídas apenas às Tasks dos Services autorizados.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Config normal<br />
PORT=3000<br />
NODE_ENV=production<br />
LOG_LEVEL=info<br />
↓<br />
Docker Service Env<br />
<br />
Secret sensível<br />
DATABASE_PASSWORD:v7<br />
↓<br />
Swarm Secret<br />
↓<br />
/run/secrets/DATABASE_PASSWORD</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 10.2 Compatibilidade com process.env

Muitas aplicações esperam process.env. A plataforma pode oferecer dois modos de injection: Secret file (recomendado) e Process environment (compatibilidade). Opcionalmente, um bootstrap/entrypoint controlado pela plataforma pode ler /run/secrets e exportar valores apenas para o processo filho imediatamente antes do exec da aplicação.

| **Modo**            | **Uso**                                                | **Segurança relativa**                       |
|---------------------|--------------------------------------------------------|----------------------------------------------|
| Secret file         | Aplicações que suportam \*\_FILE ou leitura de arquivo | Preferido                                    |
| Process environment | Aplicações que só suportam process.env                 | Compatibilidade; maior exposição operacional |

## 10.3 Fluxo completo

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>PostgreSQL da plataforma<br />
SecretVersion.encryptedValue<br />
↓<br />
Backend autorizado decripta somente durante operação<br />
↓<br />
Docker API cria/resolve Swarm Secret<br />
↓<br />
Swarm Manager<br />
↓ mTLS / distribuição do cluster<br />
Worker que executa a Task<br />
↓<br />
/run/secrets/...<br />
↓<br />
Aplicação</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

# 11. Criptografia do Vault e Recovery Key

A plataforma não deve expor a Master Encryption Key ao usuário. O usuário recebe uma Recovery Key, apresentada uma única vez, usada para recuperar/desbloquear a chave mestre por meio de envelope encryption.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Secret plaintext<br />
↓<br />
Master Encryption Key (MEK)<br />
↓<br />
SecretVersion.encryptedValue<br />
<br />
Recovery Key<br />
↓ deriva/wrapa<br />
Key Encryption Key (KEK)<br />
↓<br />
MEK protegida</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 11.1 Objetivos

- Backup do banco sozinho não revela secrets.

- Perder o banco não exige perder a capacidade de recuperar secrets, desde que backup + Recovery Key estejam disponíveis.

- Rotacionar Recovery Key não exige recriptografar todas as SecretVersions; rewrap da MEK é suficiente.

- A MEK nunca é exibida diretamente na UI.

## 11.2 UX de Recovery Key

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Security → Recovery<br />
<br />
Generate Recovery Key<br />
↓<br />
EXIBIR UMA ÚNICA VEZ<br />
↓<br />
Copy / Download TXT / Print<br />
↓<br />
Verify selected blocks<br />
↓<br />
✓ Recovery Key verified<br />
<br />
Depois:<br />
••••••••••••••<br />
[ Rotate Recovery Key ]</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

| Regra: a plataforma nunca deve registrar Recovery Key, MEK ou plaintext de secrets em logs, analytics, traces ou histórico de deployment. |
|-------------------------------------------------------------------------------------------------------------------------------------------|

# 12. O que significa HA real neste escopo

Como PostgreSQL, Redis e object storage das aplicações serão externos na primeira fase, o cluster pode permanecer stateless. Isso simplifica muito a alta disponibilidade de compute.

| **Camada**              | **Estratégia**                                       | **Status-alvo** |
|-------------------------|------------------------------------------------------|-----------------|
| Swarm control plane     | 3 Managers                                           | HA              |
| Compute                 | 2+ Workers e réplicas distribuídas                   | HA              |
| Ingress                 | 2–3+ ingress nodes com Traefik                       | HA              |
| Entrada pública         | Load Balancer redundante/provider-managed            | HA              |
| Aplicação               | Service com 2+ réplicas + health checks              | HA              |
| TLS                     | Certificate Manager recuperável + certs distribuídos | HA operacional  |
| PostgreSQL da aplicação | Terceiro gerenciado                                  | Delegado        |
| Redis da aplicação      | Terceiro gerenciado                                  | Delegado        |
| Object storage          | Terceiro gerenciado                                  | Delegado        |

## 12.1 O que a plataforma deve mostrar ao usuário

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Cluster Resilience<br />
<br />
Managers 3/3 ✓<br />
Ingress gateways 3/3 ✓<br />
Workers 6/6 ✓<br />
Load Balancer Healthy ✓<br />
Application replicas 12/12 ✓<br />
External data Connected ✓<br />
<br />
HA status: READY</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

A plataforma não deve declarar HA apenas porque existe “cluster”. O status deve ser derivado da redundância real dos componentes que ela controla.

# 13. Backups e snapshots no escopo atual

Como dados das aplicações serão inicialmente gerenciados externamente, o backup interno da plataforma concentra-se no que ela própria precisa recuperar.

| **Backup/Snapshot**      | **Conteúdo**                                                                                        |
|--------------------------|-----------------------------------------------------------------------------------------------------|
| Platform database backup | Users, Teams, Clusters, Projects, Environments, Services, Domains, Deployments e metadata de Vault. |
| Vault backup             | SecretVersions permanecem criptografadas; exige Recovery Key/MEK recuperável.                       |
| Swarm state backup       | Estado do cluster/manager necessário para disaster recovery do Swarm.                               |
| Deployment snapshot      | Imagem/digest, configurações, bindings, recursos e domínio de uma versão implantada.                |
| Environment snapshot     | Conjunto de Services, images, versions de secrets, domains e configurações de um Environment.       |
| External data backup     | Delegado inicialmente ao provider; integrações futuras podem exibir/acionar políticas.              |

## 13.1 Environment Snapshot

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Snapshot: Albert / Production / 2026-09-05 18:00<br />
<br />
api → image digest sha256:...<br />
web → image digest sha256:...<br />
worker → image digest sha256:...<br />
DB_PASS → SecretVersion v13<br />
JWT → SecretVersion v8<br />
domains → api.albert.com.br, app.albert.com.br<br />
resources → CPU/RAM/replicas<br />
cluster → production-cluster</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

Esse snapshot não copia automaticamente PostgreSQL/Redis externos. Ele congela o estado de infraestrutura e configuração controlado pela plataforma. Pode servir para rollback, auditoria ou criação de outro Environment.

# 14. Arquitetura-alvo consolidada — Parte 1

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>INTERNET<br />
│<br />
DNS / CDN opcional<br />
│<br />
▼<br />
L4 LOAD BALANCER<br />
│<br />
┌────────────────┼────────────────┐<br />
▼ ▼ ▼<br />
ingress-01 ingress-02 ingress-03<br />
Traefik A Traefik B Traefik C<br />
│ │ │<br />
└────────────────┼────────────────┘<br />
│<br />
DOCKER SWARM<br />
│<br />
┌────────────────────────┼────────────────────────┐<br />
│ │ │<br />
manager x3 workers xN overlay networks<br />
│<br />
Application Services / replicas<br />
│<br />
┌─────────────┼─────────────┐<br />
▼ ▼ ▼<br />
Managed Postgres Managed Redis Managed Object Storage<br />
<br />
PLATFORM SERVICES<br />
├── API / UI<br />
├── PostgreSQL da própria plataforma<br />
├── Vault versionado<br />
├── Certificate Manager<br />
├── Deployment / Build controller<br />
├── Docker Engine API integration<br />
└── Backup / recovery controller</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

# 15. Registro das decisões já fechadas

1.  Usar Docker Engine em vez de containerd/runc diretamente.

2.  Usar Docker Swarm desde a primeira instalação; não haverá migração posterior de containers para Services.

3.  Cluster é a unidade padrão; um cluster pode ter um único node.

4.  Projects e Clusters pertencem ao Team, e cada Environment aponta para o Cluster em que executa.

5.  Production/HML/Dev são Environments de primeira classe e possuem isolamento de rede.

6.  Utilizar Traefik como ingress/reverse proxy e executar múltiplas instâncias em produção.

7.  Usar Load Balancer externo em L4/TCP na frente dos Traefiks.

8.  Centralizar emissão/renovação de certificados em um Certificate Manager próprio, com preferência por ACME DNS-01.

9.  Criar Vault próprio de secrets; não usar OpenBao como dependência do modelo principal.

10. SecretVersion é imutável; ambientes/serviços apontam para versões específicas.

11. Secrets sensíveis são distribuídas aos workloads preferencialmente por Docker Swarm Secrets.

12. Usuário recebe Recovery Key; a Master Encryption Key não é apresentada diretamente.

13. PostgreSQL, Redis e object storage das aplicações serão terceirizados na primeira fase.

14. HA da camada de compute/ingress será responsabilidade da plataforma; HA dos dados será delegada aos providers inicialmente.

# 16. Próximas partes do documento

Este arquivo foi intencionalmente dividido. As próximas partes podem ser incorporadas ao mesmo documento em revisões subsequentes, sem recomeçar o material.

| **Parte**                             | **Conteúdo planejado**                                                                                                |
|---------------------------------------|-----------------------------------------------------------------------------------------------------------------------|
| Parte 2 — Deploy & Build              | Git/GitHub App, pipeline de deploy, BuildKit, registry, image digests, webhooks, rolling update, rollback, promotion. |
| Parte 3 — APIs & Modelo de dados      | Schema detalhado, invariantes, estados, RBAC, audit logs, contratos com Docker API e jobs assíncronos.                |
| Parte 4 — Observabilidade             | Logs, metrics, events, health checks, alertas, tracing e UX operacional.                                              |
| Parte 5 — Backup & DR                 | Backups da plataforma/Swarm, restore, Recovery Key, runbooks e testes automatizados de recuperação.                   |
| Parte 6 — Provisionamento & Providers | Onboarding de nodes, SSH/bootstrap, DNS providers, LB providers, registry providers e cloud provisioning.             |
| Parte 7 — Escalabilidade              | Autoscaling, placement, quotas, capacity planning, rate limiting, CDN e operação em alto tráfego.                     |

**Fim da Parte 1**

Documento vivo — as próximas partes devem preservar as decisões registradas acima, salvo mudança explícita de requisito.
