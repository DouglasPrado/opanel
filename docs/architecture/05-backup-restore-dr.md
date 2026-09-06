---
document: "05"
title: "Backup, Restore e Disaster Recovery"
type: "architecture"
status: "approved"
source: "docx"
---

**PLATAFORMA PAAS  
CLUSTER-FIRST**

**Documento técnico consolidado - Parte 5**

Backup, snapshots, restore, retenção, recuperação da plataforma e Disaster Recovery

| **Campo**       | **Definição**                                                                                                                                                                            |
|-----------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Status          | Documento vivo - v0.5                                                                                                                                                                    |
| Data            | 05 de setembro de 2026                                                                                                                                                                   |
| Escopo          | Proteger e recuperar o estado da própria plataforma e do cluster, sem assumir responsabilidade pelos dados stateful das aplicações nesta fase.                                           |
| Premissas       | Aplicações preferencialmente stateless; PostgreSQL, Redis e Object Storage das aplicações são serviços externos gerenciados; registry externo ou independente; Vault próprio versionado. |
| Decisão central | HA mantém o serviço disponível durante falhas. Backup/DR recupera estado após perda, corrupção, exclusão ou desastre. Os dois mecanismos são independentes e obrigatórios.               |

## Resumo executivo

A plataforma será desenhada para conseguir ser reconstruída em infraestrutura nova sem depender de um servidor específico. O backup protege metadados, secrets criptografadas, certificados, configuração do cluster e referências a artefatos. O restore deve existir como fluxo de produto, não como procedimento manual improvisado. Para incidentes graves, haverá dois caminhos: recuperação rápida do estado existente e reconstrução limpa do cluster a partir do estado desejado salvo pela plataforma.

| **Princípio:** O objetivo de Disaster Recovery não é restaurar uma VPS. É conseguir recriar a plataforma e seus workloads em infraestrutura nova, preservando identidade, configuração, secrets, releases e roteamento. |
|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|

# 1. Escopo de proteção

## 1.1 O que pertence à plataforma

| **Domínio**       | **Conteúdo**                                                                                                                           | **Criticidade** |
|-------------------|----------------------------------------------------------------------------------------------------------------------------------------|-----------------|
| Platform Database | Users, Teams, memberships, Projects, Environments, Services, deployments, domains, policies, audit metadata, bindings e configurações. | Crítica         |
| Vault             | Secret metadata, SecretVersions criptografadas e bindings por Environment/Service.                                                     | Crítica         |
| Encryption State  | Master Encryption Key embrulhada, metadados de key version e parâmetros de derivação/rotação.                                          | Crítica         |
| Certificates      | Certificados TLS, chains, private keys criptografadas, status e versões distribuídas.                                                  | Alta            |
| Swarm State       | Estado Raft, service definitions, configs, secrets materializadas e membership dos nodes.                                              | Alta            |
| Release Metadata  | Commit SHA, image digest, builder, build metadata e relação Release -\> Environment.                                                   | Alta            |
| Runtime Config    | Traefik dynamic config, ingress metadata, node labels, placement policies e cluster settings.                                          | Alta            |
| Audit Log         | Eventos administrativos e operacionais para investigação e compliance.                                                                 | Alta            |

## 1.2 O que fica fora do escopo atual

- PostgreSQL das aplicações do cliente: protegido pelo serviço gerenciado escolhido pelo usuário.

- Redis das aplicações: disponibilidade, persistência e backup delegados ao provedor externo.

- Uploads e objetos: devem estar em Object Storage externo; não depender de disco local de Worker.

- Backups de bancos de terceiros não são copiados automaticamente pela plataforma na primeira fase.

- Persistent volumes de aplicações podem existir futuramente, mas não fazem parte da garantia de HA/DR inicial.

| **Guardrail:** A plataforma pode exibir o status de proteção dos providers externos no futuro, mas não deve afirmar que o dado está protegido sem evidência fornecida pelo próprio provider. |
|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|

# 2. Backup, snapshot e rollback são coisas diferentes

| **Mecanismo**       | **Finalidade**                                    | **Exemplo**                                                       |
|---------------------|---------------------------------------------------|-------------------------------------------------------------------|
| Rollback de Release | Voltar rapidamente para um artefato já conhecido. | api sha256:new -\> sha256:previous                                |
| Config Snapshot     | Congelar estado lógico de Environment/Cluster.    | Services, domains, replicas, secret bindings.                     |
| Backup              | Criar cópia independente e recuperável do estado. | DB dump/PITR + objetos criptografados em storage externo.         |
| Provider Snapshot   | Fotografia de disco/VM do fornecedor.             | Snapshot EBS/Hetzner/DO como camada adicional.                    |
| Disaster Recovery   | Reconstruir a plataforma após perda total.        | Novo cluster + restore do DB + Recovery Key + recreate workloads. |

| **Regra:** Snapshot do servidor não substitui backup. Um snapshot preso ao mesmo provider pode desaparecer junto com a conta, região ou volume. |
|-------------------------------------------------------------------------------------------------------------------------------------------------|

# 3. Arquitetura de proteção

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>PLATFORM<br />
|<br />
v<br />
Backup Controller<br />
|<br />
+------------+------------+<br />
| | |<br />
v v v<br />
Platform DB Cluster State Certificates<br />
backup capture export<br />
| | |<br />
+------------+------------+<br />
|<br />
v<br />
Encrypt + Manifest<br />
|<br />
v<br />
External Backup Store<br />
S3 / R2 / B2 / MinIO<br />
|<br />
retention policy<br />
|<br />
v<br />
Restore Engine</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 3.1 Componentes

| **Componente**      | **Responsabilidade**                                                                            |
|---------------------|-------------------------------------------------------------------------------------------------|
| Backup Controller   | Agenda, serializa, executa e acompanha backup jobs.                                             |
| Backup Adapter      | Implementa captura para cada fonte: PostgreSQL, Swarm state, certificate bundle, config export. |
| Storage Provider    | Abstrai S3-compatible e outros destinos externos.                                               |
| Backup Manifest     | Descreve conteúdo, versões, checksums, encryption metadata, data e dependências.                |
| Restore Engine      | Valida artefatos, executa restore e registra progresso/resultado.                               |
| Verification Worker | Executa checks automáticos de integridade e restore drills.                                     |
| Retention Engine    | Aplica política de retenção sem apagar recovery points ainda referenciados/protegidos.          |

# 4. Banco da própria plataforma

## 4.1 Estratégia recomendada

O Platform Database é a fonte de verdade para o estado de produto. Mesmo que no futuro ele seja hospedado em PostgreSQL gerenciado, a plataforma deve manter uma cópia lógica independente para reduzir dependência do provider.

- Backup lógico periódico para recuperação independente do provider.

- PITR/WAL quando o provider utilizado permitir, reduzindo RPO.

- Backup full diário como recovery point simples e portátil.

- Checksum e manifesto de cada artefato antes de marcar o job como SUCCESS.

- Restore para database temporário durante verification drills.

- Schema version registrada no manifest para garantir compatibilidade com a versão do aplicativo.

## 4.2 RPO/RTO sugeridos

| **Perfil**  | **RPO alvo** | **RTO alvo** | **Estratégia**                                                   |
|-------------|--------------|--------------|------------------------------------------------------------------|
| Development | 24 h         | 4 h          | Full diário; restore manual.                                     |
| Standard    | 1 h          | 1 h          | Incremental/PITR + full diário.                                  |
| Production  | 15 min       | 30-60 min    | PITR contínuo quando disponível + full diário + restore testado. |
| Critical    | \<= 5 min    | \< 30 min    | Provider HA/PITR + cópia independente + runbook automatizado.    |

| **Importante:** Esses valores são objetivos de produto, não promessas automáticas. A UI deve exibir o RPO/RTO efetivamente alcançável com a configuração atual. |
|-----------------------------------------------------------------------------------------------------------------------------------------------------------------|

# 5. Vault próprio e chaves de recuperação

## 5.1 O que entra no backup

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Secret plaintext<br />
|<br />
v<br />
Master Encryption Key (MEK)<br />
|<br />
v<br />
Encrypted SecretVersion<br />
|<br />
v<br />
Platform Database backup<br />
<br />
Recovery Key (user-held)<br />
|<br />
v<br />
KEK / unwrap operation<br />
|<br />
v<br />
Wrapped MEK stored by platform</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

O backup pode conter SecretVersions criptografadas e a Master Encryption Key embrulhada. Ele não deve conter a Recovery Key em plaintext. A Recovery Key permanece sob custódia do usuário e permite recuperar/desembrulhar a MEK em um cenário de Disaster Recovery.

## 5.2 Propriedades obrigatórias

- SecretVersions são imutáveis; restore não altera versões antigas.

- A chave mestra nunca aparece na UI.

- A Recovery Key é exibida no onboarding apenas quando necessário e pode ser rotacionada.

- Backup do banco sem Recovery Key não deve ser suficiente para revelar os secrets.

- Perda da Recovery Key deve ser tratada como risco operacional explícito na UI.

- Rotação de Recovery Key rewrapa a MEK; não exige recriptografar todas as SecretVersions.

- Restore exige verificação criptográfica antes de ativar secrets em workloads.

## 5.3 Estado de recuperação na UI

| **Estado**         | **Significado**                                                    |
|--------------------|--------------------------------------------------------------------|
| READY              | Recovery Key verificada e backup recente disponível.               |
| KEY_NOT_VERIFIED   | Recovery Key gerada, mas confirmação ainda não concluída.          |
| BACKUP_STALE       | Recovery Key válida, mas recovery point está além do RPO desejado. |
| UNRECOVERABLE_RISK | Não há recovery path validado para secrets.                        |
| ROTATION_REQUIRED  | Política exige nova Recovery Key ou key version.                   |

# 6. Certificados TLS

## 6.1 Por que fazer backup mesmo sendo renováveis

Certificados podem ser reemitidos via ACME, mas depender exclusivamente de nova emissão durante um desastre aumenta tempo de recuperação e pode encontrar rate limits, indisponibilidade de DNS provider ou credenciais expiradas. Por isso, certificados e private keys criptografadas entram no backup da plataforma.

- Cada CertificateVersion é imutável.

- Private keys permanecem criptografadas no backup.

- Manifest registra domains, issuer, serial, issuedAt, expiresAt e fingerprint.

- Após restore, o Certificate Manager redistribui a versão ativa para todos os ingress nodes.

- Depois da recuperação, o sistema pode renovar normalmente via ACME/DNS-01.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Backup restored<br />
|<br />
v<br />
Certificate Manager<br />
|<br />
+--&gt; cert v12 + key<br />
|<br />
+--&gt; validate fingerprint/expiry<br />
|<br />
+--&gt; distribute<br />
| | |<br />
v v v<br />
Traefik Traefik Traefik</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

# 7. Estado do Docker Swarm

## 7.1 Dois modos de recuperação

A plataforma não deve depender de uma única estratégia de recuperação do Swarm. Teremos um caminho de recuperação rápida do cluster existente e um caminho de reconstrução limpa a partir do estado desejado.

| **Modo**           | **Quando usar**                                                        | **Resultado**                                                                                              |
|--------------------|------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------|
| Fast Swarm Restore | Managers perdidos, mas deseja-se preservar o cluster e estado Raft.    | Restaura backup de /var/lib/docker/swarm em manager compatível e recupera o Swarm.                         |
| Clean Rebuild      | Perda ampla, cluster corrompido ou mudança de infraestrutura/provider. | Cria novo Swarm e reconstrói networks, services, secrets, configs e ingress usando Platform DB + registry. |

## 7.2 Fast Swarm Restore

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Manager backup<br />
/var/lib/docker/swarm<br />
|<br />
v<br />
New/Recovered Manager<br />
|<br />
v<br />
Restore swarm state<br />
|<br />
v<br />
Start Docker<br />
|<br />
v<br />
Validate nodes/services/secrets<br />
|<br />
v<br />
Rejoin/replace workers</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

O snapshot do estado Raft deve ser tratado como artefato sensível. Ele contém configuração de cluster e material protegido relacionado a secrets do Swarm. O backup deve ser criptografado e nunca ficar em storage público.

## 7.3 Clean Rebuild como estratégia de independência

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Platform DB + Vault + Registry<br />
|<br />
v<br />
New infrastructure<br />
|<br />
v<br />
docker swarm init<br />
|<br />
v<br />
recreate networks<br />
|<br />
v<br />
materialize Swarm Secrets<br />
|<br />
v<br />
recreate services<br />
|<br />
v<br />
distribute certificates<br />
|<br />
v<br />
Traefik ready<br />
|<br />
v<br />
health validation</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

| **Decisão:** Clean Rebuild reduz a dependência de internals do Swarm e permite migrar de servidores ou providers. Por isso, a Platform Database deve armazenar configuração suficiente para recriar o runtime, e não apenas IDs retornados pelo Docker. |
|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|

# 8. Registry e artefatos de release

## 8.1 Imagens são parte do recovery path

O restore da configuração só funciona se as imagens de releases ainda existirem. O Registry é portanto uma dependência de DR, mesmo sendo um serviço externo.

- Deployments apontam para image digest, não apenas tags mutáveis.

- Uma imagem referenciada por Release ativa, rollback point ou snapshot protegido não pode ser removida pelo garbage collector.

- O manifest de backup registra todos os digests necessários para reconstrução.

- Registry externo deve ter sua própria política de durabilidade/replicação.

- Opcional futuro: mirror de imagens críticas em registry secundário.

| **Artefato**                   | **Retenção mínima sugerida**                        |
|--------------------------------|-----------------------------------------------------|
| Release ativa                  | Enquanto ativa + janela de auditoria.               |
| Rollback candidates            | Últimas N releases ou janela temporal configurável. |
| Environment Snapshot           | Enquanto o snapshot existir.                        |
| Protected Release              | Até remoção explícita da proteção.                  |
| Build intermediário sem deploy | Pode expirar agressivamente.                        |

# 9. Snapshots lógicos do produto

## 9.1 Environment Snapshot

Um Environment Snapshot congela o estado lógico necessário para recriar um Environment sem copiar dados externos da aplicação.

| **Incluído**         | **Exemplo**                               |
|----------------------|-------------------------------------------|
| Services             | api, web, worker                          |
| Release/Image digest | api@sha256:abc...                         |
| Resource settings    | replicas, CPU, RAM, restart/update policy |
| Domains              | api.example.com -\> api:3000              |
| Secret bindings      | DATABASE_URL -\> SecretVersion v12        |
| Variables            | NODE_ENV=production                       |
| Placement            | production=true, region=br                |
| Health configuration | path, interval, retries                   |
| Cluster reference    | cluster-prod ou target cluster no restore |

## 9.2 Cluster Configuration Snapshot

- Node inventory e roles no momento do snapshot.

- Node labels e placement conventions.

- Ingress configuration e load balancer targets.

- Traefik static/dynamic settings administradas pela plataforma.

- Certificate versions ativas.

- Network definitions e service relationships.

- Cluster-level policies e quotas.

## 9.3 Snapshot não congela secret plaintext

| **Regra:** Environment Snapshot referencia SecretVersion IDs. Ele não duplica valores de secret. No restore, o Vault resolve a versão original, preservando auditoria e evitando cópias adicionais de material sensível. |
|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|

# 10. Backup Storage Providers

O destino deve ficar fora do cluster protegido. A plataforma usa uma interface comum para permitir mais de um provider sem alterar a lógica de backup.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>BackupStorageProvider<br />
|<br />
+--&gt; S3<br />
+--&gt; Cloudflare R2<br />
+--&gt; Backblaze B2<br />
+--&gt; MinIO external<br />
+--&gt; Generic S3-compatible</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

| **Capacidade**                   | **Obrigatório**                                      |
|----------------------------------|------------------------------------------------------|
| Put/Get/Delete                   | Sim                                                  |
| Multipart upload                 | Para artefatos grandes                               |
| Object checksum                  | Sim                                                  |
| Versioning/Object Lock           | Desejável                                            |
| Lifecycle/retention              | Desejável                                            |
| Encryption at rest provider-side | Desejável, mas não substitui criptografia do cliente |
| Private networking               | Opcional conforme provider                           |

## 10.1 Credenciais do provider

As credenciais de backup são secrets da plataforma e devem usar o mesmo modelo seguro de Vault. Elas nunca são armazenadas em manifest ou logs de backup.

# 11. Criptografia dos backups

## 11.1 Envelope encryption

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Backup payload<br />
|<br />
v<br />
Random Backup Data Key<br />
|<br />
+--&gt; encrypt payload<br />
|<br />
v<br />
Wrapped Data Key<br />
|<br />
v<br />
Backup Manifest<br />
<br />
Recovery path -&gt; unwrap key -&gt; decrypt payload</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

- Cada backup possui data key própria.

- O payload é criptografado antes de sair da plataforma quando aplicável.

- O manifest contém apenas key material embrulhado e metadados não sensíveis.

- Checksums são calculados e validados antes e depois do upload.

- Logs nunca contêm secrets ou private keys descriptografadas.

# 12. Políticas de backup e retenção

## 12.1 BackupPolicy

| **Campo**    | **Exemplo**                                  |
|--------------|----------------------------------------------|
| Name         | Production Standard                          |
| Scope        | Platform / Cluster / Team                    |
| Frequency    | Hourly metadata + daily full                 |
| Retention    | 24 hourly / 14 daily / 8 weekly / 12 monthly |
| Destination  | R2 production-backups                        |
| Encryption   | Client-side enabled                          |
| Verification | Weekly restore drill                         |
| Protection   | Object lock quando disponível                |

## 12.2 Retenção em camadas

Uma política típica pode manter recovery points densos no curto prazo e mais espaçados no longo prazo:

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Last 24h -&gt; hourly<br />
Last 14d -&gt; daily<br />
Last 8w -&gt; weekly<br />
Last 12m -&gt; monthly<br />
Protected -&gt; never delete until unlocked</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 12.3 Antes de apagar

- Verificar se o backup está referenciado por snapshot protegido.

- Verificar dependências incrementais/PITR.

- Respeitar legal hold/object lock.

- Registrar evento de retenção no Audit Log.

- Nunca apagar o último recovery point válido de uma instalação.

# 13. Restore Engine

## 13.1 Restore é uma operação de primeira classe

Restore não deve ser um botão que executa scripts opacos. Ele possui entidade própria, etapas, validação, estado, logs e possibilidade de dry-run quando aplicável.

| **Estado**  | **Descrição**                                                       |
|-------------|---------------------------------------------------------------------|
| PLANNED     | Recovery point selecionado e plano gerado.                          |
| VALIDATING  | Checksum, manifest, compatibility e Recovery Key sendo verificados. |
| PREPARING   | Infraestrutura/DB temporários sendo preparados.                     |
| RESTORING   | Dados/configuração sendo restaurados.                               |
| RECONCILING | Services, secrets, certificates e routing sendo recriados.          |
| VERIFYING   | Health checks e invariantes pós-restore.                            |
| COMPLETED   | Restore finalizado com sucesso.                                     |
| FAILED      | Falha registrada; sistema não deve ocultar estado parcial.          |

## 13.2 Restore seguro por padrão

- Restore destrutivo exige reautenticação e confirmação explícita.

- Quando possível, restaurar em novo recurso antes de substituir o atual.

- DB restore preferencialmente cria database/instance temporária para validação.

- Environment restore pode criar novo Environment clone em vez de sobrescrever production.

- Após validação, troca/cutover é uma etapa separada e auditada.

# 14. Fluxos de recuperação

## 14.1 Voltar uma Release

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Production<br />
image digest v42<br />
|<br />
v<br />
Rollback<br />
|<br />
v<br />
image digest v41<br />
|<br />
v<br />
Swarm rolling update<br />
|<br />
v<br />
health check</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

Esse fluxo não usa backup; usa artefato imutável existente no Registry.

## 14.2 Restaurar configuração de Environment

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Environment Snapshot<br />
|<br />
v<br />
Select target cluster<br />
|<br />
v<br />
Resolve SecretVersions<br />
|<br />
v<br />
Resolve image digests<br />
|<br />
v<br />
Create networks/services/domains<br />
|<br />
v<br />
Validate health</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 14.3 Recuperar instalação inteira

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>New server(s)<br />
|<br />
v<br />
Install platform<br />
|<br />
v<br />
Restore Platform Database<br />
|<br />
v<br />
Enter/verify Recovery Key<br />
|<br />
v<br />
Unlock Vault + certificates<br />
|<br />
v<br />
Connect Registry + Backup Store<br />
|<br />
v<br />
Initialize new Swarm<br />
|<br />
v<br />
Recreate ingress + services<br />
|<br />
v<br />
DNS/LB cutover<br />
|<br />
v<br />
Verification + close incident</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

# 15. Disaster Recovery runbook

## 15.1 Cenário: perda total do cluster

1.  Provisionar nodes novos em provider/região saudável.

2.  Instalar a versão compatível da plataforma.

3.  Conectar ao Backup Store e selecionar último recovery point válido.

4.  Restaurar Platform Database em PostgreSQL saudável.

5.  Fornecer Recovery Key e validar a Master Encryption Key.

6.  Reconectar Registry e confirmar disponibilidade dos image digests requeridos.

7.  Inicializar Swarm novo e registrar managers/workers.

8.  Recriar networks e materializar Swarm Secrets a partir do Vault.

9.  Subir ingress gateways e distribuir certificados.

10. Recriar Services por Environment, respeitando placement/resources.

11. Executar health checks e testes sintéticos.

12. Atualizar Load Balancer/DNS se os IPs de entrada mudaram.

13. Registrar recovery completion e preservar logs/artefatos do incidente.

## 15.2 O que deve funcionar sem o cluster antigo

| **Teste de independência:** O runbook só é considerado válido se puder ser executado sem acesso a nenhum disco, manager ou Worker do cluster perdido. |
|-------------------------------------------------------------------------------------------------------------------------------------------------------|

# 16. Restore verification e drills

## 16.1 Backup bem-sucedido não significa backup recuperável

A plataforma precisa verificar restore periodicamente. O objetivo é detectar backup corrompido, chave perdida, schema incompatível, credencial expirada e processo de recuperação incompleto antes de um incidente real.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Backup completed<br />
|<br />
v<br />
Verification schedule<br />
|<br />
v<br />
Temporary isolated restore<br />
|<br />
+--&gt; DB starts<br />
+--&gt; schema valid<br />
+--&gt; Vault decrypt test<br />
+--&gt; certificates parse<br />
+--&gt; manifest checksums<br />
|<br />
v<br />
PASS / FAIL<br />
|<br />
v<br />
Dashboard + alert</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 16.2 Tipos de drill

| **Drill**           | **Frequência sugerida** | **Validação**                                                |
|---------------------|-------------------------|--------------------------------------------------------------|
| Integrity Check     | Todo backup             | Checksum, manifest, decrypt metadata.                        |
| DB Restore Test     | Semanal                 | Banco temporário abre e migrations/schema são reconhecidos.  |
| Vault Recovery Test | Mensal                  | Secret canary controlado é recuperado com Recovery Key flow. |
| Environment Rebuild | Mensal/trimestral       | Environment de teste recriado a partir de snapshot.          |
| Full DR Drill       | Trimestral/semestral    | Nova infraestrutura recria a plataforma ponta a ponta.       |

# 17. Health de proteção na UI

## 17.1 Dashboard

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Protection Status<br />
<br />
Platform DB HEALTHY<br />
Last backup 18 min ago<br />
RPO 15 min target / 18 min current<br />
Recovery Key VERIFIED<br />
Vault recovery VERIFIED<br />
Certificates PROTECTED<br />
Swarm state 4 h ago<br />
Restore test PASS - 6 days ago<br />
Backup destination HEALTHY</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 17.2 Estados que geram alerta

| **Condição**                                           | **Severidade**                   |
|--------------------------------------------------------|----------------------------------|
| Backup excedeu RPO                                     | Warning/Critical conforme atraso |
| Último backup FAILED                                   | Critical                         |
| Recovery Key não verificada                            | Critical para recovery readiness |
| Backup destination inacessível                         | Critical                         |
| Restore verification falhou                            | Critical                         |
| Certificate backup desatualizado após rotação          | Warning                          |
| Swarm state backup antigo antes de mudança de topology | Warning                          |
| Registry digest necessário indisponível                | Critical                         |

# 18. Modelo de dados

| **Entidade**         | **Campos principais**                                                                      |
|----------------------|--------------------------------------------------------------------------------------------|
| BackupPolicy         | id, teamId, scopeType, scopeId, schedule, retention, storageProviderId, verificationPolicy |
| BackupRun            | id, policyId, type, status, startedAt, completedAt, recoveryPointAt, bytes, error          |
| BackupArtifact       | id, backupRunId, kind, storageKey, checksum, encryptedSize, metadata                       |
| BackupManifest       | backupRunId, platformVersion, schemaVersion, dependencies, encryptionMetadata              |
| EnvironmentSnapshot  | id, environmentId, clusterId, specJson, createdBy, protectedUntil                          |
| ClusterSnapshot      | id, clusterId, configSpec, nodeInventory, certificateVersions                              |
| RestoreOperation     | id, backupRunId/snapshotId, target, mode, status, requestedBy, planJson                    |
| RestoreStep          | restoreOperationId, sequence, type, status, startedAt, completedAt, error                  |
| RecoveryVerification | id, backupRunId, type, status, executedAt, evidenceJson                                    |
| StorageProvider      | id, teamId/instanceId, type, encryptedCredentialsRef, bucket, prefix, status               |

# 19. API e operações principais

| **Operação**                | **Objetivo**                                   |
|-----------------------------|------------------------------------------------|
| POST /backup-policies       | Criar política.                                |
| POST /backup-runs           | Executar backup manual.                        |
| GET /backup-runs            | Listar recovery points e status.               |
| POST /environment-snapshots | Congelar estado lógico de Environment.         |
| POST /cluster-snapshots     | Registrar snapshot de configuração do cluster. |
| POST /restores/plan         | Gerar plano sem executar.                      |
| POST /restores              | Iniciar restore autorizado.                    |
| GET /restores/:id           | Acompanhar etapas e logs.                      |
| POST /recovery-key/verify   | Verificar readiness da chave sem expor MEK.    |
| POST /verification-runs     | Executar restore drill/integrity test.         |

# 20. Permissões e auditoria

## 20.1 Operações sensíveis

- Configurar ou alterar Backup Storage Provider.

- Excluir recovery point protegido.

- Alterar política de retenção.

- Executar restore destrutivo.

- Rotacionar Recovery Key.

- Exportar backup manualmente.

- Executar Full DR recovery.

- Remover proteção de snapshot/release.

## 20.2 Audit events

| **Evento**            | **Exemplo de metadados**                        |
|-----------------------|-------------------------------------------------|
| backup.policy.created | actor, scope, schedule, destination             |
| backup.completed      | recoveryPointAt, bytes, checksum, duration      |
| backup.failed         | stage, errorCode, provider                      |
| restore.requested     | actor, sourceRecoveryPoint, target, destructive |
| restore.completed     | duration, target, verificationResult            |
| recovery_key.verified | actor, method, result                           |
| snapshot.protected    | snapshotId, actor, retention override           |
| backup.deleted        | artifactId, actor, retention reason             |

# 21. Cenários de falha

| **Falha**                               | **Resposta esperada**                                                                                            |
|-----------------------------------------|------------------------------------------------------------------------------------------------------------------|
| Um Worker morre                         | HA/Swarm; sem restore necessário.                                                                                |
| Um Manager morre em cluster com quorum  | HA; substituir manager e continuar.                                                                              |
| Todos os managers são perdidos          | Fast Swarm Restore ou Clean Rebuild.                                                                             |
| Platform DB é apagado                   | Restore DB + Recovery Key + reconcile runtime.                                                                   |
| SecretVersion é alterada incorretamente | Binding rollback para versão anterior; não editar versão existente.                                              |
| Certificados são perdidos               | Restore CertificateVersions ou reemitir via ACME.                                                                |
| Registry perde uma imagem ativa         | Usar réplica/mirror se existir; caso contrário rebuild reproduzível a partir de commit pode ser último recurso.  |
| Backup Store indisponível               | Alertar imediatamente e usar destino secundário quando configurado.                                              |
| Cluster inteiro desaparece              | Full DR em infraestrutura nova.                                                                                  |
| Recovery Key perdida                    | Exibir risco crítico; sem recovery path alternativo definido, secrets históricos podem se tornar irrecuperáveis. |

# 22. Ordem de implementação

14. Definir BackupRun, BackupArtifact, BackupManifest e RestoreOperation no domínio.

15. Implementar StorageProvider S3-compatible.

16. Implementar backup/restore do Platform Database.

17. Integrar Vault encryption state e Recovery Key verification ao recovery path.

18. Exportar/restaurar CertificateVersions.

19. Criar EnvironmentSnapshot e restore para novo Environment.

20. Capturar configuração de Cluster e adicionar Clean Rebuild.

21. Adicionar backup do Swarm Raft para Fast Restore.

22. Criar retention engine e proteção de recovery points.

23. Criar restore verification automático.

24. Adicionar dashboard de Protection Readiness e alertas.

25. Executar primeiro Full DR drill em infraestrutura vazia.

# 23. Decisões consolidadas desta parte

| **Decisão**                                                                                                                | **Status** |
|----------------------------------------------------------------------------------------------------------------------------|------------|
| Stateful data das aplicações permanece em providers externos nesta fase.                                                   | Fechada    |
| A plataforma protege seu próprio estado independentemente do cluster.                                                      | Fechada    |
| Recovery Key não é armazenada em plaintext pela plataforma.                                                                | Fechada    |
| Vault e certificates entram no recovery path criptografados.                                                               | Fechada    |
| Existem dois modos de Swarm recovery: Fast Restore e Clean Rebuild.                                                        | Fechada    |
| Image digest é parte do backup manifest e do DR.                                                                           | Fechada    |
| Environment Snapshot é lógico e referencia SecretVersions, sem duplicar plaintext.                                         | Fechada    |
| Restore é entidade auditável com plano, etapas e verificação.                                                              | Fechada    |
| Backup só é considerado confiável após restore verification periódico.                                                     | Fechada    |
| Backup Storage deve ser externo ao cluster protegido.                                                                      | Fechada    |
| Platform Database: self-hosted vs managed provider permanece decisão de implementação; o formato de backup é independente. | Aberta     |

# 24. Próxima parte

A Parte 6 deve fechar a experiência de infraestrutura e conectividade: onboarding/provisionamento de nodes, providers de cloud, Load Balancer Provider, DNS Provider, Registry Provider, gerenciamento de IPs/firewall, instalação automatizada do Swarm, lifecycle de nodes e expansão/redução do cluster.

| **Resultado:** Ao final da Parte 5, a plataforma já possui um modelo coerente para sobreviver tanto a falhas comuns quanto à perda completa do cluster, sem assumir bancos e storage stateful das aplicações. |
|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|

*Fim da Parte 5 - Backup, Restore e Disaster Recovery*
