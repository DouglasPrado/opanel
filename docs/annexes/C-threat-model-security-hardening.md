---
document: "C"
title: "Threat Model e Security Hardening"
type: "annex"
status: "approved"
source: "docx"
---

**PLATAFORMA PAAS  
CLUSTER-FIRST**

**Anexo C — Threat Model e Security Hardening**

Modelo de ameaças, superfícies de ataque, controles preventivos/detectivos e baseline de hardening para produção

## Resumo executivo

Este anexo define o modelo de ameaças e o baseline de hardening da plataforma PaaS cluster-first. O objetivo não é declarar o sistema “seguro por construção”, mas tornar explícitos os ativos críticos, fronteiras de confiança, cenários de abuso, controles obrigatórios, risco residual e gates que precisam ser satisfeitos antes de produção.

O modelo assume que o Control Plane administra infraestrutura privilegiada: um erro de autorização, um token comprometido ou acesso indevido ao Docker socket pode ter impacto equivalente a comprometimento do cluster. Por isso, operações de infraestrutura são tratadas como ações privilegiadas, auditáveis, idempotentes e separadas da API pública.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th><p><strong>Invariante de segurança</strong></p>
<p>A API pública, frontend, workers comuns e builders nunca recebem acesso ao /var/run/docker.sock. Somente o Swarm Executor privilegiado, restrito aos Manager nodes e com superfície mínima, pode chamar a Docker Engine API.</p></th>
</tr>
</thead>
<tbody>
</tbody>
</table>

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th><p><strong>Limite de isolamento da v1</strong></p>
<p>A plataforma pode compartilhar Workers entre aplicações confiáveis ou semi-confiáveis do mesmo contexto operacional. Docker/Swarm não será vendido como sandbox forte para tenants mutuamente hostis. Um PaaS público com execução arbitrária de código de desconhecidos exigirá isolamento adicional por node dedicado, VM ou microVM.</p></th>
</tr>
</thead>
<tbody>
</tbody>
</table>

# 1. Objetivos de segurança

| **Objetivo**      | **Definição operacional**                                                                                                                          |
|-------------------|----------------------------------------------------------------------------------------------------------------------------------------------------|
| Confidencialidade | Secrets, chaves privadas, tokens, dados de autenticação e material de recuperação não podem ser acessados fora do escopo autorizado.               |
| Integridade       | Desired state, releases, imagens, certificados e operações não podem ser alterados silenciosamente por ator não autorizado.                        |
| Disponibilidade   | Falhas e ataques no Control Plane não devem derrubar workloads já saudáveis; componentes críticos possuem limites, HA e recuperação.               |
| Isolamento        | Teams, Environments e Services devem respeitar escopo lógico, rede, permissões, secrets e placement definidos.                                     |
| Auditabilidade    | Toda operação privilegiada precisa produzir evidência suficiente para reconstruir quem fez o quê, quando, sobre qual recurso e com qual resultado. |
| Recuperabilidade  | Comprometimento ou perda parcial deve permitir rotação de credenciais, restauração do estado e rebuild limpo do cluster.                           |

## 1.1 Princípios obrigatórios

> **•** Least privilege em usuários, tokens, containers, providers, banco e infraestrutura.
>
> **•** Deny by default: ausência de permissão explícita resulta em bloqueio.
>
> **•** Separação entre produto e privilégio de infraestrutura: API decide; executor aplica.
>
> **•** Segredos nunca são usados como identificadores, logs ou parâmetros de URL.
>
> **•** Artefatos de runtime são identificados por digest imutável, não apenas por tags mutáveis.
>
> **•** Builders são tratados como execução de código não confiável e isolados dos Managers e do Vault de produção.
>
> **•** Reautenticação/MFA para ações de alto impacto quando configurado no Team/instância.
>
> **•** Todo controle preventivo crítico deve possuir sinal detectivo correspondente quando possível.

# 2. Ativos críticos e classificação

| **Ativo**                         | **Classificação** | **Impacto de comprometimento**                                                               |
|-----------------------------------|-------------------|----------------------------------------------------------------------------------------------|
| Docker socket / Swarm Manager API | CRÍTICO           | Controle efetivo do cluster, execução privilegiada, leitura/alteração de Services e Secrets. |
| Master Encryption Key             | CRÍTICO           | Permite descriptografar material protegido pelo Vault da plataforma.                         |
| Recovery Key                      | CRÍTICO           | Permite recuperar a chave mestre; perda ou roubo afeta recuperabilidade/confidencialidade.   |
| SecretVersion plaintext           | CRÍTICO           | Credenciais de banco, providers, APIs e aplicações.                                          |
| Certificate private keys          | CRÍTICO           | Possível impersonação dos domínios servidos.                                                 |
| Registry credentials              | ALTO              | Leitura/push de imagens e possível supply-chain compromise.                                  |
| Git provider tokens               | ALTO              | Acesso a source privado e webhooks/instalações.                                              |
| Platform PostgreSQL               | ALTO              | Identidade, RBAC, desired state, operações, bindings, audit e metadata.                      |
| Build infrastructure              | ALTO              | Executa código e Dockerfiles fornecidos pelos repositórios.                                  |
| DNS provider tokens               | ALTO              | Alteração de DNS e emissão via DNS-01.                                                       |
| Audit logs                        | ALTO              | Evidência forense; adulteração reduz capacidade de investigação.                             |
| Metrics/logs                      | MÉDIO/ALTO        | Podem conter metadata sensível e, se mal tratados, secrets acidentais.                       |

# 3. Fronteiras de confiança

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th><p><strong>Fronteiras de confiança principais</strong></p>
<p>INTERNET / CLIENTE<br />
|<br />
v<br />
+----------------------+<br />
| Public API / Web UI | &lt;-- autenticação, RBAC, rate limit<br />
+----------+-----------+<br />
| commands / desired state<br />
v<br />
+----------------------+<br />
| PostgreSQL + Queue | &lt;-- boundary transacional<br />
+----------+-----------+<br />
| operações autorizadas<br />
v<br />
+----------------------+<br />
| Swarm Executor | &lt;-- PRIVILEGIADO<br />
| Manager-only |<br />
+----------+-----------+<br />
| docker.sock<br />
v<br />
+----------------------+<br />
| Docker Swarm |<br />
+----------+-----------+<br />
|<br />
+--&gt; Workers / Services<br />
+--&gt; Traefik / Edge<br />
<br />
BUILD PLANE (separado)<br />
Git --&gt; Builder isolado --&gt; Registry --&gt; Release por digest</p></th>
</tr>
</thead>
<tbody>
</tbody>
</table>

| **Boundary**       | **Regra**                                                                                            |
|--------------------|------------------------------------------------------------------------------------------------------|
| Internet → API     | Nunca confiar em identidade, IP, headers, payload ou origem sem validação.                           |
| API → DB/Queue     | Somente comandos autorizados; payload tipado e validado; idempotency key em mutações importantes.    |
| Queue → Executor   | Executor aceita somente operações originadas pelo Control Plane e com schema/versionamento esperado. |
| Executor → Docker  | Canal local privilegiado; sem exposição TCP pública da Docker API.                                   |
| Builder → Registry | Builder pode publicar artefatos autorizados, mas não administrar cluster nem ler secrets de runtime. |
| Edge → Service     | Traefik roteia apenas para Services explicitamente publicados; redes internas permanecem privadas.   |

# 4. Atores e capacidades adversárias

| **Ator**                               | **Capacidade presumida**                          | **Exemplos**                                                                       |
|----------------------------------------|---------------------------------------------------|------------------------------------------------------------------------------------|
| Internet anônimo                       | Pode enviar requests arbitrários e em volume.     | Credential stuffing, brute force, SSRF payloads, DoS de API, exploração de parser. |
| Usuário autenticado malicioso          | Possui conta válida e permissões limitadas.       | IDOR, tentativa de elevar role, ler secrets de outro Environment, abusar exec.     |
| Developer comprometido                 | Token/sessão legítima roubada.                    | Deploy malicioso, alteração de env, leitura de logs, supply-chain.                 |
| Repositório comprometido               | Código/Dockerfile/build scripts controlados.      | Exfiltração durante build, cryptomining, dependency confusion.                     |
| Workload comprometido                  | Código dentro de container obtém execução.        | Scan de rede, acesso a metadata, abuso de egress, tentativa de escape.             |
| Provider externo comprometido          | Git/DNS/Registry/LB indisponível ou token vazado. | Alteração de DNS, imagem trocada, build/deploy bloqueado.                          |
| Administrador hostil/host comprometido | Acesso root ao host.                              | Fora da proteção completa do app; pode ler memória, disk e socket.                 |

# 5. Modelo de risco

A priorização usa Likelihood (L) e Impact (I) em escala 1–5. O score bruto é L × I. Controles reduzem o risco residual, mas riscos CRÍTICOS não podem ser aceitos apenas por monitoramento.

| **Score** | **Classe** | **Regra**                                                                     |
|-----------|------------|-------------------------------------------------------------------------------|
| 1–4       | LOW        | Pode ser aceito com controles básicos e monitoramento proporcional.           |
| 5–9       | MEDIUM     | Exige owner, mitigação planejada e teste.                                     |
| 10–15     | HIGH       | Bloqueia GA da feature até mitigação ou isolamento compensatório.             |
| 16–25     | CRITICAL   | Bloqueia produção; requer controle preventivo forte e validação independente. |

# 6. Top threats — registro prioritário

| **ID** | **Ameaça**                                       | **L** | **I** | **Risco** | **Controle principal**                                                        |
|--------|--------------------------------------------------|-------|-------|-----------|-------------------------------------------------------------------------------|
| T01    | Comprometimento do docker.sock / Executor        | 3     | 5     | CRITICAL  | Executor mínimo, manager-only, sem API pública, allowlist de operações.       |
| T02    | Escape de container de workload                  | 2     | 5     | HIGH      | Hardening de containers; patching; isolamento forte para tenants hostis.      |
| T03    | Dockerfile/build malicioso acessa infraestrutura | 4     | 5     | CRITICAL  | Builders dedicados/efêmeros, sem socket, sem prod secrets, egress controlado. |
| T04    | RBAC bypass/IDOR entre Teams                     | 3     | 5     | HIGH      | Autorização server-side por recurso + testes negativos e constraints.         |
| T05    | Vazamento de SecretVersion                       | 3     | 5     | HIGH      | Envelope encryption, reveal restrito, redaction, Swarm Secrets.               |
| T06    | Roubo da Recovery Key                            | 2     | 5     | HIGH      | Exibição única, reauth, sem persistência recuperável, orientação offline.     |
| T07    | Webhook forjado/replay                           | 4     | 3     | HIGH      | Assinatura, timestamp/replay window, idempotência por delivery ID.            |
| T08    | Imagem/tag trocada após aprovação                | 3     | 5     | HIGH      | Deploy por digest imutável; registry policy e provenance.                     |
| T09    | SSRF para metadata/serviços internos             | 4     | 4     | CRITICAL  | Allowlist de destinos, egress policy, bloquear link-local/metadata.           |
| T10    | Exec/terminal abusado                            | 3     | 5     | HIGH      | RBAC, reauth, auditoria de sessão, timeout e disable por policy.              |
| T11    | DNS token comprometido                           | 2     | 5     | HIGH      | Token escopado, provider vault, rotação, audit.                               |
| T12    | Cert private key exfiltrada                      | 2     | 5     | HIGH      | Criptografia, distribuição mínima, filesystem protegido, rotação.             |
| T13    | DoS por builds/log streams/deploys               | 4     | 3     | HIGH      | Quotas, concurrency limits, backpressure, rate limit.                         |
| T14    | SQL injection / query scope bypass               | 2     | 5     | HIGH      | Queries parametrizadas, tenancy scoping, code review/testes.                  |
| T15    | Manager quorum/supply compromise                 | 2     | 5     | HIGH      | Rede privada, 3 managers, patching, autolock e backup do Raft.                |

# 7. Identidade, sessão e autorização

## 7.1 Autenticação

> **•** Passwords armazenadas somente com KDF apropriada e parâmetros atualizáveis; nunca encryption reversível.
>
> **•** MFA/TOTP ou WebAuthn deve poder ser exigido para OWNER/ADMIN e para ações críticas.
>
> **•** Sessões possuem expiração absoluta e por inatividade; logout/revocation invalida refresh/session server-side.
>
> **•** Cookies de browser: Secure, HttpOnly, SameSite apropriado; proteção CSRF se autenticação baseada em cookie.
>
> **•** Login, recuperação de conta e MFA possuem rate limit e alertas para comportamento anômalo.

## 7.2 RBAC e tenancy

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th><p><strong>Regra de autorização</strong></p>
<p>Toda decisão de acesso ocorre no backend com Team/Project/Environment explicitamente carregados. A UI esconder um botão não é controle de segurança.</p></th>
</tr>
</thead>
<tbody>
</tbody>
</table>

| **Ação**           | **Controle mínimo**                                                     |
|--------------------|-------------------------------------------------------------------------|
| Ler recurso        | Membership ativo no Team + permission correspondente.                   |
| Alterar PROD       | Permission específica; opcionalmente reauth/MFA conforme política.      |
| Reveal secret      | ADMIN/OWNER ou permission dedicada; reauth; AuditLog.                   |
| Transferir OWNER   | OWNER atual; alvo ADMIN ativo; operação atômica; AuditLog.              |
| Exec/Terminal      | Permission explícita no Service/Environment; reauth; sessão temporária. |
| Gerenciar Instance | INSTANCE_ADMIN separado de TEAM_OWNER.                                  |

## 7.3 Anti-IDOR

> **•** Nunca buscar recurso apenas por ID e depois “confiar” que a rota está no Team correto.
>
> **•** Queries de recurso devem incluir boundary de tenancy ou policy que valide owner chain.
>
> **•** IDs não sequenciais reduzem enumeração, mas não substituem autorização.
>
> **•** Testes de segurança devem tentar acessar o mesmo resource ID a partir de outro Team em todas as APIs críticas.

# 8. Docker socket, Swarm Executor e Managers

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th><p><strong>Privilégio equivalente a root</strong></p>
<p>Acesso ao Docker socket permite criar containers privilegiados, montar filesystem do host e assumir controle efetivo da máquina. O Executor é tratado como componente Tier-0.</p></th>
</tr>
</thead>
<tbody>
</tbody>
</table>

| **Controle**       | **Baseline obrigatório**                                                                                                             |
|--------------------|--------------------------------------------------------------------------------------------------------------------------------------|
| Docker socket      | Unix socket local; nunca exposto em 0.0.0.0:2375. Não montado na API pública.                                                        |
| Executor           | Imagem mínima, sem shell quando possível, read-only rootfs, usuário não-root salvo necessidade estrita de socket group.              |
| Operações          | API interna allowlistada: create/update service, network, secret, inspect, logs/exec autorizados; sem primitive “exec host command”. |
| Managers           | Rede privada; portas Swarm somente entre nodes confiáveis; workloads comuns preferencialmente não executam nos managers.             |
| Autolock           | Habilitável/obrigatório no perfil HA; unlock key protegida fora do cluster.                                                          |
| Docker API version | Negociação/compatibilidade testada; upgrades passam por maintenance workflow.                                                        |
| Audit              | Operation ID correlacionado com chamadas e mudança de desired/applied revision.                                                      |

## 8.1 Hardening de Swarm

> **•** 3 ou 5 managers para HA, com quorum monitorado; número ímpar.
>
> **•** Join tokens tratados como segredo operacional; rotacionáveis após incidente/enrollment indevido.
>
> **•** Enrollment Token da plataforma é single-use, curto e separado do token Swarm bruto.
>
> **•** Nodes removidos passam por drain/verify/remove; credenciais de providers relacionadas também são revogadas.
>
> **•** Overlay/control plane somente em rede privada/VPN quando disponível.
>
> **•** Backup do estado do Swarm e procedimento de clean rebuild testados conforme Anexo de DR.

# 9. Hardening de containers e workloads

| **Controle**      | **Default da plataforma**                                                              |
|-------------------|----------------------------------------------------------------------------------------|
| Privileged        | DENY. Somente allowlist explícita de serviços de infraestrutura da própria plataforma. |
| Host mounts       | DENY para workloads normais. Bind mounts sensíveis exigem policy administrativa.       |
| Docker socket     | DENY em workloads de usuário.                                                          |
| Capabilities      | Drop de capabilities não necessárias; impedir SYS_ADMIN por padrão.                    |
| User              | Preferir container non-root; alertar imagem que exige root.                            |
| Read-only rootfs  | Ativável/recomendado para serviços stateless compatíveis.                              |
| No-new-privileges | Ativar quando compatível.                                                              |
| Resource limits   | CPU/RAM/pids definidos para reduzir noisy neighbor e fork bombs.                       |
| Healthcheck       | Obrigatório/recomendado para serviços elegíveis a HA e rollout seguro.                 |
| Network exposure  | Nenhuma porta pública sem Domain/route ou publicação explicitamente autorizada.        |

## 9.1 Níveis de isolamento

| **Tier**                  | **Cenário**                                           | **Isolamento mínimo**                                                                                                        |
|---------------------------|-------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------|
| T0 — Trusted              | Aplicações do próprio operador/equipe confiável.      | Workers compartilhados + hardening padrão.                                                                                   |
| T1 — Semi-trusted         | Times distintos administrados pela mesma organização. | Network isolation + quotas; opcional node pool dedicado por Team/Environment.                                                |
| T2 — Hostile multi-tenant | Clientes desconhecidos executam código arbitrário.    | Não GA com Docker compartilhado apenas. Exigir node dedicado, VM/microVM, gVisor/Kata/tecnologia equivalente após avaliação. |

# 10. Build plane e código não confiável

O build plane é uma das superfícies de maior risco: um repositório pode executar scripts de instalação, build steps, Dockerfile RUN e ferramentas de package manager. O builder deve ser tratado como sandbox temporária, não como extensão confiável do Control Plane.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th><p><strong>Build plane separado do runtime</strong></p>
<p>Git / Repo<br />
|<br />
v<br />
+----------------------+<br />
| Ephemeral Builder | &lt;-- SEM docker.sock do cluster<br />
| Railpack / BuildKit | &lt;-- SEM Vault de runtime<br />
+----------+-----------+<br />
| push only / scoped credential<br />
v<br />
OCI Registry<br />
| digest<br />
v<br />
Release<br />
|<br />
v<br />
Docker Swarm</p></th>
</tr>
</thead>
<tbody>
</tbody>
</table>

| **Ameaça**           | **Controle**                                                                                                |
|----------------------|-------------------------------------------------------------------------------------------------------------|
| Dockerfile malicioso | Builder dedicado/efêmero; não montar host; não rodar em Managers.                                           |
| Exfiltração por rede | Egress limitado por policy; bloquear ranges internos/link-local/metadata; registrar destinos quando viável. |
| Roubo de secrets     | Build secrets explicitamente declaradas e temporárias; nenhuma secret de runtime por default.               |
| Cryptomining/DoS     | CPU/RAM/pids/timeouts; concurrency quota por Team; kill de build excedido.                                  |
| Cache poisoning      | Cache namespaced e invalidável; não compartilhar cache sensível entre tenants hostis.                       |
| Dependency confusion | Lockfiles, registry allowlist opcional, SBOM/scanning e políticas futuras.                                  |
| Builder persistence  | Workspace destruído após build; logs e artefatos sanitizados conforme retenção.                             |

## 10.1 Build secrets

> **•** Build secret nunca deve virar ENV permanente da imagem.
>
> **•** Não escrever secrets em layers, stdout/stderr ou metadata do BuildKit.
>
> **•** Credential de push ao Registry deve ser limitada ao repositório/namespace e expirar quando possível.
>
> **•** Pull de source privado usa token mínimo e não reutiliza token pessoal de longa duração.

# 11. Supply chain de software

| **Etapa**        | **Controle de integridade**                                                                |
|------------------|--------------------------------------------------------------------------------------------|
| Source           | Registrar provider, repo, branch/ref, commit SHA e identidade do webhook/ator.             |
| Build            | Build recebe source revision imutável e gera metadata/Build ID.                            |
| Artifact         | OCI image registrada por digest sha256; tag é apenas alias de UX.                          |
| Release          | Aponta para digest imutável + Build + source revision.                                     |
| Deploy           | Swarm usa digest aprovado, evitando tag mutável.                                           |
| Promotion        | HML → PROD reutiliza o mesmo Artifact/Release sempre que possível; não rebuilda.           |
| Registry         | Credenciais mínimas; políticas de retenção e proteção contra delete de artifact em uso.    |
| Future hardening | SBOM, vulnerability scanning, assinatura e attestations antes de políticas de enforcement. |

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th><p><strong>Regra de promoção</strong></p>
<p>Promotion deve mover um artefato já testado entre Environments. Rebuildar para produção cria um novo artefato e quebra a cadeia de evidência.</p></th>
</tr>
</thead>
<tbody>
</tbody>
</table>

# 12. Vault, SecretVersions e distribuição

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th><p><strong>Ciclo de vida do secret</strong></p>
<p>SecretVersion plaintext<br />
|<br />
v<br />
Envelope Encryption<br />
|<br />
+--&gt; encryptedValue --&gt; PostgreSQL<br />
|<br />
v (deploy autorizado)<br />
Swarm Secret versão específica<br />
|<br />
v<br />
/run/secrets/... somente na Task autorizada</p></th>
</tr>
</thead>
<tbody>
</tbody>
</table>

| **Controle**  | **Regra**                                                                                                           |
|---------------|---------------------------------------------------------------------------------------------------------------------|
| Persistência  | Somente ciphertext + metadata no PostgreSQL; chave de criptografia separada.                                        |
| Versionamento | SecretVersion é imutável; alteração cria nova versão.                                                               |
| Binding       | Environment/Service aponta para versão específica ou política permitida; PROD preferencialmente pinned.             |
| Reveal        | Não necessário para deploy; ação separada, permissionada, reauth e AuditLog.                                        |
| Distribuição  | Sensitive values usam Swarm Secrets por default; ENV plaintext somente quando compatibilidade exigir e com warning. |
| Logs          | Redaction em API/jobs/build/deploy; payload de Operation nunca inclui plaintext persistido.                         |
| Delete        | Soft delete/retention quando em uso; impedir remoção de versão referenciada por release/snapshot sem workflow.      |

## 12.1 Recovery Key

> **•** Exibida uma única vez após geração/rotação e verificada pelo usuário antes de concluir onboarding.
>
> **•** Nunca registrada em logs, analytics, error reporting ou backups da plataforma.
>
> **•** Rotação rewrapa a chave mestre; não precisa recriptografar todo o Vault.
>
> **•** Recovery Key e backup do banco não devem ficar no mesmo domínio de confiança.
>
> **•** Procedimento de recuperação exige ambiente controlado e produz AuditLog/registro operacional.

# 13. Webhooks, Git e integrações externas

| **Superfície**            | **Controle mínimo**                                                                                        |
|---------------------------|------------------------------------------------------------------------------------------------------------|
| GitHub/Git webhooks       | Validar assinatura; delivery/event ID; timestamp quando disponível; replay protection; payload size limit. |
| OAuth/installation tokens | Scopes mínimos; criptografados; rotação/revocation; nunca enviados ao browser após persistência.           |
| Callback URLs             | Allowlist rígida; state/nonce; proteção contra open redirect.                                              |
| Provider APIs             | Timeout, retry com jitter, circuit breaker e idempotência onde suportada.                                  |
| User-supplied URL         | Canonicalização; bloquear schemes inesperados; SSRF policy; DNS rebinding considerations.                  |
| Registry webhooks         | Autenticação e validação de digest/repository namespace.                                                   |

## 13.1 SSRF baseline

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th><p><strong>SSRF é risco crítico</strong></p>
<p>Qualquer feature que “busca uma URL” pode virar ponte para Docker API, metadata cloud, Redis/Postgres internos, services privados ou endpoints administrativos.</p></th>
</tr>
</thead>
<tbody>
</tbody>
</table>

> **•** Bloquear localhost, loopback, link-local, RFC1918/ULA e metadata endpoints quando a operação não exige rede interna.
>
> **•** Resolver DNS e validar IP final; tratar redirects como nova decisão de policy.
>
> **•** Não aceitar unix://, file://, gopher:// ou schemes não explicitamente suportados.
>
> **•** Builders e webhooks possuem egress/network policy própria; não confiar em firewall de aplicação apenas.

# 14. Networking, Edge e Traefik

| **Área**            | **Hardening**                                                                                              |
|---------------------|------------------------------------------------------------------------------------------------------------|
| LB → Traefik        | L4/TCP padrão; health check; origem restrita quando provider permite.                                      |
| Trusted proxies     | Configurar lista explícita; não confiar em X-Forwarded-\* de qualquer origem.                              |
| Environment network | Overlay dedicada por Environment; nenhum cross-environment implícito.                                      |
| Service exposure    | Somente Traefik ou published port explicitamente configurado.                                              |
| Rate limiting       | API pública, auth, webhooks e endpoints de alto custo possuem limites próprios.                            |
| Headers             | HSTS/CSP/frame/referrer e headers adequados para o painel; não impor política global às apps dos usuários. |
| Internal routes     | Dashboard Traefik, Docker API e exporters nunca públicos por default.                                      |
| DDoS                | Delegar volumetria a provider/CDN/LB; Control Plane aplica backpressure e quotas.                          |

## 14.1 DNS e Certificate Manager

> **•** DNS provider token com menor escopo possível, idealmente zona específica.
>
> **•** DNS-01 executado pelo Certificate Manager centralizado; Traefiks não competem pelo mesmo ACME state.
>
> **•** Private keys criptografadas em repouso e distribuídas somente aos ingress nodes necessários.
>
> **•** Renovação gera nova CertificateVersion; ativação somente após distribuição confirmada.
>
> **•** Falha de renovação dispara alerta antes da janela crítica de expiração.

# 15. Terminal, exec e ações interativas

Terminal/exec transforma um usuário com permissão de plataforma em operador dentro do container. É uma feature de alto risco e deve ser opt-in/policy-controlled.

| **Controle**             | **Requisito**                                                                                                            |
|--------------------------|--------------------------------------------------------------------------------------------------------------------------|
| Autorização              | Permission dedicada por Environment/Service; VIEWER nunca recebe exec.                                                   |
| Reautenticação           | Exigir reauth/MFA para PROD ou quando policy determinar.                                                                 |
| Target                   | Somente Task/container selecionado; nunca shell do host/Manager.                                                         |
| Sessão                   | TTL e idle timeout; encerramento automático ao perder permissão/sessão.                                                  |
| Audit                    | Quem iniciou, Service, Environment, Task, início/fim e motivo; conteúdo completo opcional conforme política/privacidade. |
| Transferência de arquivo | Não habilitar implicitamente; feature separada e auditada.                                                               |

# 16. PostgreSQL, filas e estado interno

| **Risco**           | **Controle**                                                                                      |
|---------------------|---------------------------------------------------------------------------------------------------|
| SQL injection       | Queries parametrizadas/ORM seguro; nenhuma concatenação de input em SQL.                          |
| Tenant scope bypass | Policies/queries scoped; unique constraints incluem owner quando necessário; testes cross-team.   |
| DB credential leak  | Credential em secret store da própria instalação; rotação; TLS conforme provider.                 |
| Queue tampering     | Payload interno versionado e validado; não desserializar classes arbitrárias/objetos executáveis. |
| Duplicate delivery  | Operation/Outbox idempotentes; unique keys e state machine rejeitam replay inválido.              |
| Stale worker        | Leases/fencing tokens impedem worker expirado de aplicar resultado.                               |
| Migration failure   | Expand-contract; backup e rollback plan; migrations não destrutivas em primeira fase.             |

# 17. Logs, métricas, tracing e AuditLog

| **Tipo**         | **Regra de segurança**                                                                                 |
|------------------|--------------------------------------------------------------------------------------------------------|
| Application logs | Conteúdo do usuário; redaction best-effort; acesso scoped ao Team/Environment.                         |
| Platform logs    | Nunca logar secrets, passwords, auth headers, recovery material ou private keys.                       |
| Build logs       | Tratar como não confiáveis; sanitizar UI; limitar tamanho e retenção.                                  |
| AuditLog         | Append-oriented; acesso restrito; registrar actor/resource/action/result/IP/context quando pertinente. |
| Metrics          | Evitar labels de alta cardinalidade e valores sensíveis.                                               |
| Tracing          | Sanitizar headers/body; trace ID pode correlacionar Operation e request sem carregar segredo.          |

## 17.1 Redaction

> **•** Auth headers, cookies, passwords, private keys e known secret values devem ser mascarados antes de sinks de log.
>
> **•** Não depender exclusivamente de regex genérica: cada boundary que conhece secrets deve evitar logá-los na origem.
>
> **•** Erros retornados ao usuário não incluem stack trace, SQL, paths internos ou payload criptográfico.

# 18. Host OS e node hardening

| **Área**            | **Baseline**                                                                            |
|---------------------|-----------------------------------------------------------------------------------------|
| Sistema operacional | Distribuição suportada/minimal; patches de segurança e janela de upgrade definida.      |
| SSH                 | Keys; password login desabilitável; root login restrito; allowlist/VPN quando possível. |
| Firewall            | Default deny inbound; abrir apenas portas do Edge e do Swarm na rede correta.           |
| Users/groups        | Privilégios mínimos; acesso ao grupo docker tratado como root-equivalent.               |
| Filesystem          | Permissões restritas em /etc da plataforma, certificados, config e backups temporários. |
| Time                | NTP/clock sync obrigatório para TLS, tokens, logs e consenso operacional.               |
| Disk                | Alertas de uso/inodes; proteção contra log/build cache consumir o host.                 |
| Kernel/Docker       | Versões suportadas e testadas; upgrades via maintenance/drain.                          |

# 19. Abuse prevention e quotas

| **Vetor**         | **Proteção**                                                                       |
|-------------------|------------------------------------------------------------------------------------|
| API flood         | Rate limit por IP/session/token + global protection.                               |
| Build flood       | Concurrency por Team; queue quotas; timeout; resource limit.                       |
| Deploy spam       | Coalescing/supersession quando seguro; limit de operações simultâneas por Service. |
| Log streaming     | Limite de streams por usuário/Team; backpressure; max bytes/time window.           |
| Autoscaling abuse | Min/max replicas, cooldown e hard quota do Team/cluster.                           |
| Registry abuse    | Retention/GC, limite de storage e proteção de digests em uso.                      |
| Secret versions   | Limites razoáveis e retention policy; operações bulk auditadas.                    |

# 20. Backup, DR e resposta a comprometimento

> **•** Backups criptografados e off-site; credenciais de backup não dão acesso administrativo ao cluster.
>
> **•** Recovery Key fora do backup principal; Master Key não deve viajar em plaintext junto ao dump.
>
> **•** Restore drill valida não apenas banco, mas capacidade de recuperar Vault, certificados e desired state.
>
> **•** Clean rebuild é o caminho preferido após suspeita de comprometimento profundo do host/manager.
>
> **•** Após incidente de credencial: revogar sessões/tokens, rotacionar provider credentials, secrets impactadas, join tokens e certificados quando aplicável.

## 20.1 Classes de incidente de segurança

| **Classe**     | **Exemplo**                                                           | **Resposta inicial**                                                                          |
|----------------|-----------------------------------------------------------------------|-----------------------------------------------------------------------------------------------|
| SEC-1 Critical | docker.sock/Manager ou Master Key comprometida.                       | Isolar cluster/host, suspender mutações, preservar evidência, iniciar clean rebuild/rotation. |
| SEC-2 High     | Admin session, DNS/Registry token ou production secret vazada.        | Revogar credencial, rotacionar dependências, revisar AuditLog e deployments.                  |
| SEC-3 Medium   | Webhook replay, brute force, policy violation sem impacto confirmado. | Bloquear origem/ator, ajustar controle, investigar escopo.                                    |
| SEC-4 Low      | Scan/erro de configuração sem exploração.                             | Corrigir, registrar e acompanhar tendência.                                                   |

# 21. Security testing obrigatório

| **Camada**     | **Testes mínimos**                                                                          |
|----------------|---------------------------------------------------------------------------------------------|
| Auth/RBAC      | Unit + integration + cross-team negative tests + role matrix.                               |
| API            | SAST, dependency scan, input fuzzing seletivo, SSRF test cases, rate limit.                 |
| Docker/Swarm   | Testar ausência de socket em componentes indevidos; privileged/mount/capability policies.   |
| Builders       | Repo malicioso de fixture tentando ler host, metadata, network interna e secrets.           |
| Vault          | Crypto round-trip, key rotation, wrong key failure, redaction, reveal authorization.        |
| Webhooks       | Invalid signature, replay, duplicate delivery, oversized payload, wrong event.              |
| Edge           | Trusted proxy, host header, TLS renewal, default deny routes, admin endpoints não públicos. |
| Supply chain   | Digest pinning, tag mutation, artifact GC protection, promotion sem rebuild.                |
| Backup/DR      | Restore drill + clean rebuild + recovery key verification.                                  |
| Chaos/security | Node loss durante operação, executor restart, stale lease, provider outage.                 |

## 21.1 Ferramentas/processos recomendados

> **•** Dependency/SCA scanning em Ruby/JS/Rust conforme stack final e em imagens OCI.
>
> **•** Image vulnerability scan no Registry/CI; policy inicialmente informativa e depois bloqueadora por severidade/exploitability.
>
> **•** Secret scanning em source e commits; prevenção de credenciais em repositório.
>
> **•** Pentest antes de GA multi-team e novamente antes de qualquer modo public multi-tenant hostil.
>
> **•** Revisão de threat model em features que criem nova boundary: managed DB, plugins, Kubernetes, marketplace, multi-region.

# 22. Security gates por fase

| **Gate**                  | **Condição de aprovação**                                                                              |
|---------------------------|--------------------------------------------------------------------------------------------------------|
| G1 — Internal Alpha       | Sem Docker API pública; RBAC básico testado; Vault ciphertext; builders separados logicamente.         |
| G2 — Private Beta         | Cross-team isolation testado; webhook signatures; rate limits; AuditLog; backup/restore.               |
| G3 — Production           | Executor hardened; manager network private; secret redaction; security monitoring; incident runbook.   |
| G4 — HA Production        | 3 managers, ingress HA, autolock/recovery tested, node lifecycle/rotation validated.                   |
| G5 — Public Multi-Team    | Pentest externo; quotas; abuse controls; supply-chain scanning; support process.                       |
| G6 — Hostile Multi-Tenant | NÃO liberar com Docker compartilhado apenas; exigir strong isolation architecture e novo threat model. |

# 23. Checklist de go-live

| **Área**          | **Checklist**                                                                      |
|-------------------|------------------------------------------------------------------------------------|
| Identity          | MFA/re-auth policy definida; session revocation testada; OWNER transfer auditada.  |
| RBAC              | Cross-Team/Environment negative tests passando.                                    |
| Docker            | Socket só no Executor; nenhum workload privileged por default; daemon não exposto. |
| Swarm             | Managers em rede privada; quorum/health; join token rotation documentada.          |
| Build             | Builders não executam em managers; sem runtime secrets; resource/time limits.      |
| Vault             | Encryption/recovery/rotation testadas; redaction verificada.                       |
| Supply chain      | Release por digest; promotion sem rebuild; registry credentials escopadas.         |
| Edge              | Traefik/admin endpoints privados; trusted proxies; TLS renewal testado.            |
| Webhooks          | Signature/replay/idempotency testados.                                             |
| Audit             | Eventos privilegiados chegando e consultáveis.                                     |
| Backup/DR         | Restore drill recente e recovery material validado.                                |
| Incident response | Runbook e contatos/roles definidos; capacidade de revogar/rotacionar credenciais.  |

# 24. Riscos residuais declarados

| **Risco residual**                      | **Posicionamento**                                                                                                   |
|-----------------------------------------|----------------------------------------------------------------------------------------------------------------------|
| Root no host compromete workloads       | Aceito como limite da arquitetura; hardening/patching reduzem probabilidade, não eliminam impacto.                   |
| Container escape zero-day               | Mitigado por atualização, least privilege e tiers de isolamento; hostile multi-tenant requer sandbox mais forte.     |
| Administrador legítimo malicioso        | Audit, dual-control futuro e least privilege reduzem risco; OWNER/INSTANCE_ADMIN continuam papéis de alta confiança. |
| Provider externo comprometido           | Tokens escopados, rotação e recovery reduzem blast radius; dependência não é eliminável.                             |
| Secret usado por aplicação comprometida | Uma aplicação autorizada ao secret pode lê-lo. Segmentação por Service limita blast radius.                          |
| DDoS volumétrico                        | Mitigação principal pertence ao LB/CDN/provider; o Control Plane não substitui scrubbing network.                    |

# 25. Decisões consolidadas de segurança

> **•** Control Plane público não possui acesso ao Docker socket.
>
> **•** Swarm Executor é Tier-0, manager-only e opera por comandos internos allowlistados.
>
> **•** Builders são isolados do runtime, managers e secrets de produção.
>
> **•** Deploy usa Artifact digest imutável; tags são metadata/aliases.
>
> **•** Vault é próprio, versionado e criptografado com envelope encryption; Recovery Key é separada.
>
> **•** Sensitive runtime config usa Swarm Secrets por default.
>
> **•** Environments possuem overlay networks isoladas.
>
> **•** Múltiplos Traefiks recebem certificados do Certificate Manager centralizado; DNS-01 é preferido para HA.
>
> **•** Terminal/exec é feature privilegiada e auditada.
>
> **•** Docker compartilhado não é considerado strong isolation para hostile multi-tenancy.
>
> **•** Segurança é gate de release: risco CRITICAL/HIGH sem mitigação bloqueia GA da feature.

# 26. Critérios de aceite do Anexo C

| **Critério**         | **Aceite**                                                                                            |
|----------------------|-------------------------------------------------------------------------------------------------------|
| Threat registry      | Top threats possuem owner técnico, controle preventivo e cenário de teste.                            |
| Trust boundaries     | Componentes privilegiados e não privilegiados estão claramente separados.                             |
| Docker hardening     | Nenhum componente público tem socket; policies impedem primitives perigosas por default.              |
| Build isolation      | Build malicioso de fixture não consegue acessar runtime secrets, manager ou host socket.              |
| RBAC isolation       | Suite cross-team/environment não encontra leitura/mutação indevida.                                   |
| Vault                | Ciphertext em repouso, reveal auditado, rotation/recovery testados e logs sem plaintext.              |
| Supply chain         | Artifact por digest e promotion sem rebuild funcionam end-to-end.                                     |
| Incident readiness   | É possível revogar sessões/tokens, rotacionar secrets/providers e executar clean rebuild documentado. |
| Public multi-tenancy | Permanece bloqueada até strong isolation ser desenhado e validado.                                    |
