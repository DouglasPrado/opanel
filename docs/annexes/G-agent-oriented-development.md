---
document: "G"
title: "Desenvolvimento Orientado por Agentes e Implementation Pack"
type: "annex"
status: "approved"
source: "docx"
---

**PLATAFORMA PAAS  
CLUSTER-FIRST**

**Anexo G - Desenvolvimento Orientado por Agentes e Implementation Pack**

*Guia operacional para transformar as Partes 1-10 e os Anexos A-F em código executável com agentes de desenvolvimento, incluindo adapters específicos para Codex e Claude Code*

## Resumo executivo

Este anexo define a forma recomendada de colocar toda a especificação da plataforma em prática utilizando agentes de desenvolvimento. A estratégia não é entregar centenas de páginas a um agente e pedir que ele construa a plataforma inteira. O objetivo é converter a documentação em um sistema de execução dentro do próprio repositório, no qual cada tarefa possui escopo, referências, contratos, critérios de aceite e testes explícitos.

O agente selecionado passa a trabalhar sobre um repositório que contém a verdade arquitetural, regras permanentes, documentação roteável e um Implementation Pack incremental. Codex e Claude Code são tratados como executores intercambiáveis sobre o mesmo sistema de registro; diferenças de harness ficam isoladas em adapters de instrução e operação.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th><strong>Princípio central<br />
</strong>A unidade de trabalho do agente não é “construir a plataforma”. A unidade de trabalho é uma Story implementável, testável, revisável e vinculada a uma decisão já documentada.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

# 1. Objetivo e estratégia geral

## 1.1 Objetivo

Transformar a especificação já produzida em um processo de desenvolvimento repetível, no qual qualquer agente suportado consegue entender o contexto correto, alterar apenas o necessário, executar testes, produzir evidências e permitir revisão humana ou por outro agente antes da integração.

## 1.2 Fluxo de execução

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Partes 1-10 + Anexos A-F<br />
|<br />
v<br />
Markdown no repositório<br />
|<br />
v<br />
Instruções do agente + docs/MASTER.md<br />
|<br />
v<br />
Implementation Pack<br />
|<br />
v<br />
Milestone -&gt; Story -&gt; Task<br />
|<br />
v<br />
Agente implementa<br />
|<br />
v<br />
Testes + Agent Review<br />
|<br />
v<br />
Commit<br />
|<br />
v<br />
Próxima Story</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 1.3 O que não fazer

> **•** Anexar todos os documentos em cada sessão e pedir “implemente tudo”.
>
> **•** Permitir que o agente escolha uma nova arquitetura a cada story.
>
> **•** Começar por Git, Railpack, TLS, autoscaling, MCP e HA ao mesmo tempo.
>
> **•** Abrir múltiplos worktrees/agentes antes de estabilizar o primeiro vertical slice.
>
> **•** Aceitar uma feature apenas porque compila; critérios de aceite e testes fazem parte da implementação.

# 2. Gate inicial - congelar a stack

Antes do primeiro commit funcional, a stack deve ser explicitamente congelada no repositório. O baseline recomendado neste momento é Rails para o Control Plane e Next.js para a UI, mantendo os componentes de infraestrutura já definidos. Caso a escolha mude depois, a mudança deve ser registrada como Architecture Decision Record antes de alterar o código.

| **Camada**      | **Baseline inicial**                                                         |
|-----------------|------------------------------------------------------------------------------|
| Web UI          | Next.js + React + TypeScript                                                 |
| Control Plane   | Ruby on Rails em modo API                                                    |
| Banco           | PostgreSQL                                                                   |
| Jobs            | Solid Queue inicialmente                                                     |
| Swarm Executor  | Ruby inicialmente; extração para Rust somente se houver necessidade concreta |
| Cluster         | Docker Swarm                                                                 |
| Ingress         | Traefik                                                                      |
| Build           | Railpack + BuildKit                                                          |
| Registry        | OCI Registry                                                                 |
| Observabilidade | Prometheus + Grafana Alloy/Loki conforme documentos anteriores               |

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th><strong>Regra de mudança de stack<br />
</strong>Nenhum agente pode trocar framework, fila, banco, runtime ou padrão arquitetural por preferência própria. Mudanças desse nível exigem uma decisão explícita e atualização da documentação.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

# 3. Estrutura recomendada do repositório

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>platform/<br />
├── AGENTS.md # adapter Codex<br />
├── CLAUDE.md # adapter Claude Code<br />
├── README.md<br />
├── docs/<br />
│ ├── MASTER.md<br />
│ ├── AGENT_RULES.md # regras canônicas, agnósticas de harness<br />
│ ├── architecture/<br />
│ │ ├── 01-foundation.md<br />
│ │ ├── 02-build-deploy.md<br />
│ │ ├── 03-runtime-observability.md<br />
│ │ ├── 04-identity-security.md<br />
│ │ ├── 05-backup-dr.md<br />
│ │ ├── 06-infrastructure.md<br />
│ │ ├── 07-control-plane.md<br />
│ │ ├── 08-networking-edge.md<br />
│ │ ├── 09-data-api-contracts.md<br />
│ │ └── 10-ui-use-cases.md<br />
│ ├── annexes/<br />
│ │ ├── A-roadmap.md<br />
│ │ ├── B-nfr-slos.md<br />
│ │ ├── C-security.md<br />
│ │ ├── D-testing.md<br />
│ │ ├── E-runbooks.md<br />
│ │ ├── F-mcp.md<br />
│ │ └── G-agent-development.md<br />
│ ├── decisions/<br />
│ └── implementation/<br />
├── apps/<br />
│ ├── api/<br />
│ └── web/<br />
├── infrastructure/<br />
│ ├── docker/<br />
│ ├── swarm/<br />
│ ├── traefik/<br />
│ └── dev/<br />
└── scripts/</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 3.1 DOCX versus Markdown

Os DOCX permanecem como documentação humana oficial e podem ser usados para leitura, revisão e apresentação. Dentro do repositório, entretanto, a versão operacional para agentes deve ser Markdown. O objetivo não é criar uma segunda arquitetura: a versão Markdown deve ser uma transposição fiel, com headings estáveis e links entre documentos.

| **Formato**         | **Papel**                                                                       |
|---------------------|---------------------------------------------------------------------------------|
| DOCX                | Documento humano completo, versionado externamente ou em área de documentação.  |
| Markdown            | Fonte operacional consumida por agentes, CI e developers dentro do repositório. |
| ADR                 | Registro de qualquer mudança posterior em decisões estruturais.                 |
| Implementation Pack | Tradução incremental da especificação para stories executáveis.                 |

# 4. docs/MASTER.md - roteador da verdade

MASTER.md deve ser curto. Ele não duplica os documentos; ele mapeia cada assunto para a fonte correta e lista invariantes globais que o agente precisa enxergar rapidamente.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th># Platform Specification<br />
<br />
## Core decisions<br />
- Runtime: Docker Swarm<br />
- Ingress: Traefik<br />
- Builder: Railpack + BuildKit<br />
- Backend: Rails API<br />
- Frontend: Next.js<br />
- Database: PostgreSQL<br />
- Queue: Solid Queue<br />
- PostgreSQL stores Desired State<br />
- Docker Swarm represents Actual State<br />
- Docker API is only accessible through Swarm Executor<br />
- Applications always run as Swarm Services<br />
- Environments are first-class resources<br />
- Deployments use immutable image digests<br />
<br />
## Documentation map<br />
Identity: docs/architecture/04-identity-security.md<br />
Control Plane: docs/architecture/07-control-plane.md<br />
Networking: docs/architecture/08-networking-edge.md<br />
Data/API: docs/architecture/09-data-api-contracts.md<br />
UI/Use Cases: docs/architecture/10-ui-use-cases.md<br />
Security: docs/annexes/C-security.md<br />
Testing: docs/annexes/D-testing.md<br />
Operations: docs/annexes/E-runbooks.md<br />
MCP: docs/annexes/F-mcp.md<br />
<br />
## Agent execution<br />
- Canonical engineering rules: docs/AGENT_RULES.md<br />
- Codex adapter: AGENTS.md<br />
- Claude Code adapter: CLAUDE.md<br />
- Implementation work: docs/implementation/</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 4.1 Responsabilidade

> **•** Resolver rapidamente “qual documento contém a decisão sobre este assunto?”.
>
> **•** Dar ao agente os invariantes que não podem ser quebrados.
>
> **•** Evitar que uma story precise carregar todo o acervo documental no prompt.

# 5. Instruções permanentes e adapters de agente

As regras permanentes devem existir em uma fonte canônica independente do agente. Codex e Claude Code recebem adapters próprios que apontam para a mesma política de engenharia, evitando duplicação e drift entre ferramentas.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th># Platform Agent Rules<br />
<br />
Read docs/MASTER.md before architectural changes.<br />
<br />
## Architecture<br />
- Applications MUST run as Docker Swarm Services.<br />
- The public API MUST NEVER access /var/run/docker.sock.<br />
- Docker access belongs exclusively to the Swarm Executor.<br />
- PostgreSQL stores Desired State.<br />
- Docker Swarm represents Actual State.<br />
- Reconcilers converge Actual State toward Desired State.<br />
<br />
## Scope discipline<br />
- Do not add unrelated abstractions.<br />
- Do not refactor adjacent modules without need.<br />
- Do not implement future stories early.<br />
- Do not add dependencies unless required.<br />
- Prefer the smallest complete solution that satisfies the current Story and architecture.<br />
<br />
## Changes<br />
If documentation and implementation conflict, STOP and report the conflict.<br />
Do not silently redesign the system.<br />
<br />
## Tests<br />
Run the relevant suites required by docs/annexes/D-testing.md before declaring completion.<br />
<br />
## Security<br />
Follow docs/annexes/C-security.md.<br />
Never expose docker.sock, plaintext secrets, private keys or recovery keys.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 5.1 Fonte canônica de regras

A fonte recomendada é docs/AGENT_RULES.md. Ela contém invariantes de arquitetura, disciplina de escopo, comandos de teste, segurança e Definition of Done. Arquivos nativos do harness - AGENTS.md ou CLAUDE.md - funcionam como entrypoints curtos e podem adicionar regras locais por subtree sem contradizer a fonte canônica.

## 5.2 Adapter para Codex

Codex usa AGENTS.md como entrypoint de instruções do repositório. O arquivo raiz deve ser curto e apontar para docs/AGENT_RULES.md e docs/MASTER.md. Regras adicionais podem existir em diretórios específicos quando houver comportamento local relevante; instruções mais específicas devem apenas especializar, nunca contradizer, os invariantes globais.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th># AGENTS.md - Codex adapter<br />
<br />
Read docs/AGENT_RULES.md.<br />
Read docs/MASTER.md.<br />
<br />
For every Story:<br />
1. read the Story completely;<br />
2. read only its referenced docs;<br />
3. inspect existing code before editing;<br />
4. keep changes inside the declared boundary;<br />
5. run the required tests;<br />
6. report conflicts instead of redesigning silently.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 5.3 Adapter para Claude Code

Claude Code recebe CLAUDE.md como entrypoint do projeto. O adapter deve carregar ou referenciar as mesmas regras canônicas e pode usar arquivos CLAUDE.md mais específicos por subtree quando necessário. Para stories de alto impacto, o fluxo recomendado é iniciar em planejamento, revisar a superfície de mudança e só então liberar edição.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th># CLAUDE.md - Claude Code adapter<br />
<br />
@docs/AGENT_RULES.md<br />
@docs/MASTER.md<br />
<br />
Before implementing a Story:<br />
1. read the Story completely;<br />
2. inspect relevant code before making claims or edits;<br />
3. use the referenced docs as source of truth;<br />
4. plan first for high-impact changes;<br />
5. do not redesign outside the Story boundary;<br />
6. run required tests and review your own diff.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

| **Capacidade Claude Code** | **Uso recomendado**                                                                                                                                                                          |
|----------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Plan / permission mode     | Usar modo de planejamento para mudanças de schema, segurança, operações, reconciliação, contratos públicos ou migrations de alto risco antes de permitir edição.                             |
| Subagents                  | Usar quando existem workstreams independentes, revisão isolada ou exploração paralela. Evitar subagents para tarefas pequenas, sequenciais ou fortemente acopladas.                          |
| Continuidade de sessão     | Sessões podem continuar por várias Stories relacionadas, mas a unidade de entrega continua sendo a Story + commit/PR. Recomeçar contexto quando a sessão acumular decisões não relacionadas. |
| Resume                     | Usar continuidade/resume quando for útil preservar uma investigação longa, mantendo Git, Story e arquivos de progresso como fonte persistente de estado.                                     |
| MCP                        | Claude Code pode consumir MCPs do projeto quando isso trouxer contexto ou ações úteis; MCP nunca substitui os boundaries e autorizações definidos pelo produto.                              |

## 5.4 Disciplina contra overengineering

A política abaixo vale para qualquer agente, mas deve ser reforçada especialmente quando o harness tende a ampliar escopo ou criar abstrações especulativas. O objetivo é preservar a arquitetura definida sem antecipar trabalho de milestones futuros.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Avoid over-engineering.<br />
<br />
Only make changes directly requested or clearly necessary for the current Story.<br />
Do not:<br />
- add unrelated features;<br />
- refactor adjacent modules without need;<br />
- introduce speculative extension points;<br />
- add dependencies for hypothetical future use;<br />
- create parallel abstractions when an existing pattern satisfies the Story;<br />
- implement future Stories early.<br />
<br />
Implement the smallest complete solution that satisfies the Story, architecture, security and tests.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 5.5 Matriz de adapters

| **Aspecto**    | **Codex**                                              | **Claude Code**                                                                |
|----------------|--------------------------------------------------------|--------------------------------------------------------------------------------|
| Fonte canônica | docs/AGENT_RULES.md + docs/MASTER.md                   | docs/AGENT_RULES.md + docs/MASTER.md                                           |
| Entrypoint     | AGENTS.md                                              | CLAUDE.md                                                                      |
| Regras locais  | AGENTS.md em subtrees quando necessário                | CLAUDE.md em subtrees quando necessário                                        |
| Planejamento   | Prompt/plan explícito antes de editar stories críticas | Plan/permission mode para stories críticas                                     |
| Paralelismo    | Tasks/worktrees quando contracts estiverem estáveis    | Subagents/worktrees quando workstreams forem independentes                     |
| Review         | Contexto/agente separado                               | Subagent ou sessão separada                                                    |
| Estado durável | Git + Story + docs/implementation                      | Git + Story + docs/implementation; resume é conveniência, não fonte de verdade |

# 6. Implementation Pack

## 6.1 Definição

Implementation Pack é a camada entre a especificação arquitetural e o código. Cada milestone recebe stories pequenas, com objetivo, dependências, referências, contratos, critérios de aceite e testes. O pack deve morar em docs/implementation e evoluir junto com o código.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>docs/implementation/<br />
├── M00-foundation/<br />
│ ├── 01-repository-bootstrap.md<br />
│ ├── 02-local-development.md<br />
│ └── 03-ci-baseline.md<br />
├── M01-vertical-slice/<br />
│ ├── 01-auth-team.md<br />
│ ├── 02-project.md<br />
│ ├── 03-environment.md<br />
│ ├── 04-cluster.md<br />
│ ├── 05-service.md<br />
│ ├── 06-operation-engine.md<br />
│ ├── 07-swarm-executor.md<br />
│ ├── 08-reconciler.md<br />
│ ├── 09-actual-state.md<br />
│ ├── 10-logs.md<br />
│ └── 11-scale.md<br />
└── ...</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 6.2 Granularidade

| **Grande demais**           | **Granularidade correta**                                 |
|-----------------------------|-----------------------------------------------------------|
| “Implementar Control Plane” | Criar entidade Operation, transação e estados mínimos.    |
| “Implementar deploy”        | Persistir desired state e criar Operation de deploy.      |
| “Implementar cluster”       | Registrar Cluster e validar health de um Swarm existente. |
| “Implementar UI”            | Criar tela de Service com status derivado e ação Scale.   |
| “Implementar segurança”     | Aplicar policy de autorização à criação de Service.       |

# 7. Primeiro vertical slice

A primeira entrega deve provar a espinha dorsal inteira antes de adicionar features periféricas. O objetivo é verificar que uma intenção do usuário consegue atravessar UI, domínio, persistência, Operation Engine, Executor e Docker Swarm e voltar à UI como estado real.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Login / Team<br />
↓<br />
Project<br />
↓<br />
Environment<br />
↓<br />
Service usando OCI image pronta<br />
↓<br />
Desired State<br />
↓<br />
Operation<br />
↓<br />
Swarm Executor<br />
↓<br />
Docker Service real<br />
↓<br />
Actual State<br />
↓<br />
1/1 Healthy<br />
↓<br />
Logs<br />
↓<br />
Scale 1 -&gt; 3<br />
↓<br />
3/3 Healthy</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 7.1 Fora do primeiro slice

> **•** Git providers e webhooks.
>
> **•** Railpack e BuildKit.
>
> **•** Custom domains, DNS providers e Certificate Manager.
>
> **•** Autoscaling.
>
> **•** Backup/DR automatizado.
>
> **•** MCP.

Essas capacidades entram somente depois que a linha principal Desired State -\> Operation -\> Reconciler -\> Swarm estiver comprovada.

# 8. Decomposição inicial em stories

| **ID** | **Story**                       | **Resultado**                                         |
|--------|---------------------------------|-------------------------------------------------------|
| M01-01 | Bootstrap Rails/Next/Postgres   | Aplicações sobem em dev e CI.                         |
| M01-02 | User/Team/TeamMember/OWNER      | Identidade e ownership básicos.                       |
| M01-03 | Authentication + Authorization  | Usuário autenticado e policies aplicadas.             |
| M01-04 | Project                         | Criar/listar projeto por Team.                        |
| M01-05 | Environment + Cluster placement | Ambiente aponta para Cluster.                         |
| M01-06 | Service Desired State           | Service persistido sem tocar Docker.                  |
| M01-07 | Operation Engine mínimo         | Mutação cria Operation atomicamente.                  |
| M01-08 | Swarm Executor                  | Componente privilegiado conversa com Docker API.      |
| M01-09 | Service Reconciler              | Converge Service desejado para Docker Service.        |
| M01-10 | Actual State                    | Lê tasks e deriva health/revision.                    |
| M01-11 | Logs                            | Usuário consulta logs sem acesso ao host.             |
| M01-12 | Scale 1 -\> 3                   | Alteração de desired replicas converge e atualiza UI. |

# 9. Template obrigatório de Story

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th># M01-06 - Create Service<br />
<br />
## Objective<br />
Allow a Team member to create a Service inside an Environment.<br />
<br />
## References<br />
- docs/architecture/07-control-plane.md<br />
- docs/architecture/09-data-api-contracts.md<br />
- docs/architecture/10-ui-use-cases.md<br />
- docs/annexes/C-security.md<br />
- docs/annexes/D-testing.md<br />
<br />
## Entities<br />
Service, Environment, Cluster, Operation<br />
<br />
## API<br />
POST /api/v1/environments/:environment_id/services<br />
<br />
## Input<br />
name, image, replicas, internal_port<br />
<br />
## Expected behavior<br />
1. Validate actor and permission.<br />
2. Validate environment and cluster.<br />
3. Persist Service Desired State.<br />
4. Increment desired_revision.<br />
5. Create Operation in the same transaction.<br />
6. Commit.<br />
7. Return resource + operationId.<br />
<br />
## Must NOT<br />
- access Docker directly<br />
- create raw containers<br />
- synchronously wait for runtime convergence<br />
<br />
## Acceptance Criteria<br />
- service persisted<br />
- operation persisted atomically<br />
- unauthorized actor rejected<br />
- idempotency respected where specified<br />
- audit event emitted<br />
<br />
## Tests<br />
- model/domain<br />
- request<br />
- authorization<br />
- transaction/integration</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 9.1 Story pronta para agente

Uma story só deve ser entregue ao agente quando referências, boundary e resultado esperado estiverem claros. Se a story depende de decisão arquitetural ainda não tomada, ela não está Ready.

# 10. Prompt padrão de implementação

O prompt principal deve ser agnóstico de harness. O adapter cuida apenas de como o agente carrega instruções, planeja e recebe permissões; objective, boundary, acceptance e tests permanecem idênticos.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Implemente a story:<br />
docs/implementation/M01-06-create-service.md<br />
<br />
Antes de alterar código:<br />
1. leia o arquivo de instruções aplicável ao seu harness (AGENTS.md no Codex ou CLAUDE.md no Claude Code);<br />
2. leia docs/AGENT_RULES.md;<br />
3. leia docs/MASTER.md;<br />
4. leia somente as referências indicadas pela story;<br />
5. inspecione a implementação existente;<br />
6. identifique qualquer conflito com a especificação.<br />
<br />
Depois implemente completamente a story.<br />
Não altere arquitetura fora do escopo.<br />
Execute todos os testes relevantes.<br />
<br />
Ao finalizar informe:<br />
- arquivos alterados;<br />
- decisões tomadas;<br />
- testes executados;<br />
- critérios de aceite atendidos;<br />
- pendências ou conflitos encontrados.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 10.1 Regra para autonomia

O agente pode tomar decisões locais e reversíveis de implementação. Não pode tomar silenciosamente decisões estruturais. Se encontrar ambiguidade que afete contrato, segurança, persistência ou arquitetura, deve relatar o conflito em vez de inventar um novo padrão.

## 10.2 Variações por harness

| **Harness** | **Adaptação**                                                                                                                                                                                                 |
|-------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Codex       | Usar o prompt padrão. Para mudanças críticas, pedir primeiro análise/plan sem editar; depois aprovar a execução. AGENTS.md e docs/AGENT_RULES.md devem permanecer como contexto persistente.                  |
| Claude Code | Usar o mesmo prompt de Story. Para mudanças críticas, preferir plan mode antes da edição; subagents apenas para workstreams independentes ou review. CLAUDE.md deve carregar/referenciar as regras canônicas. |

# 11. Planejar antes de implementar

Stories com alto impacto devem ter uma etapa de análise antes do código. O objetivo é revisar superfície de mudança e dependências enquanto a correção ainda é barata.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Analise a story, mas ainda não implemente.<br />
<br />
Entregue:<br />
1. impacto no schema;<br />
2. models/entities envolvidos;<br />
3. commands/application services;<br />
4. endpoints/DTOs;<br />
5. jobs/operations/reconcilers;<br />
6. eventos/outbox;<br />
7. autorização e auditoria;<br />
8. testes necessários;<br />
9. riscos e edge cases;<br />
10. arquivos que pretende criar ou alterar.<br />
<br />
Compare o plano com a documentação e aponte conflitos.<br />
Não escreva código ainda.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

Após revisão, a instrução seguinte pode ser objetiva: “Plano aprovado. Implemente exatamente o plano e execute os testes previstos.”

# 12. Review por outro agente

Uma implementação importante deve ser revisada por um contexto separado. O reviewer não deve receber como objetivo defender o código existente; deve comparar a mudança contra story, arquitetura, segurança e testes.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Revise a implementação da story M01-06.<br />
Não altere código.<br />
<br />
Compare:<br />
- diff/implementação;<br />
- story;<br />
- docs/AGENT_RULES.md;<br />
- arquivo de instruções do harness;<br />
- documentos referenciados;<br />
- requisitos de segurança;<br />
- estratégia de testes.<br />
<br />
Procure:<br />
- violações arquiteturais;<br />
- race conditions;<br />
- autorização ausente;<br />
- idempotência ausente;<br />
- auditoria ausente;<br />
- edge cases;<br />
- testes ausentes;<br />
- overengineering ou escopo não solicitado.<br />
<br />
Classifique: Critical, High, Medium, Low.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 12.1 Ciclo de correção

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Implementação<br />
↓<br />
Agent Review<br />
↓<br />
Critical/High?<br />
├─ sim -&gt; corrigir -&gt; testar -&gt; review curto<br />
└─ não -&gt; integrar</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

# 13. Commits, branches e worktrees

## 13.1 Commits pequenos

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>feat(team): implement team ownership<br />
feat(project): add project creation<br />
feat(environment): add cluster placement<br />
feat(service): persist service desired state<br />
feat(operation): introduce operation engine<br />
feat(swarm): create service executor<br />
feat(reconcile): converge service desired state</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

Evitar commits do tipo “implement platform”. A granularidade do commit deve permitir review, rollback e bisect sem carregar múltiplos conceitos não relacionados.

## 13.2 Paralelismo

No início, a sequência M0 -\> M1 -\> primeiro vertical slice deve ser majoritariamente serial. Worktrees e múltiplos agentes entram depois que schema, contracts e boundaries centrais estiverem estáveis.

| **Fase**                | **Paralelismo recomendado**                                                       |
|-------------------------|-----------------------------------------------------------------------------------|
| Foundation              | Baixo. Um fluxo principal para evitar divergência estrutural.                     |
| Vertical slice          | Baixo/médio. UI pode avançar sobre contratos já congelados.                       |
| Após contracts estáveis | Médio/alto. Vault, Build, Domains e Observability podem usar worktrees separados. |
| Release/Hardening       | Novamente controlado. Integração, migrations e security gates coordenados.        |

# 14. CI e gates para trabalho com agentes

Nenhum agente deve poder declarar uma story concluída apenas por inspeção visual. O repositório precisa tornar as regras executáveis via CI.

| **Gate**     | **Exemplos**                                                         |
|--------------|----------------------------------------------------------------------|
| Static       | format, lint, type checks, dependency checks.                        |
| Unit         | regras de domínio, policies, serializers e helpers.                  |
| Integration  | PostgreSQL real, transactions, locks, outbox.                        |
| Request/API  | contracts, authorization, error envelope.                            |
| Docker/Swarm | Executor e reconciler contra Swarm de laboratório quando necessário. |
| Security     | secret leakage, IDOR, permission boundaries, dangerous capabilities. |
| E2E          | jornada de UI associada à story quando aplicável.                    |
| Evidence     | lista de comandos/testes executados anexada ao resultado da task/PR. |

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th><strong>Regra<br />
</strong>O prompt pode pedir testes, mas o CI é a autoridade. Uma story só está integrada quando os gates relevantes estão verdes.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

# 15. Definition of Ready para uma Story

| **Critério**  | **Ready quando...**                                                            |
|---------------|--------------------------------------------------------------------------------|
| Objetivo      | Existe um resultado observável e limitado.                                     |
| Referências   | Os documentos fonte estão indicados.                                           |
| Dependências  | Stories bloqueadoras já foram concluídas ou mocks/contracts estão congelados.  |
| Boundary      | Está explícito o que a story não deve alterar.                                 |
| API/entidades | Contratos necessários estão definidos ou a story é responsável por defini-los. |
| Security      | Permissões e risco relevante estão identificados.                              |
| Acceptance    | Critérios verificáveis estão escritos.                                         |
| Tests         | Classes de teste exigidas estão especificadas.                                 |

# 16. Definition of Done para uma Story

| **Critério**     | **Done quando...**                                                        |
|------------------|---------------------------------------------------------------------------|
| Código           | Implementação completa dentro do boundary.                                |
| Migrations       | Aplicáveis e rollback/compatibilidade avaliados.                          |
| Authorization    | Policies e tenant boundaries cobertos.                                    |
| Audit/Operations | Eventos/Operation/Audit implementados quando aplicável.                   |
| Tests            | Suites relevantes passam localmente e no CI.                              |
| Review           | Nenhum Critical/High aberto.                                              |
| Docs             | Implementation Pack e contracts atualizados se necessário.                |
| Observability    | Logs/métricas/status adicionados quando o recurso introduz nova operação. |
| No drift         | Implementação não contradiz MASTER/AGENT_RULES/spec sem ADR.              |

# 17. Primeira semana recomendada

| **Dia** | **Meta**                                                                                                                 |
|---------|--------------------------------------------------------------------------------------------------------------------------|
| 1       | Criar repo; Rails; Next.js; PostgreSQL; ambiente local; CI; docs/AGENT_RULES.md; AGENTS.md; CLAUDE.md; MASTER.md; docs/. |
| 2       | User, Team, TeamMember, OWNER, autenticação e autorização.                                                               |
| 3       | Cluster, Project, Environment e schema de Service.                                                                       |
| 4       | Operation, Outbox, desiredRevision e appliedRevision.                                                                    |
| 5       | Docker client, Swarm Executor e criação de Docker Service.                                                               |
| 6       | Service Reconciler, Actual State e health derivado.                                                                      |
| 7       | UI para criar Service, acompanhar estado, logs e Scale 1 -\> 3.                                                          |

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th><strong>Marco da semana 1<br />
</strong>Ao final, a plataforma deve permitir: UI -&gt; Create Service -&gt; PostgreSQL -&gt; Operation -&gt; Executor -&gt; Docker Swarm -&gt; Running Service -&gt; UI Healthy. Essa linha vertical vale mais do que dezenas de telas sem runtime real.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

# 18. Sequência após o primeiro slice

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Slice 1 Image -&gt; Swarm<br />
↓<br />
Slice 2 Git -&gt; Railpack -&gt; BuildKit -&gt; Registry<br />
↓<br />
Slice 3 Traefik -&gt; Default Domain<br />
↓<br />
Slice 4 Vault -&gt; SecretVersion -&gt; Swarm Secret<br />
↓<br />
Slice 5 Release -&gt; Deploy -&gt; Rollback -&gt; Promotion<br />
↓<br />
Slice 6 Custom Domain -&gt; DNS -&gt; TLS<br />
↓<br />
Slice 7 Multi-node -&gt; HA -&gt; LB<br />
↓<br />
Slice 8 Observability -&gt; Alerts -&gt; Autoscaling<br />
↓<br />
Slice 9 Backup -&gt; Restore -&gt; DR<br />
↓<br />
Slice 10 MCP -&gt; Agent-first operations</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 18.1 Por que MCP entra depois

O MCP deve chamar uma Command/Query Layer madura. Implementá-lo cedo demais força o projeto a estabilizar tools sobre contratos ainda instáveis e aumenta retrabalho. Quando API, Operations, RBAC e auditoria já estiverem consolidados, o Anexo F se torna principalmente um adapter de protocolo.

# 19. Trilha de execução por milestone

| **Etapa**              | **Saída esperada**                                     |
|------------------------|--------------------------------------------------------|
| 1\. Preparar milestone | Selecionar objetivos do Anexo A e dependências.        |
| 2\. Criar stories      | Quebrar em unidades pequenas com template deste anexo. |
| 3\. Ready check        | Aplicar Definition of Ready.                           |
| 4\. Agent plan         | Para stories críticas, pedir plano sem código.         |
| 5\. Implementar        | O agente altera apenas o boundary acordado.            |
| 6\. Validar            | Executar testes e CI.                                  |
| 7\. Review             | Outro agente/humano compara diff com especificação.    |
| 8\. Corrigir           | Resolver Critical/High e regressões.                   |
| 9\. Integrar           | Commit/PR pequeno e rastreável.                        |
| 10\. Atualizar pack    | Registrar decisões locais e próxima dependência.       |

# 20. Architecture Decision Records durante a construção

Nem toda decisão aparecerá antes do código. Quando surgir uma decisão nova com impacto sistêmico, ela deve ser registrada em docs/decisions antes de virar padrão implícito.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>docs/decisions/ADR-0007-solid-queue-job-semantics.md<br />
<br />
Status: Accepted<br />
Context: ...<br />
Decision: ...<br />
Consequences: ...<br />
Alternatives considered: ...<br />
Affected docs: ...<br />
Affected modules: ...</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 20.1 Quando criar ADR

> **•** Mudança de tecnologia estrutural.
>
> **•** Alteração de contrato entre módulos.
>
> **•** Nova regra de consistência/concorrência.
>
> **•** Mudança de security boundary.
>
> **•** Exceção permanente a um invariante existente.

# 21. Context management para agentes

O objetivo é manter o contexto relevante pequeno e explícito. Uma story deve referenciar apenas os documentos necessários. O agente deve descobrir código existente pelo repositório e não receber cópias gigantes de trechos que podem ficar desatualizadas.

| **Camada de contexto** | **Conteúdo**                                            |
|------------------------|---------------------------------------------------------|
| Sempre                 | Arquivo do harness + docs/AGENT_RULES.md + story atual. |
| Roteamento             | docs/MASTER.md.                                         |
| Sob demanda            | 2-5 documentos referenciados pela story.                |
| Código                 | Arquivos e testes diretamente relacionados.             |
| Evitar                 | Todas as Partes/Anexos em todo prompt.                  |

# 22. Padrão de relatório ao finalizar uma task

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>## Resultado<br />
Story: M01-06 Create Service<br />
Status: completed<br />
<br />
## Arquivos alterados<br />
- ...<br />
<br />
## Schema / API / Events<br />
- ...<br />
<br />
## Decisões locais<br />
- ...<br />
<br />
## Testes executados<br />
- command: ...<br />
result: PASS<br />
<br />
## Acceptance Criteria<br />
- [x] ...<br />
- [x] ...<br />
<br />
## Pendências / conflitos<br />
- none</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

Esse formato cria rastreabilidade e torna mais simples pedir a outro agente que faça review da implementação sem refazer todo o raciocínio.

# 23. Critérios de sucesso desta estratégia

| **\#** | **Critério**                                                                                                             |
|--------|--------------------------------------------------------------------------------------------------------------------------|
| 1      | Todo agente recebe regras permanentes por docs/AGENT_RULES.md e pelo adapter nativo do harness (AGENTS.md ou CLAUDE.md). |
| 2      | Toda decisão arquitetural possui fonte encontrada via MASTER.md.                                                         |
| 3      | DOCX principal possui versão Markdown fiel para consumo no repositório.                                                  |
| 4      | Toda implementação relevante nasce de uma Story no Implementation Pack.                                                  |
| 5      | Stories possuem objective, references, boundary, acceptance e tests.                                                     |
| 6      | O primeiro slice prova a cadeia UI -\> Desired State -\> Operation -\> Swarm -\> Actual State.                           |
| 7      | A API pública nunca acessa docker.sock.                                                                                  |
| 8      | Mudanças estruturais geram ADR e atualização documental.                                                                 |
| 9      | Stories críticas recebem plan review antes da implementação, independentemente do harness.                               |
| 10     | Mudanças recebem review contra especificação, não apenas contra estilo de código.                                        |
| 11     | Critical/High findings bloqueiam integração.                                                                             |
| 12     | CI é autoridade de qualidade; relato do agente não substitui gate automatizado.                                          |
| 13     | Commits e PRs permanecem pequenos e semanticamente rastreáveis.                                                          |
| 14     | Paralelismo só cresce depois de contratos centrais estabilizados.                                                        |
| 15     | MCP é implementado sobre Command/Query Layer madura, não em paralelo ao core inicial.                                    |
| 16     | Uma nova sessão de qualquer agente suportado consegue iniciar uma story sem reconstruir a arquitetura por conversa.      |

# 24. Próximo passo concreto

Com este anexo aprovado, a próxima atividade prática é criar o repositório e produzir o primeiro Implementation Pack real: M00 Foundation + M01 Vertical Slice. Isso significa materializar docs/AGENT_RULES.md, AGENTS.md, CLAUDE.md, MASTER.md, estrutura docs/, as stories M00/M01 e os prompts de execução dentro do próprio Git.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th><strong>Ponto de partida recomendado<br />
Não começar pelo código de negócio. Primeiro criar o repositório como sistema de contexto e execução. Depois entregar ao agente selecionado a primeira Story pequena do M00. A partir desse momento, cada avanço da plataforma deve deixar uma trilha clara entre especificação, story, diff, testes e resultado operacional.</strong></th>
</tr>
</thead>
<tbody>
</tbody>
</table>
