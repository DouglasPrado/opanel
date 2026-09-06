---
document: "04"
title: "Identidade, Times e Segurança"
type: "architecture"
status: "approved"
source: "docx"
---

**PLATAFORMA PAAS  
CLUSTER-FIRST**

**Documento técnico consolidado - Parte 4**

Identidade, Teams, ownership, RBAC, auditoria, quotas, onboarding e segurança do produto

| **Campo**       | **Definição**                                                                                                                                                                                      |
|-----------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Status          | Documento vivo - v0.4                                                                                                                                                                              |
| Data            | 05 de setembro de 2026                                                                                                                                                                             |
| Escopo          | Definir quem pode administrar a plataforma, como Teams e permissões funcionam e como operações sensíveis são protegidas e auditadas                                                                |
| Premissas       | Cluster-first; múltiplos Teams; Projects e Environments; Vault próprio versionado; Swarm Secrets; aplicações stateless; stateful externo                                                           |
| Decisão central | O primeiro usuário do Team é OWNER. Existe exatamente um OWNER ativo por Team. A propriedade pode ser transferida para um ADMIN existente e a transferência é explícita, reautenticada e auditada. |

## Resumo executivo

Esta parte transforma a plataforma de um painel técnico em um produto multiusuário governável. O sistema precisa separar identidade humana, propriedade do Team, administração da instalação e permissões operacionais. O modelo escolhido evita que acesso ao painel implique automaticamente acesso irrestrito a todos os clusters, environments, secrets e operações destrutivas.

| **Princípio:** Propriedade e administração não são sinônimos. TEAM_OWNER governa um Team. INSTANCE_ADMIN governa a instalação. No primeiro bootstrap, a mesma pessoa pode receber ambos os papéis; depois eles podem divergir. |
|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|

# 1. Objetivos e princípios

## 1.1 Resultados esperados

- Cadastro e autenticação de usuários com sessões revogáveis e suporte a MFA.

- Teams como tenant principal e unidade de ownership, membership, quotas e auditoria.

- Exatamente um OWNER ativo por Team, com transferência explícita para um ADMIN.

- RBAC por escopo, evitando que um papel global simples conceda acesso excessivo.

- Audit Log imutável para ações administrativas e operacionais relevantes.

- Reautenticação para operações críticas como transferir ownership, revelar secrets, excluir cluster ou rotacionar Recovery Key.

- Onboarding seguro do cluster sem expor Docker API ou docker.sock publicamente.

- Quotas e guardrails para impedir abuso acidental de CPU, memória, réplicas, builds e logs.

- Separação entre credenciais humanas, API tokens e identidades de automação.

## 1.2 Princípios

- Least privilege: cada usuário recebe apenas o mínimo necessário para sua função.

- Deny by default: permissões não concedidas explicitamente são negadas.

- Scope first: autorização considera Team, Cluster, Project, Environment e Service.

- No silent privilege transfer: mudança de OWNER nunca é implícita.

- Every critical action is attributable: toda ação sensível deve identificar actor, origem, alvo e resultado.

- Infrastructure credentials never reach the browser unless o próprio fluxo exigir revelação explícita e autorizada.

# 2. Modelo de tenancy e hierarquia

O Team é o tenant principal do produto. Projects representam aplicações/negócios; Clusters representam infraestrutura; Environments ligam Project a Cluster. Essa separação permite que produção e homologação usem clusters diferentes sem duplicar Projects.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>User<br />
|<br />
+--&gt; Membership --&gt; Team<br />
|<br />
+--&gt; Projects<br />
| +--&gt; Environments<br />
| +--&gt; Services<br />
|<br />
+--&gt; Clusters<br />
+--&gt; Nodes<br />
<br />
Environment -----&gt; Cluster<br />
Service ---------&gt; Environment</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

| **Entidade** | **Ownership / papel**                                                |
|--------------|----------------------------------------------------------------------|
| User         | Identidade humana global da instalação.                              |
| Team         | Tenant lógico. Possui exatamente um OWNER e N membros.               |
| Membership   | Relaciona User a Team e define role e estado.                        |
| Project      | Agrupa Environments da mesma aplicação.                              |
| Environment  | Instância isolada do Project, como production ou homolog.            |
| Cluster      | Swarm pertencente ao Team; pode hospedar múltiplos Environments.     |
| Service      | Workload implantado dentro de um Environment.                        |
| Vault        | Biblioteca versionada de secrets do Team, referenciada por bindings. |

# 3. Bootstrap e primeiro usuário

## 3.1 Primeira instalação

Quando uma instalação ainda não possui usuários, o primeiro cadastro conclui o bootstrap. Ele cria a identidade inicial, o primeiro Team e recebe os papéis necessários para operar a instalação.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Fresh installation<br />
|<br />
v<br />
First registration<br />
|<br />
+--&gt; User created<br />
|<br />
+--&gt; Initial Team created<br />
|<br />
+--&gt; Membership role = OWNER<br />
|<br />
+--&gt; Instance role = INSTANCE_ADMIN<br />
|<br />
v<br />
Platform ready</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

| **Regra:** Somente o bootstrap da instalação concede INSTANCE_ADMIN automaticamente. Criar um novo Team depois do bootstrap concede TEAM_OWNER ao criador daquele Team, mas não INSTANCE_ADMIN. |
|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|

## 3.2 Um único OWNER por Team

- Todo Team deve possuir exatamente um membership com role OWNER e status ACTIVE.

- Não pode existir Team ativo sem OWNER.

- Não pode existir mais de um OWNER ativo simultaneamente.

- OWNER não pode remover a si mesmo nem reduzir seu próprio papel diretamente.

- Para sair do Team, o OWNER precisa primeiro transferir ownership.

- Se o OWNER estiver suspenso por procedimento de segurança, o Team entra em estado OWNERSHIP_RECOVERY_REQUIRED até resolução administrativa.

# 4. Transferência de ownership

## 4.1 Regra escolhida

| **Decisão:** A propriedade pode ser transferida apenas para um usuário que já seja membro ACTIVE do Team e tenha role ADMIN. Após a transferência, o antigo OWNER passa automaticamente para ADMIN. |
|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|

## 4.2 Fluxo normal

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>OWNER<br />
|<br />
| Manage Team &gt; Transfer ownership<br />
v<br />
Select existing ADMIN<br />
|<br />
v<br />
Reauthenticate OWNER<br />
(password/passkey/MFA)<br />
|<br />
v<br />
Show irreversible-impact confirmation<br />
|<br />
v<br />
Atomic transaction<br />
|------------------------------|<br />
| new ADMIN -&gt; OWNER |<br />
| old OWNER -&gt; ADMIN |<br />
| ownershipTransferredAt |<br />
| audit event |<br />
|------------------------------|<br />
v<br />
Notify both users</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 4.3 Regras transacionais

| **Regra**       | **Comportamento**                                                                         |
|-----------------|-------------------------------------------------------------------------------------------|
| Target          | Precisa ser Membership ACTIVE com role ADMIN no mesmo Team.                               |
| Atomicidade     | Novo OWNER e rebaixamento do antigo OWNER ocorrem na mesma transação.                     |
| Concorrência    | Lock/constraint impede duas transferências simultâneas.                                   |
| Reautenticação  | OWNER comprova identidade novamente antes da execução.                                    |
| MFA             | Se MFA estiver habilitado, deve ser exigido no step-up authentication.                    |
| Audit           | Registrar oldOwnerId, newOwnerId, teamId, IP/origem, sessionId e timestamp.               |
| Notificação     | Antigo e novo OWNER recebem notificação imediata.                                         |
| Rollback lógico | Não existe undo silencioso; para devolver ownership é feita nova transferência explícita. |

## 4.4 Recuperação excepcional

Se o OWNER perdeu acesso definitivamente, não é aceitável alterar ownership diretamente por SQL na operação normal. A plataforma deve possuir um fluxo excepcional de recuperação executável somente por INSTANCE_ADMIN, com evidência de auditoria e notificações aos membros administrativos do Team.

| **Cuidado:** Recuperação administrativa é um mecanismo de emergência e não substitui a transferência normal. Deve ser claramente marcada no Audit Log como OWNERSHIP_RECOVERY. |
|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|

# 5. Roles e membership

## 5.1 Roles base do Team

| **Role**  | **Finalidade**                                                                                |
|-----------|-----------------------------------------------------------------------------------------------|
| OWNER     | Governança máxima do Team; billing/ownership, membros, clusters, projects, Vault e políticas. |
| ADMIN     | Administração operacional completa, exceto ações exclusivas de ownership.                     |
| DEVELOPER | Deploy, restart, logs, métricas e operação de serviços dentro dos escopos permitidos.         |
| VIEWER    | Leitura de recursos, status, logs permitidos e métricas; sem mutações.                        |
| BILLING   | Acesso financeiro/consumo sem acesso operacional ou secrets; opcional numa fase posterior.    |

## 5.2 Lifecycle do membership

- INVITED: convite criado, usuário ainda não aceitou.

- ACTIVE: usuário pode autenticar e exercer permissões.

- SUSPENDED: acesso ao Team bloqueado sem apagar histórico.

- REMOVED: membership encerrado; auditoria permanece.

- Convites devem expirar e ser de uso único.

- Reenvio de convite revoga token anterior.

# 6. RBAC por escopo

Role sozinha não deve responder toda a autorização. O mesmo usuário pode ser ADMIN de um Team, mas ter restrições adicionais a um Environment sensível; ou ser DEVELOPER somente em homologação. O autorizador avalia role + scope + resource + action.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>authorize(actor, action, resource)<br />
|<br />
+--&gt; membership active?<br />
+--&gt; role permits action?<br />
+--&gt; scope includes resource?<br />
+--&gt; environment restrictions?<br />
+--&gt; step-up auth required?<br />
+--&gt; policy/guardrail permits?<br />
|<br />
v<br />
ALLOW / DENY</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 6.1 Escopos

| **Scope**   | **Exemplo**                                                       |
|-------------|-------------------------------------------------------------------|
| TEAM        | Gerenciar membros, Vault, quotas e configurações gerais.          |
| CLUSTER     | Adicionar/drain/remove node, alterar ingress, configurar cluster. |
| PROJECT     | Criar/editar Project e seus Environments.                         |
| ENVIRONMENT | Operar somente production, homolog ou outro Environment.          |
| SERVICE     | Deploy/restart/logs de um Service específico.                     |
| VAULT       | Criar/versionar/referenciar/revelar secrets conforme permissão.   |

## 6.2 Matriz inicial de permissões

| **Ação**                  | **OWNER** | **ADMIN**      | **DEVELOPER**  | **VIEWER** |
|---------------------------|-----------|----------------|----------------|------------|
| Transferir ownership      | Sim       | Não            | Não            | Não        |
| Excluir Team              | Sim       | Não            | Não            | Não        |
| Gerenciar membros/roles   | Sim       | Sim\*          | Não            | Não        |
| Adicionar/remover Cluster | Sim       | Sim            | Não            | Não        |
| Drain/remove Node         | Sim       | Sim            | Não            | Não        |
| Criar Project/Environment | Sim       | Sim            | Sim\*          | Não        |
| Deploy / rollback         | Sim       | Sim            | Sim\*          | Não        |
| Restart / scale Service   | Sim       | Sim            | Sim\*          | Não        |
| Ver logs e métricas       | Sim       | Sim            | Sim\*          | Sim\*      |
| Editar secrets            | Sim       | Sim            | Sim\*          | Não        |
| Revelar secret production | Sim       | Sim\*          | Não por padrão | Não        |
| Rotacionar Recovery Key   | Sim       | Não por padrão | Não            | Não        |

\* Dependente de scope/policy do Team. ADMIN nunca pode promover alguém para OWNER; somente transferência explícita pelo OWNER.

# 7. INSTANCE_ADMIN x TEAM_OWNER

## 7.1 Por que separar

Em uma instalação self-hosted, existe uma responsabilidade acima dos Teams: administrar a própria instância. Essa identidade não deve ser confundida com o OWNER de um Team, principalmente quando a instalação futuramente hospedar vários Teams.

| **Papel**      | **Pode**                                                                                                    |
|----------------|-------------------------------------------------------------------------------------------------------------|
| INSTANCE_ADMIN | Configura instalação, bootstrap, integrações globais, manutenção, recovery excepcional e políticas globais. |
| TEAM_OWNER     | Governa somente seu Team e os recursos pertencentes a ele.                                                  |
| TEAM_ADMIN     | Administra operação do Team sem ownership.                                                                  |

| **Regra:** Transferir TEAM_OWNER não transfere INSTANCE_ADMIN. Se o usuário que era OWNER também for INSTANCE_ADMIN, ele continua INSTANCE_ADMIN até uma operação separada alterar esse papel. |
|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|

# 8. Autenticação e sessões

## 8.1 Métodos

- E-mail + senha forte como baseline inicial.

- MFA TOTP como proteção recomendada para OWNER, ADMIN e INSTANCE_ADMIN.

- Passkeys/WebAuthn como evolução preferencial para autenticação resistente a phishing.

- OIDC/SAML podem entrar posteriormente para organizações empresariais.

## 8.2 Sessões

| **Componente**         | **Regra**                                                                                            |
|------------------------|------------------------------------------------------------------------------------------------------|
| Session                | Identificador aleatório, revogável e associado a User, device metadata e timestamps.                 |
| Access cookie/token    | Curta duração; não deve carregar autorização definitiva por longos períodos.                         |
| Refresh/session record | Persistido server-side para permitir logout remoto e revogação.                                      |
| Session list           | Usuário vê dispositivos/sessões e pode revogar individualmente.                                      |
| Sensitive change       | Mudança de senha, MFA ou recovery invalida sessões conforme política.                                |
| Suspension             | Suspender membership remove acesso ao Team imediatamente sem necessariamente encerrar sessão global. |

## 8.3 Step-up authentication

Operações de alto impacto devem exigir uma comprovação de identidade recente, mesmo que o usuário já esteja autenticado.

- Transferir ownership.

- Rotacionar/gerar Recovery Key.

- Revelar secret sensível de production.

- Excluir Cluster, Team, Project de produção ou recursos persistentes.

- Criar token de API com privilégio elevado.

- Alterar MFA ou credenciais críticas.

# 9. API tokens e identidades de automação

Pipelines e integrações não devem reutilizar sessão humana. A plataforma deve emitir credenciais próprias com escopo e expiração.

| **Tipo**              | **Uso**                                                                                                  |
|-----------------------|----------------------------------------------------------------------------------------------------------|
| Personal Access Token | Automação em nome de um User; deve possuir scopes e poder ser revogado.                                  |
| Service Account       | Identidade não humana pertencente ao Team.                                                               |
| Deploy Token          | Credencial limitada a um Project/Environment para disparar deployments.                                  |
| Webhook Secret        | Validação de eventos externos; separado de credenciais de usuário.                                       |
| Registry Credential   | Credencial de pull/push usada internamente pelo build/runtime; nunca retornada ao frontend após criação. |

- Tokens são exibidos em plaintext somente no momento da criação.

- No banco, armazenar hash do token quando validação por hash for suficiente.

- Exibir prefixo/últimos caracteres para identificação sem guardar plaintext.

- Todo token precisa de owner lógico, scopes, createdAt, lastUsedAt e revokedAt.

- Tokens inativos ou expirados devem ser rejeitados mesmo que ainda existam fisicamente.

# 10. Audit Log

## 10.1 Eventos obrigatórios

- Login, logout relevante, falha de MFA e revogação de sessão.

- Convite, alteração de role, suspensão e remoção de membro.

- Transferência ou recuperação de ownership.

- Criação, atualização e exclusão de Cluster/Node/Project/Environment/Service.

- Deploy, rollback, scale, restart, drain e exec/terminal.

- Criação de SecretVersion, alteração de binding e revelação de secret.

- Geração/rotação de Recovery Key.

- Criação/revogação de tokens de API.

- Mudanças de quotas, políticas e configurações de segurança.

## 10.2 Estrutura do evento

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>AuditEvent<br />
- id<br />
- teamId<br />
- actorType: USER | SERVICE_ACCOUNT | SYSTEM<br />
- actorId<br />
- action<br />
- resourceType<br />
- resourceId<br />
- environmentId?<br />
- requestId<br />
- sessionId?<br />
- sourceIp?<br />
- userAgent?<br />
- metadata (redacted)<br />
- result: SUCCESS | DENIED | FAILED<br />
- createdAt</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

| **Crítico:** Audit Log nunca deve registrar plaintext de secret, token, senha, private key ou Recovery Key. Metadata sensível precisa ser redigida antes de persistir. |
|------------------------------------------------------------------------------------------------------------------------------------------------------------------------|

# 11. Vault e autorização

A Parte 1 definiu o Vault versionado. Aqui a preocupação é quem pode manipular cada operação. Criar uma nova versão, alterar binding e revelar plaintext são permissões diferentes.

| **Operação**                           | **Permissão sugerida** |
|----------------------------------------|------------------------|
| Listar nomes/metadados                 | vault.read_metadata    |
| Criar Secret                           | vault.create           |
| Criar SecretVersion                    | vault.version.create   |
| Alterar binding de Environment/Service | vault.bind             |
| Revelar plaintext                      | vault.reveal           |
| Rotacionar Recovery Key                | vault.recovery.rotate  |
| Excluir secret não utilizada           | vault.delete           |

## 11.1 Production como boundary adicional

Mesmo um DEVELOPER autorizado a deploy em homologação não deve herdar acesso a secrets de produção. Permissões de Environment podem restringir reveal/edit/bind independentemente do role base.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>DEVELOPER<br />
|<br />
+--&gt; Albert / Homolog<br />
| deploy = allow<br />
| logs = allow<br />
| secret edit = allow<br />
|<br />
+--&gt; Albert / Production<br />
deploy = allow (optional)<br />
logs = allow<br />
secret reveal = DENY<br />
recovery key = DENY</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

# 12. Recovery Key e governança

A Recovery Key continua pertencendo à segurança do Team/instalação e deve ser tratada como operação de alto impacto. A UI pode facilitar armazenamento, mas não deve permitir exibição recorrente da chave original.

- Gerar durante onboarding ou habilitação do Vault.

- Mostrar apenas uma vez.

- Permitir download de arquivo de recuperação e impressão, sem armazenar plaintext no servidor.

- Exigir confirmação de que foi salva e uma verificação parcial.

- Rotação exige OWNER + step-up authentication.

- Rotação cria nova Recovery Key e rewrap da master key; não precisa recriptografar todas as SecretVersions.

- Auditar geração, verificação e rotação sem registrar a chave.

# 13. Quotas e guardrails

Quotas não são apenas billing; são proteção operacional. Um erro de configuração não deve permitir que um único usuário crie milhares de réplicas, consuma toda memória do cluster ou gere builds ilimitados.

| **Quota / guardrail** | **Exemplos**                                                |
|-----------------------|-------------------------------------------------------------|
| Clusters              | Máximo de clusters por Team.                                |
| Nodes                 | Máximo de nodes registrados por Cluster.                    |
| Projects/Environments | Limites administrativos conforme plano/política.            |
| Services              | Quantidade por Environment/Team.                            |
| Replicas              | Máximo por Service e soma máxima por Team.                  |
| CPU / RAM             | Limites máximos solicitáveis por Service e total reservado. |
| Concurrent builds     | Evita saturar builders.                                     |
| Deploy frequency      | Rate limit para automações mal configuradas.                |
| Logs retention        | Retenção e volume ingerido.                                 |
| Vault                 | Quantidade de secrets/versions ou tamanho máximo por valor. |

## 13.1 Hard limit x warning

| **Tipo**     | **Comportamento**                                                           |
|--------------|-----------------------------------------------------------------------------|
| Warning      | Permite ação, mas mostra risco/capacidade alta.                             |
| Soft limit   | Requer confirmação ou privilégio mais alto.                                 |
| Hard limit   | Bloqueia operação até quota/configuração mudar.                             |
| Safety limit | Não pode ser superado nem por OWNER sem alteração administrativa explícita. |

# 14. Onboarding seguro de Cluster

## 14.1 Primeiro Cluster

No modo inicial, a instalação pode administrar o próprio Swarm local. O painel acessa Docker através do socket local e nunca expõe /var/run/docker.sock ao navegador.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Browser<br />
|<br />
v<br />
Platform API<br />
|<br />
v<br />
local Docker socket<br />
/var/run/docker.sock<br />
|<br />
v<br />
Swarm Manager</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 14.2 Adição de nodes

Nodes adicionais entram pelo mecanismo nativo do Swarm usando join token. O painel pode gerar instruções e acompanhar o resultado, mas o join token deve ser tratado como credencial temporariamente sensível.

- Gerar/exibir join command somente para OWNER/ADMIN autorizado.

- Nunca persistir join token em logs ou Audit metadata.

- Permitir rotação do join token.

- Assim que o node entrar, registrar node ID, hostname, role, labels e status.

- Aplicar labels/placement policy somente após o node estar Ready.

# 15. Multi-cluster e acesso remoto: decisão de fronteira

O modelo de dados aceita vários Clusters por Team desde o início, mas isso não significa que a primeira versão precise administrar Docker Engines remotos pela internet. A implementação inicial pode operar o Swarm local e evoluir posteriormente para federação segura.

| **Regra de segurança:** Não abrir tcp://0.0.0.0:2375 e não expor Docker API sem TLS. Docker API é equivalente a privilégio administrativo do host. |
|----------------------------------------------------------------------------------------------------------------------------------------------------|

## 15.1 Evolução futura possível

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Central Platform<br />
|<br />
| authenticated control channel<br />
v<br />
Cluster Connector / Agent (future)<br />
|<br />
v<br />
Local Docker socket<br />
|<br />
v<br />
Remote Swarm</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

Essa evolução poderá introduzir um connector/agent mínimo por Cluster ou outro canal autenticado. A decisão ficará separada do domínio de produto para não acoplar Team/Project/Environment à tecnologia usada para acesso remoto.

# 16. Modelo de dados principal

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>User<br />
|-- InstanceRole?<br />
|<br />
+-- TeamMembership -- Team<br />
|-- TeamOwnership (implicit via OWNER membership)<br />
|-- Projects<br />
| +-- Environments --&gt; Cluster<br />
| +-- Services<br />
|<br />
|-- Clusters --&gt; Nodes<br />
|-- Vault Secrets --&gt; SecretVersions<br />
|-- ApiCredentials<br />
|-- AuditEvents<br />
+-- QuotaPolicy</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

| **Tabela**          | **Campos essenciais**                                                    |
|---------------------|--------------------------------------------------------------------------|
| users               | id, email, name, passwordHash/authData, status, createdAt                |
| instance_roles      | userId, role, createdAt, revokedAt                                       |
| teams               | id, name, slug, status, createdAt                                        |
| team_memberships    | teamId, userId, role, status, invitedBy, joinedAt                        |
| ownership_transfers | teamId, fromUserId, toUserId, actorSessionId, createdAt                  |
| projects            | id, teamId, name, slug                                                   |
| environments        | id, projectId, clusterId, name, type, protectionPolicy                   |
| clusters            | id, teamId, name, status, swarmClusterId                                 |
| nodes               | id, clusterId, swarmNodeId, hostname, role, status, labels               |
| api_credentials     | id, teamId, actorType, actorId, tokenHash, scopes, expiresAt, revokedAt  |
| audit_events        | id, teamId, actor, action, resource, metadataRedacted, result, createdAt |
| quota_policies      | id, teamId, limitsJson, updatedAt                                        |

## 16.1 Constraint de OWNER

O banco deve reforçar a regra de ownership, não apenas a aplicação. Em PostgreSQL, a implementação pode usar uma restrição/índice parcial ou uma representação separada de ownership que garanta unicidade por Team. A transferência deve ocorrer dentro de transação serializável ou usando lock do Team.

# 17. Endpoints e comandos conceituais

| **Operação**         | **Exemplo**                                 |
|----------------------|---------------------------------------------|
| Criar Team           | POST /teams                                 |
| Convidar membro      | POST /teams/:teamId/invitations             |
| Alterar role         | PATCH /teams/:teamId/members/:userId        |
| Transferir ownership | POST /teams/:teamId/ownership/transfer      |
| Suspender membro     | POST /teams/:teamId/members/:userId/suspend |
| Listar sessões       | GET /me/sessions                            |
| Revogar sessão       | DELETE /me/sessions/:sessionId              |
| Criar token          | POST /teams/:teamId/api-credentials         |
| Revogar token        | DELETE /teams/:teamId/api-credentials/:id   |
| Audit log            | GET /teams/:teamId/audit-events             |
| Quota usage          | GET /teams/:teamId/usage                    |

# 18. UX principal

## 18.1 Team switcher

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Top bar<br />
[ Team: Acme v ]<br />
- Acme<br />
- Personal Lab<br />
- Create Team<br />
<br />
Role: ADMIN<br />
Environment protection badges remain visible</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 18.2 Members

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Team Settings &gt; Members<br />
<br />
Douglas OWNER Active<br />
Helena ADMIN Active [ ... ]<br />
Thayna DEVELOPER Active [ ... ]<br />
user@x.com VIEWER Invited [ resend ]<br />
<br />
[ Invite member ]<br />
[ Transfer ownership ] &lt;- only OWNER</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 18.3 Transfer ownership screen

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Transfer Team Ownership<br />
<br />
Current owner: Douglas<br />
New owner: Helena (ADMIN)<br />
<br />
After transfer:<br />
- Helena becomes OWNER<br />
- Douglas becomes ADMIN<br />
- This action is audited<br />
- OWNER-only privileges move immediately<br />
<br />
[ Reauthenticate and transfer ]</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 18.4 Audit

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Audit Log<br />
<br />
22:01 Douglas ownership.transfer SUCCESS<br />
21:58 Helena service.deploy SUCCESS<br />
21:42 Thayna vault.reveal DENIED<br />
21:30 System node.drain SUCCESS<br />
<br />
Filters: Actor | Project | Environment | Action | Result</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

# 19. Threat model resumido

| **Ameaça**                          | **Mitigação principal**                                                |
|-------------------------------------|------------------------------------------------------------------------|
| Conta de OWNER comprometida         | MFA/passkey, step-up auth, notifications, sessão revogável, audit.     |
| Developer acessa secret de produção | RBAC por Environment + vault.reveal negado por padrão.                 |
| Token vazado                        | Scopes mínimos, expiração, hash em banco, revogação e lastUsedAt.      |
| Docker API exposta                  | Somente socket local; futura federação via canal autenticado.          |
| Join token Swarm vazado             | Não logar, restringir exibição e permitir rotação.                     |
| Audit contém segredo                | Redaction obrigatória antes da persistência.                           |
| OWNER abandona Team                 | Transferência obrigatória; recovery excepcional por INSTANCE_ADMIN.    |
| Dois transfers concorrentes         | Constraint + transação/lock no Team.                                   |
| Usuário removido mantém sessão      | Autorização revalida membership; sessão não concede acesso permanente. |

# 20. Decisões consolidadas da Parte 4

- O Team é o tenant principal.

- O primeiro usuário do primeiro bootstrap recebe TEAM_OWNER do Team inicial e INSTANCE_ADMIN da instalação.

- O criador de qualquer Team posterior recebe TEAM_OWNER somente daquele Team.

- Existe exatamente um OWNER ativo por Team.

- Ownership é transferível somente para um ADMIN ACTIVE existente no Team.

- Após a transferência, o antigo OWNER passa automaticamente para ADMIN.

- Transferência exige reautenticação e gera AuditEvent.

- INSTANCE_ADMIN e TEAM_OWNER são papéis independentes.

- RBAC é avaliado por role + scope + resource + policy.

- Production pode aplicar restrições adicionais mesmo a DEVELOPER/ADMIN.

- Tokens de automação são separados de sessões humanas.

- Audit Log não armazena plaintext sensível.

- Recovery Key é operação OWNER-only por padrão.

- Quotas fazem parte da segurança operacional, não apenas do billing.

- A primeira versão não expõe Docker API remota; multi-cluster remoto ficará atrás de uma abstração futura segura.

# 21. Critérios de aceite desta parte

- Bootstrap cria primeiro User, Team, OWNER e INSTANCE_ADMIN de forma consistente.

- Constraint impede Team sem OWNER ou com dois OWNERs ativos.

- OWNER consegue transferir propriedade para ADMIN e somente para ADMIN.

- Transferência troca roles atomicamente e aparece no Audit Log.

- ADMIN não consegue tornar a si mesmo ou outro membro OWNER diretamente.

- OWNER não consegue sair/remover-se sem transferir ownership.

- Permissões respeitam Team, Environment e Service scopes.

- Usuário sem vault.reveal não recebe plaintext de secret pela API.

- Operações críticas exigem step-up authentication.

- Tokens podem ser revogados e não são armazenados em plaintext quando desnecessário.

- Membership suspenso perde acesso imediatamente.

- Join tokens e credentials de cluster nunca aparecem em logs.

- Audit Log registra ações críticas com metadata redigida.

- A plataforma funciona sem expor Docker API publicamente.

# 22. Próxima parte

A Parte 5 deve fechar a camada de proteção e continuidade da plataforma: backups e snapshots do próprio produto, policies de retenção, restore, disaster recovery, recuperação do Vault/Recovery Key, configuração de storage externo e testes de recuperação. Depois disso, billing/planos, marketplace/templates e integrações com providers podem ser tratados como camadas adicionais.
