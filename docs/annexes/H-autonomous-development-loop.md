---
document: "H"
title: "Autonomous Development Loop"
type: "annex"
status: "approved"
source: "docx"
---

**PLATAFORMA PAAS  
CLUSTER-FIRST**

**Anexo H - Autonomous Development Loop**

Operação quase autônoma do ciclo de desenvolvimento com Claude Code, /goal, Auto Mode, hooks, Builder/Reviewer, gates determinísticos e aceitação humana por Milestone

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th><p><strong>Princípio central</strong></p>
<p>Automatizar a execução mecânica da engenharia, não terceirizar a responsabilidade do produto. O agente pode planejar, codificar, testar, revisar, corrigir e commitar Stories sozinho; decisões ambíguas, mudanças arquiteturais e aceitação do produto continuam sob gates explícitos.</p></th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## Resumo executivo

Este anexo define um modelo operacional para executar o Implementation Pack com alto grau de autonomia utilizando Claude Code. O objetivo é reduzir a necessidade de prompts manuais entre ferramentas e entre turns, permitindo que um Milestone avance por várias Stories até atingir uma condição verificável de conclusão.

O desenho combina quatro mecanismos: /goal para continuidade entre turns; um modo de permissão apropriado para reduzir interrupções; hooks determinísticos para bloquear falsos positivos de conclusão; e um estado persistente no repositório para que progresso, falhas e evidências não dependam da memória da conversa.

A autonomia é deliberadamente limitada por escopo. O nível recomendado para o início do projeto é Story 100% autônoma e Milestone quase autônomo, com aceitação humana no final. O projeto inteiro não deve ser liberado como um único goal até que vários Milestones tenham provado que o processo é estável, previsível e recuperável.

# 1. Objetivo e modelo de autonomia

## 1.1 Objetivo

Permitir que o Claude Code execute longos blocos de desenvolvimento sem supervisão contínua, mantendo rastreabilidade, segurança, qualidade e capacidade de recuperação. O usuário deixa de operar como aprovador de cada tool call e passa a atuar principalmente como Product Owner, arquiteto de exceções e acceptance reviewer.

## 1.2 Níveis de autonomia

| **Nível**           | **Escopo**                  | **Autonomia recomendada** | **Gate humano**                 |
|---------------------|-----------------------------|---------------------------|---------------------------------|
| L0 - Assistido      | Uma mudança pequena         | Baixa                     | Cada alteração relevante        |
| L1 - Story Loop     | Uma Story                   | Alta / completa           | Somente se bloqueada ou crítica |
| L2 - Milestone Loop | Várias Stories relacionadas | Muito alta                | Aceitação ao final do Milestone |
| L3 - Project Loop   | Vários Milestones           | Experimental              | Gates periódicos e exceções     |

Baseline recomendado: operar em L1 desde o primeiro Milestone; habilitar L2 quando o pipeline de testes, hooks e rollback estiver confiável; não usar L3 no início.

## 1.3 Fluxo de referência

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Specification + Implementation Pack<br />
|<br />
v<br />
Milestone Mxx<br />
|<br />
v<br />
Autonomous Loop<br />
+---------+---------+<br />
| |<br />
Builder Agent Reviewer Agent<br />
| |<br />
+---------+---------+<br />
|<br />
Test Gates<br />
|<br />
pass? / fail?<br />
| |<br />
| +--&gt; Fix Loop<br />
v<br />
Commit<br />
|<br />
next Story<br />
|<br />
v<br />
Milestone Report<br />
|<br />
v<br />
HUMAN ACCEPTANCE</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

# 2. /goal como motor de continuidade

## 2.1 Papel do /goal

O /goal deve ser utilizado como condição de conclusão do trabalho, e não como descrição genérica do produto. Enquanto a condição não for considerada satisfeita, o Claude Code continua iniciando novos turns sem exigir um novo prompt humano.

A condição deve ser mensurável e mencionar como a conclusão será demonstrada. O avaliador do /goal não executa ferramentas por conta própria; ele julga o que foi evidenciado na conversa. Por isso, testes e validações precisam ser executados pelo agente e surfacados no transcript.

## 2.2 Goal correto por Milestone

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>/goal M01 está concluído quando:<br />
- todas as Stories em docs/implementation/M01/tasks.json estão DONE;<br />
- todos os acceptance criteria das Stories estão atendidos;<br />
- a suíte exigida pelo Milestone termina com exit code 0;<br />
- o vertical slice E2E passa;<br />
- nenhum finding Critical ou High permanece aberto;<br />
- cada Story concluída possui commit;<br />
- o Milestone Report foi gerado;<br />
OU interrompa e marque BLOCKED se um blocker real não puder ser resolvido dentro da política de tentativas.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 2.3 O que não usar como goal

• “Construa a plataforma inteira.”

• “Continue até tudo ficar perfeito.”

• Condições que dependem apenas da opinião do mesmo agente que implementou.

• Goals sem limite operacional, sem estado persistente e sem critério de bloqueio.

• Goals que autorizam mudança arquitetural silenciosa para remover um blocker.

# 3. Permissões e execução sem intervenção

## 3.1 Modo recomendado

Quando Auto Mode estiver disponível para a conta e para o ambiente utilizado, ele é o modo preferencial para Milestones autônomos de baixo e médio risco. O objetivo é eliminar prompts rotineiros de permissão enquanto um classificador separado aplica verificações de segurança. Como o recurso é apresentado como research preview, ele não substitui isolamento de ambiente, hooks e revisão.

| **Modo**          | **Uso neste projeto**                                                                                        |
|-------------------|--------------------------------------------------------------------------------------------------------------|
| plan              | Exploração e planejamento de mudanças críticas antes de editar.                                              |
| acceptEdits       | Boa opção intermediária para desenvolvimento supervisionado.                                                 |
| auto              | Preferido para loops autônomos quando disponível e em workspace isolado.                                     |
| dontAsk           | Útil em automações travadas a um allowlist explícito de ferramentas.                                         |
| bypassPermissions | Não usar no host pessoal ou infraestrutura real; apenas em sandbox/VM descartável e conscientemente isolada. |

## 3.2 Guardrails independentes do modo

• Nenhuma credencial de produção deve existir no workspace autônomo.

• O agente não recebe acesso direto a servidores de produção, cloud admin ou docker.sock de produção.

• Comandos destrutivos de Git, banco, filesystem e infraestrutura devem ser bloqueados por PreToolUse/command hooks ou por allowlist.

• Dependências podem ser instaladas apenas conforme política do repositório; novas dependências precisam ser registradas no relatório da Story.

• Ações externas irreversíveis ficam fora do Autonomous Loop.

# 4. Stop Gates determinísticos

## 4.1 Por que /goal não basta

O /goal possui um avaliador sem tools. Isso é adequado para decidir se uma condição declarada está demonstrada, mas não substitui checks determinísticos. A conclusão real de uma Story ou Milestone deve ser bloqueada por gates que executam comandos e verificam estado do repositório.

## 4.2 Stop Hook recomendado

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Stop Gate<br />
|<br />
+--&gt; lint / format exit 0?<br />
+--&gt; unit / integration exit 0?<br />
+--&gt; contract tests exit 0?<br />
+--&gt; story acceptance script exit 0?<br />
+--&gt; security checks exit 0?<br />
+--&gt; tasks.json consistente yes?<br />
+--&gt; Critical/High findings zero?<br />
+--&gt; milestone report exists?<br />
<br />
if any check fails:<br />
ok: false<br />
reason: &lt;evidência objetiva&gt;<br />
-&gt; Claude continua trabalhando</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 4.3 Command hooks versus agent hooks

| **Tipo**     | **Uso**                                                                             | **Política**                                                          |
|--------------|-------------------------------------------------------------------------------------|-----------------------------------------------------------------------|
| Command hook | Checks determinísticos: testes, lint, JSON schema, git diff, arquivos obrigatórios. | Preferido para gates de produção do processo.                         |
| Prompt hook  | Julgamento simples baseado no input do hook.                                        | Usar apenas onde shell não expressa bem a regra.                      |
| Agent hook   | Verificação que precisa inspecionar arquivos e executar tools.                      | Útil para review; tratar como experimental e não como única barreira. |

A documentação atual do Claude Code informa que agent hooks são experimentais. Para um processo confiável, a última palavra sobre “pode encerrar” deve preferir scripts determinísticos sempre que o critério puder ser codificado.

# 5. Estado persistente do trabalho

## 5.1 Conversa não é banco de estado

O estado do Autonomous Loop deve ser reconstruível a partir do repositório. Uma sessão perdida, compactada ou retomada não pode destruir o conhecimento sobre o que já foi concluído.

## 5.2 tasks.json

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>{<br />
"milestone": "M01",<br />
"status": "IN_PROGRESS",<br />
"stories": [<br />
{<br />
"id": "M01-01",<br />
"file": "01-team.md",<br />
"status": "DONE",<br />
"attempts": 1,<br />
"commit": "a1b2c3d"<br />
},<br />
{<br />
"id": "M01-02",<br />
"file": "02-project.md",<br />
"status": "IN_PROGRESS",<br />
"attempts": 2<br />
},<br />
{<br />
"id": "M01-03",<br />
"file": "03-environment.md",<br />
"status": "PENDING"<br />
}<br />
]<br />
}</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 5.3 Artefatos persistentes mínimos

| **Artefato**        | **Função**                                              |
|---------------------|---------------------------------------------------------|
| tasks.json          | Estado das Stories e attempts.                          |
| Story .md           | Objetivo, boundary, referências, aceite e testes.       |
| Git history         | Checkpoints imutáveis do código.                        |
| review/\<story\>.md | Findings e decisão de review.                           |
| evidence/\<story\>/ | Saídas resumidas de testes e checks quando necessário.  |
| MILESTONE_REPORT.md | Resumo final para aceitação humana.                     |
| BLOCKERS.md         | Problemas que exigem decisão ou infraestrutura externa. |

# 6. State machine da Story

## 6.1 Estados

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>PENDING<br />
|<br />
v<br />
PLANNING<br />
|<br />
v<br />
IMPLEMENTING<br />
|<br />
v<br />
TESTING<br />
|<br />
v<br />
REVIEWING<br />
|<br />
+------ findings? ------+<br />
| |<br />
| v<br />
| FIXING<br />
| |<br />
+&lt;----------------------+<br />
|<br />
v<br />
READY_TO_COMMIT<br />
|<br />
v<br />
DONE<br />
<br />
Any active state -&gt; BLOCKED when policy is exhausted.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 6.2 Regra de tentativas

O loop não deve perseverar indefinidamente. Cada Story define uma política de tentativas. Uma falha nova e informativa pode justificar nova tentativa; repetição sem progresso aumenta o contador. Ao atingir o limite, a Story passa para BLOCKED com diagnóstico reproduzível.

| **Condição**                                      | **Ação**                                                 |
|---------------------------------------------------|----------------------------------------------------------|
| Falha de teste clara                              | Corrigir e repetir.                                      |
| Mesma falha sem progresso em múltiplas tentativas | Trocar estratégia uma vez; depois considerar BLOCKED.    |
| Dependência externa indisponível                  | Registrar BLOCKED e avançar Stories independentes.       |
| Conflito com arquitetura                          | BLOCKED imediatamente; nunca redesenhar silenciosamente. |
| Requisito ambíguo que altera produto              | BLOCKED_FOR_PRODUCT_DECISION.                            |
| Ação destrutiva ou produção necessária            | BLOCKED_FOR_HUMAN_APPROVAL.                              |

# 7. Builder Agent e Reviewer Agent

## 7.1 Separação de papéis

O agente que implementa não deve ser a única fonte de revisão. O loop usa um segundo contexto, subagent ou sessão dedicada para revisar a Story como adversário técnico, comparando diff, especificação, security requirements e tests.

| **Papel**      | **Responsabilidade**                                                                  |
|----------------|---------------------------------------------------------------------------------------|
| Builder        | Planejar, implementar, testar e produzir evidências.                                  |
| Reviewer       | Procurar violações, regressões, overengineering, gaps de segurança e testes ausentes. |
| Gate scripts   | Decidir objetivamente se checks determinísticos passam.                               |
| Human reviewer | Aceitar comportamento do produto e resolver exceções de arquitetura/UX.               |

## 7.2 Critério de fechamento do review

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Critical = 0<br />
High = 0<br />
Medium = 0 ou explicitamente aceito pela política do Milestone<br />
Low = pode virar backlog se não afetar acceptance/security<br />
<br />
Reviewer != justificativa para refatorar fora do boundary.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

# 8. Git como sistema de checkpoint

## 8.1 Um commit por Story concluída

Cada Story só recebe status DONE depois de review e gates. O commit é o checkpoint do loop. Isso reduz blast radius, facilita bisect, permite reverter uma Story sem apagar todo o progresso e torna o relatório de Milestone auditável.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>feat(team): implement team ownership<br />
feat(project): implement project lifecycle<br />
feat(environment): add cluster placement<br />
feat(service): persist desired state<br />
feat(operation): introduce operation workflow<br />
feat(swarm): create service executor<br />
feat(reconcile): converge service desired state</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 8.2 Branch e worktree

No início, um Milestone deve trabalhar em uma branch única e Stories sequenciais no caminho crítico. Worktrees paralelos entram somente quando contratos e boundaries estiverem estabilizados. Cada worktree precisa de Story exclusiva para evitar dois agentes editando o mesmo domínio ao mesmo tempo.

# 9. Milestone Loop

## 9.1 Algoritmo operacional

1\. Carregar CLAUDE.md, AGENT_RULES, MASTER e README do Milestone.

2\. Validar tasks.json e selecionar a primeira Story PENDING não bloqueada por dependência.

3\. Planejar a Story e comparar o plano com seus boundaries.

4\. Implementar a menor solução completa.

5\. Executar testes definidos na Story.

6\. Acionar review independente.

7\. Corrigir findings dentro da política.

8\. Rodar Stop Gates da Story.

9\. Criar commit e atualizar tasks.json.

10\. Selecionar a próxima Story.

11\. Ao terminar todas as Stories, executar gates completos do Milestone.

12\. Gerar MILESTONE_REPORT.md e devolver controle ao humano.

## 9.2 Milestone Report

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th># M01 - READY FOR ACCEPTANCE<br />
<br />
Stories: 17/17 DONE<br />
Blocked: 0<br />
Commits: 17<br />
<br />
Quality<br />
- Unit/Integration: 186/186<br />
- Contract: 22/22<br />
- E2E: 14/14<br />
- Security checks: PASS<br />
- Critical: 0<br />
- High: 0<br />
<br />
Vertical Slice<br />
- create Team: PASS<br />
- create Project: PASS<br />
- create Environment: PASS<br />
- create Service: PASS<br />
- Swarm service running: PASS<br />
- scale 1 -&gt; 3: PASS<br />
- actual state 3/3: PASS<br />
<br />
Human acceptance requested:<br />
- UX flow<br />
- behavior vs specification<br />
- known Medium/Low findings</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

# 10. Human gates

## 10.1 O que o humano aprova

| **Gate**               | **Humano verifica**                                             |
|------------------------|-----------------------------------------------------------------|
| Milestone Acceptance   | Comportamento real, UX, coerência com produto e arquitetura.    |
| Architecture Exception | Qualquer mudança que altere decisão registrada em docs/ ou ADR. |
| Security Exception     | Risco residual fora da política.                                |
| External Side Effect   | Ações irreversíveis ou que afetam ambiente real.                |
| Blocked Decision       | Requisito ambíguo, conflito de produto ou escolha não prevista. |

## 10.2 O que o humano deixa de fazer

• Aprovar cada edição de arquivo.

• Pedir manualmente para rodar testes após cada mudança.

• Repetir “continue” a cada turn.

• Lembrar ao agente qual Story vem depois.

• Revisar todo controller ou migration antes de existir evidência de que a Story funciona.

# 11. Ações proibidas no loop autônomo

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th><p><strong>No-go zone</strong></p>
<p>O Autonomous Development Loop é um executor de desenvolvimento. Ele não ganha automaticamente autoridade operacional sobre produção.</p></th>
</tr>
</thead>
<tbody>
</tbody>
</table>

| **Ação**                                                  | **Política**                                                               |
|-----------------------------------------------------------|----------------------------------------------------------------------------|
| Deploy em produção                                        | Somente em workflow explicitamente autorizado fora do loop de codificação. |
| Alterar DNS real                                          | Bloqueado.                                                                 |
| Acessar secrets de produção                               | Bloqueado.                                                                 |
| Excluir banco/volume/registry real                        | Bloqueado.                                                                 |
| Force push em branch protegida                            | Bloqueado.                                                                 |
| Modificar docs de arquitetura para “fazer o teste passar” | Bloqueado; precisa ADR/decisão humana.                                     |
| Desabilitar testes ou gates para completar goal           | Bloqueado.                                                                 |
| Usar bypassPermissions no host de trabalho                | Não recomendado; apenas sandbox descartável deliberada.                    |

# 12. Sandbox e isolamento do agente

## 12.1 Ambiente recomendado

O ideal é executar o loop em workspace reproduzível e descartável, com banco e serviços de desenvolvimento locais, credenciais mínimas, acesso de rede limitado e nenhuma identidade administrativa de cloud. Quanto maior a autonomia, maior deve ser a qualidade do isolamento.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Developer machine / CI host<br />
|<br />
+--&gt; isolated worktree / container / VM<br />
|<br />
+--&gt; source repo<br />
+--&gt; dev PostgreSQL<br />
+--&gt; test Redis/queue if required<br />
+--&gt; disposable Docker/Swarm Lab<br />
+--&gt; fake/test providers<br />
+--&gt; no production credentials</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 12.2 Swarm Lab

Testes que precisam da Docker Engine ou Swarm devem apontar para um lab descartável. O agente não deve ter o socket Docker de produção. Destruição e recriação do ambiente de teste precisa ser um comando documentado e seguro.

# 13. Recuperação de contexto

## 13.1 Nova sessão

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>new Claude session<br />
|<br />
v<br />
CLAUDE.md<br />
|<br />
AGENT_RULES.md<br />
|<br />
MASTER.md<br />
|<br />
tasks.json<br />
|<br />
git log / git status<br />
|<br />
current Story<br />
|<br />
continue from persisted state</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

Resume e continue são conveniências. A fonte de verdade continua sendo Git + arquivos do Implementation Pack. Se uma sessão só consegue continuar porque “lembra” de algo que não está persistido, o processo está errado.

# 14. Execução headless e Dev Orchestrator

## 14.1 Fase 1 - Claude Code diretamente

No primeiro momento, o loop pode rodar diretamente no Claude Code interativo ou em print mode. /goal funciona também em execução não interativa, permitindo que uma invocação prossiga até a condição ser atingida ou interrompida.

| claude -p "/goal M01 atende integralmente a condição definida em docs/implementation/M01/GOAL.md" |
|---------------------------------------------------------------------------------------------------|

## 14.2 Fase 2 - wrapper do projeto

Quando o processo estiver estável, um wrapper próprio pode preparar ambiente, invocar Claude Code, coletar output estruturado, aplicar limites, armazenar logs e gerar o relatório final. O wrapper não toma decisões de produto; ele orquestra o protocolo já definido.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>./dev milestone M01<br />
|<br />
v<br />
Dev Orchestrator<br />
|<br />
+--&gt; prepare sandbox<br />
+--&gt; validate implementation pack<br />
+--&gt; invoke Claude Code<br />
+--&gt; enforce max turns / time / budget<br />
+--&gt; collect structured output<br />
+--&gt; archive evidence<br />
+--&gt; produce final status<br />
|<br />
v<br />
READY | BLOCKED | FAILED</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 14.3 Limites de execução

| **Limite**         | **Exemplo de política**                                                 |
|--------------------|-------------------------------------------------------------------------|
| Turns              | Definir teto por Milestone em execução headless.                        |
| Attempts por Story | 3 tentativas sem progresso antes de BLOCKED, salvo política específica. |
| Tempo              | Interromper loops claramente estagnados; registrar checkpoint.          |
| Custo/tokens       | Registrar consumo por Milestone para acompanhar eficiência.             |
| Mudanças           | Bloquear diffs fora do boundary da Story.                               |

# 15. Observabilidade do processo de desenvolvimento

## 15.1 Métricas

| **Métrica**                      | **Objetivo**                                             |
|----------------------------------|----------------------------------------------------------|
| Story autonomous completion rate | Percentual de Stories concluídas sem intervenção humana. |
| Blocked rate                     | Quantas Stories exigem decisão externa.                  |
| First-pass test rate             | Percentual que passa gates na primeira implementação.    |
| Review escape rate               | Defeitos encontrados pelo humano após review automático. |
| Rework after acceptance          | Mudanças pedidas depois do gate humano.                  |
| Average attempts/story           | Detectar loops improdutivos.                             |
| Tokens/cost per Story            | Medir eficiência da automação.                           |
| Cycle time/story                 | Tempo entre PENDING e DONE.                              |
| Rollback rate                    | Quantas Stories precisaram ser revertidas.               |

## 15.2 Logs mínimos

• ID do Milestone e Story.

• Session ID quando disponível.

• Commits produzidos.

• Test commands e resultado resumido.

• Findings do Reviewer.

• Número de attempts.

• Motivo de BLOCKED/FAILED.

• Mudanças de dependency ou migration.

# 16. Failure modes do Autonomous Loop

| **Falha**                         | **Detecção**                      | **Resposta**                                        |
|-----------------------------------|-----------------------------------|-----------------------------------------------------|
| Agente declara DONE cedo          | Stop Gate falha                   | Continuar com reason objetiva.                      |
| Loop repete a mesma correção      | Attempts sem progresso            | Trocar estratégia uma vez; depois BLOCKED.          |
| Agente amplia escopo              | Diff boundary check/review        | Reverter mudanças extras e reforçar Story.          |
| Teste é removido para ficar verde | Review + protected files/policies | Falha crítica; restaurar teste.                     |
| Conversa perde contexto           | Estado não bate com repo          | Rebootstrap por tasks.json + Git.                   |
| Hook fica bloqueando em ciclo     | Cap/guard do Stop hook            | Registrar diagnóstico; evitar continuação infinita. |
| Dependência externa cai           | Test/health check                 | BLOCKED_EXTERNAL_DEPENDENCY.                        |
| Milestone gera regressão          | Full suite / E2E                  | Corrigir antes de READY.                            |

# 17. Estratégia de adoção

## 17.1 Rollout em cinco fases

| **Fase** | **Modo**                               | **Critério para avançar**                       |
|----------|----------------------------------------|-------------------------------------------------|
| F0       | Story assistida                        | Processo e artifacts funcionam manualmente.     |
| F1       | Story autônoma                         | 5-10 Stories seguidas sem violações críticas.   |
| F2       | Milestone autônomo com humano no final | 2-3 Milestones aceitos com baixo rework.        |
| F3       | Milestones consecutivos                | Gates e métricas mostram confiabilidade.        |
| F4       | Orchestrator headless                  | Execução reproduzível, auditável e recuperável. |

## 17.2 Primeiro piloto recomendado

O primeiro piloto deve ser o vertical slice inicial do roadmap, porque ele é significativo o suficiente para testar banco, domínio, Operations, Executor e UI, mas ainda possui um boundary claro. Não iniciar o piloto com TLS, DR, autoscaling ou MCP.

# 18. Template operacional de GOAL.md

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th># M01 Autonomous Goal<br />
<br />
## Completion condition<br />
M01 is READY when every required Story is DONE, all mandatory checks pass,<br />
the vertical slice works end-to-end, Critical/High findings are zero,<br />
and MILESTONE_REPORT.md is generated.<br />
<br />
## Required proof<br />
- task state validated<br />
- test commands and exit codes recorded<br />
- E2E acceptance executed<br />
- review results recorded<br />
- one commit per completed Story<br />
<br />
## Constraints<br />
- do not change architecture outside referenced docs<br />
- do not disable tests or gates<br />
- do not access production infrastructure<br />
- do not add speculative features<br />
<br />
## Block policy<br />
If a Story cannot progress after the allowed attempts, mark it BLOCKED with<br />
a reproducible reason and continue only with independent Stories.<br />
<br />
## End state<br />
READY, BLOCKED, or FAILED. Never silently abandon work.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

# 19. Definition of Done do Autonomous Loop

| **\#** | **Critério**                                                                           |
|--------|----------------------------------------------------------------------------------------|
| 1      | Story possui objetivo, boundary, referências, aceite e testes antes de entrar no loop. |
| 2      | tasks.json é schema-valid e representa o estado real.                                  |
| 3      | /goal é scoped ao Milestone ou à Story, nunca ao produto inteiro no início.            |
| 4      | Conclusão é protegida por Stop Gates determinísticos.                                  |
| 5      | Builder e Reviewer têm papéis separados.                                               |
| 6      | Critical e High ficam zerados antes de DONE.                                           |
| 7      | Cada Story DONE possui commit identificável.                                           |
| 8      | Nenhuma credencial de produção existe no sandbox.                                      |
| 9      | Mudanças arquiteturais não são feitas silenciosamente.                                 |
| 10     | Ações destrutivas externas são bloqueadas.                                             |
| 11     | Falhas repetidas convergem para BLOCKED, não loop infinito.                            |
| 12     | Nova sessão consegue reconstruir estado sem memória privada da conversa.               |
| 13     | Milestone executa suíte completa antes de READY.                                       |
| 14     | MILESTONE_REPORT.md contém evidências objetivas.                                       |
| 15     | Humano consegue aceitar/rejeitar o Milestone olhando produto + relatório.              |
| 16     | Métricas básicas de autonomia e rework são registradas.                                |
| 17     | Rollback para checkpoint anterior é simples e testado.                                 |
| 18     | Processo pode ser interrompido sem perder progresso válido.                            |

# 20. Decisão recomendada para este projeto

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th><p><strong>Baseline operacional</strong></p>
<p>Automatizar completamente o Story Loop; automatizar o Milestone Loop até READY; manter um gate humano de produto ao final de cada Milestone. Após alguns Milestones com baixo rework e nenhum incidente de segurança/processo, aumentar gradualmente a autonomia. O primeiro objetivo não é “zero humanos”; é “zero intervenção mecânica desnecessária”.</p></th>
</tr>
</thead>
<tbody>
</tbody>
</table>

Nesse modelo, o usuário atua onde possui maior valor: validação do produto, experiência, prioridades e exceções. O Claude Code assume o trabalho repetitivo de implementação, testes, revisão inicial, correções e checkpoints. O sistema de gates evita que velocidade seja obtida trocando previsibilidade por confiança cega.

# 21. Referências técnicas atuais

| **Documento**                              | **URL**                                                  |
|--------------------------------------------|----------------------------------------------------------|
| Claude Code - /goal                        | https://code.claude.com/docs/en/goal                     |
| Claude Code - Hooks                        | https://code.claude.com/docs/en/hooks                    |
| Claude Code - Hooks guide                  | https://code.claude.com/docs/en/hooks-guide              |
| Claude Code - Permission modes / Auto mode | https://code.claude.com/docs/en/permission-modes         |
| Claude Code - CLI reference                | https://docs.anthropic.com/en/docs/claude-code/cli-usage |

As capacidades específicas do Claude Code podem evoluir. O Implementation Pack e os gates deste anexo devem permanecer agnósticos sempre que possível; /goal, Auto Mode e hooks são adapters de execução, não a fonte de verdade da arquitetura ou dos critérios de aceite.
