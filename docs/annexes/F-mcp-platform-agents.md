---
document: "F"
title: "MCP da Plataforma e Agentes"
type: "annex"
status: "approved"
source: "docx"
---

**PLATAFORMA PAAS  
CLUSTER-FIRST**

**Anexo F - MCP da Plataforma e Agentes**

*Especificação para conectar agentes de IA ao Control Plane e operar a plataforma por linguagem natural com OAuth, RBAC, approvals, auditabilidade e MCP*

## Resumo executivo

Este anexo define um MCP oficial da plataforma para que o usuário conecte ChatGPT, Claude, Codex, IDEs, agentes internos ou outros hosts compatíveis e administre a plataforma por linguagem natural. O MCP deve oferecer a mesma superfície funcional da UI e da API pública, mas nunca acesso direto ao Docker Engine, ao docker.sock ou aos componentes internos privilegiados.

A decisão central é tratar o MCP como mais um cliente do Control Plane. Toda leitura passa por Queries autorizadas; toda mutação passa pelos mesmos Commands, Operations, políticas, reconciliação, auditoria e gates de segurança definidos nas Partes 1-10 e nos Anexos A-E.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th><strong>Objetivo de produto<br />
</strong>Depois de conectar o MCP, um usuário autorizado deve conseguir pedir ao agente ações como criar projetos, configurar ambientes, subir serviços, conectar Git, disparar builds, fazer deploy/rollback, alterar escala, configurar domínio/TLS, administrar secrets sem expor plaintext, investigar incidentes, consultar métricas e executar operações administrativas compatíveis com seu papel. A autoridade final continua sendo a política da plataforma, não o modelo de IA.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

# 1. Objetivo, escopo e invariantes

## 1.1 Objetivo

O MCP transforma a plataforma em uma infraestrutura agent-first: tudo que é importante na UI deve possuir uma capacidade equivalente para agentes, com contratos estruturados e seguros. A experiência esperada é que o usuário descreva a intenção e o agente descubra contexto, proponha ou execute a ação, acompanhe a Operation até o fim e explique o resultado.

## 1.2 Invariantes arquiteturais

| **Invariante**     | **Regra**                                                                                                             |
|--------------------|-----------------------------------------------------------------------------------------------------------------------|
| Sem bypass         | MCP não acessa Docker, Swarm, Registry, banco ou Vault diretamente. Usa Application Services do Control Plane.        |
| Mesma autorização  | Permissão efetiva = scopes OAuth ∩ RBAC do usuário ∩ boundary de recursos ∩ policy do ambiente.                       |
| Desired State      | Mutações alteram estado desejado e disparam Operation/Reconciler; MCP não aplica patches ad hoc no runtime.           |
| Auditável          | Toda chamada relevante registra ator humano, cliente MCP, tool, recurso, Operation, approval e resultado.             |
| Least privilege    | Conexões recebem apenas scopes e recursos necessários; produção pode ser read-only independentemente de HML.          |
| Sem secret leakage | Listagens e logs não retornam secret plaintext. Reveal é capability separada, desabilitada por padrão.                |
| Long-running       | Deploy/build/restore não bloqueiam uma chamada HTTP por minutos; retornam Operation e podem usar Tasks como extensão. |
| Protocol-first     | Contratos de tools são versionados, com JSON Schema e erros estruturados; nomes não mudam sem depreciação.            |

## 1.3 Fora de escopo

> **•** Expor uma shell genérica do host, Docker socket, Docker Engine API ou acesso SSH por MCP.
>
> **•** Permitir que o agente ignore approvals, RBAC, quotas ou políticas de produção.
>
> **•** Duplicar regras de negócio dentro do servidor MCP.
>
> **•** Usar o MCP como data plane do tráfego das aplicações hospedadas.

# 2. Arquitetura de referência

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Agente / MCP Host<br />
|<br />
| HTTPS + OAuth<br />
v<br />
/mcp MCP Gateway (stateless)<br />
|<br />
+--&gt; AuthN / OAuth / Scopes<br />
+--&gt; RBAC + Resource Boundary + Policies<br />
|<br />
v<br />
Application Services / Commands / Queries<br />
| |<br />
| write | read<br />
v v<br />
Operation Engine Read Models<br />
|<br />
v<br />
Reconciler / Swarm Executor<br />
|<br />
v<br />
Docker Engine / Swarm / Traefik / BuildKit / Registry</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 2.1 MCP Gateway

O MCP Gateway é um adapter de protocolo. Ele converte tools/resources/prompts do MCP em chamadas internas aos mesmos serviços de aplicação usados pela API pública. Ele não contém lógica de deploy, TLS, Vault ou cluster; apenas valida contrato, autentica, autoriza, chama a camada correta e serializa o resultado.

## 2.2 Stateless e alta disponibilidade

A baseline deve acompanhar a revisão MCP 2026-07-28, cujo core é stateless. Cada request carrega a versão do protocolo e metadados necessários; qualquer réplica do Gateway pode processar a chamada. Isso permite executar várias réplicas atrás de Traefik/LB sem sticky session e sem store de sessão MCP.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th><strong>Decisão<br />
</strong>O endpoint remoto oficial será um único endpoint HTTPS, por exemplo https://control.example.com/mcp. Estado durável pertence ao banco da plataforma (Operation, Approval, OAuth Grant etc.), não a uma sessão MCP em memória.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

# 3. Baseline do protocolo MCP

## 3.1 Versão alvo

| **Item**          | **Decisão**                                                                                                                                  |
|-------------------|----------------------------------------------------------------------------------------------------------------------------------------------|
| Revisão primária  | MCP 2026-07-28.                                                                                                                              |
| Compatibilidade   | Manter compatibilidade com uma revisão anterior apenas se o SDK escolhido fornecer suporte confiável; anunciar depreciação antes de remover. |
| Core              | Stateless request/response.                                                                                                                  |
| Descoberta        | server/discover quando o cliente desejar conhecer capabilities antes da primeira ação.                                                       |
| Formato           | JSON-RPC sobre HTTP, com schemas JSON para inputs/outputs.                                                                                   |
| Transporte remoto | Streamable HTTP / HTTP conforme a revisão suportada pelo SDK.                                                                                |
| Transporte local  | stdio somente via bridge opcional platform-mcp; não como servidor principal.                                                                 |
| Extensões         | Tasks e MCP Apps são opcionais; nenhuma função crítica pode depender exclusivamente de uma extensão não suportada pelo cliente.              |

## 3.2 Headers e roteamento

O edge deve preservar e, quando útil, observar headers de protocolo como MCP-Protocol-Version, Mcp-Method e Mcp-Name. Eles podem apoiar observabilidade e rate limiting por categoria, mas autorização final continua ocorrendo no Gateway.

## 3.3 Catálogo cacheável

A lista de tools deve ser determinística para uma dada combinação de versão + policy. Tools proibidas por configuração podem ser omitidas, porém recursos temporariamente indisponíveis devem preferir retornar um erro de capability/estado em vez de fazer o catálogo oscilar a cada segundo.

# 4. Experiência de conexão do usuário

## 4.1 Tela Agents & MCP

| **Área**      | **Conteúdo**                                                                               |
|---------------|--------------------------------------------------------------------------------------------|
| Connections   | Nome, cliente, usuário, Team, preset, recursos permitidos, status, último uso e expiração. |
| Connect       | URL MCP, botão de copiar, instrução genérica de conexão e fluxo OAuth.                     |
| Permissions   | Scopes, projetos/ambientes permitidos, produção read-only, exec/secret reveal/admin.       |
| Approvals     | Pendentes, aprovadas, negadas, expiradas, ator e operação resultante.                      |
| Activity      | Histórico de tool calls, Operation IDs, latência, erro e audit links.                      |
| Security      | Revogar grants, rotação, restrições de IP/organização e políticas de step-up.              |
| Compatibility | Versões MCP e recursos detectados para cada cliente.                                       |

## 4.2 Fluxo principal - Remote MCP + OAuth

| **Etapa** | **Experiência**                                                                            |
|-----------|--------------------------------------------------------------------------------------------|
| 1         | Usuário abre Settings \> Agents & MCP e seleciona Connect agent.                           |
| 2         | A plataforma mostra a URL canônica do MCP e presets de permissão.                          |
| 3         | Usuário adiciona a URL no MCP host.                                                        |
| 4         | O host descobre metadados de autorização e abre o login/consentimento.                     |
| 5         | Usuário autentica, escolhe Team, resource boundary e scopes permitidos.                    |
| 6         | Host recebe access token vinculado ao recurso MCP.                                         |
| 7         | Agente descobre tools/resources e pode operar imediatamente dentro dos limites concedidos. |
| 8         | A plataforma registra a conexão e mostra atividade/revogação em tempo real.                |

## 4.3 Bridge stdio opcional

Para hosts que não suportam MCP remoto/OAuth adequadamente, a plataforma pode distribuir um binário/CLI platform-mcp. O host inicia esse processo via stdio; a bridge autentica no Control Plane remoto e apenas traduz stdio \<-\> HTTPS. Tokens devem ficar no keychain do sistema operacional, nunca em arquivos plaintext por padrão.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>MCP Host<br />
| stdio<br />
v<br />
platform-mcp (local bridge)<br />
| HTTPS + OAuth/token seguro<br />
v<br />
https://control.example.com/mcp</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

# 5. Autenticação e autorização

## 5.1 OAuth para MCP remoto

O servidor MCP protegido deve atuar como OAuth resource server. O fluxo deve seguir a autorização MCP vigente: Protected Resource Metadata para discovery, PKCE S256, resource indicators/audience binding e validação estrita do issuer/audience. Access tokens nunca são aceitos por query string e não são repassados para APIs downstream.

## 5.2 Registro de clientes

A preferência deve ser Client ID Metadata Documents/preregistration compatível com a revisão atual do protocolo. Dynamic Client Registration pode existir apenas como compatibilidade quando necessário. O servidor de autorização deve proteger qualquer fetch de metadata contra SSRF.

## 5.3 Presets de permissão

| **Preset** | **Exemplos de acesso**                                                           | **Produção**                  |
|------------|----------------------------------------------------------------------------------|-------------------------------|
| Observer   | Listar estado, deploys, logs filtrados, métricas, operações e incidentes.        | Read-only                     |
| Developer  | Observer + alterar serviços/config em ambientes permitidos, builds e deploy HML. | Read-only por padrão          |
| Deployer   | Developer + deploy/rollback/promotion e domínios.                                | Write com approvals de policy |
| Operator   | Deployer + scale, restart, node maintenance, backups, incident actions.          | Write controlado              |
| Admin      | Administração do Team, providers e policies.                                     | Alto privilégio               |
| Custom     | Scopes e resource boundaries escolhidos explicitamente.                          | Conforme policy               |

## 5.4 Escopos propostos

| **Grupo**     | **Scopes**                                                               |
|---------------|--------------------------------------------------------------------------|
| Context       | team:read, project:read, environment:read                                |
| Services      | service:read, service:write, service:deploy, service:scale, service:exec |
| Build         | build:read, build:write                                                  |
| Networking    | domain:read, domain:write, certificate:read, certificate:write           |
| Vault         | secret:metadata, secret:write, secret:bind, secret:reveal                |
| Cluster       | cluster:read, node:read, node:operate, node:admin                        |
| Observability | logs:read, metrics:read, alert:write, incident:write                     |
| Recovery      | backup:read, backup:create, restore:plan, restore:execute                |
| Identity      | member:read, member:write, owner:transfer                                |
| Platform      | audit:read, operation:read, operation:cancel, instance:admin             |

## 5.5 Autorização efetiva

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>ALLOW = token_scope<br />
AND team_membership<br />
AND RBAC_role<br />
AND resource_boundary<br />
AND environment_policy<br />
AND feature_entitlement<br />
AND approval_policy<br />
AND current_resource_state</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

Uma tool pode aparecer no catálogo e ainda ser negada para um recurso específico. O retorno deve explicar o requisito ausente sem vazar informação sobre recursos fora do Team.

# 6. Modelo de approvals e ações destrutivas

## 6.1 Níveis de risco

| **Nível**               | **Exemplos**                                                                                       | **Execução**                                                                                 |
|-------------------------|----------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------|
| R0 - Read               | Listar projetos, status, métricas, operações.                                                      | Sem approval adicional.                                                                      |
| R1 - Reversível         | Criar HML service, ajustar env não sensível, scale dentro de policy.                               | Consentimento do MCP host + RBAC.                                                            |
| R2 - Alto impacto       | Deploy PROD, rollback PROD, drain Worker, renovar/alterar domínio crítico.                         | Policy pode exigir server-side Approval.                                                     |
| R3 - Crítico/destrutivo | Delete service PROD, restore, remover Manager, transferir OWNER, secret reveal, force-new-cluster. | Approval humano obrigatório + step-up quando aplicável; algumas ações nunca serão MCP tools. |

## 6.2 Approval server-side

Para operações configuradas como R2/R3, a chamada da tool pode retornar APPROVAL_REQUIRED com approval_id, resumo da mudança, recursos afetados, risco, expiração e approval_url. O agente informa o usuário, que aprova no host compatível ou na UI da plataforma. O agente consulta approval.get e reapresenta a ação com o approval_id aprovado.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Agent -&gt; services.delete(prod)<br />
Server -&gt; APPROVAL_REQUIRED { approval_id: "apr_123", approval_url: "..." }<br />
Human -&gt; aprova na UI / experiência suportada<br />
Agent -&gt; approvals.get(apr_123) =&gt; APPROVED<br />
Agent -&gt; services.delete(prod, approval_id: "apr_123")<br />
Server -&gt; Operation op_789</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 6.3 Auto-approval controlado

Service accounts podem receber políticas de auto-approval apenas para ações explicitamente delimitadas (por exemplo, scale entre 2 e 10 réplicas em HML). Nunca existe um switch global “agent may do anything”.

# 7. Superfície MCP - Tools

## 7.1 Convenção

Tools devem ser pequenas, tipadas e orientadas a intenção de produto. Nomes recomendados usam namespace, por exemplo services.deploy. Cada tool declara JSON Schema de entrada/saída e annotations de leitura/destrutividade/idempotência quando aplicável, mas o servidor não confia nessas hints para segurança.

## 7.2 Contexto, Teams, Projects e Environments

| **Tool**                              | **Função**                                                              |
|---------------------------------------|-------------------------------------------------------------------------|
| platform.whoami                       | Identidade, Team memberships, scopes e boundaries efetivos.             |
| platform.capabilities                 | Capabilities da plataforma e features habilitadas.                      |
| teams.list / teams.get                | Descoberta de Teams acessíveis.                                         |
| projects.list / projects.get          | Consultar projetos.                                                     |
| projects.create / update / delete     | Administrar projetos conforme RBAC.                                     |
| environments.list / get               | Consultar ambientes e cluster associado.                                |
| environments.create / update / delete | Administrar ambientes.                                                  |
| environments.promote                  | Promover configuração/release entre ambientes quando a policy permitir. |

## 7.3 Services, deploys e runtime

| **Tool**                | **Função**                                                                   |
|-------------------------|------------------------------------------------------------------------------|
| services.list / get     | Estado desejado + observado, health e release atual.                         |
| services.create         | Criar service por imagem, Git/source ou template suportado.                  |
| services.update         | Alterar config não sensível, recursos, portas e policy.                      |
| services.deploy         | Criar deployment de release/image/source.                                    |
| services.redeploy       | Reaplicar release corrente.                                                  |
| services.rollback       | Selecionar release anterior e iniciar rollback.                              |
| services.scale          | Alterar replicas ou autoscaling policy.                                      |
| services.restart        | Restart reconciliado das tasks.                                              |
| services.pause / resume | Suspender/retomar quando suportado.                                          |
| services.delete         | Excluir Service; normalmente R2/R3 em PROD.                                  |
| runtime.tasks           | Listar Tasks/replicas do Service.                                            |
| runtime.task_restart    | Reiniciar task de forma controlada.                                          |
| runtime.exec            | Abrir execução controlada; alto privilégio.                                  |
| runtime.terminal_create | Criar terminal temporário/WebSocket token; desabilitado por padrão para MCP. |

## 7.4 Source, Build, Artifact e Release

| **Tool**              | **Função**                                                                    |
|-----------------------|-------------------------------------------------------------------------------|
| sources.list          | Listar conexões Git/source.                                                   |
| sources.connect       | Iniciar autorização de provider e retornar URL/device flow quando necessário. |
| builds.list / get     | Status, commit, duração, cache e artifact.                                    |
| builds.create         | Disparar Railpack/BuildKit para source revision.                              |
| builds.cancel / retry | Cancelar ou repetir build.                                                    |
| builds.logs           | Ler logs por cursor e filtro.                                                 |
| artifacts.get         | Consultar digest OCI e metadados.                                             |
| releases.list / get   | Consultar releases imutáveis.                                                 |
| releases.promote      | Promover release entre environments compatíveis.                              |

## 7.5 Networking, domains e TLS

| **Tool**             | **Função**                                                                  |
|----------------------|-----------------------------------------------------------------------------|
| domains.list / get   | Consultar bindings, DNS e TLS.                                              |
| domains.add          | Vincular custom domain a Service/route.                                     |
| domains.verify       | Executar verificação DNS.                                                   |
| domains.remove       | Remover binding com safeguards.                                             |
| certificates.status  | Consultar versão, issuer e validade.                                        |
| certificates.renew   | Solicitar renovação/reconciliação.                                          |
| routes.list / update | Consultar/alterar host, path, port e protocol dentro das regras do produto. |

## 7.6 Vault e secrets

| **Tool**                | **Função**                                                                     |
|-------------------------|--------------------------------------------------------------------------------|
| secrets.list            | Somente metadata; nunca plaintext.                                             |
| secrets.get             | Metadata, versões e bindings autorizados.                                      |
| secrets.create          | Criar secret logical.                                                          |
| secrets.set_value       | Criar SecretVersion a partir de valor fornecido pelo usuário/agente.           |
| secrets.bind / unbind   | Associar versão a env/service key.                                             |
| secrets.promote_version | Alterar binding para versão específica.                                        |
| secrets.rotate          | Criar nova versão e coordenar atualização.                                     |
| secrets.reveal          | Capability excepcional; desligada por padrão, R3, step-up, audit e TTL mínimo. |

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th><strong>Regra de segurança<br />
</strong>O agente deve conseguir configurar e usar secrets sem precisar lê-los depois. O caminho feliz é write-only: receber o valor do usuário, criar a SecretVersion e bindar ao Service. Logs, tool results e audit nunca registram o plaintext.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 7.7 Cluster e nodes

| **Tool**                | **Função**                                                          |
|-------------------------|---------------------------------------------------------------------|
| clusters.list / get     | Status, quorum, capacity e ingress.                                 |
| nodes.list / get        | Role, availability, labels, capacity e health.                      |
| nodes.enrollment_create | Criar token/script de enrollment com TTL e uso único.               |
| nodes.drain / activate  | Maintenance controlada.                                             |
| nodes.promote / demote  | Alterar role Manager/Worker; policy de quorum obrigatória.          |
| nodes.remove            | Remover node com validações.                                        |
| clusters.reconcile      | Solicitar reconciliation/diagnóstico sem comando Docker arbitrário. |

## 7.8 Observability, incidents e operations

| **Tool**                            | **Função**                                            |
|-------------------------------------|-------------------------------------------------------|
| logs.read / search                  | Logs paginados, filtros e cursor; redaction aplicada. |
| metrics.query                       | Consultas pré-definidas/limitadas de métricas.        |
| alerts.list / acknowledge           | Consultar e reconhecer alertas.                       |
| incidents.list / get                | Consultar incidente e timeline.                       |
| incidents.create / update / resolve | Operar ciclo de incidente.                            |
| operations.list / get               | Acompanhar state machines.                            |
| operations.cancel                   | Solicitar cancelamento quando permitido.              |
| operations.wait                     | Polling bounded até estado terminal ou timeout curto. |

## 7.9 Backup, restore, identidade e administração

| **Tool**                     | **Função**                                         |
|------------------------------|----------------------------------------------------|
| backups.list / create        | Consultar/disparar backups.                        |
| snapshots.create / get       | Capturar/consultar snapshot lógico de Environment. |
| restore.plan                 | Gerar plano de restore sem executar.               |
| restore.execute              | Executar plano aprovado; R3.                       |
| members.list / invite        | Gerenciar membros conforme RBAC.                   |
| members.role_update / remove | Alterar membership.                                |
| ownership.transfer           | Transferir Team OWNER; R3 e step-up.               |
| audit.search                 | Buscar eventos de auditoria.                       |
| providers.list / test        | Consultar/testar providers.                        |
| instance.status              | Status da instalação para INSTANCE_ADMIN.          |
| instance.upgrade_plan        | Gerar plano de upgrade.                            |
| instance.upgrade_execute     | Executar upgrade conforme policy; R3.              |

# 8. Resources e Prompts

## 8.1 Resources read-only

Resources são apropriados para contexto reutilizável e navegável sem executar mutações. URIs devem ser opacas/estáveis e sempre autorizadas no momento da leitura.

| **Resource template**                | **Conteúdo**                                      |
|--------------------------------------|---------------------------------------------------|
| paas://teams/{team_id}               | Resumo do Team e permissões.                      |
| paas://projects/{project_id}         | Project + environments.                           |
| paas://environments/{environment_id} | Resumo do environment, cluster, services e drift. |
| paas://services/{service_id}         | Desired/actual state, release, health e routes.   |
| paas://deployments/{deployment_id}   | Timeline e resultado.                             |
| paas://operations/{operation_id}     | State machine, attempts e erro sanitizado.        |
| paas://clusters/{cluster_id}         | Capacity, nodes, ingress e health.                |
| paas://incidents/{incident_id}       | Timeline e status.                                |
| paas://runbooks/{runbook_id}         | Runbook operacional aplicável, sem credenciais.   |

## 8.2 Prompts opcionais

| **Prompt**             | **Objetivo**                                                    |
|------------------------|-----------------------------------------------------------------|
| deploy_application     | Coletar source, environment e requisitos e guiar deploy seguro. |
| diagnose_service       | Investigar health, logs, deploy, metrics e dependências.        |
| production_change_plan | Produzir plano antes de mudança de alto impacto.                |
| incident_triage        | Aplicar triagem consistente e referenciar Runbooks do Anexo E.  |
| restore_plan           | Gerar plano de restore com blast radius, RPO/RTO e approvals.   |

Prompts são conveniência, não autoridade. A segurança é determinada pelas tools e pelo Control Plane.

# 9. Operações longas, progresso e cancelamento

## 9.1 Operation como contrato canônico

Build, deploy, rollback, restore, certificate issuance, node maintenance e upgrade retornam rapidamente um objeto Operation. O agente usa operations.get/wait para acompanhar. A UI e o MCP observam a mesma state machine.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>{<br />
"operation_id": "op_01...",<br />
"kind": "DEPLOY_SERVICE",<br />
"status": "QUEUED",<br />
"resource": {"type":"service","id":"svc_..."},<br />
"created_at": "...",<br />
"links": {"resource":"paas://operations/op_01..."}<br />
}</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 9.2 Tasks extension

Quando cliente e servidor anunciarem a extensão MCP Tasks compatível, uma Operation pode ser mapeada a uma Task para polling/deferred result. O banco continua armazenando Operation como fonte de verdade; MCP Task é apenas uma representação de protocolo.

## 9.3 Cancellation

Cancelar uma chamada MCP não significa automaticamente cancelar uma Operation já persistida. Para trabalhos duráveis, o cliente deve usar operations.cancel ou o mecanismo de Task quando aplicável. O servidor registra a intenção de cancelamento e a state machine decide se o ponto atual é cancelável.

# 10. Logs, métricas e controle de contexto

Agentes têm context window finito. Tools de observabilidade devem retornar dados resumidos por padrão e permitir drill-down explícito.

| **Controle**       | **Regra**                                                                                       |
|--------------------|-------------------------------------------------------------------------------------------------|
| Logs               | limit, cursor, since, until, level, search; nunca retornar megabytes sem solicitação.           |
| Metrics            | Queries pré-definidas ou DSL limitada; ranges e cardinalidade limitados.                        |
| Build logs         | Chunk + cursor + linhas de erro relevantes.                                                     |
| Operation timeline | Eventos compactos e paginados.                                                                  |
| Redaction          | Secrets, tokens, Authorization headers e padrões sensíveis mascarados antes de chegar ao MCP.   |
| Untrusted text     | Conteúdo das apps/logs é tratado como dados não confiáveis e não como instruções para o agente. |

# 11. Contrato de respostas e erros

## 11.1 Structured content

Toda tool importante deve retornar structuredContent estável, com IDs e estados canônicos. Texto humano pode complementar, mas agentes não devem precisar parsear frases para encontrar operation_id, service_id ou status.

## 11.2 Error taxonomy

| **Código**             | **Significado**                        | **Ação esperada do agente**           |
|------------------------|----------------------------------------|---------------------------------------|
| AUTH_REQUIRED          | Token ausente/inválido.                | Reautenticar.                         |
| INSUFFICIENT_SCOPE     | Scope OAuth insuficiente.              | Solicitar step-up/novo consentimento. |
| FORBIDDEN              | RBAC/policy nega recurso.              | Explicar limite; não repetir.         |
| APPROVAL_REQUIRED      | Ação exige aprovação humana.           | Mostrar resumo/url e aguardar.        |
| APPROVAL_EXPIRED       | Approval inválido/expirado.            | Solicitar novo approval.              |
| NOT_FOUND              | Recurso não existe ou não é visível.   | Revalidar IDs/contexto.               |
| CONFLICT               | Estado mudou ou operação concorrente.  | Reconsultar estado.                   |
| VALIDATION_ERROR       | Argumentos inválidos.                  | Corrigir com fields estruturados.     |
| OPERATION_IN_PROGRESS  | Mutação equivalente/concorrente ativa. | Acompanhar Operation existente.       |
| DRIFT_BLOCKED          | Drift/policy impede mutação.           | Diagnosticar/reconciliar.             |
| RATE_LIMITED           | Quota/rate limit.                      | Backoff.                              |
| DEPENDENCY_UNAVAILABLE | Provider/cluster indisponível.         | Informar degradação e retry policy.   |

# 12. Auditoria e identidade do agente

## 12.1 Evento de auditoria mínimo

| **Campo**                     | **Exemplo**                                        |
|-------------------------------|----------------------------------------------------|
| actor_user_id                 | usr\_...                                           |
| mcp_client_id                 | https://agent.example/client.json                  |
| agent_connection_id           | agc\_...                                           |
| tool                          | services.deploy                                    |
| scope_set                     | service:deploy environment:read                    |
| resource                      | service svc\_... / env env\_...                    |
| arguments_digest              | Hash do payload após redaction.                    |
| approval_id                   | apr\_... quando aplicável.                         |
| operation_id                  | op\_... quando mutação assíncrona.                 |
| result                        | SUCCEEDED / DENIED / ERROR                         |
| ip / user_agent / client_info | Metadados permitidos pela política de privacidade. |
| trace_id                      | Correlação ponta a ponta.                          |

Secret plaintext, bearer tokens e credenciais nunca entram no audit log.

# 13. Modelo de dados adicional

| **Entidade**          | **Campos principais / papel**                                                              |
|-----------------------|--------------------------------------------------------------------------------------------|
| AgentConnection       | id, teamId, userId, name, preset, status, expiresAt, lastUsedAt.                           |
| AgentResourceBoundary | connectionId, projectId/environmentId/clusterId, accessMode.                               |
| OAuthGrant            | subject, clientId, resource, scopes, issuedAt, expiresAt, revokedAt, refresh metadata.     |
| AgentPolicy           | connectionId/teamId, prodMode, approvals, allowedTools/deniedTools, exec/reveal flags.     |
| ApprovalRequest       | id, actor, connectionId, action, target, summary, risk, expiresAt, status, approvedBy.     |
| McpExecutionAudit     | tool call identity, trace, redacted arguments digest, result, duration, operationId.       |
| McpClientProfile      | client id/name, metadata URL, protocol versions seen, trust/admin notes quando necessário. |

## 13.1 Constraints

> **•** AgentConnection pertence exatamente a um Team e a um usuário/service account.
>
> **•** Grant revogado não pode ser reutilizado, mesmo com token de refresh antigo.
>
> **•** Approval é single-use e ligado ao digest da ação; mudar argumentos invalida aprovação.
>
> **•** Resource boundaries não podem apontar para recursos de outro Team.
>
> **•** secret:reveal, owner:transfer, instance:admin e runtime.exec nunca entram em presets comuns.

# 14. UI detalhada de Agents & MCP

## 14.1 Lista de conexões

Colunas: nome, usuário, cliente, preset, Team, boundary, PROD mode, último uso, expiração e status. Ações: Details, Edit policy, Revoke, Rotate/reconnect.

## 14.2 Wizard New Agent Connection

| **Passo**                  | **Campos**                                                              |
|----------------------------|-------------------------------------------------------------------------|
| 1\. Identity               | Nome amigável e tipo: personal agent / service account.                 |
| 2\. Scope                  | Team e projects/environments acessíveis.                                |
| 3\. Preset                 | Observer, Developer, Deployer, Operator, Admin ou Custom.               |
| 4\. Production             | No access / Read-only / Write with approval / Custom.                   |
| 5\. Sensitive capabilities | Exec, secret reveal, ownership e instance admin - todos off por padrão. |
| 6\. Lifetime               | Expiração e sessão/refresh policy.                                      |
| 7\. Connect                | URL MCP e instruções OAuth/stdio bridge.                                |
| 8\. Verify                 | Tool de whoami executada e capability report exibido.                   |

## 14.3 Connection details

Tabs recomendadas: Overview, Permissions, Resource Access, Approvals, Activity, OAuth/Security e Compatibility. O usuário deve conseguir revogar a conexão com um clique e ver imediatamente que chamadas futuras falham.

# 15. Casos de uso MCP

| **ID** | **Caso de uso**                        | **Resultado**                                            |
|--------|----------------------------------------|----------------------------------------------------------|
| MCP-01 | Conectar agente via OAuth              | Agente autenticado e limitado ao Team/scopes escolhidos. |
| MCP-02 | Descobrir projetos/ambientes           | Agente encontra IDs sem o usuário copiá-los.             |
| MCP-03 | Criar Project + HML Environment        | Recursos criados e auditados.                            |
| MCP-04 | Criar Service por image                | Operation converge para Service healthy.                 |
| MCP-05 | Conectar Git e disparar Railpack build | Artifact OCI criado.                                     |
| MCP-06 | Deploy em HML                          | Release ativa e health validado.                         |
| MCP-07 | Promover release para PROD             | Approval/policy aplicada e deploy rastreado.             |
| MCP-08 | Rollback PROD                          | Release anterior restaurada via Operation.               |
| MCP-09 | Criar secret e bindar                  | Valor nunca é retornado depois da escrita.               |
| MCP-10 | Adicionar domínio custom               | DNS/TLS acompanha até READY.                             |
| MCP-11 | Escalar Service                        | desired replicas alteradas e reconciliadas.              |
| MCP-12 | Diagnosticar service unhealthy         | Agente correlaciona status, logs, metrics e deploy.      |
| MCP-13 | Investigar build failed                | Agente busca trecho relevante e sugere correção.         |
| MCP-14 | Acompanhar Operation longa             | Polling/task até terminal state.                         |
| MCP-15 | Drain de Worker                        | Valida capacity e inicia manutenção aprovada.            |
| MCP-16 | Criar snapshot/backup                  | Backup registrado com status final.                      |
| MCP-17 | Planejar restore                       | Plano gerado sem mudança de estado.                      |
| MCP-18 | Executar restore                       | Approval R3 + Operation + validação.                     |
| MCP-19 | Consultar auditoria                    | Retorna eventos autorizados e redigidos.                 |
| MCP-20 | Revogar conexão do agente              | Tokens/grants deixam de funcionar imediatamente.         |

# 16. Exemplos de jornadas agent-first

## 16.1 “Suba esta aplicação em HML”

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>1. platform.whoami<br />
2. projects.list / environments.list<br />
3. sources.connect (se necessário)<br />
4. services.create<br />
5. builds.create<br />
6. operations.get/wait<br />
7. services.deploy<br />
8. operations.get/wait<br />
9. services.get + logs.read<br />
10. Resposta final com URL, release e health</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 16.2 “Promova exatamente o que está em HML para PROD”

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>1. releases.get(HML current)<br />
2. environment policy / diff<br />
3. releases.promote(target=PROD, digest=&lt;mesmo digest&gt;)<br />
4. Se policy exigir: APPROVAL_REQUIRED<br />
5. Após approval: deployment Operation<br />
6. health gate<br />
7. Resposta com release digest e rollback candidate</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 16.3 “Minha API está fora do ar, descubra o que aconteceu”

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>1. services.get<br />
2. deployments.list (últimos)<br />
3. runtime.tasks<br />
4. logs.search(error/fatal)<br />
5. metrics.query(latency/error/cpu/memory)<br />
6. incidents.list / alerts.list<br />
7. Correlacionar timeline<br />
8. Propor ação; executar somente se scopes/policy permitirem</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

# 17. Segurança específica de agentes

## 17.1 Prompt injection em dados operacionais

Logs, README, commit messages, labels, container output e respostas de aplicações podem conter texto malicioso tentando instruir o modelo. O MCP deve marcar esses campos como dados e manter tool descriptions/instructions controladas pela plataforma. O servidor nunca deve interpretar texto de logs como comandos.

## 17.2 SSRF e URLs fornecidas pelo agente

Tools que aceitem repository URL, webhook URL, provider metadata ou callback devem usar allowlists/normalização e as proteções SSRF do Threat Model. O fato de uma URL ter sido sugerida por um modelo não muda o nível de confiança.

## 17.3 Terminal e exec

Exec é o maior amplificador de risco porque aproxima o agente de código arbitrário. Por padrão fica fora dos presets. Quando habilitado, deve ter TTL curto, command/session audit, resource boundary e bloqueio para managers/control-plane containers.

## 17.4 “Tudo pelo agente” não significa “sem controles”

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th><strong>Princípio<br />
</strong>A meta é cobertura funcional, não autoridade irrestrita. O agente pode iniciar qualquer fluxo de produto que a conexão permita; ações críticas ainda podem exigir aprovação humana. Isso preserva a experiência agent-first sem transformar um prompt mal interpretado em incidente de infraestrutura.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

# 18. Implementação recomendada se o Control Plane usar Rails

## 18.1 Stack

Se a decisão final for Rails, a implementação pode usar o SDK Ruby oficial do MCP (gem mcp), que possui servidor/cliente, integração Rails e suporte ao protocolo atual. O Gateway pode viver no mesmo monólito modular do Control Plane, compartilhando Application Services, policies, SQL transactions e observabilidade.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Rails Control Plane<br />
app/mcp/<br />
server.rb<br />
tools/<br />
resources/<br />
prompts/<br />
authorization/<br />
serializers/<br />
app/commands/ &lt;- reutilizado<br />
app/queries/ &lt;- reutilizado<br />
app/policies/ &lt;- reutilizado<br />
app/operations/ &lt;- reutilizado</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 18.2 Regra de dependência

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>MCP Tool -&gt; Command/Query -&gt; Domain/Application -&gt; DB/Operation<br />
<br />
NUNCA:<br />
MCP Tool -&gt; Docker API<br />
MCP Tool -&gt; SQL ad hoc para mutações<br />
MCP Tool -&gt; lógica duplicada da API/UI</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 18.3 Deploy do Gateway

O endpoint /mcp pode rodar nas mesmas réplicas web do Control Plane ou em process type dedicado se houver necessidade de scaling/rate limit independente. Como a revisão 2026-07-28 é stateless, múltiplas réplicas podem operar atrás do Traefik sem affinity de sessão.

# 19. Observabilidade do MCP

| **Métrica**                  | **Uso**                                                   |
|------------------------------|-----------------------------------------------------------|
| mcp_requests_total           | Volume por method/tool/status.                            |
| mcp_request_duration_seconds | p50/p95/p99 por tool.                                     |
| mcp_tool_denied_total        | Scopes/RBAC/policy/approval denials.                      |
| mcp_approval_required_total  | Frequência por tool e ambiente.                           |
| mcp_operation_started_total  | Mutações originadas por agentes.                          |
| mcp_protocol_version_total   | Versões/clientes em uso para depreciação.                 |
| mcp_rate_limited_total       | Abuso ou loops de agente.                                 |
| mcp_active_connections       | Grants/connections usados recentemente, não sessões HTTP. |

Trace ID deve atravessar MCP Gateway -\> Command -\> Operation -\> Reconciler -\> Executor sempre que a ação gerar trabalho interno.

# 20. Testes e conformidade

| **Categoria** | **Obrigatório**                                                                                    |
|---------------|----------------------------------------------------------------------------------------------------|
| Protocol      | Conformance suite do MCP/SDK escolhido; requests inválidos e versões suportadas.                   |
| OAuth         | PKCE, issuer/audience/resource, expiry, revocation, insufficient_scope e CSRF/redirect validation. |
| Authorization | Matriz scopes x RBAC x boundary x environment policy.                                              |
| Approvals     | Digest binding, single-use, expiry, deny, replay e alteração de argumentos.                        |
| Tools         | Schema validation, idempotência, errors estruturados e ausência de bypass.                         |
| Secrets       | Nenhum plaintext em result/log/audit/trace.                                                        |
| HA            | Duas ou mais réplicas MCP atrás de LB; qualquer request em qualquer instância.                     |
| Load          | tools/list/cache, reads e bursts de agents sem afetar Control Plane crítico.                       |
| Adversarial   | Prompt injection em logs, URLs SSRF, tool loops, enumeração cross-team.                            |
| E2E           | Casos MCP-01..MCP-20 com agentes/clients de referência.                                            |

# 21. Rollout recomendado

| **Fase**         | **Escopo**                                                                       | **Gate**                                           |
|------------------|----------------------------------------------------------------------------------|----------------------------------------------------|
| F1 - Read-only   | whoami, teams/projects/envs/services, operations, logs, metrics, audit limitado. | Zero cross-team leak; OAuth/RBAC completos.        |
| F2 - Safe writes | Project/Environment/Service HML, config, scale dentro de policy, builds.         | Idempotência + audit + rollback.                   |
| F3 - Delivery    | Deploy, rollback, promotion, domains/TLS, secret write/bind.                     | Approvals e production policy.                     |
| F4 - Operations  | Node maintenance, backups, incidents, restore plan.                              | Chaos/DR tests.                                    |
| F5 - Privileged  | Exec, restore execute, ownership/admin capabilities selecionadas.                | Step-up, R3 approval e security review específica. |

# 22. Critérios de aceite

> **•** AC-MCP-01 - Usuário conecta um agente remoto usando apenas a URL do MCP e OAuth, sem copiar token manual no fluxo padrão.
>
> **•** AC-MCP-02 - O MCP nunca precisa de docker.sock e não possui acesso direto ao Docker Engine.
>
> **•** AC-MCP-03 - Qualquer tool call é limitada por scopes, RBAC, resource boundary e environment policy.
>
> **•** AC-MCP-04 - PROD pode ser read-only mesmo quando a conexão tem write em HML.
>
> **•** AC-MCP-05 - Tools de mutação retornam Operation ID quando o trabalho é assíncrono.
>
> **•** AC-MCP-06 - O agente consegue acompanhar uma Operation até estado terminal sem manter conexão HTTP longa obrigatória.
>
> **•** AC-MCP-07 - Deploy e rollback preservam artifact/release por digest imutável.
>
> **•** AC-MCP-08 - Logs e tool results passam por redaction antes de sair do Control Plane.
>
> **•** AC-MCP-09 - Secret write/bind funciona sem revelar plaintext em leitura posterior.
>
> **•** AC-MCP-10 - secret:reveal e runtime.exec estão desabilitados por padrão.
>
> **•** AC-MCP-11 - Ações R3 exigem approval humano/step-up conforme policy e approval é ligado ao digest da ação.
>
> **•** AC-MCP-12 - Revogar AgentConnection/Grant bloqueia novas chamadas rapidamente e de forma auditável.
>
> **•** AC-MCP-13 - Cross-team enumeration não revela se um ID existe fora do boundary.
>
> **•** AC-MCP-14 - O catálogo de tools possui schemas estáveis e versionados.
>
> **•** AC-MCP-15 - Existe bridge stdio opcional para hosts sem suporte adequado a MCP remoto.
>
> **•** AC-MCP-16 - O Gateway escala horizontalmente sem sticky session na baseline 2026-07-28.
>
> **•** AC-MCP-17 - Audit correlaciona user, MCP client, tool, approval e Operation.
>
> **•** AC-MCP-18 - Os 20 casos de uso MCP principais possuem E2E automatizado.
>
> **•** AC-MCP-19 - O MCP possui rate limits e proteção contra loops/abuso de agentes.
>
> **•** AC-MCP-20 - A experiência UI permite visualizar, editar e revogar conexões e approvals.
>
> **•** AC-MCP-21 - Falhas de provider/cluster retornam erro estruturado sem induzir o agente a bypass operacional.
>
> **•** AC-MCP-22 - Nenhuma regra de negócio existe somente no MCP; API/UI e MCP compartilham Application Services.

# 23. Referências técnicas

As decisões de protocolo deste anexo foram alinhadas à documentação oficial disponível em setembro de 2026:

> **•** Model Context Protocol - revisão 2026-07-28: https://blog.modelcontextprotocol.io/posts/2026-07-28/
>
> **•** Model Context Protocol - especificação e documentação: https://modelcontextprotocol.io/specification/latest
>
> **•** MCP Ruby SDK oficial: https://ruby.sdk.modelcontextprotocol.io/
>
> **•** Repositório do MCP Ruby SDK: https://github.com/modelcontextprotocol/ruby-sdk

A revisão 2026-07-28 tornou o core stateless, adicionou server/discover, headers de roteamento e endureceu autorização. O SDK Ruby oficial já possui suporte ao protocolo moderno e integração para Rails. Como MCP continua evoluindo, a versão suportada deve ser tratada como compatibility contract testado, não como detalhe hardcoded espalhado pelo domínio.

# 24. Decisão final

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th><strong>Decisão consolidada<br />
</strong>A plataforma terá um MCP oficial, remoto e OAuth-first, como interface de primeira classe do Control Plane. O objetivo é paridade funcional com a UI para operações autorizadas, mantendo Desired State, Operations, RBAC, approvals, audit e segurança como fronteiras obrigatórias. O MCP aumenta a forma de operar a plataforma; ele não aumenta a autoridade de quem o utiliza.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

Com este anexo, o modelo agent-first passa a fazer parte da especificação arquitetural: qualquer feature futura relevante deve avaliar três superfícies em conjunto - UI, API e MCP - todas apoiadas no mesmo domínio e nos mesmos contratos internos.
