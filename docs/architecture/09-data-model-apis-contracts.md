---
document: "09"
title: "Modelo de Dados, APIs e Contratos do Sistema"
type: "architecture"
status: "approved"
source: "docx"
---

**PLATAFORMA PAAS  
CLUSTER-FIRST**

**Documento técnico consolidado - Parte 9**

Modelo de dados, APIs, eventos, constraints e contratos internos

## Resumo executivo

Esta parte transforma as decisões arquiteturais das Partes 1 a 8 em um modelo técnico único. O PostgreSQL da plataforma passa a ser a fonte de verdade para identidade, tenancy, projetos, environments, serviços, builds, releases, operações, Vault, domínios, certificados, observabilidade, backups e auditoria. Docker Swarm continua sendo a fonte do estado real de runtime; o Control Plane reconcilia os dois mundos.

O objetivo não é criar um schema “bonito”, e sim impedir ambiguidades durante a implementação. Cada recurso recebe ownership claro, identificadores estáveis, regras de integridade, estados permitidos, índices, APIs e eventos. O documento também define quais dados são imutáveis, quais são versionados, quais podem ser soft-deleted e quais nunca podem conter plaintext sensível.

| **Campo**       | **Definição**                                    |
|-----------------|--------------------------------------------------|
| Status          | Documento vivo - v0.9                            |
| Escopo          | Modelo persistente e contratos do Control Plane  |
| Banco principal | PostgreSQL                                       |
| Runtime externo | Docker Engine / Docker Swarm                     |
| Princípio       | Desired state persistido; actual state observado |
| Tenancy         | Team como boundary primária de ownership         |

# 1. Princípios do modelo de dados

| **Regra central:** o banco da plataforma descreve intenção e histórico; o Docker/Swarm descreve execução atual. Nenhum dos dois, isoladamente, representa o produto completo. |
|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|

| **Princípio**               | **Aplicação**                                                                                                                |
|-----------------------------|------------------------------------------------------------------------------------------------------------------------------|
| IDs opacos                  | Todas as entidades usam IDs não sequenciais expostos externamente; nomes e slugs nunca são chaves primárias.                 |
| Imutabilidade seletiva      | Artifact, Release, SecretVersion, AuditLog e eventos consumados não são editados; novas versões substituem alterações.       |
| Soft delete controlado      | Team, Project, Environment e Service entram em lifecycle de deleção; recursos efêmeros podem ser hard-deleted após retenção. |
| Optimistic concurrency      | Recursos mutáveis possuem revision/version para impedir lost update.                                                         |
| Multi-tenant por construção | Toda query de domínio parte de teamId ou de uma cadeia que o determine sem ambiguidade.                                      |
| Segredos nunca plaintext    | Valores sensíveis persistem apenas cifrados; logs, events e operation payloads referenciam IDs/versões.                      |
| Auditabilidade              | Toda ação administrativa relevante registra actor, escopo, requestId e before/after sanitizado.                              |
| Idempotência                | Comandos externos e jobs críticos aceitam idempotencyKey ou possuem natural key única.                                       |

# 2. Visão global das entidades

IDENTITY / TENANCY  
User ──\< TeamMember \>── Team  
│ │  
└── Session ├── Project ──\< Environment ──\< Service  
├── Cluster ──\< Node  
├── Secret ──\< SecretVersion  
└── ApiToken / AuditLog  
  
DELIVERY  
Service ──\< Build ──\> Artifact ──\< Release ──\< Deployment  
│  
└── Environment  
  
CONTROL PLANE  
Resource ──\< Operation ──\< OperationAttempt  
└── OutboxEvent ──\> Queue  
  
EDGE  
Service ──\< Domain ──\> Certificate  
Environment ──\< NetworkBinding  
Cluster ──\< IngressGateway / LoadBalancerBinding  
  
PROTECTION / OPS  
Environment ──\< Snapshot  
Cluster ──\< ClusterSnapshot  
Team ──\< BackupPolicy  
Service ──\< AlertRule / Incident

Os relacionamentos acima são lógicos. Nem toda ligação precisa virar foreign key direta se isso aumentar acoplamento; porém ownership e integridade precisam ser verificáveis no banco. Recursos que atravessam módulos, como Release e SecretVersion, são referenciados por ID imutável.

# 3. Identidade, tenancy e governança

## 3.1 User

| **Campo**             | **Tipo / regra** | **Observação**                                                                  |
|-----------------------|------------------|---------------------------------------------------------------------------------|
| id                    | uuid/ulid PK     | Identificador externo estável.                                                  |
| email                 | citext UNIQUE    | Normalizado; não reutilizar silenciosamente enquanto conta estiver em retenção. |
| displayName           | text             | Nome de exibição.                                                               |
| status                | UserStatus       | ACTIVE, SUSPENDED, DELETED_PENDING.                                             |
| emailVerifiedAt       | timestamptz?     | Pode ser exigido antes de ações críticas.                                       |
| createdAt / updatedAt | timestamptz      | UTC.                                                                            |

## 3.2 Team e TeamMember

| **Entidade**   | **Campos essenciais**                                 | **Constraints críticas**                                                        |
|----------------|-------------------------------------------------------|---------------------------------------------------------------------------------|
| Team           | id, name, slug, ownerUserId, status, createdAt        | slug único; ownerUserId deve possuir membership ACTIVE.                         |
| TeamMember     | teamId, userId, role, status, invitedBy, joinedAt     | UNIQUE(teamId,userId); exatamente um OWNER ativo por Team.                      |
| TeamInvitation | teamId, email, role, tokenHash, expiresAt, acceptedAt | token em hash; expiração; uma invitation ativa por team/email quando aplicável. |

| **Ownership:** o primeiro usuário do Team é OWNER. Transferência só pode apontar para membro ADMIN ativo, ocorre em transação única e transforma o antigo OWNER em ADMIN. TEAM_OWNER não implica INSTANCE_ADMIN. |
|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|

## 3.3 InstanceRole

Papéis de instância ficam separados de TeamMember porque administram a instalação, não um tenant específico. Um usuário pode ser Team OWNER sem poder operar cluster global, e um Instance Admin pode administrar infraestrutura sem ser proprietário comercial de todos os Teams.

| **Role**          | **Escopo**                                                      |
|-------------------|-----------------------------------------------------------------|
| INSTANCE_ADMIN    | Configuração global, bootstrap, clusters, providers e recovery. |
| INSTANCE_OPERATOR | Operação técnica sem poderes máximos de identidade/recovery.    |
| INSTANCE_AUDITOR  | Leitura de auditoria e segurança.                               |

# 4. Clusters, nodes e capacidade

## 4.1 Cluster

| **Campo**                         | **Regra**                                                                                                                                     |
|-----------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------|
| id                                | PK opaca.                                                                                                                                     |
| teamId                            | Owner do cluster quando instalação multi-tenant permitir clusters dedicados; nullable apenas para cluster de sistema explicitamente modelado. |
| name / slug                       | Nome humano e chave amigável.                                                                                                                 |
| status                            | PROVISIONING, READY, DEGRADED, MAINTENANCE, UNREACHABLE, DELETING.                                                                            |
| swarmId                           | ID observado do Swarm; UNIQUE quando conhecido.                                                                                               |
| desiredRevision / appliedRevision | Controle de reconciliação.                                                                                                                    |
| networkProfileId                  | Política de rede/firewall associada.                                                                                                          |
| createdAt / deletedAt             | Lifecycle.                                                                                                                                    |

## 4.2 Node

| **Campo**        | **Regra**                                                                   |
|------------------|-----------------------------------------------------------------------------|
| clusterId        | FK obrigatório.                                                             |
| swarmNodeId      | UNIQUE por cluster.                                                         |
| hostname         | Nome observado.                                                             |
| role             | MANAGER ou WORKER.                                                          |
| capabilities     | INGRESS, BUILDER e labels adicionais não precisam substituir role do Swarm. |
| availability     | ACTIVE, PAUSE, DRAIN.                                                       |
| status           | JOINING, READY, DEGRADED, DOWN, REMOVING.                                   |
| advertiseAddress | Endereço interno confiável.                                                 |
| labels           | JSONB validado / ou tabela normalizada quando usada em filtros frequentes.  |
| lastSeenAt       | Heartbeat/observação do Control Plane.                                      |

## 4.3 EnrollmentToken

| **Campo** | **Regra**                    |
|-----------|------------------------------|
| clusterId | Cluster alvo.                |
| role      | Role/capability autorizada.  |
| tokenHash | Nunca persistir token bruto. |
| expiresAt | TTL curto.                   |
| maxUses   | Normalmente 1.               |
| usedCount | Incremento transacional.     |
| revokedAt | Revogação imediata.          |
| createdBy | Auditabilidade.              |

# 5. Projects, Environments e Services

## 5.1 Project

Project representa o produto lógico. Não é filho rígido de Cluster. O Team possui Projects e Clusters separadamente; cada Environment escolhe onde executar.

| **Campo**            | **Regra**                         |
|----------------------|-----------------------------------|
| teamId               | Ownership.                        |
| name / slug          | UNIQUE(teamId,slug) entre ativos. |
| description          | Opcional.                         |
| defaultEnvironmentId | Opcional; referência de UX.       |
| status               | ACTIVE, ARCHIVED, DELETING.       |

## 5.2 Environment

| **Campo**                         | **Regra**                                               |
|-----------------------------------|---------------------------------------------------------|
| projectId                         | FK.                                                     |
| clusterId                         | Cluster onde este Environment executa.                  |
| name / slug                       | UNIQUE(projectId,slug).                                 |
| type                              | PRODUCTION, HOMOLOGATION, DEVELOPMENT, PREVIEW, CUSTOM. |
| desiredRevision / appliedRevision | Reconciliação.                                          |
| networkId                         | Overlay network principal.                              |
| autoPromoteSecrets                | false por padrão em Production.                         |
| status                            | PROVISIONING, READY, DEGRADED, PAUSED, DELETING.        |

## 5.3 Service

| **Grupo**    | **Campos**                                                       |
|--------------|------------------------------------------------------------------|
| Identidade   | id, environmentId, name, slug, serviceType.                      |
| Runtime      | imageRef/releaseId, replicas, command, args, ports, healthcheck. |
| Resources    | cpuReservation, cpuLimit, memoryReservation, memoryLimit.        |
| Placement    | constraints, preferences, capabilities required.                 |
| Build source | sourceConnectionId, repository, branch, rootDir, buildStrategy.  |
| State        | desiredRevision, appliedRevision, status, lastHealthyAt.         |
| Lifecycle    | createdAt, archivedAt, deletedAt.                                |

| **Naming:** o nome técnico do Swarm deve ser determinístico e derivado de IDs/slugs sanitizados, mas o produto nunca depende desse nome como identificador primário. |
|----------------------------------------------------------------------------------------------------------------------------------------------------------------------|

# 6. Configuração, variáveis e Vault

## 6.1 EnvironmentVariable

| **Campo**   | **Regra**                                                                                       |
|-------------|-------------------------------------------------------------------------------------------------|
| serviceId   | Binding normalmente por Service; inheritance pode ser materializado/resolvido no Control Plane. |
| key         | Validada e única no escopo efetivo.                                                             |
| value       | Somente para valores não sensíveis.                                                             |
| scope       | TEAM, PROJECT, ENVIRONMENT, SERVICE quando a UI oferecer inheritance.                           |
| isSensitive | Se true, não usar esta tabela; promover para SecretBinding.                                     |
| revision    | Permite compare-and-swap.                                                                       |

## 6.2 Secret e SecretVersion

| **Entidade**         | **Campos essenciais**                                                             | **Imutabilidade**                                         |
|----------------------|-----------------------------------------------------------------------------------|-----------------------------------------------------------|
| Secret               | id, teamId, name, scope, description, createdBy                                   | Metadados editáveis com audit.                            |
| SecretVersion        | id, secretId, versionNumber, ciphertext, encryptionMetadata, createdBy, createdAt | Imutável depois de criada.                                |
| ServiceSecretBinding | serviceId, targetName, secretVersionId, injectionMode                             | Troca de versão cria mudança no desired state do Service. |

A plataforma diferencia o nome canônico da Secret do nome recebido pela aplicação. O mesmo SecretVersion pode ser usado por múltiplos Services, enquanto cada binding define targetName e injectionMode.

## 6.3 EncryptionKeyEnvelope

O banco precisa armazenar apenas material envelopado: master/data key cifrada por uma KEK derivada/protegida pela Recovery Key. A Recovery Key não é persistida em forma recuperável. Rotação da Recovery Key rewrapa a chave, não todas as SecretVersions.

| **Campo**        | **Regra**                                                 |
|------------------|-----------------------------------------------------------|
| id               | Versão do envelope.                                       |
| wrappedKey       | Ciphertext da chave mestra/data key.                      |
| kdf / parameters | Parâmetros necessários à recuperação.                     |
| createdAt        | Versão temporal.                                          |
| retiredAt        | Mantida apenas enquanto necessário ao recovery planejado. |

# 7. Source connections e integração Git

| **Entidade**      | **Responsabilidade**                                                                   |
|-------------------|----------------------------------------------------------------------------------------|
| SourceConnection  | Conexão com provider: GitHub App, Git genérico ou futuro GitLab.                       |
| RepositoryBinding | repo/provider installation escolhidos pelo Team.                                       |
| WebhookDelivery   | deliveryId, eventType, payloadHash, receivedAt, processedAt, status.                   |
| SourceRevision    | repository, commitSha, branch/tag de origem; commitSha é a identidade real da revisão. |

| **Webhook:** deliveryId do provider ou uma chave derivada deve ser UNIQUE para tornar redelivery idempotente. |
|---------------------------------------------------------------------------------------------------------------|

# 8. Build, Artifact, Release e Deployment

## 8.1 Build

| **Campo**              | **Regra**                                       |
|------------------------|-------------------------------------------------|
| serviceId              | Service que solicitou o build.                  |
| sourceRevisionId       | Commit imutável.                                |
| strategy               | RAILPACK ou DOCKERFILE.                         |
| status                 | QUEUED, RUNNING, SUCCEEDED, FAILED, CANCELED.   |
| builderNodeId          | Node que executou quando aplicável.             |
| startedAt / finishedAt | Métricas e troubleshooting.                     |
| logRef                 | Referência a logs, não blob gigante no row.     |
| cacheMetadata          | Metadados não sensíveis para reuso/diagnóstico. |

## 8.2 Artifact

| **Campo**        | **Regra**                                  |
|------------------|--------------------------------------------|
| id               | PK.                                        |
| registryRef      | Nome/repositório OCI.                      |
| digest           | sha256:...; UNIQUE no namespace relevante. |
| platforms        | amd64/arm64 etc.                           |
| sizeBytes        | Opcional.                                  |
| sbomRef          | Futuro, sem acoplar schema ao formato.     |
| createdByBuildId | Proveniência.                              |
| retentionClass   | Permite GC seguro.                         |

## 8.3 Release

Release é a unidade imutável que pode ser promovida entre Environments. Ela referencia Artifact por digest e congela a configuração de execução necessária para reproduzir aquele release, sem incluir plaintext de secrets.

| **Campo**        | **Regra**                                                                                          |
|------------------|----------------------------------------------------------------------------------------------------|
| serviceLineageId | Identifica o serviço lógico entre Environments, quando a promoção HML→PROD exigir correspondência. |
| artifactId       | Digest imutável.                                                                                   |
| sourceRevisionId | Commit de origem.                                                                                  |
| runtimeSpecHash  | Hash do spec não sensível.                                                                         |
| createdAt        | Imutável.                                                                                          |
| createdBy        | User/system.                                                                                       |

## 8.4 Deployment

| **Campo**                 | **Regra**                                                                           |
|---------------------------|-------------------------------------------------------------------------------------|
| environmentId / serviceId | Destino.                                                                            |
| releaseId                 | Artefato que será aplicado.                                                         |
| status                    | REQUESTED, PREPARING, DEPLOYING, VERIFYING, HEALTHY, FAILED, ROLLED_BACK, CANCELED. |
| strategy                  | ROLLING por padrão.                                                                 |
| previousDeploymentId      | Base para rollback.                                                                 |
| operationId               | Operação de Control Plane correspondente.                                           |
| requestedBy               | Actor.                                                                              |
| timestamps                | created, started, healthy, finished.                                                |

# 9. Operations, jobs e consistência

## 9.1 Operation

| **Campo**                          | **Regra**                                                                    |
|------------------------------------|------------------------------------------------------------------------------|
| id                                 | PK.                                                                          |
| teamId / resourceType / resourceId | Escopo explícito.                                                            |
| type                               | DEPLOY, SCALE, UPDATE_DOMAIN, ROTATE_SECRET_BINDING, DRAIN_NODE, etc.        |
| status                             | PENDING, CLAIMED, RUNNING, WAITING, SUCCEEDED, FAILED, CANCELED, SUPERSEDED. |
| desiredRevision                    | Revision que a operação pretende aplicar.                                    |
| idempotencyKey                     | UNIQUE por escopo apropriado quando originada externamente.                  |
| leaseOwner / leaseUntil            | Claim temporário.                                                            |
| fencingToken                       | Monotônico para rejeitar executor atrasado.                                  |
| attemptCount                       | Controle de retry.                                                           |
| payload                            | JSONB sanitizado e versionado por schemaVersion.                             |
| errorCode                          | Código estável; mensagem humana separada.                                    |

## 9.2 OperationAttempt

Cada tentativa possui início/fim, executor, erro categorizado e telemetria. Não se sobrescreve a tentativa anterior; isso preserva a linha do tempo de retries.

## 9.3 OutboxEvent

| **Campo**                   | **Regra**                    |
|-----------------------------|------------------------------|
| id                          | ID do evento.                |
| aggregateType / aggregateId | Entidade que originou.       |
| eventType                   | Nome estável e versionável.  |
| schemaVersion               | Versão explícita.            |
| payload                     | Sem secrets.                 |
| occurredAt                  | Tempo do commit lógico.      |
| publishedAt                 | Null até publicação.         |
| partitionKey                | Ordenação quando necessária. |

| **Transação:** mudança de desired state e gravação do OutboxEvent ocorrem na mesma transação PostgreSQL. Publicação na fila acontece depois, evitando dual-write inconsistente. |
|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|

# 10. Actual state e observações do Swarm

O actual state é derivado e pode ser reconstruído. Não deve competir com desired state no mesmo conjunto de colunas.

| **Entidade**       | **Uso**                                                                   |
|--------------------|---------------------------------------------------------------------------|
| ServiceObservation | replicas desired/running, image digest observado, health e update status. |
| NodeObservation    | status, availability, resources, engine version, lastSeenAt.              |
| IngressObservation | health de cada gateway/Traefik.                                           |
| ClusterObservation | quorum, managers, workers, swarm metadata.                                |
| DriftRecord        | diferença detectada, severidade, firstSeenAt, lastSeenAt, resolution.     |

Observações podem ter TTL ou retenção menor. Estado histórico de operação relevante deve ser promovido para Deployment, Incident ou AuditLog antes de expirar.

# 11. Networking, Domain e Certificate

## 11.1 Network

| **Campo**      | **Regra**                                                |
|----------------|----------------------------------------------------------|
| environmentId  | Uma rede de aplicação por Environment no desenho padrão. |
| swarmNetworkId | Actual state observado.                                  |
| name           | Nome técnico determinístico.                             |
| driver         | overlay.                                                 |
| encrypted      | Política configurável; registrar intenção.               |
| status         | PROVISIONING, READY, DEGRADED, DELETING.                 |

## 11.2 Domain

| **Campo**                 | **Regra**                                                         |
|---------------------------|-------------------------------------------------------------------|
| teamId                    | Ownership.                                                        |
| environmentId / serviceId | Destino.                                                          |
| hostname                  | Normalizado/punycode; UNIQUE entre domínios ativos da instalação. |
| targetPort                | Porta interna do Service.                                         |
| tlsMode                   | MANAGED, PROVIDED, DISABLED conforme política.                    |
| certificateId             | Certificado ativo quando aplicável.                               |
| status                    | PENDING_DNS, PENDING_CERT, ACTIVE, DEGRADED, REVOKED.             |
| isDefault                 | Subdomínio gerado pela plataforma.                                |

## 11.3 Certificate e CertificateVersion

Certificate representa a intenção para um conjunto de names; CertificateVersion representa material emitido. Assim a renovação não sobrescreve a versão atualmente distribuída.

| **Entidade**            | **Campos**                                                                                                   |
|-------------------------|--------------------------------------------------------------------------------------------------------------|
| Certificate             | id, teamId, primaryName, SANs, challengeType, status, activeVersionId.                                       |
| CertificateVersion      | certificatePem, encryptedPrivateKey, chainPem, issuedAt, notBefore, notAfter, providerOrderRef, fingerprint. |
| CertificateDistribution | certificateVersionId, ingressNodeId, status, distributedAt, verifiedAt.                                      |

# 12. Providers e credenciais externas

DNS, Registry, Load Balancer, Backup Storage e futuros Cloud Providers seguem o mesmo padrão: configuração normalizada + credential binding para SecretVersion. Credencial nunca fica duplicada em JSON de provider.

| **Entidade**              | **Campos principais**                                            |
|---------------------------|------------------------------------------------------------------|
| ProviderConnection        | teamId, type, name, config JSONB não sensível, status.           |
| ProviderCredentialBinding | providerConnectionId, secretVersionId, purpose.                  |
| ProviderResourceBinding   | providerConnectionId, resourceType, externalId, localResourceId. |

# 13. Observabilidade, alertas e incidentes

## 13.1 AlertRule

| **Campo**            | **Regra**                                     |
|----------------------|-----------------------------------------------|
| scopeType / scopeId  | Cluster, Environment ou Service.              |
| metric / expression  | Modelo interno ou expressão provider-neutral. |
| threshold / window   | Condição.                                     |
| severity             | INFO, WARNING, CRITICAL.                      |
| status               | ENABLED, MUTED, DISABLED.                     |
| notificationPolicyId | Destino.                                      |

## 13.2 Incident

| **Campo**              | **Regra**                                  |
|------------------------|--------------------------------------------|
| teamId                 | Owner.                                     |
| source                 | ALERT, DEPLOYMENT, NODE, SECURITY, MANUAL. |
| severity               | SEV1..SEV4 ou enum equivalente.            |
| status                 | OPEN, ACKNOWLEDGED, MITIGATED, RESOLVED.   |
| resourceRefs           | Referências estruturadas.                  |
| startedAt / resolvedAt | Timeline.                                  |
| summary                | Sem dados sensíveis.                       |

## 13.3 Log e Metric references

Logs e séries temporais não devem ser armazenados em massa no PostgreSQL transacional. O banco guarda configurações, índices de alto nível, bookmarks e referências para a camada de observabilidade. Isso evita transformar o banco do Control Plane em datastore de telemetria.

# 14. Backup, Snapshot e Disaster Recovery

| **Entidade**        | **Função**                                                           |
|---------------------|----------------------------------------------------------------------|
| BackupPolicy        | schedule, retention, destination provider, encryption policy.        |
| BackupRun           | execução concreta, status, startedAt, finishedAt, manifestRef.       |
| BackupArtifact      | tipo, checksum, objectKey, size, encryption metadata.                |
| EnvironmentSnapshot | manifesto lógico de releases, bindings de secrets, domains e config. |
| ClusterSnapshot     | configuração lógica do cluster e referências de recovery.            |
| RestoreJob          | origem, target, mode FAST_SWARM_RESTORE/CLEAN_REBUILD, status.       |
| RestoreVerification | health checks e resultado do restore drill.                          |

| **Recovery Key:** backup do banco e backup da chave de recuperação não devem ser tratados como o mesmo ativo. O usuário precisa manter a Recovery Key fora do storage primário da plataforma. |
|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|

# 15. AuditLog, sessions, API tokens e segurança

## 15.1 AuditLog

| **Campo**                 | **Regra**                                                                         |
|---------------------------|-----------------------------------------------------------------------------------|
| id                        | Imutável.                                                                         |
| teamId                    | Nullable somente para eventos de instância.                                       |
| actorType / actorId       | USER, API_TOKEN, SYSTEM, RECOVERY.                                                |
| action                    | Nome estável: team.owner.transferred, service.deployed, secret.version.created... |
| resourceType / resourceId | Alvo.                                                                             |
| requestId / correlationId | Rastreabilidade.                                                                  |
| ip / userAgent            | Quando houver interação externa; respeitar política de retenção.                  |
| before / after            | JSON sanitizado; nunca secret value.                                              |
| createdAt                 | Append-only.                                                                      |

## 15.2 Session

| **Campo**             | **Regra**                 |
|-----------------------|---------------------------|
| userId                | FK.                       |
| tokenHash / sessionId | Nunca token bruto.        |
| expiresAt             | TTL.                      |
| revokedAt             | Logout/revogação.         |
| mfaLevel              | Contexto de autenticação. |
| lastSeenAt            | Opcional para segurança.  |

## 15.3 ApiToken

| **Campo**       | **Regra**             |
|-----------------|-----------------------|
| teamId / userId | Owner e actor.        |
| name            | Identificação humana. |
| tokenHash       | Somente hash.         |
| scopes          | Lista validada.       |
| expiresAt       | Recomendado.          |
| lastUsedAt      | Auditoria.            |
| revokedAt       | Revogação.            |

# 16. Quotas, limites e billing readiness

Mesmo sem billing completo, limites precisam existir no modelo para proteger a instalação. O domínio deve suportar quotas por Team e overrides por plano sem espalhar “if premium” pelos módulos.

| **Entidade**    | **Exemplos**                                                                     |
|-----------------|----------------------------------------------------------------------------------|
| Plan            | Nome lógico e conjunto padrão de limites.                                        |
| TeamEntitlement | Feature flags/entitlements efetivos.                                             |
| TeamQuota       | maxProjects, maxServices, maxClusters, maxMembers, maxSecrets, buildConcurrency. |
| UsageCounter    | Uso atual ou janela agregada; não substituir telemetria detalhada.               |

# 17. Enums e state machines consolidadas

| **Recurso** | **Estados principais**                                                                       |
|-------------|----------------------------------------------------------------------------------------------|
| Environment | PROVISIONING → READY ↔ DEGRADED / PAUSED → DELETING → DELETED                                |
| Service     | DRAFT / PROVISIONING → RUNNING ↔ DEGRADED / STOPPED → DELETING                               |
| Build       | QUEUED → RUNNING → SUCCEEDED \| FAILED \| CANCELED                                           |
| Deployment  | REQUESTED → PREPARING → DEPLOYING → VERIFYING → HEALTHY \| FAILED \| ROLLED_BACK \| CANCELED |
| Operation   | PENDING → CLAIMED → RUNNING ↔ WAITING → SUCCEEDED \| FAILED \| CANCELED \| SUPERSEDED        |
| Domain      | PENDING_DNS → PENDING_CERT → ACTIVE ↔ DEGRADED → REVOKED                                     |
| Certificate | PENDING → ISSUING → DISTRIBUTING → ACTIVE → RENEWING → ACTIVE \| FAILED \| REVOKED           |
| Node        | JOINING → READY ↔ DEGRADED / DRAINING → REMOVING → REMOVED                                   |
| BackupRun   | QUEUED → RUNNING → VERIFYING → SUCCEEDED \| FAILED                                           |
| RestoreJob  | PLANNED → RUNNING → VERIFYING → SUCCEEDED \| FAILED \| CANCELED                              |

Transitions inválidas devem ser rejeitadas no domínio, não “corrigidas” silenciosamente. APIs retornam erro estável como INVALID_STATE_TRANSITION.

# 18. Constraints e índices obrigatórios

| **Área**        | **Constraint / índice**                                                      |
|-----------------|------------------------------------------------------------------------------|
| Membership      | UNIQUE(teamId,userId); partial unique garantindo um OWNER ativo por Team.    |
| Project         | UNIQUE(teamId,slug) WHERE deletedAt IS NULL.                                 |
| Environment     | UNIQUE(projectId,slug) WHERE deletedAt IS NULL.                              |
| Service         | UNIQUE(environmentId,slug) WHERE deletedAt IS NULL.                          |
| Domain          | UNIQUE(normalizedHostname) WHERE status != REVOKED.                          |
| SecretVersion   | UNIQUE(secretId,versionNumber).                                              |
| WebhookDelivery | UNIQUE(providerConnectionId,externalDeliveryId).                             |
| Artifact        | UNIQUE(registryRef,digest) ou digest global conforme modelo de registry.     |
| Operation       | UNIQUE(scope,idempotencyKey) quando key não-null.                            |
| Outbox          | INDEX(publishedAt,occurredAt) para publisher.                                |
| Reconcile       | INDEX(resourceType,status,nextAttemptAt) em Operations.                      |
| Audit           | INDEX(teamId,createdAt DESC), INDEX(resourceType,resourceId,createdAt DESC). |

# 19. Estratégia de IDs, slugs e versões

| **Elemento**             | **Escolha**                                                                        |
|--------------------------|------------------------------------------------------------------------------------|
| ID interno/exposto       | UUIDv7 ou ULID são adequados; decisão final deve ser única para toda a plataforma. |
| Slug                     | Humano, mutável com restrições; nunca referenciado por foreign key.                |
| Revision                 | bigint monotônico por recurso para optimistic concurrency e reconcile.             |
| Secret version           | inteiro monotônico por Secret.                                                     |
| Schema version de events | inteiro explícito no envelope.                                                     |
| Digest de artifact       | OCI digest é identidade do conteúdo, não tag.                                      |
| Request/correlation id   | ID novo por boundary externo e propagado internamente.                             |

# 20. API pública: convenções

| **Princípio:** a API manipula recursos de produto e desired state; ela não expõe uma cópia crua da Docker Engine API. |
|-----------------------------------------------------------------------------------------------------------------------|

| **Tema**    | **Convenção**                                                                        |
|-------------|--------------------------------------------------------------------------------------|
| Base        | /v1/teams/{teamId}/... para recursos tenant-scoped; endpoints de instance separados. |
| Errors      | Envelope com code estável, message, requestId e details sanitizado.                  |
| Mutation    | Retornar recurso atualizado e, quando assíncrona, operationId.                       |
| Concurrency | If-Match/revision ou campo expectedRevision para mutações sensíveis.                 |
| Idempotency | Idempotency-Key em deploy, create, promote, rotate e operações externas críticas.    |
| Pagination  | Cursor-based para logs administrativos, audit e grandes coleções.                    |
| Filtering   | Filtros explícitos; evitar DSL arbitrária na primeira versão.                        |
| AuthZ       | Checagem server-side baseada em TeamMember/InstanceRole; nunca confiar em UI.        |

## 20.1 Recursos principais

/v1/teams  
/v1/teams/{teamId}/members  
/v1/teams/{teamId}/projects  
/v1/projects/{projectId}/environments  
/v1/environments/{environmentId}/services  
/v1/services/{serviceId}/deployments  
/v1/services/{serviceId}/scale  
/v1/teams/{teamId}/secrets  
/v1/secrets/{secretId}/versions  
/v1/services/{serviceId}/secret-bindings  
/v1/environments/{environmentId}/domains  
/v1/clusters/{clusterId}/nodes  
/v1/clusters/{clusterId}/enrollment-tokens  
/v1/operations/{operationId}  
/v1/audit-logs

# 21. Contratos de comando internos

Módulos não devem chamar Docker diretamente. Eles produzem Commands tipados para o Operation Engine / Swarm Executor. Os payloads carregam IDs e specs já autorizados, nunca objetos HTTP crus.

CommandEnvelope\<T\> {  
commandId  
commandType  
schemaVersion  
teamId?  
resourceType  
resourceId  
desiredRevision  
actor  
correlationId  
idempotencyKey?  
payload: T  
}  
  
ScaleServiceCommand {  
serviceId  
replicas  
expectedRevision  
}  
  
ApplyReleaseCommand {  
serviceId  
deploymentId  
releaseId  
artifactDigest  
runtimeSpecHash  
secretBindingVersionIds\[\]  
}

# 22. Contratos de eventos

Eventos descrevem fatos consumados. Comandos pedem uma ação; eventos dizem que algo aconteceu. Nomes devem ser estáveis, orientados ao domínio e versionados.

| **Evento**                       | **Quando emitir**                              |
|----------------------------------|------------------------------------------------|
| team.owner.transferred.v1        | Commit da transferência de ownership.          |
| service.desired_state.changed.v1 | Qualquer alteração relevante no spec desejado. |
| build.succeeded.v1               | Artifact criado e persistido.                  |
| deployment.requested.v1          | Deployment e Operation criados.                |
| deployment.healthy.v1            | Release validada como saudável.                |
| secret.version.created.v1        | Nova versão cifrada persistida.                |
| domain.activated.v1              | DNS/TLS/Traefik reconciliados.                 |
| node.joined.v1                   | Node observado e associado ao cluster.         |
| incident.opened.v1               | Incidente criado.                              |
| backup.verified.v1               | Backup e verificação concluídos.               |

| **Payloads:** eventos nunca carregam segredo, private key, registry password, raw provider token ou conteúdo completo de variáveis sensíveis. |
|-----------------------------------------------------------------------------------------------------------------------------------------------|

# 23. Contratos de leitura / views

A UI precisa de leituras compostas que não devem obrigar o frontend a montar 20 requests. Read models podem ser SQL views/materialized views ou queries dedicadas, sem transformar o domínio write-side em DTO de tela.

| **Read model**          | **Conteúdo**                                                                  |
|-------------------------|-------------------------------------------------------------------------------|
| ProjectOverview         | Project + Environments + health agregado + último deployment.                 |
| EnvironmentOverview     | Services, domains, release atual, secret binding status, cluster.             |
| ServiceRuntimeView      | desired vs actual replicas, image digest, health, resources, last operation.  |
| ClusterReadinessView    | managers, workers, ingress, builders, quorum, LB/DNS health.                  |
| ProtectionReadinessView | last backup, restore verification, recovery key status.                       |
| SecurityOverview        | MFA adoption, owner/admins, active API tokens, recent sensitive audit events. |

# 24. Transaction boundaries

| **Caso**            | **Na mesma transação**                                                                  |
|---------------------|-----------------------------------------------------------------------------------------|
| Alterar replicas    | Update Service desired spec + revision + criar Operation + OutboxEvent.                 |
| Criar SecretVersion | Insert SecretVersion + AuditLog + OutboxEvent; nunca chamar Docker dentro da transação. |
| Transferir OWNER    | Promover target, rebaixar antigo OWNER, atualizar Team.ownerUserId, AuditLog.           |
| Request deployment  | Criar Deployment + Operation + refs de Release + OutboxEvent.                           |
| Adicionar domínio   | Criar/atualizar Domain desired state + Operation + audit.                               |
| Consumir enrollment | Validar tokenHash/TTL/uses e incrementar usedCount atomicamente.                        |

Chamadas de rede, Docker API, GitHub, DNS, Registry, ACME e Load Balancer nunca ficam abertas dentro de transações do PostgreSQL. Elas acontecem depois via Operation/worker e precisam ser idempotentes.

# 25. Exclusão, retenção e garbage collection

| **Recurso**                 | **Política**                                                                         |
|-----------------------------|--------------------------------------------------------------------------------------|
| User/Team                   | Soft delete + período de retenção; remoção final exige regras de compliance/backup.  |
| Project/Environment/Service | DELETING → reconcile runtime → tombstone/soft delete → GC posterior.                 |
| Build logs                  | Retenção configurável; metadados do Build permanecem mais tempo.                     |
| Artifact                    | GC somente quando nenhum Release/Deployment/Snapshot protegido referenciar o digest. |
| SecretVersion               | Não apagar enquanto bindings, snapshots ou políticas de retenção exigirem recovery.  |
| AuditLog                    | Append-only durante retenção definida.                                               |
| Operations/Attempts         | Retenção longa o suficiente para suporte; payload sanitizado.                        |
| Observations                | TTL curto/médio porque são reconstruíveis.                                           |

# 26. Migrações e compatibilidade

O schema do banco, eventos e command payloads evoluem separadamente. Migração de banco não deve exigir que todos os workers sejam atualizados no mesmo milissegundo.

> **•** Preferir expand-and-contract: adicionar coluna/tabela compatível, migrar leitores/escritores, backfill, depois remover legado.
>
> **•** Eventos possuem schemaVersion e consumers devem tolerar versões suportadas durante rolling upgrade.
>
> **•** Commands persistidos em fila precisam ser processáveis após deploy do Control Plane; mudanças incompatíveis exigem migrador ou versionamento.
>
> **•** Release/runtime specs devem continuar reproduzíveis após evolução da UI.

# 27. Validações de domínio essenciais

| **Ação**          | **Validação**                                                                                    |
|-------------------|--------------------------------------------------------------------------------------------------|
| Criar Service     | Environment e Cluster ativos; slug livre; limites do Team; build/source compatíveis.             |
| Deploy Production | Release válida; SecretVersions existentes; domínio/health policy coerentes; permissões do actor. |
| Scale             | replicas dentro de quota e resource policy; Service não em DELETING.                             |
| Bind Secret       | Secret pertence ao Team permitido; version ativa/retida; targetName válido.                      |
| Transfer Owner    | target é ADMIN ativo; não é o mesmo OWNER; reautenticação/MFA conforme política.                 |
| Remover Manager   | quorum permanece seguro; node drenado; não remover último manager.                               |
| Remover Domain    | avaliar impacto de certificate/SAN e DNS gerenciado.                                             |
| GC Artifact       | nenhuma referência protegida por Release, Deployment, Snapshot ou rollback window.               |

# 28. Modelo de erro estável

ErrorResponse {  
code: "INVALID_STATE_TRANSITION"  
message: "Não é possível ..."  
requestId: "req\_..."  
details?: { ...sanitized }  
}  
  
Exemplos de code:  
NOT_FOUND  
FORBIDDEN  
REVISION_CONFLICT  
QUOTA_EXCEEDED  
INVALID_STATE_TRANSITION  
RESOURCE_LOCKED  
PROVIDER_UNAVAILABLE  
BUILD_FAILED  
DEPLOYMENT_UNHEALTHY  
SWARM_QUORUM_RISK  
SECRET_VERSION_NOT_AVAILABLE

# 29. Ordem de implementação do schema

1\. Identity: User, Session, Team, TeamMember e InstanceRole.

2\. Project, Environment, Cluster e Node.

3\. Service + desiredRevision/appliedRevision + Operations/Outbox.

4\. SourceConnection, SourceRevision, Build, Artifact e Release.

5\. Deployment e promoção/rollback.

6\. Secret, SecretVersion, bindings e key envelope.

7\. Network, Domain, Certificate e provider connections.

8\. AuditLog, ApiToken, quotas e entitlements.

9\. Observations, AlertRule e Incident.

10\. BackupPolicy, snapshots, restore e DR.

11\. Read models e views de dashboard.

12\. Retention/GC e ferramentas administrativas.

# 30. Critérios de aceite da Parte 9

| **Critério**  | **Aceite**                                                                           |
|---------------|--------------------------------------------------------------------------------------|
| Ownership     | Toda entidade tenant-scoped possui caminho inequívoco até Team.                      |
| Imutabilidade | Artifact, Release, SecretVersion e AuditLog não são alterados in-place.              |
| Reconciliação | Service/Environment/Cluster suportam desiredRevision e appliedRevision.              |
| Idempotência  | Webhooks e operações críticas possuem natural/explicit idempotency key.              |
| Segurança     | Nenhuma tabela de domínio armazena segredo plaintext ou token recuperável.           |
| Integridade   | Unique/partial indexes protegem slugs, ownership e versões.                          |
| Operabilidade | Operations, attempts, audit e correlation IDs permitem reconstruir uma ação.         |
| Evolução      | Events e commands possuem schemaVersion e migrations seguem expand-contract.         |
| API           | API pública manipula domínio, não expõe Docker API bruta.                            |
| DR            | Referências de Releases/Secrets/Artifacts permitem reconstrução descrita na Parte 5. |

| **Resultado:** com este modelo, as Partes 1 a 8 deixam de ser apenas decisões conceituais e passam a ter um mapa persistente único. A Parte 10 pode, então, transformar o conjunto em milestones implementáveis sem redefinir entidades durante o desenvolvimento. |
|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
