---
document: "D"
title: "Estratégia Completa de Testes"
type: "annex"
status: "approved"
source: "docx"
---

**PLATAFORMA PAAS  
CLUSTER-FIRST**

**Anexo D — Estratégia Completa de Testes**

*Test strategy, ambientes, automação, qualidade, resiliência e gates de release para validar o Control Plane e o Runtime*

## Resumo executivo

Este anexo transforma as decisões arquiteturais, os casos de uso, os SLOs e o Threat Model da plataforma em uma estratégia de verificação executável. O objetivo é impedir que a qualidade dependa de testes manuais isolados ou de uma única suíte E2E: cada camada deve ser validada no nível mais barato e determinístico possível, e os riscos de infraestrutura devem ser exercitados em ambientes Docker/Swarm reais antes de produção.

A estratégia adota quatro ideias centrais: pirâmide de testes para lógica de domínio, contratos explícitos nas fronteiras, ambientes reais para comportamento de infraestrutura e gates progressivos de release. Testes de carga, chaos, restore, upgrade e segurança não são atividades opcionais de fim de projeto; eles fazem parte da definição de production-ready.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th><p><strong>Regra de ouro</strong></p>
<p>Nenhuma alteração pode ser considerada segura apenas porque a API respondeu 200. Para operações de infraestrutura, o teste precisa verificar também estado persistido, Operation, efeitos no Swarm, estado observado, idempotência, rollback/compensação e sinais de observabilidade.</p></th>
</tr>
</thead>
<tbody>
</tbody>
</table>

# 1. Objetivos e princípios da estratégia

## 1.1 Objetivos

• Validar comportamento funcional do produto e invariantes de domínio.

• Validar integração com PostgreSQL, Docker Engine, Swarm, Registry, Traefik, BuildKit/Railpack, DNS e storage.

• Provar que operações são idempotentes, recuperáveis e seguras sob concorrência e falhas.

• Medir se a plataforma cumpre os NFRs e SLOs definidos no Anexo B.

• Exercitar cenários de segurança e abuso definidos no Anexo C.

• Provar que backup, restore, upgrade e rollback funcionam antes de uma emergência real.

• Produzir evidência objetiva para promover uma versão entre ambientes.

## 1.2 Princípios obrigatórios

| **Princípio**                          | **Aplicação prática**                                                                                                                   |
|----------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------|
| Shift-left sem simular o mundo inteiro | Domínio e application services rodam rápido em unit/integration tests; Docker/Swarm é usado apenas quando o comportamento depende dele. |
| Testar contratos, não detalhes         | Fronteiras de módulos e providers possuem contract tests; refactors internos não devem quebrar suítes sem alteração de comportamento.   |
| Infra precisa de infra real            | Scheduler, rolling update, overlay, secrets, events, restart e placement não são validados apenas por mocks.                            |
| Determinismo antes de volume           | Flaky tests são defeitos. Retries não podem esconder uma suíte instável.                                                                |
| Falhas são casos de uso                | Timeout, duplicidade, crash, perda de quorum e indisponibilidade externa fazem parte da matriz normal de testes.                        |
| Evidência reproduzível                 | Carga, restore, chaos, segurança e upgrade geram artefatos com versão, commit, ambiente, parâmetros e resultado.                        |
| Produção não é laboratório             | Testes destrutivos usam ambientes dedicados ou janelas/controladores explicitamente aprovados.                                          |

# 2. Taxonomia e pirâmide de testes

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th><strong>Static checks / schema / lint<br />
</strong>↓<br />
<strong>Unit tests<br />
</strong>↓<br />
<strong>Integration tests<br />
</strong>↓<br />
<strong>Contract tests<br />
</strong>↓<br />
<strong>Docker / Swarm integration<br />
</strong>↓<br />
<strong>E2E<br />
</strong>↓<br />
<strong>Load · Chaos · Security · Restore · Upgrade</strong></th>
</tr>
</thead>
<tbody>
</tbody>
</table>

A quantidade de testes diminui conforme o custo e a abrangência aumentam. O topo da pirâmide não substitui as camadas inferiores: um E2E não deve ser usado para testar todas as combinações de validação que podem ser verificadas em milissegundos no domínio.

| **Classe**      | **Objetivo**                                 | **Frequência**            | **Bloqueia** |
|-----------------|----------------------------------------------|---------------------------|--------------|
| Static          | Compilação, lint, tipos, migrations, schemas | Todo PR                   | Merge        |
| Unit            | Regras puras, state machines, policies, diff | Todo PR                   | Merge        |
| Integration     | DB, repositories, jobs, transações, crypto   | Todo PR                   | Merge        |
| Contract        | API, eventos, providers, executor            | Todo PR / merge           | Merge        |
| Docker/Swarm    | Efeito real da Docker API e reconciliação    | Merge / nightly           | Release      |
| E2E             | Jornadas reais UI/API → runtime              | Merge / release candidate | Release      |
| Performance     | SLOs, capacidade e regressão                 | Nightly / RC              | Produção     |
| Chaos           | Comportamento sob falhas                     | Nightly / RC              | Produção HA  |
| Security        | Controles e abuso                            | PR + RC + periódico       | Produção     |
| Restore/Upgrade | Recuperação e mudança de versão              | RC / periódico            | Produção     |

# 3. Ambientes de teste

| **Ambiente**      | **Propósito**             | **Características**                                                                       |
|-------------------|---------------------------|-------------------------------------------------------------------------------------------|
| Local             | Feedback do desenvolvedor | PostgreSQL isolado; Docker local; fixtures; sem dependências externas obrigatórias.       |
| CI ephemeral      | PR/merge                  | DB por job; serviços auxiliares descartáveis; seed determinístico; paralelização.         |
| Swarm Integration | Runtime real              | Cluster Swarm dedicado, Registry, Traefik; pode ser recriado automaticamente.             |
| Build Lab         | Código não confiável      | Builders isolados; BuildKit/Railpack; sem acesso ao Control Plane/produção.               |
| Performance Lab   | Carga/capacidade          | Topologia fixa e registrada; métricas completas; sem ruído de workloads não relacionados. |
| Chaos/DR Lab      | Falhas destrutivas        | Permite matar nodes, perder quorum, restaurar DB/Swarm e simular perda de dependências.   |
| Staging/HML       | Release candidate         | Configuração próxima de produção; integrações reais não destrutivas; dados sintéticos.    |

## 3.1 Reprodutibilidade

• Cada ambiente de laboratório deve ser provisionável por código e possuir versão conhecida de Docker, Traefik, BuildKit e componentes da plataforma.

• Os testes não podem depender de ordem global; recursos recebem IDs/sufixos únicos e cleanup idempotente.

• Clock, random e providers externos devem ser controláveis nos testes onde determinismo for necessário.

• Fixtures de produção não devem ser copiadas para CI; usar dados sintéticos e sanitizados.

# 4. Static checks e testes unitários

## 4.1 Static checks

| **Check**                 | **Falha que deve detectar**                                                      |
|---------------------------|----------------------------------------------------------------------------------|
| Compiler/type checker     | Tipos incompatíveis, imports inválidos, APIs internas quebradas.                 |
| Lint/format               | Padrões proibidos, complexidade ou convenções críticas.                          |
| Migration validation      | Migração inválida, dependência fora de ordem, mudança destrutiva não autorizada. |
| OpenAPI/schema validation | DTO/evento incompatível ou referência quebrada.                                  |
| Dependency/license scan   | Pacotes vulneráveis ou licenças fora da política.                                |
| Secret scan               | Tokens, chaves privadas e credentials commitidos.                                |
| Container/IaC lint        | Dockerfiles/configurações perigosas e manifestos inválidos.                      |

## 4.2 Escopo dos unit tests

• State machines: Operation, Build, Deployment, Certificate, Backup, RestoreJob e Node.

• RBAC/policies e regras de ownership.

• Diff Desired State × Actual State e classificação NOOP/CREATE/UPDATE_SAFE/ROLLOUT/DELETE/BLOCKED/DRIFT.

• Cálculo de revisions, supersession, retry/backoff e deadlines.

• Validação de domains, ports, resource limits, quotas e bindings.

• Autoscaling: janela, cooldown, limites e decisão de scale.

• Criptografia de envelope: apenas propriedades e invariantes; primitives reais ficam em integração.

• Normalização de provider errors para o error model da plataforma.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th><p><strong>Não mockar o próprio domínio</strong></p>
<p>Unit tests devem instanciar os objetos/regras reais. Mocks são reservados para fronteiras externas; não devem reproduzir internamente a lógica que está sendo testada.</p></th>
</tr>
</thead>
<tbody>
</tbody>
</table>

# 5. Integração com PostgreSQL e transações

Os testes de persistência devem usar PostgreSQL real, nunca SQLite como substituto, porque a arquitetura depende de constraints, índices, locks, JSONB, isolamento transacional, partial indexes e concorrência específicos do PostgreSQL.

| **Área**              | **Cenários obrigatórios**                                                        |
|-----------------------|----------------------------------------------------------------------------------|
| Constraints           | OWNER único; slugs; domain bindings; versão imutável; FKs e checks.              |
| Transactions          | Desired State + Operation + Outbox persistidos atomicamente.                     |
| Idempotency           | Mesma idempotency key não duplica mutação/Operation.                             |
| Locks/leasing         | Dois workers não aplicam a mesma Operation; fencing rejeita worker antigo.       |
| Outbox                | Commit publica uma vez logicamente; crash entre commit e publish é recuperável.  |
| Pagination            | Cursor estável sob inserções concorrentes.                                       |
| Soft delete/retention | Recursos ocultos sem quebrar auditoria e referências imutáveis.                  |
| Migrations            | Upgrade e downgrade/forward-fix conforme política; expand-contract sem downtime. |

## 5.1 Testes de concorrência de banco

Criar testes específicos com múltiplas conexões/barreiras para reproduzir race conditions. A suíte deve provar, entre outros, que duas requisições simultâneas de scale, deploy ou transfer de ownership resultam em um estado final válido e auditável, sem lost update.

# 6. Contract tests: APIs, eventos e módulos

## 6.1 API pública

| **Contrato**         | **Verificação**                                                                       |
|----------------------|---------------------------------------------------------------------------------------|
| Request/response DTO | Campos obrigatórios, formatos, enums, compatibilidade e validação.                    |
| Error envelope       | Código estável, mensagem segura, details, correlationId/operationId quando aplicável. |
| Pagination/filtering | Cursor, ordering, filtros e limites.                                                  |
| Authorization        | Mesma rota exercitada por OWNER/ADMIN/MEMBER/sem permissão.                           |
| Async mutation       | Retorna Operation/operationId e não promete conclusão síncrona indevida.              |
| Versioning           | Mudanças incompatíveis exigem nova versão ou janela formal de depreciação.            |

## 6.2 Eventos e Outbox

Eventos de domínio/integração possuem schema versionado. Consumer contract tests devem provar compatibilidade entre produtor e consumidor, tolerância a campos adicionais e comportamento diante de duplicidade, reordenação quando permitida e replay.

## 6.3 Provider contracts

| **Provider interface** | **Contract tests mínimos**                                          |
|------------------------|---------------------------------------------------------------------|
| Registry               | Push/pull/manifest/digest/auth/not found/rate limit.                |
| DNS                    | Create/update/delete TXT/A/AAAA/CNAME, propagation state, conflict. |
| Load Balancer          | Target add/remove/health, idempotência e provider error.            |
| Object Storage         | Put/get/list/delete, checksum, multipart quando usado.              |
| Git                    | Webhook validation, commit resolution, clone credential lifecycle.  |
| Certificate/ACME       | Challenge lifecycle, renewal, failure/retry e version activation.   |

# 7. Docker Engine e Swarm integration tests

Esta é uma suíte separada dos testes comuns. Ela deve conversar com Docker Engine real e, para comportamento de orquestração, com um cluster Swarm real. Não é suficiente mockar respostas da API Docker.

| **Subsistema**       | **Cenários**                                                           |
|----------------------|------------------------------------------------------------------------|
| Service lifecycle    | Create, inspect, update, scale, remove e convergência de Tasks.        |
| Rolling update       | Nova image digest, update_config, health failure, rollback.            |
| Restart/self-healing | Matar Task/container e observar reposição pelo Swarm.                  |
| Placement            | Node labels/constraints e ausência de node elegível.                   |
| Networks             | Overlay por Environment, service discovery e isolamento.               |
| Secrets              | Attach somente a Service autorizada; version rotation; remoção segura. |
| Events               | Consume, reconnect, duplicate/replay handling e resync.                |
| Nodes                | Join, drain, activate, promote/demote quando suportado pelo fluxo.     |
| Executor             | Docker socket apenas no executor; API pública sem acesso direto.       |

## 7.1 Teste do reconciler

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th><strong>Desired State rev 42<br />
</strong>↓<br />
<strong>Reconciler computes diff<br />
</strong>↓<br />
<strong>Operation RUNNING<br />
</strong>↓<br />
<strong>Docker Service Update<br />
</strong>↓<br />
<strong>Swarm converges Tasks<br />
</strong>↓<br />
<strong>Actual State observed<br />
</strong>↓<br />
<strong>appliedRevision = 42 · Operation SUCCEEDED</strong></th>
</tr>
</thead>
<tbody>
</tbody>
</table>

Para cada ação principal deve existir pelo menos um cenário de convergência normal, um de retry recuperável, um de falha terminal e um de operação superseded por uma revisão mais nova.

# 8. Build pipeline: Git, Railpack, BuildKit e Registry

| **Cenário**          | **Resultado esperado**                                                                                  |
|----------------------|---------------------------------------------------------------------------------------------------------|
| Repo suportado       | Railpack detecta, gera plano, BuildKit produz OCI image e Registry retorna digest.                      |
| Dockerfile explícito | Ignora auto-detection e usa Dockerfile configurado.                                                     |
| Commit pinning       | Build referencia SHA exato; novo push não altera build antigo.                                          |
| Cache hit/miss       | Resultado funcional idêntico; métricas de cache registradas.                                            |
| Build failure        | Logs completos, secret redaction, Operation/Build FAILED e nenhum Release inválido.                     |
| Timeout/cancel       | Processo é terminado e recursos temporários limpos.                                                     |
| Malicious build      | Sem acesso a manager socket, Vault de produção ou metadata/cloud endpoints proibidos.                   |
| Registry unavailable | Retry/backoff; não inicia deploy sem artifact digest disponível.                                        |
| Rebuild same commit  | Artifact pode mudar apenas se inputs/build environment versionados mudarem; provenance registra inputs. |

## 8.1 Corpus de aplicações de teste

Manter um repositório de fixtures versionado com aplicações pequenas representando stacks suportadas, monorepo, health check, WebSocket/SSE, migrations, build pesado, build que falha, Dockerfile customizado e casos de segurança. Esse corpus é uma dependência do produto, não exemplos descartáveis.

# 9. Networking, Traefik, domains e certificados

| **Área**          | **Testes**                                                                                                       |
|-------------------|------------------------------------------------------------------------------------------------------------------|
| Default domain    | Service publicado recebe hostname esperado e responde através do LB/Traefik.                                     |
| Custom domain     | Binding, DNS readiness, certificate issuance e ativação.                                                         |
| Traefik discovery | Labels em Swarm Service geram router/service corretos.                                                           |
| TLS rotation      | Nova CertificateVersion distribuída; ACK; activation; conexões novas usam cert novo.                             |
| Multi-Traefik     | Todas as instâncias servem o mesmo certificado/rota; uma instância pode cair sem indisponibilidade acima do SLO. |
| WebSocket/SSE     | Upgrade/stream permanece funcional durante tráfego e rolling update conforme política.                           |
| HTTP redirects    | HTTP→HTTPS, headers e policy definidos.                                                                          |
| Domain conflict   | Dois Teams/Services não podem apropriar o mesmo hostname segundo regra global.                                   |

# 10. Vault, secrets e criptografia

| **Cenário**           | **Verificação**                                                                 |
|-----------------------|---------------------------------------------------------------------------------|
| Create SecretVersion  | Ciphertext persistido; plaintext ausente de logs/DB não criptografado.          |
| Binding pin           | Environment/Service aponta para versão exata.                                   |
| Promotion             | HML pode usar versão nova sem alterar PROD até promoção explícita.              |
| Swarm materialization | Secret técnico criado/attached apenas ao Service autorizado.                    |
| Rotation              | Nova versão não muta versão anterior; rollback recupera binding antigo.         |
| Recovery Key          | Backup/restore do master key funciona; chave errada falha sem revelar material. |
| Redaction             | API, logs, errors, audit e telemetry não exibem plaintext.                      |
| Access control        | Membro sem permissão não lê/edita/revela secret.                                |

# 11. End-to-end e jornadas críticas

Os E2E devem representar casos de uso reais definidos na Parte 10. O teste deve atravessar UI/API, persistência, Operation Engine e runtime quando o caso de uso possui efeito de infraestrutura.

| **Jornada E2E**                              | **Passo terminal observável**                                     |
|----------------------------------------------|-------------------------------------------------------------------|
| Bootstrap → primeiro Team → primeiro Project | Team/owner persistidos e dashboard operacional.                   |
| Criar Environment e Service por image        | Docker Service 1/1 healthy + logs acessíveis.                     |
| Scale 1→3                                    | Swarm 3/3 e UI converge para healthy.                             |
| Git → Railpack → deploy                      | Commit SHA → Build → digest → Release → Deployment healthy.       |
| Rollback                                     | Release anterior volta a ser aplicada e health confirma.          |
| HML → PROD promotion                         | Mesmo artifact digest promovido; config/secret policy respeitada. |
| Custom domain                                | DNS/TLS ready e request chega ao Service correto.                 |
| Rotate secret                                | Nova versão aplicada apenas onde binding mudou.                   |
| Node drain                                   | Tasks realocadas e UI reflete manutenção.                         |
| Backup → restore                             | Estado escolhido é restaurado e validado funcionalmente.          |
| Ownership transfer                           | Novo OWNER único; antigo vira ADMIN; audit presente.              |

## 11.1 Regra para E2E UI

Seletores devem usar atributos semânticos/roles/test IDs estáveis, nunca classes CSS frágeis. A suíte deve validar loading, empty, error, degraded, forbidden e operation-in-progress, não apenas o happy path.

# 12. Realtime, logs e terminal

| **Fluxo**          | **Cenários**                                                                     |
|--------------------|----------------------------------------------------------------------------------|
| SSE operations     | Reconexão com cursor/last-event, evento duplicado, conexão lenta e encerramento. |
| Live logs          | Follow, reconnect, task rotation, múltiplas replicas, redaction.                 |
| Historical logs    | Range temporal, pagination, retention e backend indisponível.                    |
| Terminal WebSocket | Handshake autorizado, resize, input/output, disconnect, timeout e audit.         |
| Backpressure       | Cliente lento não derruba worker/control plane nem cresce memória sem limite.    |

# 13. Performance, carga, stress e soak

Os testes de performance devem usar os objetivos numéricos do Anexo B como fonte de verdade. Resultados sem topologia, dataset, versão e perfil de carga registrados não contam como evidência comparável.

| **Perfil**    | **Objetivo**                                    | **Duração típica**       |
|---------------|-------------------------------------------------|--------------------------|
| Smoke load    | Validar script e observabilidade                | Minutos                  |
| Baseline      | Estabelecer referência por versão               | Curta                    |
| Expected peak | Comprovar SLO no pico esperado                  | Curta/média              |
| Burst         | Avaliar salto súbito e filas                    | Minutos                  |
| Stress        | Encontrar limite e modo de degradação           | Até saturação controlada |
| Soak          | Memory leak, fila acumulada, handles e drift    | Horas                    |
| Scalability   | Adicionar nodes/replicas e medir ganho/overhead | Ciclos comparáveis       |

## 13.1 Superfícies a medir

• API do Control Plane: leitura, mutações assíncronas, listagens e dashboards.

• Operation Engine: throughput, queue wait, execution time e retries.

• Reconciler: quantidade de resources/revisions processados por janela.

• Docker/Swarm: latência de create/update/scale e tempo até convergência.

• Logs/metrics ingestion e consultas.

• Build queue e concorrência dos builders.

• Traefik/data plane em laboratório separado, sem confundir capacidade das apps com capacidade do Control Plane.

## 13.2 Critério de regressão

Cada release candidate deve ser comparado a uma baseline compatível. Regressão significativa em p95/p99, throughput, CPU/memória, fila ou erro precisa de justificativa/aceite explícito; média sozinha não é critério suficiente.

# 14. Chaos e resiliência

Chaos tests verificam invariantes durante falhas, não apenas se “o serviço voltou”. Cada experimento define steady state, hipótese, injeção, blast radius, abort condition, métricas e evidências.

| **Experimento**                          | **Invariante principal**                                                        |
|------------------------------------------|---------------------------------------------------------------------------------|
| Matar Worker com Tasks                   | Swarm repõe Tasks em nodes elegíveis; Control Plane converge.                   |
| Matar um Manager em cluster de 3         | Quorum permanece; mutações continuam dentro do SLO.                             |
| Perder quorum                            | Operações que exigem manager ficam BLOCKED/degraded, sem afirmar sucesso.       |
| Matar uma instância Traefik              | LB remove target/requests continuam pelas demais.                               |
| Interromper Registry                     | Deploy novo não avança sem artifact; workloads atuais seguem.                   |
| Interromper PostgreSQL                   | Control Plane falha fechado e recupera sem corrupção/lost operation.            |
| Reiniciar Control Plane durante deploy   | Operation é retomada/reconciliada sem duplicar efeito.                          |
| Reiniciar Executor durante Docker update | Lease/fencing evita dupla aplicação; reconcile conclui estado.                  |
| Partition Manager↔Worker                 | Estado degraded visível; scheduler/runtime seguem comportamento esperado.       |
| Disk pressure/full                       | Alertas antes do crítico; writes falham de forma controlada; runbook acionável. |
| DNS provider timeout                     | Certificate/Domain operation retry sem loop agressivo.                          |
| Object storage indisponível              | Backup não é marcado como concluído sem objeto válido.                          |

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th><p><strong>Abort conditions</strong></p>
<p>Experimentos destrutivos devem parar automaticamente se o blast radius ultrapassar o esperado, se dados não descartáveis entrarem em risco ou se os guardrails do ambiente falharem.</p></th>
</tr>
</thead>
<tbody>
</tbody>
</table>

# 15. Backup, restore e Disaster Recovery testing

Backup sem restore testado não conta como proteção. A suíte de DR deve provar tanto o Fast Swarm Restore quanto o Clean Rebuild definido na Parte 5, respeitando RPO/RTO do Anexo B.

| **Teste**                 | **Evidência de sucesso**                                                         |
|---------------------------|----------------------------------------------------------------------------------|
| DB restore                | Schema, counts/checksums críticos e operações recentes conforme RPO.             |
| Vault restore             | SecretVersions descriptografáveis com Recovery Key correta.                      |
| Wrong key                 | Restore protegido falha; não produz plaintext parcial.                           |
| Registry/artifact restore | Release referencia digest recuperável.                                           |
| Swarm state restore       | Manager recuperado forma estado esperado quando caminho é aplicável.             |
| Clean rebuild             | Novo cluster é reconstruído a partir de Control Plane + Vault + Registry/config. |
| Environment snapshot      | Services, images, resources, domains e secret bindings reaplicados.              |
| Corrupt/incomplete backup | Detectado por checksum/manifest; não marcado como restorable.                    |

## 15.1 Restore drill

Executar drills periódicos sem conhecimento privilegiado do operador: a pessoa deve seguir o runbook e usar apenas artefatos que estariam disponíveis num incidente real. Medir RTO real e registrar passos manuais que precisam virar automação.

# 16. Upgrade, migrations e compatibilidade

| **Mudança**              | **Testes obrigatórios**                                                                  |
|--------------------------|------------------------------------------------------------------------------------------|
| Aplicação/DB             | Expand migration → código compatível → contract → cleanup em versão posterior.           |
| Docker Engine            | Versão atual e próxima suportada; API negotiation; Service/Secret/Network lifecycle.     |
| Traefik                  | Config/labels/file provider, TLS e routes antes/depois.                                  |
| BuildKit/Railpack        | Corpus de builds e cache/provenance.                                                     |
| PostgreSQL               | Driver, migrations, locks, backup/restore e performance smoke.                           |
| Provider API             | Contract suite contra sandbox/fixture e alteração de versão.                             |
| Rolling platform upgrade | Sem interromper data plane além do permitido pelo SLO.                                   |
| Rollback                 | Versão anterior pode operar durante janela compatível ou existe forward-fix documentado. |

## 16.1 N-1 / N compatibility

Durante rolling upgrade, definir explicitamente quais combinações de componentes N e N-1 são suportadas. API, Executor, workers e schema não podem presumir atualização atômica do sistema inteiro.

# 17. Testes de segurança

O Anexo C define ameaças e controles; esta seção define como eles são exercitados de forma automatizada ou periódica.

| **Categoria**     | **Cenários**                                                                                  |
|-------------------|-----------------------------------------------------------------------------------------------|
| Auth/RBAC/IDOR    | Troca de IDs entre Teams; role escalation; revoked session/token; ownership invariants.       |
| Secrets           | Redaction; access control; plaintext scanning; secret exfiltration attempts.                  |
| SSRF              | Metadata endpoints, loopback, private ranges, DNS rebinding quando aplicável.                 |
| Webhooks          | Assinatura inválida, replay, timestamp antigo, payload enorme.                                |
| Terminal/exec     | Permissão, audit, timeout, command/session isolation.                                         |
| Builder isolation | Tentativa de docker.sock, manager network, Vault, cloud metadata e host mounts.               |
| Supply chain      | Dependency/container scanning, digest pinning, provenance/signature policy quando habilitada. |
| Rate/abuse        | Login, token, webhook, build, deploy, logs e expensive queries.                               |
| Network           | Portas Swarm não expostas publicamente; manager/executor access restrictions.                 |
| Crypto/Recovery   | Key rotation, wrong key, tamper, backup+restore.                                              |

## 17.1 Segurança em CI vs periódica

Checks rápidos (SAST, secrets, dependency scan, auth tests) rodam em PR. DAST, scans de imagem, testes de isolamento e exercícios ofensivos mais pesados rodam em release candidate e periodicamente. Pentest externo/manual não é substituído pela automação.

# 18. Concorrência, idempotência e falhas distribuídas

| **Cenário**               | **Resultado esperado**                                                      |
|---------------------------|-----------------------------------------------------------------------------|
| Webhook duplicado         | Um build lógico; duplicata registrada/ignorada conforme contrato.           |
| Dois deploys rápidos      | Release mais nova vence; anterior pode ficar SUPERSEDED.                    |
| Scale durante deploy      | Ordem/policy definida; estado final combina revisão válida sem lost update. |
| Retry após timeout Docker | Inspect/reconcile antes de repetir efeito não idempotente.                  |
| Worker perde lease        | Worker antigo não commita resultado após fencing token inválido.            |
| Outbox publish duplicado  | Consumer idempotente; efeito lógico único.                                  |
| API client retry          | Idempotency key devolve operação existente.                                 |
| Node event atrasado       | Actual State posterior não é revertido por observação stale.                |

Esses cenários devem ser reproduzidos com barreiras/fault injection explícitos. Eles não podem depender de “tentar várias vezes até acontecer”.

# 19. Testes de observabilidade e diagnósticos

| **Sinal**      | **Teste**                                                                                   |
|----------------|---------------------------------------------------------------------------------------------|
| Logs           | Correlation/operation IDs, níveis, redaction e ausência de secrets.                         |
| Metrics        | Contadores/histogramas incrementam na operação correta; labels sem cardinalidade explosiva. |
| Tracing        | Spans atravessam API → job/operation → provider/executor quando habilitado.                 |
| Alerts         | Synthetic failure dispara alerta e recuperação resolve/fecha conforme policy.               |
| Dashboards     | Queries essenciais funcionam com dataset de referência.                                     |
| Audit          | Ações sensíveis geram registro imutável com actor/resource/action/result.                   |
| Degraded state | UI/API apresenta dependência indisponível sem mascarar como healthy.                        |

# 20. Pipeline de CI/CD e gates

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th><strong>Pull Request<br />
</strong>Static + Unit + Integration + Contract + Security fast<br />
<strong>↓<br />
</strong>Merge/Main<br />
<strong>Docker integration + selected E2E<br />
</strong>↓<br />
<strong>Nightly<br />
</strong>Full Swarm + Build corpus + Load smoke + Chaos subset<br />
<strong>↓<br />
</strong>Release Candidate<br />
<strong>Full E2E + Performance + Security + Restore/Upgrade required<br />
</strong>↓<br />
<strong>Production<br />
</strong>Progressive rollout + health/error-budget guardrails</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

| **Gate**             | **Bloqueadores mínimos**                                                                |
|----------------------|-----------------------------------------------------------------------------------------|
| PR                   | Compile/lint; unit/integration/contract; migrations; auth/RBAC; secret/dependency scan. |
| Merge                | PR gate + Docker/Swarm smoke + journeys críticas selecionadas.                          |
| Nightly              | Suíte completa de integração; flaky rate dentro do limite; labs limpos.                 |
| Release Candidate    | E2E completo; NFR/SLO; security; restore/upgrade; regressão analisada.                  |
| Production promotion | Todos gates verdes ou waiver explícito, temporal e auditado.                            |

## 20.1 Política de flaky tests

• Teste flaky é colocado em quarentena com owner e prazo curto, não silenciosamente retry até verde.

• Retry de infraestrutura pode existir no harness, mas precisa ser distinguido de retry da assertion.

• Falhas intermitentes em testes de segurança, restore ou concorrência bloqueiam release até entendimento.

• Medir flaky rate e top offenders como métrica de engenharia.

# 21. Ferramentas e harnesses

A especificação não obriga uma única ferramenta. A escolha deve privilegiar integração com a stack final, execução headless, relatórios reproduzíveis e capacidade de injetar falhas. Abaixo está o papel esperado, não uma dependência arquitetural.

| **Necessidade**  | **Capacidade requerida**                                                  |
|------------------|---------------------------------------------------------------------------|
| Unit/integration | Runner rápido, paralelização, fixtures e coverage.                        |
| API/contract     | HTTP client, schema/OpenAPI validation e snapshot estrutural controlado.  |
| Browser E2E      | Browser real, tracing, screenshots/video em falha e selectors semânticos. |
| Load             | RPS/arrival-rate, scenarios, thresholds p95/p99, distributed runners.     |
| Chaos            | Controle de processes/containers/nodes/network e abort conditions.        |
| Security         | SAST/SCA/secret scan, DAST e container image scanning.                    |
| Infra harness    | Criar/destruir cluster Swarm e dependências de laboratório.               |
| Reports          | JUnit/JSON + métricas + metadata de commit/ambiente/topologia.            |

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th><p><strong>Stack final</strong></p>
<p>Quando a linguagem do Control Plane for definida definitivamente (Rails ou Rust), o Implementation Pack deverá escolher runners/libraries concretos. O contrato deste anexo permanece o mesmo independentemente da linguagem.</p></th>
</tr>
</thead>
<tbody>
</tbody>
</table>

# 22. Test data, fixtures e isolamento

| **Regra**                  | **Aplicação**                                                                  |
|----------------------------|--------------------------------------------------------------------------------|
| Synthetic by default       | Dados gerados explicitamente para cenários; sem PII real.                      |
| Factories small            | Criar apenas dados necessários para o cenário.                                 |
| Seed reference             | Dataset versionado para performance e dashboards.                              |
| Unique namespaces          | Team/project/service/domain por test run.                                      |
| Cleanup idempotent         | Pode rodar novamente após crash.                                               |
| Clock control              | Expiração, retries, cert renewal e retention testáveis sem esperar tempo real. |
| External provider fixtures | Sandbox ou fake server contratual; testes reais separados e rate-aware.        |
| Secrets                    | Somente credentials de teste rotacionáveis; nunca reutilizar produção.         |

# 23. Rastreabilidade: Use Case → Risco → Teste

A cobertura não deve ser avaliada somente por porcentagem de linhas. Cada caso de uso crítico e cada risco prioritário precisa apontar para uma ou mais suítes e um gate.

| **Origem**            | **Exemplo de evidência**                                |
|-----------------------|---------------------------------------------------------|
| Parte 10 Use Case     | UC Deploy → E2E deploy + contract + Docker integration. |
| Anexo B SLO           | SLO API p95 → performance threshold automatizado.       |
| Anexo C Threat        | SSRF → security suite + negative integration tests.     |
| Parte 5 DR            | Clean Rebuild → restore drill.                          |
| Parte 7 Control Plane | Outbox/reconcile → DB concurrency + fault injection.    |
| Parte 8 Edge          | Multi-Traefik TLS → edge integration + chaos.           |

## 23.1 Coverage mínimo por recurso crítico

Service, Deployment, SecretVersion, Domain/Certificate, Node, Backup/Restore e ownership devem possuir: unit rules, DB constraints, authorization negatives, API contract, happy-path integration e pelo menos um failure-path relevante. Recursos que geram efeito no Swarm também exigem Docker/Swarm integration.

# 24. Evidências, relatórios e qualificação de release

| **Artefato**       | **Conteúdo mínimo**                                                                 |
|--------------------|-------------------------------------------------------------------------------------|
| Test report        | Commit, suite, duração, pass/fail/skip, ambiente.                                   |
| Performance report | Topologia, dataset, load profile, RPS, concurrency, p50/p95/p99, errors, resources. |
| Chaos report       | Hypothesis, steady state, injection, timeline, abort condition, outcome.            |
| Restore report     | Backup IDs/checksums, procedure, RPO real, RTO real, validações.                    |
| Security report    | Scanner/version, findings, severity, disposition/waiver.                            |
| Upgrade report     | N→N+1 path, compatibility window, migrations, rollback/forward-fix.                 |
| Release evidence   | Links para todos os gates aplicáveis e waivers.                                     |

## 24.1 Waivers

Um gate só pode ser ignorado com waiver explícito contendo risco, justificativa, owner, expiração e mitigação. Waiver permanente é mudança de política e deve alterar a documentação, não viver como exceção eterna no pipeline.

# 25. Definition of Ready e Definition of Done para testes

## 25.1 Feature Ready

• Use Case/critério de aceite identificado.

• Contrato/API/evento definido quando aplicável.

• Riscos/failure modes relevantes conhecidos.

• Estratégia de dados/fixture definida.

• Métrica/log/audit necessário identificado.

## 25.2 Feature Done

• Unit/integration/contract adequados implementados.

• Negative authorization e failure paths testados.

• E2E adicionado quando jornada crítica ou regressão justificar.

• Docker/Swarm test presente quando existe efeito real de runtime.

• Observabilidade exercitada.

• Documentação/fixtures atualizadas.

• Nenhum flaky test conhecido introduzido.

• Gates aplicáveis verdes.

# 26. Cadência recomendada

| **Cadência**       | **Execução**                                                                |
|--------------------|-----------------------------------------------------------------------------|
| Por commit/PR      | Static, unit, integration, contract, auth/security rápidos.                 |
| Por merge          | Docker/Swarm smoke e E2E críticos.                                          |
| Nightly            | Full integration, build corpus, E2E amplo, performance smoke, chaos subset. |
| Release candidate  | Performance completa, security pesada, restore e upgrade relevantes.        |
| Mensal/trimestral  | DR drill, chaos amplo, pentest/review conforme risco, capacity baseline.    |
| Após incidente     | Regression test específico antes de fechar ação corretiva.                  |
| Após upgrade infra | Compatibility suite do componente alterado.                                 |

# 27. Ordem de implementação da infraestrutura de testes

| **Fase** | **Entregável**                                                   |
|----------|------------------------------------------------------------------|
| T0       | Runner, factories, Postgres test DB, CI static/unit/integration. |
| T1       | API/contract harness + auth matrix + migration checks.           |
| T2       | Docker local integration + Executor/reconciler harness.          |
| T3       | Swarm Lab automatizado + Registry + Traefik.                     |
| T4       | Browser E2E das jornadas críticas.                               |
| T5       | Build corpus + isolated Build Lab.                               |
| T6       | Performance Lab + thresholds do Anexo B.                         |
| T7       | Chaos/DR Lab + fault injection + restore automation.             |
| T8       | Security gates completos + release evidence aggregation.         |

Essa ordem acompanha o Roadmap do Anexo A: a infraestrutura de testes cresce junto com a superfície funcional, evitando construir um laboratório complexo antes do primeiro vertical slice, mas também evitando deixar resiliência e DR apenas para o final.

# 28. Critérios de aceite do Anexo D

| **ID** | **Critério**                                                                                            |
|--------|---------------------------------------------------------------------------------------------------------|
| D-01   | Existe separação explícita entre unit, integration, contract, Swarm, E2E e testes não funcionais.       |
| D-02   | PostgreSQL real é usado para validar constraints, transações, locks e migrations.                       |
| D-03   | Comportamentos de Swarm são exercitados em cluster real antes de release.                               |
| D-04   | Pipeline Git/Railpack/BuildKit/Registry possui corpus reproduzível de builds.                           |
| D-05   | Use Cases críticos da Parte 10 possuem E2E rastreável.                                                  |
| D-06   | SLOs/NFRs do Anexo B viram thresholds mensuráveis.                                                      |
| D-07   | Ameaças prioritárias do Anexo C possuem testes/controles verificáveis.                                  |
| D-08   | Chaos cobre node, manager/quorum, Traefik, DB, Registry e processo de deploy.                           |
| D-09   | Backup é validado por restore real e RPO/RTO são medidos.                                               |
| D-10   | Upgrade e migrations são testados com compatibilidade N/N-1 quando necessária.                          |
| D-11   | Concorrência, idempotência, leases/fencing e Outbox são testados deliberadamente.                       |
| D-12   | Testes verificam observabilidade, audit e estados degraded.                                             |
| D-13   | PR, merge, nightly, RC e produção possuem gates definidos.                                              |
| D-14   | Flaky tests possuem política, owner e métrica; retries não mascaram falhas.                             |
| D-15   | Relatórios de performance, chaos, restore, security e upgrade são arquivados como evidência de release. |
| D-16   | Existe estratégia de fixtures/dados sem uso de PII de produção.                                         |
| D-17   | A infraestrutura de testes pode ser provisionada/limpa de forma reproduzível.                           |
| D-18   | Production promotion exige gates verdes ou waiver explícito e expirável.                                |

## Conclusão

Com este anexo, “testar a plataforma” deixa de significar executar uma suíte genérica e passa a significar provar sistematicamente domínio, contratos, runtime, segurança, resiliência, capacidade e recuperabilidade. A suíte é parte do Control Plane: cada nova capacidade precisa chegar acompanhada do nível de evidência compatível com o risco operacional que introduz.
