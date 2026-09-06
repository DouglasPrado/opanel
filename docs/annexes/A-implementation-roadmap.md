---
document: "A"
title: "Roadmap de Implementação"
type: "annex"
status: "approved"
source: "docx"
---

**PLATAFORMA PAAS  
CLUSTER-FIRST**

**Anexo A — Roadmap de Implementação**

Milestones, dependências, caminho crítico, critérios de aceite e paralelização

## Resumo executivo

Este anexo transforma as dez partes da especificação da plataforma em uma sequência executável de desenvolvimento. O objetivo não é criar um cronograma por datas, e sim definir dependências técnicas, entregas verticais, critérios objetivos de conclusão e quais frentes podem avançar em paralelo sem comprometer o caminho crítico.

A estratégia recomendada é construir a plataforma por fatias verticais que terminam em comportamento observável pelo usuário. Evita-se implementar subsistemas completos isoladamente por meses. Cada milestone deve deixar o produto mais operacional, ainda que sob feature flags ou acesso interno.

| **Regra principal:** um milestone só é considerado concluído quando o comportamento chega à UI/API, persiste estado, executa a operação real quando aplicável, possui observabilidade mínima e passa pelos critérios de aceite definidos aqui. |
|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|

| **Decisão**               | **Diretriz**                                                                                         |
|---------------------------|------------------------------------------------------------------------------------------------------|
| Cluster-first             | Swarm existe desde o primeiro node; Services são Docker Services, não containers standalone.         |
| Railpack-first            | Railpack é o builder automático padrão; Dockerfile é o caminho explícito.                            |
| Stateless-first           | Postgres, Redis e object storage das aplicações ficam externos na primeira fase.                     |
| Control Plane seguro      | API pública nunca recebe docker.sock; executor privilegiado aplica mudanças no Swarm.                |
| Desired state             | PostgreSQL da plataforma expressa intenção; reconcilers convergem runtime.                           |
| HA progressivo            | single-node funciona, mas a mesma arquitetura evolui para 3 managers, N workers e múltiplos ingress. |
| Secrets versionadas       | Vault próprio mantém SecretVersion imutável; Swarm Secret distribui ao workload.                     |
| Edge separado             | LB L4 externo → Traefik host mode → overlay → Service.                                               |
| Dados gerenciados         | HA de Postgres/Redis/storage de aplicações é delegada a terceiros inicialmente.                      |
| Sem calendário artificial | roadmap ordena dependências; datas devem ser estimadas somente após breakdown técnico por equipe.    |

# 1. Definição de pronto do roadmap

O roadmap utiliza quatro níveis de conclusão. A equipe não deve confundir “código escrito” com “capacidade entregue”.

| **Nível**   | **Significado**                                                 |
|-------------|-----------------------------------------------------------------|
| Implemented | Código existe e compila.                                        |
| Integrated  | Componente conversa com dependências reais e persiste estado.   |
| Operable    | Logs, erros, retry, status e ação operacional mínima existem.   |
| Accepted    | Critérios funcionais, segurança e testes obrigatórios passaram. |

| **Definition of Done:** para marcar um milestone como DONE, todas as entregas críticas devem estar no nível Accepted. Itens explicitamente diferidos devem estar documentados como backlog, não escondidos como “quase pronto”. |
|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|

# 2. Workstreams de implementação

| **Stream**        | **Responsabilidade**                                                        | **Observação**                                                   |
|-------------------|-----------------------------------------------------------------------------|------------------------------------------------------------------|
| A. Product/API    | Auth, Team, Project, Environment, Service, APIs e regras de domínio.        | Pode avançar cedo com runtime mockado.                           |
| B. Control Plane  | Operations, Outbox, queues, reconciler, executor Swarm, idempotência.       | É o coração do caminho crítico.                                  |
| C. Delivery       | Git, Railpack, BuildKit, Registry, Artifact, Release, Deployment.           | Depende do modelo Service e executor.                            |
| D. Edge           | Traefik, domains, DNS, Certificate Manager e LB integrations.               | Pode ser desenvolvido em paralelo ao build após Service existir. |
| E. Security       | Vault, SecretVersion, Recovery Key, RBAC, audit.                            | Auth/RBAC começa cedo; Vault entra antes de produção.            |
| F. Observability  | logs, metrics, events, alerts, operations center.                           | Começa mínimo e cresce junto dos milestones.                     |
| G. Infrastructure | bootstrap, enrollment, nodes, providers e cluster readiness.                | Bootstrap inicial é crítico; providers avançados podem esperar.  |
| H. UX             | App shell, onboarding, Projects, Services, Deployments, runtime e settings. | Pode usar contratos/mock APIs para adiantar.                     |

# 3. Caminho crítico

M0 Foundation  
↓  
M1 Identity + Team  
↓  
M2 Swarm Bootstrap + Executor  
↓  
M3 Project / Environment / Service  
↓  
M4 Desired State + Reconcile Runtime  
↓  
M5 Delivery Pipeline (Git → Railpack → BuildKit → Artifact)  
↓  
M6 Deployment / Release / Rollback  
↓  
M7 Edge (Traefik + Domain + TLS)  
↓  
M8 Vault + Swarm Secrets  
↓  
M9 Observability + Operations  
↓  
M10 HA Cluster Expansion  
↓  
M11 Backup / DR  
↓  
M12 Hardening + Scale Validation  
↓  
M13 Release Candidate / Production Readiness

Alguns streams podem começar antes de sua posição no diagrama, mas não devem bloquear o caminho principal. Por exemplo, o design de Vault pode começar durante M3, porém production secrets só são aceitas quando M8 estiver concluído.

# 4. Visão geral dos milestones

| **ID** | **Milestone**        | **Principal capacidade entregue**                               | **Bloqueia**         |
|--------|----------------------|-----------------------------------------------------------------|----------------------|
| M0     | Foundation           | Monorepo, CI, DB, migrations, contracts, environments internos. | Todos                |
| M1     | Identity & Team      | Login, bootstrap owner, Team, membership, RBAC base.            | M3+                  |
| M2     | Swarm Bootstrap      | Cluster single-node, executor seguro, Docker/Swarm access.      | M4                   |
| M3     | Core Product Model   | Project → Environment → Service, CRUD e UI base.                | M4/M5                |
| M4     | Runtime Reconcile    | Desired state → Docker Service real; scale/restart/status.      | M6+                  |
| M5     | Build & Artifact     | Git → Railpack/Dockerfile → BuildKit → Registry → digest.       | M6                   |
| M6     | Deployment Lifecycle | Release, rollout, health, rollback, promotion.                  | M7/M9                |
| M7     | Networking & TLS     | Traefik, domains, LB path, Certificate Manager.                 | Production traffic   |
| M8     | Vault & Secrets      | SecretVersion, bindings, encryption, Swarm Secrets.             | Production security  |
| M9     | Observability        | Logs, metrics, events, alerts, Ops Center.                      | Production operation |
| M10    | HA & Nodes           | Enrollment, N nodes, managers/workers/ingress, readiness.       | HA claim             |
| M11    | Backup & DR          | Platform backup, restore, snapshots, recovery drills.           | Production readiness |
| M12    | Hardening            | Security, chaos, load, concurrency, failure handling.           | RC                   |
| M13    | Release Candidate    | End-to-end acceptance, upgrade/rollback, runbooks.              | Go-live              |

# 5. Milestones detalhados

## M0 — Foundation e Development Platform

| **Campo**              | **Definição**                                                                                                                                                                        |
|------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Objetivo               | Criar uma base de engenharia que permita evoluir o produto sem acumular dívida estrutural desde o primeiro commit.                                                                   |
| Dependências           | Nenhuma.                                                                                                                                                                             |
| Resultado de saída     | Monorepo executável localmente; banco PostgreSQL da plataforma; migrations; packages/contracts; CI; lint/typecheck/test; configuração segura por environment; feature flags mínimas. |
| Pode rodar em paralelo | UX shell, design system e contratos de API podem começar em paralelo.                                                                                                                |

**Critérios de aceite**

> **•** Repositório sobe localmente com um único comando documentado.
>
> **•** API e Web compartilham contratos versionados sem duplicação manual de tipos críticos.
>
> **•** Migration pode ser aplicada e revertida em ambiente de desenvolvimento.
>
> **•** CI impede merge com typecheck/test/lint falhando.
>
> **•** Segredos de desenvolvimento não são versionados no Git.
>
> **•** Existe health endpoint da própria plataforma e readiness do banco.

**Testes obrigatórios**

> **•** Teste de migration clean database → latest.
>
> **•** Teste de configuração inválida falhando no startup.
>
> **•** Pipeline CI completo em branch de teste.
>
> **•** Smoke test API + Web + PostgreSQL.

**Fora de escopo neste milestone**

> **•** Docker Swarm real, GitHub App, observabilidade avançada.

## M1 — Identidade, Team e Governança Base

| **Campo**              | **Definição**                                                                                                                                                      |
|------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Objetivo               | Permitir bootstrap seguro da primeira conta, criação do Team e controle de acesso coerente com a Parte 4.                                                          |
| Dependências           | M0.                                                                                                                                                                |
| Resultado de saída     | Auth; primeiro usuário como TEAM_OWNER + INSTANCE_ADMIN; Team; TeamMember; ADMIN/DEVELOPER/VIEWER; convites básicos; sessões; audit mínimo de ações de identidade. |
| Pode rodar em paralelo | UX de Projects pode ser prototipada com mocks; M2 pode começar com autenticação técnica interna.                                                                   |

**Critérios de aceite**

> **•** Primeira conta cria o primeiro Team e recebe os papéis definidos.
>
> **•** Cada Team possui exatamente um OWNER ativo.
>
> **•** OWNER pode transferir ownership apenas para ADMIN ativo; operação é atômica e auditada.
>
> **•** Antigo OWNER vira ADMIN após transferência.
>
> **•** Usuário sem permissão recebe 403 no backend mesmo se manipular UI/API.
>
> **•** UI oculta/desabilita ações incompatíveis com papel atual.

**Testes obrigatórios**

> **•** Testes de matriz RBAC.
>
> **•** Teste concorrente de duas tentativas de transferir ownership.
>
> **•** Teste de sessão revogada.
>
> **•** Teste de convite expirado/reutilizado.

**Fora de escopo neste milestone**

> **•** SSO enterprise, SCIM e billing.

## M2 — Bootstrap Swarm e Executor Privilegiado

| **Campo**              | **Definição**                                                                                                                                                                                  |
|------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Objetivo               | Fazer a plataforma controlar um Docker Swarm single-node sem expor a Docker API ao usuário ou à API pública.                                                                                   |
| Dependências           | M0; M1 para exposição via UI administrativa.                                                                                                                                                   |
| Resultado de saída     | Inicialização/detecção do Swarm; Cluster e Node persistidos; Swarm Executor restrito aos managers; docker.sock somente no executor; leitura de nodes/services/tasks; operação básica auditada. |
| Pode rodar em paralelo | M3 modelagem e UI; enrollment design; observability mínima.                                                                                                                                    |

**Critérios de aceite**

> **•** Instalação vazia consegue inicializar um Swarm e registrar o primeiro Manager.
>
> **•** API pública não possui mount do docker.sock.
>
> **•** Executor consegue listar e inspecionar Services/Tasks/Nodes.
>
> **•** Falha de Docker daemon aparece como Cluster UNREACHABLE/DEGRADED, não como timeout genérico.
>
> **•** Operações do executor possuem correlation/operation ID.
>
> **•** 2375 não é aberto publicamente.

**Testes obrigatórios**

> **•** Teste contra Docker real em ambiente efêmero.
>
> **•** Teste de daemon indisponível.
>
> **•** Teste de socket inacessível pela API pública.
>
> **•** Teste de versão incompatível da Engine/Swarm.

**Fora de escopo neste milestone**

> **•** Multi-node, providers cloud e HA.

## M3 — Project, Environment e Service

| **Campo**              | **Definição**                                                                                                                                                               |
|------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Objetivo               | Entregar o modelo central do produto sem ainda exigir pipeline completo de build.                                                                                           |
| Dependências           | M1; M2 recomendado para validação real de Service depois.                                                                                                                   |
| Resultado de saída     | CRUD de Project; Environment vinculado a Cluster; Service com source/runtime/config; network lógica por Environment; desiredRevision; UI de Projects/Environments/Services. |
| Pode rodar em paralelo | Vault schema, build contracts e UI Service wizard.                                                                                                                          |

**Critérios de aceite**

> **•** Team cria Project e production Environment.
>
> **•** Environment aponta para Cluster sem Project depender hierarquicamente do Cluster.
>
> **•** Service possui identidade determinística e configurações versionáveis.
>
> **•** Production e HML podem existir no mesmo Project com configurações distintas.
>
> **•** Environment cria/possui network overlay lógica própria quando reconciliado.
>
> **•** Slugs e nomes obedecem constraints definidas na Parte 9.

**Testes obrigatórios**

> **•** Testes de constraints de ownership/slug.
>
> **•** Teste de isolamento entre Teams.
>
> **•** Teste de exclusão bloqueada quando dependências críticas existem.
>
> **•** API contract tests para Project/Environment/Service.

**Fora de escopo neste milestone**

> **•** Deploy Git automático, domains e HA.

## M4 — Desired State, Operations e Runtime Reconcile

| **Campo**              | **Definição**                                                                                                                                                                         |
|------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Objetivo               | Transformar um Service persistido em um Docker Swarm Service real e manter desired state e actual state convergentes.                                                                 |
| Dependências           | M2 + M3.                                                                                                                                                                              |
| Resultado de saída     | Operation Engine; Outbox; queue; Swarm Executor commands; Service reconciler; create/update/delete; replicas; resource limits; restart; actual state; Docker Events + periodic sweep. |
| Pode rodar em paralelo | M5 Delivery e M7 Edge podem começar usando Service estável.                                                                                                                           |

**Critérios de aceite**

> **•** Criar Service com imagem pronta resulta em Docker Service real.
>
> **•** Alterar replicas 1→3 converge para 3/3 Tasks ou retorna estado degradado explicável.
>
> **•** Repetir a mesma operação é idempotente.
>
> **•** Modificação manual no Swarm é detectada como drift e corrigida segundo Platform Wins.
>
> **•** Duas operações conflitantes no mesmo Service são serializadas/superseded corretamente.
>
> **•** Restart do Control Plane durante operação não perde intenção persistida.

**Testes obrigatórios**

> **•** Integration tests com Swarm real.
>
> **•** Teste de webhook/event duplicado no runtime.
>
> **•** Teste de crash entre DB commit e enqueue usando Outbox.
>
> **•** Teste concorrente de scale.
>
> **•** Teste de drift manual.
>
> **•** Teste de executor restart.

**Fora de escopo neste milestone**

> **•** Autoscaling, HA multi-node e historical metrics.

## M5 — Source, Railpack, BuildKit e Registry

| **Campo**              | **Definição**                                                                                                                                                                           |
|------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Objetivo               | Converter código-fonte em Artifact OCI imutável reutilizável pelo runtime.                                                                                                              |
| Dependências           | M3; M4 para deploy automático pós-build.                                                                                                                                                |
| Resultado de saída     | SourceConnection; Git public/private inicial; checkout por commit SHA; Railpack default; Dockerfile mode; BuildKit builders; cache; Registry provider; Artifact por digest; build logs. |
| Pode rodar em paralelo | M6 modelagem Release/Deployment; GitHub App UI; builder node provisioning.                                                                                                              |

**Critérios de aceite**

> **•** Repositório suportado gera Build Plan Railpack e Artifact OCI.
>
> **•** Dockerfile explícito ignora detecção automática quando selecionado.
>
> **•** Artifact é identificado por digest e não apenas por tag mutável.
>
> **•** Build falho não altera release atual do Service.
>
> **•** Build logs são streamados e persistem conforme política.
>
> **•** Build não executa nos Manager nodes por padrão quando houver builder dedicado.

**Testes obrigatórios**

> **•** Build de projeto Node simples via Railpack.
>
> **•** Build via Dockerfile.
>
> **•** Teste de build failure.
>
> **•** Teste de cache hit/miss.
>
> **•** Teste de registry auth inválida.
>
> **•** Teste de código malicioso tentando acessar recursos proibidos do builder.

**Fora de escopo neste milestone**

> **•** Multi-arch avançado e marketplace de builders.

## M6 — Release, Deployment, Rolling Update e Rollback

| **Campo**              | **Definição**                                                                                                                                                 |
|------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Objetivo               | Criar o ciclo de entrega imutável e observável da aplicação.                                                                                                  |
| Dependências           | M4 + M5.                                                                                                                                                      |
| Resultado de saída     | Release; Deployment state machine; artifact promotion; rollout Swarm; health verification; rollback; promotion HML→PROD sem rebuild; Git webhook auto-deploy. |
| Pode rodar em paralelo | M7 Edge, M8 Vault e M9 Observability.                                                                                                                         |

**Critérios de aceite**

> **•** Deployment referencia Artifact digest imutável.
>
> **•** Rollout saudável conclui somente após runtime/health confirmar.
>
> **•** Falha no rollout não marca sucesso apenas porque Docker aceitou update.
>
> **•** Rollback reaplica release anterior sem rebuild.
>
> **•** Promotion HML→PROD utiliza o mesmo artifact digest.
>
> **•** Webhook duplicado para o mesmo commit não gera deploys redundantes fora da política.
>
> **•** UI separa Build logs de Runtime events.

**Testes obrigatórios**

> **•** Rolling update com múltiplas réplicas.
>
> **•** Healthcheck falhando durante rollout.
>
> **•** Rollback automático/manual.
>
> **•** Promotion entre Environments.
>
> **•** Webhook duplicado/fora de ordem.
>
> **•** Control Plane restart no meio do rollout.

**Fora de escopo neste milestone**

> **•** Canary/blue-green avançados.

## M7 — Ingress, Domains e Certificate Manager

| **Campo**              | **Definição**                                                                                                                                                                                 |
|------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Objetivo               | Expor Services à internet através do caminho padrão LB L4 → Traefik host mode → overlay → Service.                                                                                            |
| Dependências           | M4; M6 recomendado para releases estáveis.                                                                                                                                                    |
| Resultado de saída     | Traefik global em ingress nodes; labels Swarm; Domain model; default domain; custom domain; DNS validation; Certificate Manager; ACME DNS-01; distribuição versionada de certificates; HTTPS. |
| Pode rodar em paralelo | LB Provider e DNS Provider integrations específicas.                                                                                                                                          |

**Critérios de aceite**

> **•** Service recebe domínio e responde via Traefik sem publicar porta diretamente no host.
>
> **•** Múltiplos Traefiks conseguem atender o mesmo domínio.
>
> **•** Certificate Manager emite/renova certificado e distribui a todas as instâncias ingress.
>
> **•** Nenhum Traefik precisa compartilhar acme.json gravável entre réplicas.
>
> **•** Domain mostra estados DNS_PENDING/CERT_PENDING/READY/ERROR.
>
> **•** WebSocket e SSE atravessam o ingress corretamente.

**Testes obrigatórios**

> **•** Teste com dois ou mais Traefiks.
>
> **•** Teste de remoção de uma réplica ingress durante tráfego.
>
> **•** Teste de certificado renovado sem downtime.
>
> **•** Teste DNS incorreto.
>
> **•** Teste WebSocket/SSE.
>
> **•** Teste de host header/routing isolado por Team/Environment.

**Fora de escopo neste milestone**

> **•** WAF próprio e CDN própria.

## M8 — Vault Versionado e Distribuição de Secrets

| **Campo**              | **Definição**                                                                                                                                                                                    |
|------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Objetivo               | Oferecer secrets próprias da plataforma com versionamento, bindings e distribuição segura para workloads.                                                                                        |
| Dependências           | M1 + M3 + M4.                                                                                                                                                                                    |
| Resultado de saída     | Secret; SecretVersion imutável; encryption envelope; Recovery Key; bindings por Service/Environment; pinned version; promoção/rollback; Swarm Secret materialization; audit de acesso/alteração. |
| Pode rodar em paralelo | M9 observability e M11 backup.                                                                                                                                                                   |

**Critérios de aceite**

> **•** Valor de SecretVersion não é armazenado plaintext no PostgreSQL.
>
> **•** Environment/Service referencia versão específica da secret.
>
> **•** Criar vN+1 não altera automaticamente Production pinned em vN.
>
> **•** Promover/rollback altera binding e causa rollout controlado quando necessário.
>
> **•** Secret só é entregue ao Service autorizado.
>
> **•** Recovery Key é mostrada uma vez, verificável e rotacionável sem recriptografar todo o vault.
>
> **•** UI nunca revela valor por acidente em listagens/logs/errors.

**Testes obrigatórios**

> **•** Teste crypto round-trip e chave errada.
>
> **•** Teste Recovery Key rotation.
>
> **•** Teste binding HML/PROD com versões distintas.
>
> **•** Teste acesso sem permission.
>
> **•** Teste de secret não aparecendo em logs/audit payloads.
>
> **•** Teste de Task movida para outro node recebendo Swarm Secret correta.

**Fora de escopo neste milestone**

> **•** Dynamic DB credentials e PKI.

## M9 — Logs, Metrics, Alerts e Operations Center

| **Campo**              | **Definição**                                                                                                                                                                 |
|------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Objetivo               | Tornar o sistema operável sem SSH como mecanismo primário de diagnóstico.                                                                                                     |
| Dependências           | M4/M6; integrações podem crescer incrementalmente.                                                                                                                            |
| Resultado de saída     | Live logs; historical log backend; service/task/cluster metrics; deployment events; alert rules; incidents; Operations Center; SSE/WebSocket de operações; terminal auditado. |
| Pode rodar em paralelo | M10 HA e M11 DR.                                                                                                                                                              |

**Critérios de aceite**

> **•** Usuário acompanha deployment em tempo real sem polling agressivo.
>
> **•** Logs live funcionam mesmo com várias Tasks.
>
> **•** CPU/RAM/replicas/restarts têm histórico suficiente para diagnóstico.
>
> **•** Falha de Service cria status e contexto observável, não somente stack trace interno.
>
> **•** Alertas evitam tempestade por deduplicação/silenciamento básico.
>
> **•** Terminal/exec exige permissão e gera Audit Log.

**Testes obrigatórios**

> **•** Teste de logs com Task replacement.
>
> **•** Teste de métricas após node reiniciar.
>
> **•** Teste de operação longa via SSE/WebSocket.
>
> **•** Teste de alert deduplication.
>
> **•** Teste de terminal não autorizado.
>
> **•** Teste de retention/cleanup básico.

**Fora de escopo neste milestone**

> **•** APM completo e tracing distribuído obrigatório.

## M10 — Enrollment, Multi-node e High Availability

| **Campo**              | **Definição**                                                                                                                                                                        |
|------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Objetivo               | Expandir a instalação de um node para cluster real sem mudar o modelo de aplicação.                                                                                                  |
| Dependências           | M2 + M4 + M7; M9 recomendado.                                                                                                                                                        |
| Resultado de saída     | Enrollment Token single-use; bootstrap script; Worker/Manager/Ingress/Builder roles; labels; promote/demote; drain; remove; Cluster Readiness; LB targets; 3-manager quorum support. |
| Pode rodar em paralelo | Cloud provider auto-provisioning pode ser paralelo após enrollment manual estar sólido.                                                                                              |

**Critérios de aceite**

> **•** Novo node entra via token temporário e aparece READY no painel.
>
> **•** Token expirado/reutilizado é rejeitado.
>
> **•** Drain move workloads compatíveis sem perda indevida de desired state.
>
> **•** Cluster com 3 Managers tolera perda de um Manager mantendo gerenciamento.
>
> **•** Múltiplos ingress atrás do LB mantêm tráfego quando um ingress falha.
>
> **•** Worker perdido tem Tasks stateless reagendadas em nodes elegíveis.
>
> **•** UI diferencia “cluster funcional” de “HA Ready”.

**Testes obrigatórios**

> **•** Teste join/remove worker.
>
> **•** Teste promote/demote manager preservando quorum.
>
> **•** Kill -9 de worker sob tráfego.
>
> **•** Kill de um manager em cluster de 3.
>
> **•** Kill de um ingress com healthcheck no LB.
>
> **•** Teste firewall/portas inválidas no enrollment.

**Fora de escopo neste milestone**

> **•** Multi-region/federação de múltiplos Swarms.

## M11 — Backup, Snapshots e Disaster Recovery

| **Campo**              | **Definição**                                                                                                                                                                                           |
|------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Objetivo               | Garantir que a plataforma possa ser reconstruída após perda do cluster ou corrupção operacional.                                                                                                        |
| Dependências           | M1–M10 suficientes para snapshot consistente; M8 é crítico para Vault.                                                                                                                                  |
| Resultado de saída     | Backup PostgreSQL da plataforma; backup config/metadata; Swarm state strategy; certificate backup; registry retention; environment snapshot; external backup provider; restore engine; recovery drills. |
| Pode rodar em paralelo | M12 chaos/security pode usar o DR como rede de segurança.                                                                                                                                               |

**Critérios de aceite**

> **•** Backup não depende exclusivamente do mesmo cluster que protege.
>
> **•** Restore de banco + Recovery Key recupera Vault e metadata.
>
> **•** Existe caminho Fast Swarm Restore e caminho Clean Rebuild.
>
> **•** Clean Rebuild recria Services a partir do estado do produto e Artifacts existentes.
>
> **•** Restore drill gera status verificável no painel.
>
> **•** Backups têm checksum/encryption/retention definidos.

**Testes obrigatórios**

> **•** Restore em ambiente isolado.
>
> **•** Perda simulada de manager state.
>
> **•** Restore com Recovery Key incorreta deve falhar com segurança.
>
> **•** Teste de artifact ausente no registry durante rebuild.
>
> **•** Teste de certificado restaurado/redistribuído.
>
> **•** Teste de backup parcial/corrompido.

**Fora de escopo neste milestone**

> **•** Backup dos bancos gerenciados dos clientes além de integrações informativas.

## M12 — Hardening, Concorrência, Chaos e Capacity

| **Campo**              | **Definição**                                                                                                                                                            |
|------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Objetivo               | Provar comportamento sob abuso, falha, carga e condições concorrentes antes de chamar a plataforma de production-grade.                                                  |
| Dependências           | M1–M11.                                                                                                                                                                  |
| Resultado de saída     | Security hardening; threat tests; chaos suite; load test do Control Plane e ingress; concurrency tests; rate limits; resource quotas; upgrade safety; failure injection. |
| Pode rodar em paralelo | UX polish pode avançar em paralelo.                                                                                                                                      |

**Critérios de aceite**

> **•** Nenhum endpoint externo acessa Docker API arbitrariamente.
>
> **•** Operações concorrentes críticas não corrompem desired state.
>
> **•** API suporta carga operacional alvo sem fila colapsar.
>
> **•** Perda de Worker/Ingress/Manager único dentro da tolerância não causa indisponibilidade global esperada.
>
> **•** Build workload não consegue comprometer Manager/Control Plane pelos mecanismos testados.
>
> **•** Rate limits e quotas impedem abuso óbvio de build/deploy/log streaming.
>
> **•** Recovery de operação após restart é determinístico.

**Testes obrigatórios**

> **•** Load test API/queue/reconciler.
>
> **•** Load test ingress separado da aplicação cliente.
>
> **•** Chaos: manager/worker/ingress/executor/DB connectivity.
>
> **•** Security tests de SSRF/path traversal/webhook forgery/token reuse.
>
> **•** Teste de Dockerfile malicioso no builder.
>
> **•** Teste de 100+ operações concorrentes em resources distintos e conflitos no mesmo Service.

**Fora de escopo neste milestone**

> **•** Garantia de capacidade baseada apenas em “visitas/mês”; capacidade deve ser medida em throughput/latência/concurrency.

## M13 — Release Candidate e Production Readiness

| **Campo**              | **Definição**                                                                                                                                                                           |
|------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Objetivo               | Fechar as lacunas entre “funciona” e “pode ser operado de forma responsável”.                                                                                                           |
| Dependências           | M0–M12.                                                                                                                                                                                 |
| Resultado de saída     | End-to-end acceptance; runbooks; upgrade/rollback da própria plataforma; observability baseline; backup verified; security checklist; onboarding limpo; documentation; release process. |
| Pode rodar em paralelo | Nenhum stream crítico deve ficar fora do RC.                                                                                                                                            |

**Critérios de aceite**

> **•** Nova instalação percorre onboarding até primeiro deploy sem intervenção manual não documentada.
>
> **•** Cluster pode sair de single-node para HA seguindo UI/runbook.
>
> **•** Git push pode chegar a deployment healthy com domain/TLS/secrets configurados.
>
> **•** Rollback, secret rotation, node drain e restore foram demonstrados em ambiente de staging.
>
> **•** Runbooks cobrem falhas críticas conhecidas.
>
> **•** Release da plataforma possui migration/upgrade/rollback strategy.
>
> **•** Todos os critérios blocking estão verdes; pendências aceitas estão explicitamente classificadas.

**Testes obrigatórios**

> **•** E2E completo do onboarding ao deploy.
>
> **•** Upgrade N-1 → N com workloads ativos.
>
> **•** Rollback da plataforma quando migration permitir ou forward-fix runbook testado.
>
> **•** DR drill final.
>
> **•** Failover ingress/worker/manager sob tráfego.
>
> **•** Permission/audit regression suite.

**Fora de escopo neste milestone**

> **•** Features comerciais avançadas, marketplace e managed data plane próprio.

# 6. Primeiro vertical slice recomendado

Antes de tentar implementar todos os milestones em profundidade, a equipe deve buscar um vertical slice extremamente pequeno, porém real, atravessando produto → control plane → Swarm.

Login / Team  
↓  
Create Project  
↓  
Create Production Environment  
↓  
Create Service from nginx:alpine  
↓  
Desired State persisted  
↓  
Operation queued  
↓  
Swarm Executor  
↓  
Docker Service created  
↓  
Actual State observed  
↓  
UI shows 1/1 Healthy  
↓  
View live logs  
↓  
Scale 1 → 3  
↓  
UI shows 3/3 Healthy

| **Por que:** este slice valida autenticação, modelo central, banco, operation engine, Docker API, Swarm, reconciliation, status e UI antes de adicionar Git/BuildKit/Traefik/Vault. Se essa espinha dorsal estiver errada, todo o resto ficará caro de corrigir. |
|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|

# 7. Sequência de incremento do vertical slice

| **Incremento** | **Nova capacidade**                                   |
|----------------|-------------------------------------------------------|
| VS-1           | Image pronta → Swarm Service → health/status.         |
| VS-2           | Scale/restart/update image.                           |
| VS-3           | Traefik + domínio interno/default.                    |
| VS-4           | Git public → Railpack → BuildKit → artifact → deploy. |
| VS-5           | GitHub App + webhook auto-deploy.                     |
| VS-6           | Vault secret binding → Swarm Secret.                  |
| VS-7           | Custom domain + Certificate Manager.                  |
| VS-8           | Second node → reschedule after worker failure.        |
| VS-9           | Second/third ingress + LB failover.                   |
| VS-10          | Backup/restore do próprio control plane.              |

# 8. Matriz de paralelização

| **Após** | **Stream 1**       | **Stream 2**         | **Stream 3**        | **Stream 4**            |
|----------|--------------------|----------------------|---------------------|-------------------------|
| M0       | M1 Identity        | M2 Bootstrap técnico | UX App Shell        | Schema/contracts        |
| M2+M3    | M4 Runtime         | M5 Delivery          | M7 Edge foundation  | M8 Vault foundation     |
| M4       | Runtime polish     | Traefik/domains      | Build/registry      | Observability collector |
| M6       | Rollback/promotion | Vault integration    | Certificate Manager | Ops Center              |
| M8+M9    | M10 HA/enrollment  | M11 Backup/DR        | Security hardening  | UX polish               |
| M10+M11  | M12 chaos/load     | RC runbooks          | Upgrade path        | Documentation           |

Paralelização não significa ausência de contratos. Antes de dividir streams, schemas, command/event contracts e estados precisam ser acordados conforme a Parte 9.

# 9. Dependências que não devem ser invertidas

| **Não fazer**                                                      | **Motivo**                                                                |
|--------------------------------------------------------------------|---------------------------------------------------------------------------|
| Criar GitHub auto-deploy antes de Operation/Deployment idempotente | Webhooks duplicados e retries virarão fonte de deploy inconsistente.      |
| Criar autoscaling antes de métricas confiáveis e scale idempotente | Controller reagirá a dados ruins e poderá oscilar.                        |
| Oferecer Production secrets antes de Vault/Recovery/Audit          | A dívida de segurança nasce no dado mais sensível.                        |
| Vender HA antes de ingress + quorum + node failure tests           | Ter “cluster” não significa tolerar falha.                                |
| Adicionar provider cloud antes de enrollment manual estável        | Automatiza um fluxo ainda não compreendido.                               |
| Criar managed Postgres/Redis próprio neste roadmap                 | Expande o produto para data-plane stateful antes do compute estar sólido. |
| Otimizar para 100M visitas/mês sem workload model                  | Visitas não definem RPS, concorrência, cache ou custo de DB.              |

# 10. Feature flags e rollout interno

| **Flag**               | **Uso recomendado**                                              |
|------------------------|------------------------------------------------------------------|
| builds.enabled         | Ativa source build após image deploy estar estável.              |
| domains.custom.enabled | Libera custom domains após default routing.                      |
| vault.enabled          | Libera SecretVersion apenas quando recovery estiver operacional. |
| ha.enrollment.enabled  | Libera Add Node após single-node runtime estável.                |
| autoscaling.enabled    | Somente após metrics + manual scale estáveis.                    |
| backup.restore.enabled | Restore pode ficar staff-only antes de self-service.             |
| terminal.enabled       | Restrito até RBAC/audit hardening.                               |

# 11. Gates de qualidade por classe

| **Gate**      | **Antes de avançar para**                                                                         |
|---------------|---------------------------------------------------------------------------------------------------|
| Runtime Gate  | M5+: create/update/scale idempotentes e Swarm status confiável.                                   |
| Delivery Gate | M7+: artifact digest, rollback e deployment state machine confiáveis.                             |
| Security Gate | Production usage: RBAC, Vault, Recovery Key, audit e executor isolation.                          |
| HA Gate       | Claim HA: 3 managers ou política equivalente, múltiplos ingress, LB health checks, failure tests. |
| DR Gate       | Production critical: off-site backup + restore drill verificado.                                  |
| Scale Gate    | High traffic: load test com workload model e SLOs, não estimativa por visitas.                    |
| Release Gate  | RC: upgrade path, runbooks, failure tests e end-to-end acceptance.                                |

# 12. Backlog explicitamente pós-core

Os itens abaixo são compatíveis com a arquitetura, mas não devem bloquear a primeira versão production-ready descrita neste roadmap.

> **•** Multi-cluster federation / multi-region active-active.
>
> **•** Managed PostgreSQL, Redis ou distributed storage próprios.
>
> **•** Kubernetes runtime provider.
>
> **•** Marketplace público de templates/plugins.
>
> **•** Enterprise SSO, SCIM e políticas organizacionais avançadas.
>
> **•** Canary/blue-green avançados e traffic splitting sofisticado.
>
> **•** Service mesh e mTLS automático entre todos os services.
>
> **•** Billing/metering comercial completo.
>
> **•** Cost optimization/recommendations automáticas.
>
> **•** Multi-tenant build farm distribuída entre regiões.
>
> **•** AI assistant operacional.

# 13. Checklist para iniciar desenvolvimento

| **Item**               | **Saída esperada**                                                    |
|------------------------|-----------------------------------------------------------------------|
| Repositório            | Monorepo criado com packages e apps definidos.                        |
| Schema base            | User/Team/Cluster/Project/Environment/Service + migrations.           |
| Contracts              | Commands/events/API DTOs de M0–M4 definidos.                          |
| Dev Swarm              | Ambiente local/VM de integração com Swarm real.                       |
| CI                     | Typecheck, lint, unit e integration gates.                            |
| UX skeleton            | App Shell + rotas principais da Parte 10.                             |
| Security baseline      | Secrets de infraestrutura fora do Git; docker.sock boundary definida. |
| Test harness           | Helpers para criar/destroir services/networks em testes.              |
| Observability baseline | Correlation ID e structured logs desde o início.                      |
| ADR log                | Decisões arquiteturais importantes registradas e versionadas.         |

# 14. Critério de encerramento do Anexo A

Este roadmap está completo quando a equipe consegue pegar qualquer milestone, decompor em issues técnicas sem rediscutir o produto, e demonstrar objetivamente quando aquele milestone terminou. Mudanças de escopo devem atualizar este anexo e a parte da especificação afetada, evitando divergência entre documentação e implementação.

| **Próximo documento recomendado:** Anexo B — Requisitos Não Funcionais e SLOs. Ele deve quantificar disponibilidade, latência, RPO/RTO, tempos de deploy/build, retenções, limites operacionais e critérios de capacidade que este roadmap precisa atingir. |
|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
