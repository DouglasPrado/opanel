---
document: "10"
title: "UX/UI e Casos de Uso"
type: "architecture"
status: "approved"
source: "docx"
---

**PLATAFORMA PAAS  
CLUSTER-FIRST**

**Documento técnico consolidado - Parte 10**

UX/UI completa, fluxos de produto e catálogo de casos de uso

## Resumo executivo

Esta parte especifica toda a experiência de uso da plataforma definida nas Partes 1 a 9. O foco deixa de ser infraestrutura interna e passa a ser como um usuário percebe, navega e opera o produto: onboarding, Teams, Clusters, Projects, Environments, Services, Deployments, Vault, Domains, Observability, Backups, Security e Administration.

A UI deve esconder Docker, Swarm, Traefik, BuildKit, Railpack, Raft, overlay networks e reconciliadores sem esconder o estado operacional. O usuário trabalha com conceitos do produto; detalhes de infraestrutura aparecem apenas onde agregam diagnóstico, controle ou segurança.

| **Objetivo:** este documento deve ser suficiente para desenhar os wireframes e implementar as rotas, estados, permissões, ações e feedbacks da interface sem redescobrir o comportamento do produto durante o desenvolvimento. |
|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|

| **Campo**    | **Definição**                                                                        |
|--------------|--------------------------------------------------------------------------------------|
| Escopo       | Aplicação web administrativa da plataforma.                                          |
| Orientação   | Desktop-first; responsiva para leitura e ações operacionais essenciais.              |
| Mental model | Team → Project → Environment → Service; Clusters ficam como infraestrutura paralela. |
| Princípio    | Progressive disclosure: simples por padrão, avançado quando necessário.              |
| Estado       | UI reflete desired state, actual state e operações em andamento.                     |
| Segurança    | Ação privilegiada é explícita, auditável e contextual.                               |

# 1. Princípios de UX

| **Princípio**                   | **Regra de interface**                                                                                          |
|---------------------------------|-----------------------------------------------------------------------------------------------------------------|
| Produto, não Docker             | Usuário cria Service, não “container”; scale altera réplicas; domínio publica Service.                          |
| Estado sempre visível           | Todo recurso relevante mostra Healthy/Degraded/Deploying/Failed/Paused e a causa resumida.                      |
| Ação assíncrona explícita       | Deploy, scale, restore, join e certificate issuance geram operação acompanhável; nenhum botão “parece travado”. |
| Segurança por contexto          | Production e ações destrutivas usam affordances mais fortes; secrets nunca aparecem inadvertidamente.           |
| Progressive disclosure          | Opções avançadas de placement, rollout, ports e health check não poluem o fluxo básico.                         |
| Reversibilidade                 | Rollback, restore e cancelamento são oferecidos quando tecnicamente possíveis.                                  |
| Navegação estável               | Team, Project e Environment permanecem visíveis no breadcrumb/context switcher.                                 |
| Sem falso sucesso               | Uma operação só aparece como concluída após confirmação do runtime, não apenas após persistência no banco.      |
| Diagnóstico próximo do problema | Falha de deploy mostra build/deployment events, logs relevantes e ação recomendada na mesma tela.               |
| Least privilege                 | A UI não mostra ações proibidas como se fossem disponíveis; permissões também são validadas no backend.         |

# 2. Atores e níveis de permissão

| **Ator**          | **Escopo típico**                  | **O que precisa ver**                                                                      |
|-------------------|------------------------------------|--------------------------------------------------------------------------------------------|
| TEAM_OWNER        | Governança completa do Team.       | Members, ownership, Projects, Vault, billing/quotas quando existir, Security e Audit.      |
| ADMIN             | Administração operacional do Team. | Projects, Environments, Services, Vault conforme policy, members sem transferir ownership. |
| DEVELOPER         | Entrega e operação de aplicações.  | Deploys, logs, metrics, envs/secrets autorizadas, domains e runtime.                       |
| VIEWER            | Leitura.                           | Status, dashboards, deployments e logs permitidos; nenhuma mutação.                        |
| INSTANCE_ADMIN    | Instalação inteira.                | Clusters, Nodes, Providers, recovery, readiness e configurações globais.                   |
| INSTANCE_OPERATOR | Operação da infraestrutura.        | Nodes, maintenance, alerts, cluster health sem poderes máximos de identidade/recovery.     |
| INSTANCE_AUDITOR  | Compliance/read-only.              | Audit Logs, security posture e histórico operacional.                                      |

# 3. Arquitetura de informação

## 3.1 Estrutura global

APP SHELL  
├── Team Switcher  
├── Global Search / Command Palette  
├── Notifications / Operations  
├── User Menu  
│  
├── Projects  
│ └── Project  
│ ├── Overview  
│ └── Environment  
│ ├── Overview  
│ ├── Services  
│ ├── Deployments  
│ ├── Domains  
│ ├── Variables & Secrets  
│ ├── Observability  
│ └── Snapshots  
│  
├── Vault  
├── Clusters  
│ └── Cluster  
│ ├── Overview  
│ ├── Nodes  
│ ├── Ingress  
│ ├── Builders  
│ ├── Networking  
│ └── Operations  
│  
├── Activity / Audit  
└── Settings  
├── Team  
├── Members  
├── Security  
├── Providers  
├── Backup / Recovery  
└── Instance (INSTANCE_ADMIN)

## 3.2 Rotas sugeridas

| **Área**      | **Rota lógica**                             |
|---------------|---------------------------------------------|
| Projects      | /t/:team/projects                           |
| Project       | /t/:team/projects/:project                  |
| Environment   | /t/:team/projects/:project/env/:environment |
| Service       | .../env/:environment/services/:service      |
| Vault         | /t/:team/vault                              |
| Clusters      | /t/:team/clusters                           |
| Cluster       | /t/:team/clusters/:cluster                  |
| Audit         | /t/:team/audit                              |
| Team Settings | /t/:team/settings/\*                        |
| Instance      | /instance/\*                                |

# 4. App Shell e navegação global

## 4.1 Header

| **Elemento**      | **Comportamento**                                                                   |
|-------------------|-------------------------------------------------------------------------------------|
| Team Switcher     | Troca contexto sem perder acesso rápido ao último Project de cada Team.             |
| Search / Cmd+K    | Busca Projects, Environments, Services, Domains, Deployments e Commands permitidos. |
| Operations Center | Mostra operações running/failed e permite abrir detalhes.                           |
| Notifications     | Alertas operacionais, convites, falhas e avisos de segurança.                       |
| User Menu         | Perfil, sessões, MFA, theme, sign out.                                              |

## 4.2 Sidebar

A sidebar é orientada a produto. “Projects” vem antes de “Clusters”. Infraestrutura aparece como área própria, não como pai de Project. Isto preserva a decisão de que Project pertence ao negócio e Environment aponta para um Cluster.

| **Item** | **Badge / estado**                                            |
|----------|---------------------------------------------------------------|
| Projects | Contagem opcional; sem badge permanente.                      |
| Vault    | Badge apenas para atenção: secrets outdated/rotation pending. |
| Clusters | Degraded/Unreachable count.                                   |
| Activity | Failed operations não reconhecidas.                           |
| Settings | Security/recovery warning quando necessário.                  |

# 5. Onboarding completo

## 5.1 Primeiro acesso / bootstrap

Create account  
↓  
Verify identity  
↓  
Create Team  
↓  
User becomes TEAM_OWNER + INSTANCE_ADMIN  
↓  
Initialize encryption  
↓  
Generate Recovery Key  
↓  
Verify Recovery Key  
↓  
Initialize first Swarm cluster  
↓  
Configure ingress / default domain  
↓  
Create first Project  
↓  
Deploy first Service

| **Etapa**     | **UI**                                                   | **Bloqueio**                                                 |
|---------------|----------------------------------------------------------|--------------------------------------------------------------|
| Conta         | Nome, email, senha/SSO futuro.                           | Email/MFA conforme policy.                                   |
| Team          | Nome e slug.                                             | Slug único.                                                  |
| Recovery      | Mostrar chave uma vez + download/copy/print + challenge. | Não concluir sem confirmação explícita.                      |
| Cluster       | Detectar/instalar ou inicializar Swarm.                  | Docker/portas/readiness.                                     |
| Ingress       | LB/DNS/default wildcard quando configurados.             | Pode ser “later” apenas se deploy sem domínio for permitido. |
| First Project | Nome + production environment.                           | Cluster READY.                                               |
| First Service | Git/Image + Railpack/Dockerfile + variables.             | Source/build válidos.                                        |

## 5.2 Checklist pós-onboarding

O dashboard inicial deve mostrar um checklist dismissible com segurança e produção, não um tutorial genérico.

> **•** Adicionar 3 Managers para HA quando cluster for Production crítico.
>
> **•** Adicionar 2+ Ingress nodes e Load Balancer.
>
> **•** Configurar DNS Provider.
>
> **•** Verificar Recovery Key.
>
> **•** Configurar backup externo da plataforma.
>
> **•** Convidar outro ADMIN.
>
> **•** Criar primeiro Environment de homologação.

# 6. Dashboard do Team

| **Bloco**          | **Conteúdo**                                                                                                  |
|--------------------|---------------------------------------------------------------------------------------------------------------|
| Health summary     | Projects healthy/degraded; clusters healthy/degraded; failed deployments; active incidents.                   |
| Recent deployments | Service, Environment, release/commit, actor, status, duration.                                                |
| Attention          | Certificates expiring, recovery not verified, cluster under-replicated, failed backup, secret update pending. |
| Projects           | Cards/list com prod status e último deployment.                                                               |
| Infrastructure     | Clusters resumidos; capacity e ingress health.                                                                |
| Activity           | Audit/operations relevantes, sem despejar logs técnicos.                                                      |

| **Regra:** o dashboard não vira “Grafana”. Ele responde: está tudo saudável? o que mudou? o que precisa de atenção? onde entro para agir? |
|-------------------------------------------------------------------------------------------------------------------------------------------|

# 7. Projects

## 7.1 Lista de Projects

| **Coluna / card** | **Conteúdo**                                     |
|-------------------|--------------------------------------------------|
| Name              | Nome + slug.                                     |
| Production status | Healthy/Degraded/No production env.              |
| Environments      | Prod/HML/Preview count.                          |
| Last deploy       | Tempo, actor e status.                           |
| Cluster           | Cluster do Environment principal.                |
| Attention         | Incidente, cert, secret update ou failed deploy. |

## 7.2 Criar Project

Fluxo curto: nome, slug e criação opcional do primeiro Environment. Não pedir build, Git ou domínio antes do Project existir.

| **Campo**                     | **Default**                            |
|-------------------------------|----------------------------------------|
| Name                          | Obrigatório.                           |
| Slug                          | Derivado, editável.                    |
| Create production environment | Ligado por padrão.                     |
| Cluster                       | Cluster default do Team ou seleção.    |
| Template                      | Blank inicialmente; templates futuros. |

## 7.3 Project Overview

PROJECT: Albert  
  
Production ● Healthy 8 services last deploy 18m  
Homolog ● Healthy 7 services last deploy 2h  
Preview PR-183 ● Ready 2 services expires 18h  
  
Recent releases  
Incidents  
Environment comparison  
\[ Create Environment \]

A tela do Project é principalmente um agregador de Environments. Configurações compartilhadas do Project, como Source defaults ou Vault scope, ficam em uma área secundária “Project Settings”.

# 8. Environments

## 8.1 Environment header

| **Elemento**         | **Comportamento**                                             |
|----------------------|---------------------------------------------------------------|
| Environment switcher | Production/HML/Dev/Preview.                                   |
| Type badge           | PRODUCTION recebe destaque visual persistente.                |
| Cluster              | Link para cluster onde executa.                               |
| Health               | Agregado dos Services + Domains + incidents.                  |
| Primary actions      | Deploy/promotion quando aplicável; Create Service.            |
| Danger context       | Ações destrutivas em Production exigem confirmação reforçada. |

## 8.2 Tabs do Environment

| **Tab**             | **Conteúdo**                                                           |
|---------------------|------------------------------------------------------------------------|
| Overview            | Health, services, traffic summary, last deploys, incidents, attention. |
| Services            | Lista/tabela de Services.                                              |
| Deployments         | Timeline consolidada.                                                  |
| Domains             | Domínios de todos os services.                                         |
| Variables & Secrets | Bindings e configurações compartilhadas.                               |
| Observability       | Métricas agregadas e alerts.                                           |
| Snapshots           | Environment snapshots / restore workflows.                             |
| Settings            | Cluster binding, type, lifecycle e danger zone.                        |

## 8.3 Environment compare

A UI pode comparar HML e PROD para detectar drift de release/config sem revelar values de secrets. Mostrar apenas versão/identidade da SecretVersion.

| **Comparar**   | **Exemplo**                       |
|----------------|-----------------------------------|
| Release        | HML sha256:A / PROD sha256:B      |
| Secret binding | DATABASE_URL v12 / v11            |
| Replicas       | 1 / 8                             |
| CPU/RAM        | 0.5/512M / 2/2G                   |
| Domain         | hml.example.com / api.example.com |

# 9. Services — visão geral

## 9.1 Lista de Services

| **Coluna**  | **Conteúdo**                              |
|-------------|-------------------------------------------|
| Service     | Nome + type/icon.                         |
| Status      | Healthy/Deploying/Degraded/Failed/Paused. |
| Release     | Short SHA + image digest abreviado.       |
| Replicas    | running / desired.                        |
| Resources   | CPU/RAM atual vs limite.                  |
| Domain      | Primary domain.                           |
| Last deploy | Tempo + actor.                            |
| Actions     | Deploy, restart, scale, overflow menu.    |

## 9.2 Service page

SERVICE: api ● Healthy  
Production / Albert 8 / 8 replicas  
  
Tabs  
Overview \| Deployments \| Runtime \| Logs \| Metrics \| Networking \| Variables & Secrets \| Settings  
  
Overview  
- Current release  
- Traffic + latency summary  
- Replicas / resources  
- Domains  
- Last deployment  
- Alerts / incidents  
- Quick actions

# 10. Service — criação e configuração

## 10.1 Create Service wizard

| **Step**          | **Campos**                                                                |
|-------------------|---------------------------------------------------------------------------|
| 1\. Source        | Git repository, Docker image; service name.                               |
| 2\. Build         | Automatic Railpack (default) ou Dockerfile; root dir; optional overrides. |
| 3\. Runtime       | Start command override, internal port, replicas, CPU/RAM.                 |
| 4\. Configuration | Variables + Vault secret bindings.                                        |
| 5\. Networking    | Optional domain; health check.                                            |
| 6\. Review        | Resumo + security warnings + Create & Deploy.                             |

| **Default saudável:** se Railpack detectar runtime/port/start command com confiança, o wizard preenche e reduz perguntas. O usuário pode revisar antes do primeiro deploy. |
|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------|

## 10.2 Service Settings

| **Seção**   | **Campos**                                         |
|-------------|----------------------------------------------------|
| General     | Name, description, service lineage.                |
| Source      | Repo, branch, root dir, auto-deploy.               |
| Build       | Railpack/Dockerfile, build vars, cache controls.   |
| Runtime     | Command, args, replicas, restart/update policy.    |
| Resources   | CPU/RAM reservations and limits.                   |
| Health      | HTTP/TCP/command health check, intervals/timeouts. |
| Placement   | Advanced constraints/preferences.                  |
| Danger Zone | Pause, archive/delete service.                     |

# 11. Deployments e Builds

## 11.1 Deployment list

| **Campo**   | **Visual**                                                      |
|-------------|-----------------------------------------------------------------|
| Status      | Queued/Building/Deploying/Verifying/Healthy/Failed/Rolled back. |
| Source      | Branch + short commit.                                          |
| Artifact    | Digest abreviado.                                               |
| Actor       | User/Webhook/System.                                            |
| Timing      | Created, duration.                                              |
| Environment | Prod/HML.                                                       |
| Actions     | Open, rollback quando elegível, cancel quando seguro.           |

## 11.2 Deployment detail

DEPLOYMENT \#1842  
  
✓ Source resolved 2s  
✓ Railpack plan 1s  
✓ BuildKit build 48s  
✓ Artifact pushed 5s  
✓ Swarm rollout 12s  
✓ Health verification 8s  
  
Release: sha256:abc...  
Commit: a81fc2  
Actor: GitHub webhook  
  
\[ View build logs \] \[ View runtime events \] \[ Rollback \]

Build logs e runtime events são separados visualmente. Falha em build não deve parecer falha de container; falha no rollout não deve obrigar o usuário a vasculhar o log completo do build.

## 11.3 Promotion HML → Production

A promoção sempre referencia uma Release já construída por digest. A UI deve deixar claro que não haverá rebuild.

Promote release  
  
From: Albert / Homolog  
Release: a81fc2 · sha256:abc...  
  
To: Albert / Production  
Current: 91bc44 · sha256:def...  
  
Configuration differences  
- Replicas: 1 → keep Production value 8  
- DATABASE_URL: HML v12 → keep Production v9  
  
\[ Promote same artifact \]

# 12. Runtime e scaling

## 12.1 Runtime tab

| **Bloco**       | **Conteúdo**                                                 |
|-----------------|--------------------------------------------------------------|
| Replica summary | Desired, running, healthy, updating.                         |
| Tasks           | Task ID, node, status, release, startedAt, restarts.         |
| Resources       | CPU/RAM per task e aggregated.                               |
| Placement       | Node distribution e constraints.                             |
| Actions         | Restart service, restart task opcional, scale, pause/resume. |

## 12.2 Scale dialog

Mostrar capacidade e impacto, não apenas um input de número.

Scale api  
  
Current replicas: 8  
New replicas: \[ 12 \]  
  
Estimated cluster headroom after scale  
CPU 46% used  
Memory 61% used  
  
\[ Cancel \] \[ Scale to 12 \]

## 12.3 Autoscaling UI

| **Campo**        | **Exemplo**                          |
|------------------|--------------------------------------|
| Enabled          | On/Off.                              |
| Min / Max        | 3 / 30.                              |
| Signal           | CPU, memory, custom metric futuro.   |
| Scale out        | CPU \> 70% for 2m.                   |
| Scale in         | CPU \< 30% for 10m.                  |
| Cooldown         | Evita oscilação.                     |
| Recent decisions | Timeline explicando por que escalou. |

# 13. Logs e terminal

## 13.1 Logs

| **Controle** | **Comportamento**                                                  |
|--------------|--------------------------------------------------------------------|
| Scope        | Service / task / deployment.                                       |
| Follow       | Live stream.                                                       |
| Time range   | Histórico quando backend suporta.                                  |
| Search       | Texto/regex futuro.                                                |
| Level        | Filtragem quando estruturado.                                      |
| Download     | Export limitado por time range e permissão.                        |
| Redaction    | Secrets conhecidos e padrões sensíveis mascarados quando possível. |

## 13.2 Terminal / Exec

| **Segurança:** terminal é uma ação privilegiada e auditada. A UI exige selecionar uma Task específica; nunca oferece shell no host a partir da tela de Service. |
|-----------------------------------------------------------------------------------------------------------------------------------------------------------------|

| **Elemento**  | **Regra**                                                               |
|---------------|-------------------------------------------------------------------------|
| Task selector | Somente tasks running.                                                  |
| Shell         | /bin/sh default; fallback conhecido.                                    |
| Banner        | Environment e Production warning persistentes.                          |
| Session       | Tempo de início, actor e task registrados.                              |
| Close         | Sessão termina no backend e não permanece reconectável silenciosamente. |

# 14. Networking e Domains

## 14.1 Networking tab do Service

| **Seção**       | **Conteúdo**                                               |
|-----------------|------------------------------------------------------------|
| Internal        | Overlay network, service DNS name, ports internos.         |
| Public exposure | Domains ligados ao Service.                                |
| Protocol        | HTTP/HTTPS; TCP futuro.                                    |
| Ingress         | Gateway/cluster status.                                    |
| Advanced        | Sticky session, forwarded headers, middlewares permitidos. |

## 14.2 Add Domain

Add domain  
  
Hostname api.example.com  
Target port 3000  
HTTPS ✓ Automatic  
Redirect HTTP ✓  
  
DNS status Waiting for DNS  
Certificate Will be issued after validation  
  
\[ Add domain \]

## 14.3 Domain detail

| **Bloco** | **Exemplo**                                         |
|-----------|-----------------------------------------------------|
| Routing   | api.example.com → Albert / Production / api :3000.  |
| DNS       | Resolved to public LB / mismatch / pending.         |
| TLS       | Certificate active; issuer; expires; renewal state. |
| Ingress   | 3/3 gateways serving current cert version.          |
| Traffic   | Requests/error summary optional.                    |
| Actions   | Retry validation, rotate/renew, remove domain.      |

# 15. Vault e Variables & Secrets

## 15.1 Vault list

| **Coluna**     | **Conteúdo**                                             |
|----------------|----------------------------------------------------------|
| Secret         | Canonical name.                                          |
| Scope          | Team/Project.                                            |
| Versions       | Count + latest.                                          |
| Used by        | Services/Environments count.                             |
| Latest version | v12, created time.                                       |
| Attention      | New version not promoted / unused / rotation due futuro. |

## 15.2 Secret detail

DATABASE_URL  
Project: Albert  
  
Versions  
v12 created Sep 05 Used by Homolog/API  
v11 created Aug 18 Used by Production/API  
v10 unused  
  
\[ Create new version \]  
  
Usage  
Production / api → v11  
Homolog / api → v12

Valores não aparecem na listagem. Reveal, se permitido, é uma ação explícita com reautenticação e audit. A UI trabalha majoritariamente com versões e bindings, não com plaintext.

## 15.3 Variables & Secrets do Service

| **Key**      | **Source**           | **Version / value** | **Injection** |
|--------------|----------------------|---------------------|---------------|
| NODE_ENV     | Plain variable       | production          | Environment   |
| LOG_LEVEL    | Plain variable       | info                | Environment   |
| DATABASE_URL | Vault / DATABASE_URL | v11                 | Swarm Secret  |
| JWT_SECRET   | Vault / JWT_SECRET   | v4                  | Swarm Secret  |

## 15.4 Atualizar binding

Ao existir uma nova SecretVersion, Production não muda automaticamente. A tela mostra “new version available” e oferece Update binding. HML pode usar policy automática se explicitamente configurada.

# 16. Clusters

## 16.1 Cluster list

| **Coluna** | **Conteúdo**                                  |
|------------|-----------------------------------------------|
| Cluster    | Name + region/provider label.                 |
| Status     | Ready/Degraded/Unreachable/Maintenance.       |
| Managers   | Ready / desired resilience.                   |
| Workers    | Ready / total.                                |
| Ingress    | Healthy gateways.                             |
| Capacity   | CPU/RAM headroom.                             |
| Projects   | Environments executando ali.                  |
| Attention  | Quorum, node down, cert distribution, backup. |

## 16.2 Cluster Overview

CLUSTER: production-br ● Ready  
  
Managers 3/3 Quorum safe  
Workers 6/6  
Ingress 3/3  
Builders 2/2  
  
CPU 42% used  
Memory 58% used  
  
Readiness  
✓ manager quorum  
✓ ingress HA  
✓ private network  
✓ backup current  
✓ recovery configured

## 16.3 Nodes

| **Coluna**   | **Conteúdo**                                |
|--------------|---------------------------------------------|
| Node         | Hostname + ID.                              |
| Role         | Manager/Worker + capabilities.              |
| Availability | Active/Drain/Pause.                         |
| Status       | Ready/Down.                                 |
| CPU/RAM      | Capacity e current usage.                   |
| Tasks        | Running workload count.                     |
| Labels       | environment, zone, ingress, builder.        |
| Actions      | Drain, maintenance, promote/demote, remove. |

## 16.4 Add Node

Add node  
  
Role Worker  
Capabilities \[ \] Ingress \[ \] Builder  
TTL 15 minutes  
  
\[ Generate enrollment command \]  
  
curl ... \| sh -s -- --token enr\_\*\*\*\*\*\*\*\*  
  
Expires in 14:52 · single use  
\[ Revoke \]

# 17. Cluster Maintenance

Entrar em maintenance/drain é um fluxo guiado. A UI lista impacto antes de executar.

Drain node worker-03  
  
Running tasks: 17  
Movable: 15  
Blocked: 2  
  
Blocked workloads  
- service-x requires node.label=zone-a  
- service-y has no remaining capacity  
  
\[ Cancel \] \[ Drain anyway disabled \]

| **Regra:** não esconder constraints que impedem evacuação. A UI deve explicar por que a operação está bloqueada e o que precisa mudar. |
|----------------------------------------------------------------------------------------------------------------------------------------|

# 18. Observability

## 18.1 Metrics

| **Nível**   | **Métricas**                                                             |
|-------------|--------------------------------------------------------------------------|
| Cluster     | CPU, RAM, node availability, ingress health.                             |
| Environment | requests, errors, aggregate CPU/RAM, deployments.                        |
| Service     | replicas, CPU/RAM, network, restarts, latency/traffic quando disponível. |
| Task        | CPU/RAM/restarts/node.                                                   |
| Ingress     | requests, 4xx/5xx, latency, gateways healthy.                            |

## 18.2 Alerts

| **Tela**            | **Comportamento**                            |
|---------------------|----------------------------------------------|
| Alert rules         | List/create/edit; scope e thresholds.        |
| Active alerts       | Severity, resource, openedAt, latest value.  |
| History             | Resolved alerts e duration.                  |
| Notification target | Email/webhook/Slack futuro sem acoplar core. |
| Mute                | Escopo e expiration obrigatórios; auditado.  |

## 18.3 Incidents

Incident é uma entidade operacional agregadora, não apenas um alerta. Pode agrupar deploy failed + error rate + node loss e receber notas/owner.

# 19. Backups, Snapshots e Recovery

## 19.1 Protection dashboard

| **Bloco**             | **Conteúdo**                                                            |
|-----------------------|-------------------------------------------------------------------------|
| Platform DB           | Last backup, verify status, retention.                                  |
| Vault                 | Backup/recovery envelope protected.                                     |
| Swarm state           | Last snapshot.                                                          |
| Certificates          | Protected/config state.                                                 |
| Environment snapshots | Recent snapshots.                                                       |
| Recovery readiness    | Recovery Key verified, restore drill age, external backup reachability. |

## 19.2 Environment Snapshot

Create snapshot  
  
Environment: Albert / Production  
Includes  
✓ Releases and runtime configuration  
✓ Secret version bindings (not plaintext)  
✓ Domains and certificate references  
✓ Service topology  
  
External managed database data is NOT included.  
  
\[ Create snapshot \]

## 19.3 Restore flow

Restore deve favorecer criação paralela/preview quando possível. A UI diferencia “restore configuration” de “restore managed external data”, que está fora do escopo atual.

# 20. Team, Members e Ownership

## 20.1 Members

| **Coluna**    | **Conteúdo**                                    |
|---------------|-------------------------------------------------|
| User          | Name/email.                                     |
| Role          | OWNER/ADMIN/DEVELOPER/VIEWER.                   |
| Status        | Active/Invited/Suspended.                       |
| Last activity | Opcional e privacy-aware.                       |
| Actions       | Change role, remove; OWNER tem ações especiais. |

## 20.2 Invite member

Owner/Admin escolhe email + role. Não é permitido convidar diretamente como OWNER. Ownership é sempre obtido via fluxo de transferência.

## 20.3 Transfer ownership

Transfer Team ownership  
  
Current owner: Douglas  
New owner: Helena (ADMIN)  
  
After transfer  
- Helena becomes OWNER  
- Douglas becomes ADMIN  
- This action is audited  
  
Re-enter password / MFA  
\[ Transfer ownership \]

| **Invariante:** a UI só lista ADMINs ativos como destino e a transação garante exatamente um OWNER ativo antes e depois da operação. |
|--------------------------------------------------------------------------------------------------------------------------------------|

# 21. Security e Recovery Key

## 21.1 Security dashboard

| **Item**        | **Estado**                              |
|-----------------|-----------------------------------------|
| MFA             | Configured / recommended / required.    |
| Recovery Key    | Verified / not verified / rotated date. |
| Active sessions | Devices/sessions.                       |
| API tokens      | Active count, last used.                |
| Secret reveals  | Recent sensitive events.                |
| Audit anomalies | Futuro; sem automação opaca no core.    |

## 21.2 Recovery Key

A chave é exibida apenas no momento de criação/rotação. Depois a UI mostra fingerprint/metadata, nunca o valor.

Recovery Key  
  
Status ✓ Verified  
Fingerprint RK-92AF…41C8  
Created Sep 05, 2026  
Last tested Sep 05, 2026  
  
\[ Rotate Recovery Key \] \[ Run recovery verification \]

# 22. Providers e Instance Administration

| **Área**                | **UI**                                                                             |
|-------------------------|------------------------------------------------------------------------------------|
| Load Balancer Providers | Credentials, regions/capabilities, targets sync status.                            |
| DNS Providers           | Connected zones, permissions test, DNS-01 support.                                 |
| Registry Providers      | Registry URL, credentials, push/pull test.                                         |
| Backup Storage          | S3-compatible endpoint, bucket, retention test.                                    |
| Cloud Providers         | Futuro: server provisioning capability.                                            |
| Instance                | Global domain, email, security policy, upgrades, feature flags quando necessários. |

| **Credential UX:** provider credentials são secrets do sistema. A UI exibe apenas metadata, last verified e rotate/reconnect actions. |
|---------------------------------------------------------------------------------------------------------------------------------------|

# 23. Audit Log e Activity

| **Filtro**          | **Exemplos**                                                                  |
|---------------------|-------------------------------------------------------------------------------|
| Actor               | User, webhook, system.                                                        |
| Action              | team.owner.transferred, service.scaled, secret.version.created, domain.added. |
| Resource            | Project/Environment/Service/Cluster/Secret.                                   |
| Time                | Range.                                                                        |
| Result              | Succeeded/Failed/Denied.                                                      |
| Request / Operation | Correlation IDs para troubleshooting.                                         |

Detalhe do evento mostra metadata sanitizada e links para recursos/operation. Nunca mostra secret plaintext, provider credentials ou recovery key.

# 24. Operations Center e notificações

## 24.1 Operations Center

| **Estado** | **Exibição**                                                              |
|------------|---------------------------------------------------------------------------|
| Running    | Progress/stage, resource, startedAt, cancel quando permitido.             |
| Failed     | Erro resumido, retry action quando segura, link para logs/events.         |
| Blocked    | Dependência/lock/reconciliation reason.                                   |
| Succeeded  | Mantido por período curto na lista rápida; histórico no recurso/activity. |

## 24.2 Toasts vs persistent notifications

| **Tipo**                | **Uso**                                                                            |
|-------------------------|------------------------------------------------------------------------------------|
| Toast                   | Ação imediata aceita: “Scale requested”. Não usar para resultado assíncrono final. |
| Operation badge         | Processo em andamento.                                                             |
| Persistent notification | Falha, security warning, certificate/backup issue.                                 |
| Inline banner           | Problema contextual naquela tela.                                                  |
| Incident                | Problema operacional agregado de maior duração.                                    |

# 25. Estados universais de UI

| **Estado**                          | **Regra**                                                                    |
|-------------------------------------|------------------------------------------------------------------------------|
| Loading                             | Skeleton da estrutura; não spinner de página inteira salvo bootstrap.        |
| Empty                               | Explicar valor + CTA contextual.                                             |
| No permission                       | Explicar restrição sem vazar dados.                                          |
| Offline / Control Plane unreachable | Preservar última leitura com timestamp quando possível; mutações bloqueadas. |
| Stale actual state                  | Badge “last observed …”; não declarar Healthy sem observação recente.        |
| Operation running                   | Ação principal disabled/replaced conforme conflito.                          |
| Partial failure                     | Mostrar subcomponentes: 7/8 replicas healthy em vez de apenas “failed”.      |
| Deleted / archived                  | Read-only durante retenção quando aplicável.                                 |

# 26. Ações destrutivas e confirmações

| **Ação**            | **Confirmação**                                              |
|---------------------|--------------------------------------------------------------|
| Delete Service      | Nome do Service; impacto e volumes/config refs.              |
| Delete Environment  | Digitar nome; listar Services/Domains; snapshot recomendado. |
| Remove Node         | Exigir DRAIN/evacuation quando possível; informar quorum.    |
| Demote Manager      | Bloquear se comprometer quorum.                              |
| Delete Secret       | Bloquear se bindings ativos; version lifecycle separado.     |
| Rotate Recovery Key | Reauth + confirmação de nova key salva.                      |
| Transfer Owner      | Reauth/MFA + destino ADMIN.                                  |
| Restore             | Mostrar alvo, snapshot e efeitos no desired state.           |

# 27. Command Palette / busca global

O Command Palette acelera operação sem substituir navegação. Todos os resultados respeitam tenancy e RBAC.

Cmd+K  
  
Search  
\> albert api  
  
Albert / Production / api Service  
api.albert.com.br Domain  
Deployment \#1842 Deployment  
  
Commands  
Restart api  
Open logs  
Scale api…

# 28. Responsividade e acessibilidade

| **Tema**      | **Regra**                                                                                                                |
|---------------|--------------------------------------------------------------------------------------------------------------------------|
| Desktop-first | Operações densas, logs e metrics assumem desktop.                                                                        |
| Mobile        | Status, acknowledge alert, view logs resumidos e emergency restart podem funcionar; config avançada pode exigir desktop. |
| Keyboard      | Navegação de tabs, command palette, dialogs e tables acessíveis.                                                         |
| Color         | Status nunca depende só de cor; usar icon + label.                                                                       |
| Focus         | Dialogs preservam focus e retornam ao trigger.                                                                           |
| Tables        | Headers semânticos e alternativa responsiva quando necessário.                                                           |
| Secrets       | Não copiar automaticamente para clipboard; confirmação visual após copy.                                                 |
| Time          | Mostrar timezone do usuário e opção de UTC em logs/events.                                                               |

# 29. Inventário consolidado de telas

| **Grupo**     | **Telas**                                                                                          |
|---------------|----------------------------------------------------------------------------------------------------|
| Auth          | Sign in, Sign up, Verify email, MFA challenge, Forgot/reset password.                              |
| Bootstrap     | Create Team, Recovery Key, Initialize Cluster, Ingress setup, First Project.                       |
| Team          | Dashboard, Projects list, Project overview.                                                        |
| Environment   | Overview, Services, Deployments, Domains, Variables & Secrets, Observability, Snapshots, Settings. |
| Service       | Overview, Deployments, Runtime, Logs, Metrics, Networking, Variables & Secrets, Settings.          |
| Deploy        | Create Service wizard, Deployment detail, Build logs, Promotion, Rollback.                         |
| Vault         | Secret list, Secret detail, Create version, Binding dialog, Reveal dialog.                         |
| Cluster       | List, Overview, Nodes, Node detail, Add node, Ingress, Networking, Operations, Maintenance.        |
| Observability | Alerts, Alert detail, Incidents, Incident detail.                                                  |
| Protection    | Protection dashboard, backup policies, snapshots, restore, recovery verification.                  |
| Team Settings | General, Members, Ownership, Security, API tokens, Audit.                                          |
| Instance      | Clusters global, Providers, Backup/Recovery, Instance security/settings.                           |
| Global        | Operations Center, Notifications, Command Palette, User profile/sessions.                          |

# 30. Catálogo de casos de uso

| **ID** | **Caso de uso**                      | **Ator**                      |
|--------|--------------------------------------|-------------------------------|
| UC-001 | Criar conta e primeiro Team          | New user                      |
| UC-002 | Gerar e verificar Recovery Key       | OWNER/INSTANCE_ADMIN          |
| UC-003 | Inicializar primeiro cluster Swarm   | INSTANCE_ADMIN                |
| UC-004 | Adicionar Worker ao cluster          | INSTANCE_ADMIN/OPERATOR       |
| UC-005 | Adicionar Ingress node               | INSTANCE_ADMIN/OPERATOR       |
| UC-006 | Colocar node em Drain                | INSTANCE_ADMIN/OPERATOR       |
| UC-007 | Promover Worker a Manager            | INSTANCE_ADMIN                |
| UC-008 | Remover node com segurança           | INSTANCE_ADMIN                |
| UC-009 | Criar Project                        | OWNER/ADMIN                   |
| UC-010 | Criar Environment                    | OWNER/ADMIN                   |
| UC-011 | Mover Environment para outro Cluster | OWNER/ADMIN + instance policy |
| UC-012 | Criar Service via Git + Railpack     | ADMIN/DEVELOPER               |
| UC-013 | Criar Service via Docker image       | ADMIN/DEVELOPER               |
| UC-014 | Configurar recursos/healthcheck      | ADMIN/DEVELOPER               |
| UC-015 | Fazer deploy manual                  | ADMIN/DEVELOPER               |
| UC-016 | Auto-deploy por webhook              | System                        |
| UC-017 | Cancelar deployment                  | ADMIN/DEVELOPER               |
| UC-018 | Rollback para release anterior       | ADMIN/DEVELOPER               |
| UC-019 | Promover HML para Production         | ADMIN/DEVELOPER               |
| UC-020 | Escalar manualmente                  | ADMIN/DEVELOPER               |
| UC-021 | Configurar autoscaling               | ADMIN                         |
| UC-022 | Restart Service                      | ADMIN/DEVELOPER               |
| UC-023 | Abrir terminal em Task               | ADMIN/DEVELOPER privileged    |
| UC-024 | Adicionar domínio customizado        | ADMIN/DEVELOPER               |
| UC-025 | Validar DNS e emitir certificado     | System                        |
| UC-026 | Renovar e distribuir certificado     | System                        |
| UC-027 | Remover domínio                      | ADMIN/DEVELOPER               |
| UC-028 | Criar Secret                         | OWNER/ADMIN                   |
| UC-029 | Criar nova SecretVersion             | OWNER/ADMIN                   |
| UC-030 | Bind SecretVersion a Service         | ADMIN/DEVELOPER permitted     |
| UC-031 | Promover SecretVersion HML→PROD      | ADMIN                         |
| UC-032 | Reveal secret                        | OWNER/ADMIN with permission   |
| UC-033 | Consultar logs                       | DEVELOPER/VIEWER              |
| UC-034 | Consultar métricas                   | DEVELOPER/VIEWER              |
| UC-035 | Criar Alert Rule                     | ADMIN/DEVELOPER               |
| UC-036 | Acknowledge/resolve Incident         | ADMIN/OPERATOR                |
| UC-037 | Criar Environment Snapshot           | ADMIN                         |
| UC-038 | Restaurar Snapshot                   | ADMIN                         |
| UC-039 | Executar backup da plataforma        | INSTANCE_ADMIN/System         |
| UC-040 | Executar recovery verification       | OWNER/INSTANCE_ADMIN          |
| UC-041 | Convidar membro                      | OWNER/ADMIN                   |
| UC-042 | Alterar role de membro               | OWNER/ADMIN                   |
| UC-043 | Transferir ownership                 | OWNER                         |
| UC-044 | Remover membro                       | OWNER/ADMIN                   |
| UC-045 | Criar/revogar API token              | User/Admin per scope          |
| UC-046 | Consultar Audit Log                  | OWNER/ADMIN/AUDITOR           |
| UC-047 | Configurar DNS Provider              | INSTANCE_ADMIN                |
| UC-048 | Configurar LB Provider               | INSTANCE_ADMIN                |
| UC-049 | Configurar Registry Provider         | INSTANCE_ADMIN                |
| UC-050 | Configurar Backup Storage            | INSTANCE_ADMIN                |

# 31. Casos de uso detalhados — onboarding e cluster

### UC-001 — Criar conta e primeiro Team

| **Campo**          | **Definição**                                                |
|--------------------|--------------------------------------------------------------|
| Ator principal     | Novo usuário                                                 |
| Permissão          | Público                                                      |
| Pré-condições      | Instalação bootstrap disponível; email ainda não cadastrado. |
| Gatilho            | Usuário inicia cadastro.                                     |
| Resultado esperado | Usuário autenticado; Team com exatamente um OWNER.           |

**Fluxo principal**

> **1.** Preenche identidade e credencial.
>
> **2.** Confirma email/MFA conforme policy.
>
> **3.** Informa nome e slug do Team.
>
> **4.** Sistema cria User, Team e TeamMember OWNER em uma única operação consistente.
>
> **5.** Se for primeiro bootstrap da instalação, atribui INSTANCE_ADMIN conforme regra da instância.
>
> **6.** Redireciona para configuração de Recovery Key.

**Alternativas / falhas**

> **•** Email já existente → oferecer sign in/recovery.
>
> **•** Slug ocupado → sugerir alternativas sem perder dados preenchidos.

### UC-002 — Gerar e verificar Recovery Key

| **Campo**          | **Definição**                                                |
|--------------------|--------------------------------------------------------------|
| Ator principal     | TEAM_OWNER / INSTANCE_ADMIN                                  |
| Permissão          | security.recovery.manage                                     |
| Pré-condições      | Team criado; encryption envelope inicializável.              |
| Gatilho            | Onboarding ou Security → Recovery.                           |
| Resultado esperado | Recovery Key verificada sem persistir plaintext recuperável. |

**Fluxo principal**

> **1.** Sistema gera material de recuperação e exibe a Recovery Key uma única vez.
>
> **2.** UI oferece copy/download/print.
>
> **3.** Usuário confirma que salvou.
>
> **4.** Sistema solicita challenge com blocos/trechos da chave.
>
> **5.** Após validação, marca recoveryVerifiedAt e mostra apenas fingerprint/metadata.

**Alternativas / falhas**

> **•** Usuário fecha modal antes da verificação → onboarding permanece incompleto e uma nova key pode ser regenerada invalidando a anterior.
>
> **•** Challenge falha → não marcar verified.

### UC-003 — Inicializar primeiro cluster Swarm

| **Campo**          | **Definição**                                 |
|--------------------|-----------------------------------------------|
| Ator principal     | INSTANCE_ADMIN                                |
| Permissão          | cluster.bootstrap                             |
| Pré-condições      | Docker host compatível; usuário no bootstrap. |
| Gatilho            | Usuário escolhe Initialize Cluster.           |
| Resultado esperado | Primeiro Cluster registrado e operável.       |

**Fluxo principal**

> **1.** Control Plane executa readiness checks.
>
> **2.** Exibe interfaces/IPs detectados e sugere advertise address confiável.
>
> **3.** Usuário confirma.
>
> **4.** Inicializa Swarm e registra swarmId.
>
> **5.** Cria/valida networks base e infraestrutura necessária.
>
> **6.** Cluster entra em READY ou DEGRADED com diagnóstico.

**Alternativas / falhas**

> **•** Swarm já existe → detectar/adotar somente se compatível e autorizado.
>
> **•** Portas/rede inválidas → bloquear e mostrar checks específicos.

### UC-004 — Adicionar Worker ao cluster

| **Campo**          | **Definição**                                   |
|--------------------|-------------------------------------------------|
| Ator principal     | INSTANCE_ADMIN / INSTANCE_OPERATOR              |
| Permissão          | cluster.node.enroll                             |
| Pré-condições      | Cluster READY; conectividade privada planejada. |
| Gatilho            | Cluster → Nodes → Add Node.                     |
| Resultado esperado | Worker conectado sem Docker API pública.        |

**Fluxo principal**

> **1.** Usuário escolhe Worker e capabilities opcionais.
>
> **2.** Sistema gera Enrollment Token single-use com TTL curto.
>
> **3.** UI mostra bootstrap command.
>
> **4.** Novo host executa script; token é validado.
>
> **5.** Docker é validado/instalado conforme política e host entra no Swarm.
>
> **6.** Control Plane observa novo Node e marca READY.
>
> **7.** Token é consumido e não pode ser reutilizado.

**Alternativas / falhas**

> **•** Token expirado/revogado → bootstrap aborta antes de join.
>
> **•** Node entra no Swarm mas não completa readiness → DEGRADED com remediation.

### UC-006 — Colocar node em Drain

| **Campo**          | **Definição**                                      |
|--------------------|----------------------------------------------------|
| Ator principal     | INSTANCE_OPERATOR                                  |
| Permissão          | cluster.node.maintain                              |
| Pré-condições      | Node READY; cluster alcançável.                    |
| Gatilho            | Node → Drain.                                      |
| Resultado esperado | Node em DRAIN sem perda não planejada de workload. |

**Fluxo principal**

> **1.** Sistema calcula tasks, constraints, quorum e capacity impact.
>
> **2.** UI mostra workloads movíveis e bloqueados.
>
> **3.** Se seguro, usuário confirma.
>
> **4.** Control Plane altera availability para DRAIN.
>
> **5.** Swarm reprograma workloads.
>
> **6.** UI acompanha evacuation até zero tasks elegíveis ou estado bloqueado.

**Alternativas / falhas**

> **•** Manager crítico → bloquear se quorum ficaria inseguro.
>
> **•** Placement/capacity bloqueia tasks → mostrar quais Services precisam ação.

# 32. Casos de uso detalhados — Projects, Environments e Services

### UC-009 — Criar Project

| **Campo**          | **Definição**                         |
|--------------------|---------------------------------------|
| Ator principal     | OWNER / ADMIN                         |
| Permissão          | project.create                        |
| Pré-condições      | Team ativo.                           |
| Gatilho            | Projects → Create Project.            |
| Resultado esperado | Project criado com ownership do Team. |

**Fluxo principal**

> **1.** Usuário informa name/slug.
>
> **2.** Opcionalmente escolhe criar Production Environment.
>
> **3.** Se criar Environment, escolhe Cluster.
>
> **4.** Sistema persiste Project e Environment desejados.
>
> **5.** Reconciler cria network do Environment quando necessário.
>
> **6.** UI abre Project Overview.

**Alternativas / falhas**

> **•** Slug duplicado → validação inline.
>
> **•** Cluster unavailable → permitir Project sem Environment ou escolher outro cluster.

### UC-010 — Criar Environment

| **Campo**          | **Definição**                   |
|--------------------|---------------------------------|
| Ator principal     | OWNER / ADMIN                   |
| Permissão          | environment.create              |
| Pré-condições      | Project ativo; Cluster READY.   |
| Gatilho            | Project → Create Environment.   |
| Resultado esperado | Environment isolado disponível. |

**Fluxo principal**

> **1.** Escolhe nome, type e Cluster.
>
> **2.** Sistema valida slug e permissions.
>
> **3.** Cria Environment em PROVISIONING.
>
> **4.** Network reconciler cria overlay network isolada.
>
> **5.** Environment vira READY.
>
> **6.** UI oferece Create Service ou clone configuration de outro Environment.

**Alternativas / falhas**

> **•** Cluster degraded → warning/bloqueio conforme policy.
>
> **•** Falha ao criar network → Environment DEGRADED com Retry.

### UC-012 — Criar Service via Git + Railpack

| **Campo**          | **Definição**                                    |
|--------------------|--------------------------------------------------|
| Ator principal     | ADMIN / DEVELOPER                                |
| Permissão          | service.create + deploy.create                   |
| Pré-condições      | Environment READY; Source connection autorizada. |
| Gatilho            | Environment → Create Service.                    |
| Resultado esperado | Service criado e release saudável executando.    |

**Fluxo principal**

> **1.** Escolhe repository/branch/root directory.
>
> **2.** Builder default é Automatic (Railpack).
>
> **3.** Railpack detection preenche runtime/build plan preview quando disponível.
>
> **4.** Usuário define resources, variables/secrets e optional domain.
>
> **5.** Review mostra configuração final.
>
> **6.** Sistema cria Service desired state e solicita Build/Deployment.
>
> **7.** Build gera Artifact; Release é criada; Swarm rollout é executado.
>
> **8.** Após health verification, Service aparece HEALTHY.

**Alternativas / falhas**

> **•** Detection inconclusiva → pedir overrides ou Dockerfile.
>
> **•** Build falha → Service permanece criado sem release saudável; mostrar build logs.
>
> **•** Rollout falha → Deployment FAILED; release anterior permanece/rollback conforme policy.

### UC-013 — Criar Service via Docker image

| **Campo**          | **Definição**                                              |
|--------------------|------------------------------------------------------------|
| Ator principal     | ADMIN / DEVELOPER                                          |
| Permissão          | service.create + deploy.create                             |
| Pré-condições      | Environment READY; registry credentials se imagem privada. |
| Gatilho            | Create Service → Docker Image.                             |
| Resultado esperado | Service saudável por artifact imutável.                    |

**Fluxo principal**

> **1.** Usuário informa image ref preferencialmente com tag/digest.
>
> **2.** Sistema resolve/puxa metadata e autenticação.
>
> **3.** Usuário configura runtime, secrets, resources e networking.
>
> **4.** Sistema cria Release/Deployment apontando ao artifact resolved.
>
> **5.** Swarm cria Service e verifica health.

**Alternativas / falhas**

> **•** Image inexistente/auth failure → não iniciar rollout.
>
> **•** Tag mutável → resolver digest e armazenar release por digest.

### UC-015 — Fazer deploy manual

| **Campo**          | **Definição**                            |
|--------------------|------------------------------------------|
| Ator principal     | ADMIN / DEVELOPER                        |
| Permissão          | deployment.create                        |
| Pré-condições      | Service configurado; source válido.      |
| Gatilho            | Service → Deploy.                        |
| Resultado esperado | Release aplicada e runtime reconciliado. |

**Fluxo principal**

> **1.** Sistema captura SourceRevision/commit alvo.
>
> **2.** Cria Build se necessário.
>
> **3.** Artifact é produzido/pushed e Release imutável criada.
>
> **4.** Deployment prepara secret bindings e runtime spec.
>
> **5.** Swarm Executor aplica rolling update.
>
> **6.** Verifier acompanha Tasks/health.
>
> **7.** Deployment marca HEALTHY e appliedRevision avança.

**Alternativas / falhas**

> **•** Novo deploy solicitado durante rollout → aplicar supersession/queue policy e explicar na UI.
>
> **•** Health falha → FAILED ou automatic rollback conforme policy.

### UC-018 — Rollback para release anterior

| **Campo**          | **Definição**                                     |
|--------------------|---------------------------------------------------|
| Ator principal     | ADMIN / DEVELOPER                                 |
| Permissão          | deployment.rollback                               |
| Pré-condições      | Existe Deployment saudável anterior compatível.   |
| Gatilho            | Deployment/Service → Rollback.                    |
| Resultado esperado | Novo deployment saudável usando release anterior. |

**Fluxo principal**

> **1.** UI mostra current e target Release.
>
> **2.** Exibe diferenças relevantes de runtime/bindings que serão restauradas.
>
> **3.** Usuário confirma.
>
> **4.** Sistema cria novo Deployment do tipo ROLLBACK referenciando artifact existente.
>
> **5.** Swarm executa rolling update sem rebuild.
>
> **6.** Health verification confirma resultado.

**Alternativas / falhas**

> **•** Artifact foi coletado indevidamente → bloquear e informar retention issue.
>
> **•** SecretVersion necessária indisponível → bloquear antes do rollout.

### UC-019 — Promover HML para Production

| **Campo**          | **Definição**                                                       |
|--------------------|---------------------------------------------------------------------|
| Ator principal     | ADMIN / DEVELOPER                                                   |
| Permissão          | deployment.promote                                                  |
| Pré-condições      | Release saudável em HML; Production Service lineage correspondente. |
| Gatilho            | HML Deployment → Promote.                                           |
| Resultado esperado | Mesmo artifact testado em HML executando em Production.             |

**Fluxo principal**

> **1.** UI seleciona Production target.
>
> **2.** Sistema mostra mesmo Artifact digest e diferenças de configuração.
>
> **3.** Production-specific secrets/resources/domains são mantidos por padrão.
>
> **4.** Usuário confirma “Promote same artifact”.
>
> **5.** Cria Deployment em Production sem Build.
>
> **6.** Executa rollout e health verification.
>
> **7.** Registra provenance HML → Production.

**Alternativas / falhas**

> **•** Service lineage ausente → pedir target manual ou bloquear.
>
> **•** Production policy exige approval futuro → estado awaiting approval quando recurso existir.

# 33. Casos de uso detalhados — scaling, domains e Vault

### UC-020 — Escalar Service manualmente

| **Campo**          | **Definição**                              |
|--------------------|--------------------------------------------|
| Ator principal     | ADMIN / DEVELOPER                          |
| Permissão          | service.scale                              |
| Pré-condições      | Service ativo; cluster capacity conhecida. |
| Gatilho            | Service → Scale.                           |
| Resultado esperado | Desired e actual replicas convergidos.     |

**Fluxo principal**

> **1.** UI mostra replicas atuais e cluster headroom.
>
> **2.** Usuário informa desired replicas.
>
> **3.** Sistema valida quotas/capacity policy.
>
> **4.** Atualiza desired state e cria Operation SCALE.
>
> **5.** Executor atualiza Swarm Service.
>
> **6.** Reconciler confirma running/healthy replicas.
>
> **7.** UI encerra operação apenas após actual state convergir.

**Alternativas / falhas**

> **•** Capacity insuficiente → warning/bloqueio conforme policy.
>
> **•** Operação concorrente de rollout → serializar ou supersede conforme regra.

### UC-024 — Adicionar domínio customizado

| **Campo**          | **Definição**                               |
|--------------------|---------------------------------------------|
| Ator principal     | ADMIN / DEVELOPER                           |
| Permissão          | domain.create                               |
| Pré-condições      | Service healthy; target port conhecido.     |
| Gatilho            | Service → Networking → Add Domain.          |
| Resultado esperado | Hostname servindo o Service com TLS válido. |

**Fluxo principal**

> **1.** Usuário informa hostname, target port e HTTPS preference.
>
> **2.** Sistema cria Domain PENDING_DNS.
>
> **3.** DNS checker verifica resolução para LB esperado.
>
> **4.** Certificate Manager inicia ACME quando elegível.
>
> **5.** Certificate é emitido e distribuído aos ingress gateways.
>
> **6.** Traefik route fica ativa.
>
> **7.** Domain status muda ACTIVE.

**Alternativas / falhas**

> **•** DNS mismatch → mostrar registro esperado/observado.
>
> **•** ACME falha → CERTIFICATE_ERROR com retry.
>
> **•** Nem todos ingress confirmam cert → DEGRADED até convergir.

### UC-029 — Criar nova SecretVersion

| **Campo**          | **Definição**                                                 |
|--------------------|---------------------------------------------------------------|
| Ator principal     | OWNER / ADMIN                                                 |
| Permissão          | vault.secret.version.create                                   |
| Pré-condições      | Secret existente; encryption key disponível.                  |
| Gatilho            | Vault → Secret → New Version.                                 |
| Resultado esperado | Nova versão disponível, sem impacto automático em Production. |

**Fluxo principal**

> **1.** Usuário informa novo value em campo protegido.
>
> **2.** Backend cifra antes de persistir e cria SecretVersion imutável.
>
> **3.** UI não altera bindings existentes automaticamente.
>
> **4.** Mostra “new version available” nos Services consumidores.
>
> **5.** Audit registra criação sem plaintext.

**Alternativas / falhas**

> **•** Encryption unavailable → bloquear; nunca fallback para plaintext.
>
> **•** Valor vazio/invalid policy → validação.

### UC-030 — Bind SecretVersion a Service

| **Campo**          | **Definição**                                             |
|--------------------|-----------------------------------------------------------|
| Ator principal     | ADMIN / DEVELOPER autorizado                              |
| Permissão          | vault.secret.bind                                         |
| Pré-condições      | Service e SecretVersion pertencem ao escopo permitido.    |
| Gatilho            | Service → Variables & Secrets → Add/Update Secret.        |
| Resultado esperado | Service usa versão selecionada sem expor plaintext na UI. |

**Fluxo principal**

> **1.** Usuário escolhe canonical Secret e versão.
>
> **2.** Define targetName e injection mode.
>
> **3.** Sistema valida scope/RBAC.
>
> **4.** Atualiza desired state do Service.
>
> **5.** Materializa/atualiza Swarm Secret opaca.
>
> **6.** Executa rollout controlado quando necessário.
>
> **7.** Reconciler confirma tasks usando nova binding.

**Alternativas / falhas**

> **•** Binding de Production requer role mais alta conforme policy.
>
> **•** SecretVersion revoked/unavailable → bloquear.

### UC-031 — Promover SecretVersion HML → Production

| **Campo**          | **Definição**                                             |
|--------------------|-----------------------------------------------------------|
| Ator principal     | ADMIN                                                     |
| Permissão          | vault.secret.promote                                      |
| Pré-condições      | HML usa versão nova e Production ainda usa antiga.        |
| Gatilho            | Secret detail / Environment compare → Promote.            |
| Resultado esperado | Production passa a referenciar a SecretVersion promovida. |

**Fluxo principal**

> **1.** UI mostra usos atuais e target Production.
>
> **2.** Usuário confirma versão a promover.
>
> **3.** Sistema altera somente binding de Production; não copia plaintext.
>
> **4.** Cria Operation/Rollout dos Services afetados.
>
> **5.** Acompanha health e mostra resultado por Service.

**Alternativas / falhas**

> **•** Múltiplos Services afetados → operação composta com status parcial.
>
> **•** Um Service falha → não mascarar; oferecer rollback binding por Service.

# 34. Casos de uso detalhados — observabilidade, backup e governança

### UC-033 — Consultar logs

| **Campo**          | **Definição**                                   |
|--------------------|-------------------------------------------------|
| Ator principal     | DEVELOPER / VIEWER                              |
| Permissão          | logs.read                                       |
| Pré-condições      | Service existe; permissão de leitura.           |
| Gatilho            | Service → Logs.                                 |
| Resultado esperado | Usuário diagnostica Service sem acesso ao host. |

**Fluxo principal**

> **1.** UI abre janela recente com follow opcional.
>
> **2.** Usuário filtra task/time range/search.
>
> **3.** Backend transmite dados e aplica redaction/policies.
>
> **4.** UI sinaliza gaps ou backend unavailable explicitamente.

**Alternativas / falhas**

> **•** Task reiniciada → permitir alternar instâncias e mostrar lifecycle.
>
> **•** Log backend histórico indisponível → oferecer live/recent only.

### UC-037 — Criar Environment Snapshot

| **Campo**          | **Definição**                                                   |
|--------------------|-----------------------------------------------------------------|
| Ator principal     | ADMIN                                                           |
| Permissão          | snapshot.create                                                 |
| Pré-condições      | Environment estável ou usuário aceita snapshot de estado atual. |
| Gatilho            | Environment → Snapshots → Create.                               |
| Resultado esperado | Snapshot consistente da configuração da plataforma.             |

**Fluxo principal**

> **1.** Sistema captura topology, releases, runtime config, domain refs e SecretVersion bindings.
>
> **2.** Não captura plaintext nem bancos externos gerenciados.
>
> **3.** Snapshot recebe ID/status e é armazenado conforme policy.
>
> **4.** UI lista snapshot com composição e restore eligibility.

**Alternativas / falhas**

> **•** Operation concorrente em andamento → warning ou aguardar consistent point.
>
> **•** External provider unavailable → snapshot config pode falhar conforme escopo.

### UC-040 — Executar recovery verification

| **Campo**          | **Definição**                               |
|--------------------|---------------------------------------------|
| Ator principal     | OWNER / INSTANCE_ADMIN                      |
| Permissão          | security.recovery.verify                    |
| Pré-condições      | Recovery Key existente.                     |
| Gatilho            | Security → Recovery → Verify.               |
| Resultado esperado | Recovery readiness comprovada recentemente. |

**Fluxo principal**

> **1.** UI solicita chave/trechos conforme fluxo seguro.
>
> **2.** Backend testa derivação/decryption do envelope sem persistir chave.
>
> **3.** Registra verification timestamp e fingerprint.
>
> **4.** Opcionalmente combina com restore drill da plataforma em ambiente isolado.

**Alternativas / falhas**

> **•** Chave inválida → não revelar metadata criptográfica sensível; mostrar failure e guidance.

### UC-041 — Convidar membro

| **Campo**          | **Definição**                         |
|--------------------|---------------------------------------|
| Ator principal     | OWNER / ADMIN                         |
| Permissão          | team.member.invite                    |
| Pré-condições      | Team ativo; email não é membro ativo. |
| Gatilho            | Settings → Members → Invite.          |
| Resultado esperado | Novo membro ativo no Team.            |

**Fluxo principal**

> **1.** Usuário informa email e role não-OWNER.
>
> **2.** Sistema cria convite com token expirável.
>
> **3.** Convidado aceita e autentica/cria conta.
>
> **4.** Membership vira ACTIVE com role escolhida.
>
> **5.** Audit registra inviter e role.

**Alternativas / falhas**

> **•** Email já membro → oferecer edit role.
>
> **•** Convite expirado → reenviar gera novo token e invalida anterior.

### UC-043 — Transferir ownership

| **Campo**          | **Definição**                                                |
|--------------------|--------------------------------------------------------------|
| Ator principal     | TEAM_OWNER                                                   |
| Permissão          | team.owner.transfer                                          |
| Pré-condições      | Novo owner é ADMIN ativo; OWNER reautenticado/MFA.           |
| Gatilho            | Settings → Members/Ownership → Transfer.                     |
| Resultado esperado | Team mantém exatamente um OWNER e propriedade é transferida. |

**Fluxo principal**

> **1.** UI lista apenas ADMINs elegíveis.
>
> **2.** Owner seleciona destino e revisa efeitos.
>
> **3.** Reautentica.
>
> **4.** Backend executa transação: destino ADMIN→OWNER; antigo OWNER→ADMIN; atualiza ownerUserId.
>
> **5.** Audit registra before/after e actor.
>
> **6.** UI atualiza permissions imediatamente.

**Alternativas / falhas**

> **•** Destino deixou de ser ADMIN entre leitura e submit → transação falha sem alterar owner.
>
> **•** Reauth expirada → exigir novamente.

# 35. Critérios de aceite da Parte 10

> **•** A navegação deixa claro que Projects/Environments são produto e Clusters são infraestrutura.
>
> **•** Todas as entidades principais das Partes 1–9 possuem ao menos uma tela de list/detail ou aparecem contextualizadas em outra tela.
>
> **•** Todo fluxo assíncrono relevante possui estado observável e Operation detail.
>
> **•** Production é visualmente distinguível e ações destrutivas têm confirmação proporcional ao risco.
>
> **•** Secrets e Recovery Key nunca aparecem em plaintext fora de fluxos explícitos e autorizados.
>
> **•** Owner transferível respeita exatamente um OWNER ativo e destino ADMIN.
>
> **•** UI diferencia Build failure, Deployment failure, Runtime degradation e Edge/DNS/TLS failure.
>
> **•** Desired state e actual state divergentes são representados sem falso “success”.
>
> **•** Cluster HA/readiness e capacity são compreensíveis sem o usuário dominar Swarm.
>
> **•** Use cases possuem permissions e outcomes verificáveis pelo backend.
>
> **•** Wireframes podem ser produzidos diretamente a partir do inventário de telas e fluxos descritos aqui.
>
> **•** Nenhuma tela precisa expor Docker Engine API, docker.sock ou detalhes internos como requisito de uso normal.

Fim da Parte 10 — UX/UI e Casos de Uso.
