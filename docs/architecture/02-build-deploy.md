---
document: "02"
title: "Deploy & Build"
type: "architecture"
status: "approved"
source: "docx"
---

**PLATAFORMA PAAS  
CLUSTER-FIRST**

**Documento técnico consolidado - Parte 2**

Deploy, Git, BuildKit, registry, artefatos imutáveis, rolling update, rollback e promoção entre environments

| **Status**  | Documento vivo - v0.2                                                                                   |
|-------------|---------------------------------------------------------------------------------------------------------|
| **Data**    | 05 de setembro de 2026                                                                                  |
| **Escopo**  | Definir o ciclo completo de source -\> build -\> artifact -\> release -\> deployment                    |
| **Decisão** | Build e runtime separados; produção sempre implanta artefatos imutáveis, nunca código-fonte diretamente |

**Resumo executivo**

Esta parte define como uma alteração de código se transforma em um workload executado pelo cluster. O pipeline será orientado a artefatos imutáveis: cada build produz uma imagem OCI identificada por digest; um deployment referencia esse artefato, aplica configuração específica do Environment e atualiza um Docker Swarm Service com estratégia controlada de rollout. Homologação e produção podem usar configurações e secrets diferentes, mas uma promoção reutiliza exatamente o mesmo artefato já testado.

| **Decisão central: BUILD não é DEPLOY. Build transforma source em artefato imutável. Deploy associa esse artefato a um Environment e o executa no Swarm. Produção nunca reconstrói uma imagem durante uma promoção.** |
|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|

# 1. Objetivo e limites desta parte

O pipeline precisa ser reproduzível, auditável e seguro. A plataforma deve conseguir responder, para qualquer versão em execução: qual repositório originou o artefato, qual commit foi usado, quando foi construído, qual digest está implantado, quais configurações foram resolvidas e quem disparou a operação.

## 1.1 Resultados esperados

- Deploy manual de uma imagem OCI existente.

- Deploy a partir de repositório Git com Railpack automático ou Dockerfile explícito.

- Integração com GitHub App para repositórios privados e webhooks.

- Build automático via Railpack sobre BuildKit; Dockerfile continua disponível como estratégia explícita usando BuildKit/Buildx.

- Publicação do artefato em registry acessível por todos os nodes.

- Atualização de Docker Swarm Service com healthcheck e rolling update.

- Rollback para release anterior sem rebuild.

- Promoção de HML para Produção reutilizando o mesmo digest.

- Histórico completo de builds, releases, deployments e eventos.

## 1.2 Fora do escopo imediato

- Builders adicionais além do Railpack (como Cloud Native Buildpacks ou compatibilidade legada) antes do fluxo principal estar sólido.

- CI genérico para testes arbitrários no estilo GitHub Actions.

- Kubernetes ou outro scheduler além de Swarm.

- Banco, Redis e object storage gerenciados dentro do cluster.

- Deploy multi-cluster global ativo-ativo na primeira fase.

# 2. Os quatro objetos do ciclo de entrega

| **Objeto**      | **Significado**                                                                      |
|-----------------|--------------------------------------------------------------------------------------|
| Source Revision | Estado exato do código: provider, repository, branch/tag e commit SHA.               |
| Build           | Execução que transforma uma Source Revision em imagem OCI.                           |
| Artifact        | Imagem resultante, identificada de forma imutável por registry + digest.             |
| Deployment      | Aplicação de um Artifact em um Service de um Environment com configuração resolvida. |

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Source Revision<br />
commit: a81fc2...<br />
|<br />
v<br />
Build #582<br />
|<br />
v<br />
Artifact<br />
registry/app@sha256:9df...<br />
|<br />
+------------------+<br />
| |<br />
v v<br />
HML Deployment PROD Deployment<br />
secret bindings v7 secret bindings v9<br />
replicas 1 replicas 6</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

| **O mesmo Artifact pode participar de vários Deployments. Isso é o que torna a promoção HML -\> Produção confiável: muda o ambiente e sua configuração; não muda o binário/container image testado.** |
|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|

# 3. Sources: Git, repositórios e revisão exata

## 3.1 Source configurado no Service

| **Campo**      | **Exemplo / função**                                           |
|----------------|----------------------------------------------------------------|
| provider       | github, git-url ou image                                       |
| repository     | owner/repository                                               |
| defaultBranch  | main                                                           |
| buildContext   | ./                                                             |
| dockerfilePath | ./Dockerfile                                                   |
| autoDeploy     | true/false                                                     |
| watchPaths     | apps/api/\*\*, packages/core/\*\*                              |
| submodules     | habilitado/desabilitado                                        |
| buildMethod    | railpack (default) ou dockerfile                               |
| railpackConfig | railpack.json opcional + overrides controlados pela plataforma |

Branch é uma referência móvel e não deve ser considerada identidade de release. No instante do trigger, a plataforma resolve a branch para um commit SHA e o Build fica permanentemente ligado àquele SHA.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>branch: main<br />
| resolve<br />
v<br />
commit: a81fc2a89d... &lt;- imutável<br />
|<br />
v<br />
Build</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 3.2 Monorepos

O Service deve suportar build context e Dockerfile independentes. Assim, um mesmo repository pode originar múltiplos Services.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>repository/<br />
apps/<br />
api/ &lt;- buildContext apps/api<br />
web/ &lt;- buildContext apps/web<br />
packages/<br />
shared/<br />
Dockerfile.api</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

Uma otimização futura é usar watch paths para não gerar deploy de api quando um commit altera apenas documentação ou outro app sem dependência.

# 4. GitHub App e autenticação

Para uma plataforma multiusuário, GitHub App é preferível a pedir Personal Access Tokens permanentes. O Team conecta uma instalação do GitHub App e concede acesso somente aos repositórios desejados.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Team<br />
|<br />
+-- GitHubConnection<br />
installationId<br />
account/login<br />
allowed repositories<br />
|<br />
+--&gt; Repository A<br />
+--&gt; Repository B</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 4.1 Permissões mínimas

| **Permissão**                   | **Uso**                                        |
|---------------------------------|------------------------------------------------|
| Contents: Read                  | Clonar/baixar código e resolver commits.       |
| Metadata: Read                  | Identificação do repository.                   |
| Webhooks                        | Receber push/branch/tag conforme configuração. |
| Pull Requests: Read (opcional)  | Preview environments no futuro.                |
| Commit Status/Checks (opcional) | Publicar status do deployment no GitHub.       |

## 4.2 Tokens temporários

O backend gera installation tokens de curta duração quando precisa acessar o repository. Eles não são tratados como secret permanente da aplicação. O token nunca deve aparecer em build logs, deployment logs ou no frontend.

## 4.3 Webhook

Todo webhook deve ter assinatura validada antes de qualquer ação. Depois da validação, o evento é convertido em um trigger interno idempotente.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>GitHub push<br />
|<br />
v<br />
Webhook endpoint<br />
| verify signature<br />
v<br />
Resolve repository + branch<br />
|<br />
v<br />
Create Deployment Trigger<br />
| deduplicate delivery id + commit<br />
v<br />
Queue</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

# 5. Triggers de deployment

| **Trigger** | **Comportamento**                                                    |
|-------------|----------------------------------------------------------------------|
| Manual      | Usuário escolhe branch/commit ou Artifact e solicita deploy.         |
| Push        | Webhook de branch configurada inicia build + deploy.                 |
| Redeploy    | Reexecuta o deployment usando o mesmo Artifact e configuração atual. |
| Rollback    | Cria novo deployment apontando para um Artifact/Release anterior.    |
| Promote     | Implanta em outro Environment o Artifact já aprovado.                |
| API         | Automação externa solicita deployment explicitamente.                |

| **Rollback e redeploy devem criar novos registros de Deployment. Histórico nunca é reescrito; o sistema é append-only do ponto de vista operacional.** |
|--------------------------------------------------------------------------------------------------------------------------------------------------------|

# 6. Railpack + BuildKit: sistema de construção

Railpack será o builder automático padrão. Ele analisa o source, gera um Build Plan e usa BuildKit como backend para produzir a imagem OCI sem exigir Dockerfile. Para projetos que precisam de controle total, o usuário pode selecionar a estratégia Dockerfile, também executada por BuildKit/Buildx. O produto deve tratar BuildKit como infraestrutura de build e Railpack como a camada de detecção/planejamento do modo automático, nunca como comandos de shell espalhados pelo backend.

## 6.1 Estratégias de build

Automatic (default): Railpack detecta linguagem/framework, resolve versões e comandos, produz um Build Plan e executa esse plano sobre BuildKit. O usuário pode sobrescrever build command, start command e configuração por arquivo railpack.json quando necessário.

Dockerfile (advanced): a plataforma usa o Dockerfile fornecido pelo projeto e chama BuildKit/Buildx diretamente. Esse modo existe para workloads não detectáveis ou que exijam controle fino da imagem.

A saída dos dois caminhos deve ser idêntica para o restante do sistema: uma imagem OCI publicada em registry e identificada por digest. Deploy, promoção e rollback não precisam saber como a imagem foi construída.

## 6.2 Fluxo de build

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Source Revision<br />
|<br />
v<br />
Checkout workspace temporário<br />
|<br />
v<br />
Build Strategy<br />
- Railpack (default) -&gt; Build Plan<br />
- Dockerfile (advanced)<br />
|<br />
v<br />
BuildKit<br />
- build args<br />
- build secrets<br />
- cache<br />
|<br />
v<br />
OCI image<br />
|<br />
v<br />
Registry<br />
|<br />
v<br />
Artifact(digest)</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 6.3 Build arguments x build secrets x runtime secrets

| **Tipo**       | **Pode ir para imagem?**                                | **Exemplo**         | **Tratamento**                          |
|----------------|---------------------------------------------------------|---------------------|-----------------------------------------|
| Build arg      | Pode acabar em metadata/layers dependendo do Dockerfile | NEXT_PUBLIC_API_URL | Somente valores não sensíveis.          |
| Build secret   | Não deve persistir na imagem                            | NPM_TOKEN           | Entregue ao BuildKit como secret mount. |
| Runtime secret | Não participa do build                                  | DATABASE_PASSWORD   | Vault -\> Swarm Secret no deployment.   |

| **Regra: segredo de runtime nunca deve ser necessário para construir a imagem. Se um build precisa de credencial privada (ex.: npm registry), ela entra como Build Secret e é descartada ao final.** |
|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|

# 7. Isolamento e segurança dos builders

Um Dockerfile é código arbitrário. Instruções RUN podem baixar binários, consumir CPU, tentar acessar rede e explorar o ambiente do builder. Por isso, build é uma fronteira de segurança própria.

## 7.1 Regras obrigatórias

- Não executar builds nos Swarm Managers.

- Não montar o docker.sock do host dentro de containers que executam source não confiável.

- Executar builders em nodes dedicados ou infraestrutura separada.

- Aplicar limites de CPU, memória, disco e tempo máximo.

- Workspace temporário e eliminado após sucesso/falha.

- Credenciais do registry e Git com escopo mínimo e vida curta.

- Separar logs de build de logs de runtime.

- Considerar BuildKit rootless/isolado conforme maturidade e modelo multi-tenant.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Swarm Managers<br />
X sem builds<br />
<br />
Builder Pool<br />
builder-01<br />
builder-02<br />
builder-03<br />
|<br />
v<br />
Registry<br />
|<br />
v<br />
Runtime Workers</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 7.2 Builder Pool

O scheduler de builds pode ser da própria plataforma: escolhe um builder saudável com capacidade, cria o job, transmite progresso e libera recursos ao final. Isso não precisa ser o mesmo scheduler usado para workloads de aplicação.

# 8. Cache de build

Cache é decisivo para experiência de deploy. O primeiro build pode instalar todas as dependências; builds seguintes devem reutilizar layers não invalidadas.

| **Nível**                            | **Uso**                                                                  |
|--------------------------------------|--------------------------------------------------------------------------|
| Cache local do builder               | Muito rápido, porém desaparece se o próximo build cair em outro builder. |
| Registry cache                       | Compartilhado entre builders; adequado para cluster de build.            |
| Cache por Service                    | Evita poluição e colisão entre projetos.                                 |
| Cache key por plataforma/arquitetura | Separa amd64/arm64 e diferentes estratégias de build.                    |

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Build #1<br />
FROM node MISS<br />
npm install MISS<br />
app build MISS<br />
<br />
Build #2<br />
FROM node HIT<br />
npm install HIT<br />
app build MISS</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

A plataforma pode mostrar métricas de cache no Build: bytes reutilizados, etapas em cache e duração de cada step.

# 9. Registry e artefatos imutáveis

Em cluster multi-node, todos os workers precisam conseguir baixar a mesma imagem. Por isso, a primeira versão pode usar GHCR, Docker Hub privado ou outro registry OCI; não é necessário operar um registry próprio imediatamente.

## 9.1 Naming

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>registry.example.com/&lt;team&gt;/&lt;project&gt;/&lt;service&gt;:&lt;tag&gt;<br />
<br />
Exemplo:<br />
registry.example.com/acme/albert/api:git-a81fc2</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

A tag é amigável, mas não é identidade imutável. Depois do push, a plataforma resolve e persiste o digest:

| registry.example.com/acme/albert/api@sha256:9df41b... |
|-------------------------------------------------------|

| **Docker Swarm Service deve ser implantado preferencialmente com referência por digest. Tags podem mudar; digest identifica exatamente o conteúdo testado.** |
|--------------------------------------------------------------------------------------------------------------------------------------------------------------|

## 9.2 Artifact

| **Campo**  | **Conteúdo**                                |
|------------|---------------------------------------------|
| id         | Identificador interno.                      |
| buildId    | Build que produziu o artefato.              |
| repository | Registry/repository OCI.                    |
| tag        | Alias humano, ex.: git-a81fc2.              |
| digest     | sha256 imutável.                            |
| platform   | linux/amd64 inicialmente; outras no futuro. |
| size       | Tamanho para telemetria/custos.             |
| createdAt  | Data de publicação.                         |

# 10. Release: configuração pronta para implantação

É útil separar Artifact de Release. Artifact é somente a imagem. Release é a combinação do artefato com uma fotografia da configuração resolvida necessária para um Service em um Environment.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Release #91 - Albert / HML / API<br />
<br />
Artifact<br />
sha256:9df...<br />
<br />
Configuration snapshot<br />
replicas: 1<br />
resources: 0.5 CPU / 512 MiB<br />
env: NODE_ENV=hml<br />
secret bindings:<br />
DATABASE_URL -&gt; secret version 7<br />
domains:<br />
api.hml.albert.com<br />
healthcheck:<br />
/health</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

Uma Release não precisa persistir plaintext de secrets; deve registrar os IDs/versões referenciados. No momento do deployment, o backend autorizado resolve e materializa as Swarm Secrets correspondentes.

# 11. Criação/atualização do Docker Swarm Service

O deployment converte a Release em uma Service Spec do Swarm. A plataforma não executa \`docker run\`; ela cria ou atualiza um Docker Service.

| **Parte do Service Spec** | **Origem na plataforma**                                       |
|---------------------------|----------------------------------------------------------------|
| Image                     | Artifact digest.                                               |
| Env                       | Variáveis não sensíveis resolvidas.                            |
| Secrets                   | Bindings para Swarm Secrets materializadas.                    |
| Networks                  | Overlay network do Environment e redes adicionais autorizadas. |
| Replicas                  | Configuração do Service/Environment.                           |
| Resources                 | CPU e memória reservados/limitados.                            |
| Placement                 | Labels, constraints e preferences.                             |
| Healthcheck               | Docker image ou override da plataforma.                        |
| UpdateConfig              | Política de rolling update.                                    |
| Labels                    | Traefik routing e metadata interna.                            |

## 11.1 Identidade determinística

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>service name:<br />
&lt;team&gt;-&lt;project&gt;-&lt;environment&gt;-&lt;service&gt;<br />
<br />
network:<br />
&lt;team&gt;-&lt;project&gt;-&lt;environment&gt;<br />
<br />
labels internas:<br />
platform.team_id=...<br />
platform.project_id=...<br />
platform.environment_id=...<br />
platform.service_id=...</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

IDs internos nas labels facilitam reconciliação sem depender do nome visível, que pode ser alterado.

# 12. Rolling update e zero/minimal downtime

A política default deve priorizar disponibilidade. Para serviços HTTP stateless, o padrão mais seguro costuma ser iniciar a nova Task antes de encerrar a anterior quando houver capacidade suficiente.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>v10 v10 v10<br />
|<br />
| start-first<br />
v<br />
v11 v10 v10 v10<br />
| health OK<br />
v<br />
v11 v11 v10 v10<br />
...<br />
<br />
v11 v11 v11</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

| **Parâmetro**   | **Default sugerido / função**                        |
|-----------------|------------------------------------------------------|
| order           | start-first para workloads compatíveis.              |
| parallelism     | 1 ou porcentagem conservadora inicialmente.          |
| delay           | Pequeno intervalo entre lotes quando necessário.     |
| monitor         | Janela para considerar a Task estável.               |
| failureAction   | rollback em Produção; pause pode ser opção avançada. |
| maxFailureRatio | Tolerância explícita de falhas durante rollout.      |

## 12.1 Capacidade durante start-first

Start-first exige capacidade temporária para manter Task antiga e nova simultaneamente. O painel deve detectar cluster sem headroom e avisar que o rollout pode precisar usar stop-first ou reduzir paralelismo.

# 13. Health checks e elegibilidade para tráfego

Um container iniciado não significa uma aplicação pronta. O Service deve possuir healthcheck confiável. A plataforma pode permitir healthcheck herdado da imagem ou override por Environment/Service.

| **Tipo** | **Exemplo**                                             |
|----------|---------------------------------------------------------|
| HTTP     | GET /health -\> 200                                     |
| TCP      | Conexão à porta da aplicação.                           |
| Command  | Comando executado no container.                         |
| None     | Permitido apenas com aviso; reduz segurança do rollout. |

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Task created<br />
|<br />
v<br />
STARTING<br />
| health checks<br />
v<br />
HEALTHY<br />
|<br />
+--&gt; elegível para tráfego<br />
<br />
Falha repetida<br />
|<br />
v<br />
UNHEALTHY -&gt; rollout failure / rollback</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

Além do Docker health status, Traefik pode executar checks HTTP próprios em cenários avançados. O produto deve evitar confundir liveness com readiness; inicialmente, um endpoint de health desenhado corretamente pode cumprir ambos para apps stateless simples.

# 14. Rollback

Rollback não recompila código. Ele cria um novo Deployment cuja Release base é uma versão anterior conhecida.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Deployment 101<br />
artifact sha256:AAA<br />
<br />
Deployment 102<br />
artifact sha256:BBB &lt;- problema<br />
<br />
Rollback<br />
|<br />
v<br />
Deployment 103<br />
artifact sha256:AAA</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 14.1 O que deve voltar

| **Elemento**      | **Comportamento**                                                         |
|-------------------|---------------------------------------------------------------------------|
| Artifact          | Volta para o digest anterior.                                             |
| Service spec      | Replica a configuração da Release escolhida ou permite política definida. |
| Secret bindings   | Podem ser restaurados para versões daquela Release, com confirmação.      |
| Domains           | Normalmente permanecem; release snapshot registra o estado.               |
| External database | Não é revertido automaticamente.                                          |
| Migrations        | Exigem estratégia da aplicação; não há rollback genérico seguro.          |

| **Banco é a principal fronteira do rollback. A plataforma pode voltar a imagem em segundos, mas não deve executar downgrade de schema automaticamente sem uma estratégia explícita do projeto.** |
|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|

# 15. Promoção HML -\> Produção

Promoção é diferente de refazer o deploy da branch main. Ela seleciona um Artifact já validado e cria uma Release no Environment de destino.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>HML<br />
Artifact sha256:ABC<br />
Secrets HML<br />
replicas 1<br />
|<br />
| Promote Artifact<br />
v<br />
PRODUCTION<br />
Artifact sha256:ABC &lt;- exatamente o mesmo<br />
Secrets PROD<br />
replicas 8</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 15.1 Fluxo de UX

1.  Usuário abre um Deployment saudável em HML.

2.  Clica em Promote.

3.  Escolhe Production como destino.

4.  UI mostra diff de configuração entre HML e Production.

5.  Artifact fica travado no mesmo digest.

6.  Secrets são resolvidas pelos bindings de Production.

7.  Deployment de Production usa sua própria política de rollout.

8.  Resultado fica ligado ao deployment de origem para auditoria.

| **A promoção elimina a classe de erro "o que testamos em HML não é exatamente o que foi para Produção". Build once, deploy many.** |
|------------------------------------------------------------------------------------------------------------------------------------|

# 16. Concorrência, locks e idempotência

Deploy é assíncrono e pode receber triggers duplicados. A plataforma precisa tratar concorrência explicitamente.

| **Regra**                                | **Motivo**                                                          |
|------------------------------------------|---------------------------------------------------------------------|
| 1 deployment mutável por Service por vez | Evita dois rollouts alterando a mesma Service Spec simultaneamente. |
| Webhook delivery id idempotente          | GitHub pode reenviar eventos.                                       |
| Build dedup por revision+config          | Evita compilar duas vezes o mesmo commit com a mesma configuração.  |
| Operations possuem idempotency key       | Retry de jobs não deve criar recursos duplicados.                   |
| Cancel é best-effort e registrado        | Build/rollout podem estar em etapas não imediatamente canceláveis.  |

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Service Deployment Lock<br />
<br />
queued #201<br />
active #200<br />
queued #202<br />
<br />
#200 finish<br />
|<br />
v<br />
re-evaluate queue<br />
|<br />
+--&gt; supersede obsolete #201?<br />
+--&gt; execute latest #202?</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

Para auto-deploy em branches muito ativas, uma política opcional pode cancelar/superseder deployments ainda não iniciados quando um commit mais novo chegar.

# 17. Estados de Build e Deployment

## 17.1 Build

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>QUEUED<br />
-&gt; PREPARING<br />
-&gt; CHECKOUT<br />
-&gt; BUILDING<br />
-&gt; PUSHING<br />
-&gt; SUCCEEDED<br />
<br />
Falhas:<br />
FAILED / CANCELED / TIMED_OUT</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 17.2 Deployment

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>QUEUED<br />
-&gt; RESOLVING_CONFIG<br />
-&gt; MATERIALIZING_SECRETS<br />
-&gt; UPDATING_SERVICE<br />
-&gt; ROLLING_OUT<br />
-&gt; VERIFYING<br />
-&gt; HEALTHY<br />
<br />
Falhas:<br />
FAILED<br />
ROLLED_BACK<br />
CANCELED</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

Estados devem ser derivados de eventos duráveis, não apenas de mensagens voláteis na fila.

# 18. Eventos, logs e auditoria

Build log é stream operacional; DeploymentEvent é histórico estruturado. Ambos são necessários.

| **Evento**             | **Exemplo de metadata**                       |
|------------------------|-----------------------------------------------|
| DEPLOYMENT_CREATED     | actor, trigger, source revision.              |
| BUILD_STARTED          | builder id, cache scope.                      |
| ARTIFACT_PUBLISHED     | registry, digest.                             |
| CONFIG_RESOLVED        | release id, secret version ids sem plaintext. |
| SERVICE_UPDATE_STARTED | swarm service id/version.                     |
| TASK_HEALTHY           | task/node.                                    |
| ROLLBACK_STARTED       | from/to release.                              |
| DEPLOYMENT_HEALTHY     | duration, replicas healthy.                   |

## 18.1 Streaming para UI

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Builder / Swarm events<br />
|<br />
v<br />
Backend event stream<br />
|<br />
+--&gt; persist structured events<br />
|<br />
+--&gt; SSE/WebSocket<br />
|<br />
v<br />
Browser</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

A UI deve continuar funcionando após reload: eventos persistidos reconstroem o histórico, e o stream entrega apenas novidades.

# 19. Modelo de dados sugerido

| **Entidade**              | **Relações / função**                                                          |
|---------------------------|--------------------------------------------------------------------------------|
| SourceConnection          | Team -\> provider credentials/installation metadata.                           |
| Repository                | Team + SourceConnection; identificação do repository remoto.                   |
| ServiceSource             | Service -\> Repository + branch + build config.                                |
| Build                     | Source Revision + builderType (railpack/dockerfile) + build settings + status. |
| Artifact                  | Build -\> OCI repository/tag/digest.                                           |
| Release                   | Environment Service + Artifact + configuration snapshot.                       |
| Deployment                | Release + trigger + actor + lifecycle.                                         |
| DeploymentEvent           | Deployment -\> eventos estruturados append-only.                               |
| BuildLogChunk / log store | Referência ao log bruto do build.                                              |
| Promotion                 | Deployment origem -\> Deployment destino.                                      |

## 19.1 Relação principal

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Team<br />
Project<br />
Environment<br />
Service<br />
ServiceSource ---&gt; Repository<br />
|<br />
v<br />
Build<br />
|<br />
v<br />
Artifact<br />
|<br />
v<br />
Release<br />
|<br />
v<br />
Deployment<br />
|<br />
+--&gt; DeploymentEvent</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

# 20. UX mínima da área de deploy

## 20.1 Tela do Service

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Albert / Production / API<br />
<br />
Status Healthy<br />
Artifact sha256:9df...<br />
Source github/acme/albert @ main<br />
Replicas 6 / 6<br />
Last deploy 12 min ago<br />
<br />
[ Deploy ] [ Redeploy ] [ Rollback ]<br />
<br />
Deployments<br />
#182 HEALTHY a81fc2 4m 12s<br />
#181 ROLLED_BACK 7be019 1m 08s<br />
#180 HEALTHY 61af02 3m 44s</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 20.2 Tela de Deployment

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Deployment #182<br />
<br />
Trigger GitHub push<br />
Commit a81fc2<br />
Artifact sha256:9df...<br />
Actor GitHub / main<br />
<br />
Timeline<br />
19:31:02 created<br />
19:31:04 checkout<br />
19:31:07 build started<br />
19:33:40 artifact published<br />
19:33:43 rolling update<br />
19:35:14 6/6 healthy<br />
<br />
[ Promote ]</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

# 21. Pipeline completo de referência

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>1. Trigger<br />
GitHub push / manual / promote / rollback<br />
|<br />
2. Resolve Source Revision<br />
branch -&gt; immutable commit SHA<br />
|<br />
3. Build (quando necessário)<br />
Railpack default / Dockerfile advanced<br />
isolated BuildKit builder<br />
|<br />
4. Publish Artifact<br />
OCI registry -&gt; digest<br />
|<br />
5. Create Release<br />
artifact + env config + secret version bindings<br />
|<br />
6. Materialize Swarm Secrets<br />
|<br />
7. Update Docker Swarm Service<br />
image digest + networks + resources + Traefik labels<br />
|<br />
8. Rolling Update<br />
|<br />
9. Verify health<br />
|<br />
10. HEALTHY<br />
persist release/deployment/event history</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

# 22. Plano de implementação desta parte

| **Marco**              | **Critério de aceite**                                                                                        |
|------------------------|---------------------------------------------------------------------------------------------------------------|
| B1 - Image deploy      | Informar imagem/digest e criar Service saudável no Swarm.                                                     |
| B2 - Release history   | Persistir Artifact, Release, Deployment e eventos.                                                            |
| B3 - Build pipeline    | Repo público -\> Railpack automático (default) ou Dockerfile -\> BuildKit -\> registry -\> digest -\> deploy. |
| B4 - GitHub App        | Repo privado, installation token e webhook assinado.                                                          |
| B5 - Rolling/health    | Update controlado com verificação e rollback automático.                                                      |
| B6 - Vault binding     | Release referencia SecretVersions e deployment cria Swarm Secrets.                                            |
| B7 - Promotion         | HML -\> PROD usando o mesmo digest, sem rebuild.                                                              |
| B8 - Builder isolation | Builders dedicados, limites e cleanup.                                                                        |
| B9 - Cache             | Cache compartilhado ou registry cache com métricas básicas.                                                   |

# 23. Decisões consolidadas - Parte 2

| **Decisão**                                                                                                                 | **Estado** |
|-----------------------------------------------------------------------------------------------------------------------------|------------|
| Source é sempre resolvido para commit SHA antes do build.                                                                   | Definido   |
| Build e deploy são domínios separados.                                                                                      | Definido   |
| Railpack é o builder automático default; BuildKit é o backend de construção. Dockerfile permanece como estratégia avançada. | Definido   |
| Builders não rodam nos Swarm Managers.                                                                                      | Definido   |
| Registry externo pode ser usado inicialmente.                                                                               | Definido   |
| Artifact é identificado por OCI digest, não apenas tag.                                                                     | Definido   |
| Swarm Service é implantado com artefato imutável.                                                                           | Definido   |
| Secrets de runtime não entram no build.                                                                                     | Definido   |
| Produção usa rolling update + health verification.                                                                          | Definido   |
| Rollback cria novo Deployment e não faz rebuild.                                                                            | Definido   |
| Promoção HML -\> PROD reutiliza exatamente o mesmo digest.                                                                  | Definido   |
| Migrations de banco não recebem rollback automático genérico.                                                               | Definido   |
| Logs brutos e eventos estruturados são mantidos separadamente.                                                              | Definido   |

| **Próxima parte sugerida: observabilidade e operação - métricas, logs de runtime, eventos do Swarm, alertas, autoscaling, health do cluster, capacity/headroom, auditoria e incident response.** |
|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
