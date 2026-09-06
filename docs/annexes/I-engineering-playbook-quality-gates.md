---
document: "I"
title: "Engineering Playbook e Quality Gates"
type: "annex"
status: "approved"
source: "docx"
---

**PLATAFORMA PAAS  
CLUSTER-FIRST**

**Anexo I - Engineering Playbook e Quality Gates**

Processo de desenvolvimento, padrões arquiteturais, reutilização de componentes, gates pré/pós-commit, review, merge, fitness functions e qualidade contínua para humanos e agentes

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th><p><strong>Princípio central</strong></p>
<p>Código correto não é apenas código que passa nos testes. Para entrar na base ele deve respeitar arquitetura, autorização, observabilidade, padrões de dados, reutilização, simplicidade, segurança, rollback e os gates definidos neste playbook. O mesmo padrão vale para código humano e código gerado por agentes.</p></th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## Resumo executivo

Este anexo define o sistema operacional de engenharia do repositório. Ele complementa o Anexo D, que define a estratégia de testes, o Anexo G, que define o desenvolvimento orientado por agentes, e o Anexo H, que define o loop autônomo. Aqui são estabelecidas as regras que cada mudança deve respeitar antes, durante e depois de um commit.

Os exemplos assumem como stack de trabalho o Control Plane em Rails, PostgreSQL, uma UI React/TypeScript integrada ao backend e os subsistemas de infraestrutura definidos nas Partes 1-10. As regras de engenharia, entretanto, são independentes de pequenos ajustes de framework e devem sobreviver à evolução da implementação.

# 1. Escopo, autoridade e precedência

## 1.1 O que este documento governa

• Organização e boundaries do código.

• Padrões de projeto aceitos e critérios para introduzi-los.

• Qualidade mínima para backend, frontend, banco, jobs, reconcilers, providers e infraestrutura.

• Reutilização e evolução do design system/componentes React existentes.

• Pre-commit, commit, post-commit, PR, merge e release quality gates.

• Política de dependências, refatoração, tech debt e mudanças fora de escopo.

• Fitness functions que transformam regras arquiteturais em checks executáveis.

• Critérios usados por Builder Agents, Reviewer Agents e pelo Autonomous Development Loop.

## 1.2 Ordem de precedência

| **Prioridade** | **Fonte**                                   | **Regra**                                                 |
|----------------|---------------------------------------------|-----------------------------------------------------------|
| 1              | Partes 1-10 + anexos normativos             | Arquitetura, segurança, dados e comportamento do produto. |
| 2              | Story / ADR aprovado                        | Decisão específica e escopo da mudança.                   |
| 3              | Este Engineering Playbook                   | Como a mudança deve ser implementada e validada.          |
| 4              | docs/AGENT_RULES.md / AGENTS.md / CLAUDE.md | Adaptação operacional para o agente.                      |
| 5              | Preferência do desenvolvedor/agente         | Só vale quando nenhuma fonte acima define o assunto.      |

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th><p><strong>Regra de conflito</strong></p>
<p>Se uma implementação exigir violar uma regra de nível superior, o agente deve interromper, registrar o conflito e pedir uma decisão/ADR. Não é permitido “resolver” o conflito alterando silenciosamente a arquitetura.</p></th>
</tr>
</thead>
<tbody>
</tbody>
</table>

# 2. Princípios de engenharia

| **Princípio**                        | **Aplicação prática**                                                                                           |
|--------------------------------------|-----------------------------------------------------------------------------------------------------------------|
| Explicitness over magic              | Fluxos críticos ficam visíveis em Commands, Policies, Jobs, Operations e Reconcilers; evitar callbacks ocultos. |
| Smallest complete solution           | Implementar o menor design completo que satisfaz a Story; não implementar histórias futuras por antecipação.    |
| Server-enforced invariants           | Autorização, unicidade, integridade e limites críticos não dependem apenas da UI.                               |
| Idempotency by design                | Operações reexecutáveis precisam convergir sem duplicar efeitos.                                                |
| Desired State is authoritative       | Reconcilers convergem Actual State; não transformam Docker em fonte primária da configuração.                   |
| Observability is part of the feature | Operações relevantes saem com contexto, logs, métricas/audit necessários para operar.                           |
| Secure by default                    | A ausência de configuração explícita não deve abrir acesso, expor segredo ou habilitar privilégio maior.        |
| Reuse before creation                | Procurar, compor ou estender componentes/abstrações existentes antes de criar uma nova.                         |
| Reversible change                    | Mudanças de código, schema e rollout devem privilegiar rollback e expand-contract.                              |
| Evidence over confidence             | DONE depende de checks executados e evidências; não de “parece correto”.                                        |

# 3. Processo padrão de desenvolvimento

## 3.1 Fluxo normativo

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Story READY<br />
↓<br />
Branch / Worktree → Read scope + references → Plan (quando necessário)<br />
↓<br />
Implement smallest complete change → Local Quality Gate → Automated Review<br />
↓<br />
PRE-COMMIT GATE → Commit → POST-COMMIT GATE<br />
↓<br />
PR / CI GATE → MERGE GATE → Story DONE</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 3.2 Antes de alterar código

1\. Ler a Story inteira e identificar acceptance criteria, arquivos/referências e restrições.

2\. Inspecionar implementação existente e procurar componentes, helpers, queries, policies e padrões já usados.

3\. Confirmar se a mudança é local ou exige plano explícito.

4\. Identificar migration, autorização, concorrência, observabilidade e rollback quando aplicáveis.

5\. Não escrever código enquanto existir conflito material entre Story e arquitetura.

## 3.3 Durante a implementação

• Manter a mudança dentro do escopo da Story.

• Adicionar testes junto com o comportamento, não depois como etapa opcional.

• Evitar “limpar o bairro” se isso ampliar risco ou diff sem necessidade.

• Atualizar documentação/ADR somente quando a mudança altera contrato, decisão ou operação.

• Não esconder falhas com rescue genérico, retries infinitos, timeouts excessivos ou skips permanentes.

# 4. Boundaries e padrões no backend

## 4.1 Papéis principais

| **Tipo**           | **Responsabilidade**                                                                                             | **Não deve fazer**                                                     |
|--------------------|------------------------------------------------------------------------------------------------------------------|------------------------------------------------------------------------|
| Controller         | Receber request, autenticar contexto, validar/serializar entrada, chamar Application Layer, renderizar resposta. | Regra de negócio complexa, Docker, SQL ad hoc espalhado.               |
| Command / Use Case | Mutação de negócio explícita e orquestração transacional.                                                        | Renderização HTTP, conhecimento de UI.                                 |
| Query              | Leitura otimizada e composição de read models.                                                                   | Mutar domínio.                                                         |
| Policy             | Autorização server-side contextual.                                                                              | Executar a operação.                                                   |
| Model              | Invariantes locais, relacionamentos e comportamento intrínseco pequeno.                                          | Orquestração cross-domain ou side effects críticos escondidos.         |
| Job                | Execução assíncrona, retry policy e handoff para Application Layer.                                              | Duplicar regra de negócio do Command.                                  |
| Reconciler         | Comparar Desired x Actual e convergir de modo idempotente.                                                       | Modificar intenção do usuário/Desired State.                           |
| Provider Adapter   | Isolar APIs externas e normalizar erros/contratos.                                                               | Vazar SDK específico para o domínio.                                   |
| Swarm Executor     | Único boundary privilegiado para Docker API.                                                                     | Decidir autorização de produto ou receber request público diretamente. |

## 4.2 Active Record e callbacks

Callbacks de Active Record podem ser usados para comportamento local, determinístico e sem efeitos externos. Não devem ser usados para disparar deploy, enviar webhook, criar Operation, alterar Swarm, publicar evento externo ou executar fluxos que precisam de retry/auditoria explícitos.

| **Aceitável**                                  | **Evitar / proibido**                                              |
|------------------------------------------------|--------------------------------------------------------------------|
| Normalização local simples antes de validação. | after_commit que dispara deploy/reconcile sem Operation explícita. |
| Validação intrínseca da entidade.              | Callback que chama provider externo.                               |
| Relacionamentos e scopes simples.              | Cascade de regra de negócio difícil de rastrear.                   |

# 5. Design patterns: quando usar e quando não usar

| **Pattern**       | **Use quando**                                                                          | **Não use quando**                                                         |
|-------------------|-----------------------------------------------------------------------------------------|----------------------------------------------------------------------------|
| Command           | Existe uma mutação de negócio com autorização, transação, audit ou efeitos coordenados. | É apenas um setter trivial sem regra.                                      |
| Strategy          | Há duas ou mais estratégias intercambiáveis reais sob o mesmo contrato.                 | Só existe uma implementação e nenhuma variação concreta prevista na Story. |
| Adapter           | Integração com Docker, DNS, LB, Registry, Git, storage ou serviço externo.              | Para envolver uma chamada interna simples sem boundary externo.            |
| Factory           | A criação varia por tipo/provider e essa escolha é parte do domínio.                    | Para esconder um construtor simples.                                       |
| State Machine     | Estados/transições são explícitos e transições inválidas importam.                      | Para booleanos simples.                                                    |
| Outbox            | Efeito/evento precisa ser atômico com commit de banco e publicado depois.               | Para chamada síncrona local sem requisito de durabilidade.                 |
| Idempotency Key   | Request/operation pode ser repetida pelo cliente ou retry.                              | Em leitura pura.                                                           |
| Lease + Fencing   | Múltiplos workers podem competir por trabalho exclusivo e lock expirável.               | Quando transação/unique constraint resolve.                                |
| Circuit Breaker   | Provider externo degradado causa avalanche de chamadas/falhas.                          | Antes de medir ou quando timeout/retry limitado resolve.                   |
| Repository custom | Persistência precisa realmente ser isolada por boundary/algoritmo complexo.             | Repository genérico CRUD sobre Active Record.                              |

## 5.1 Regra anti-abstração especulativa

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th><p><strong>YAGNI normativo</strong></p>
<p>Não criar interface para uma única classe, factory sem múltiplas estratégias, generic repository, event bus global, plugin point ou camada adicional somente porque “pode ser útil no futuro”. A abstração entra quando existe pressão concreta da Story ou duas implementações reais que justifiquem o contrato.</p></th>
</tr>
</thead>
<tbody>
</tbody>
</table>

# 6. Frontend: reutilização, design system e composição

## 6.1 Hierarquia de componentes

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>app/frontend/<br />
components/<br />
ui/ # primitives: Button, Input, Dialog, Tabs...<br />
shared/ # componentes compostos reutilizados por múltiplas features<br />
features/ # componentes de um domínio específico<br />
layouts/ # shells, navigation, page layouts<br />
pages/ # páginas Inertia / entry points<br />
hooks/<br />
lib/<br />
types/</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

O caminho exato pode variar, mas as quatro categorias devem continuar visíveis. Componentes existentes em React têm prioridade sobre reimplementação em outra tecnologia apenas por preferência do agente.

## 6.2 Regra antes de criar um componente

1\. Pesquisar por nome, responsabilidade, aparência e uso equivalente.

2\. Verificar se um primitive existente resolve por composição.

3\. Verificar se uma variante/prop pequena resolve sem transformar o componente em “god component”.

4\. Verificar se o comportamento é realmente compartilhado ou feature-specific.

5\. Criar novo componente somente quando as alternativas acima não atendem de forma clara.

## 6.3 Reuse Gate

| **Pergunta**                              | **Se SIM**                                | **Se NÃO**                   |
|-------------------------------------------|-------------------------------------------|------------------------------|
| Existe componente equivalente?            | Reusar; não duplicar.                     | Continuar análise.           |
| Existe primitive/composição que resolve?  | Compor.                                   | Continuar análise.           |
| Uma variante pequena mantém coesão?       | Adicionar variante testada.               | Criar componente específico. |
| O componente aparece em 2+ features?      | Avaliar mover para shared.                | Manter na feature.           |
| Novo componente replica visual existente? | Bloquear review até justificar diferença. | Aceitável.                   |

## 6.4 Estado e dados

• Preferir props server-driven e estado local de UI quando suficiente.

• Não introduzir store global para estado que pertence a uma página/feature.

• Separar estado remoto do Control Plane de estado puramente visual.

• Não duplicar server state em múltiplas caches sem estratégia explícita.

• Realtime deve atualizar read models/props de forma previsível; não criar uma segunda fonte de verdade no browser.

# 7. Padrões de código e legibilidade

## 7.1 Regras gerais

• Nomes descrevem intenção de negócio; evitar abbreviations obscuras.

• Métodos/funções devem ter uma responsabilidade coerente e tamanho suficiente para serem compreendidos sem esconder fluxo em dezenas de wrappers.

• Comentários explicam “por quê”, invariantes ou trade-offs; não narram código óbvio.

• TODO/FIXME exige referência a Story/issue e não pode esconder requisito crítico.

• Erros devem ser tipados/classificados quando isso altera retry, status ou resposta ao cliente.

• Nunca capturar Exception/StandardError genericamente e retornar sucesso.

## 7.2 Complexidade

Complexidade não deve ser reduzida por métricas cegas através de fragmentação artificial. O gate procura decisões demais, nesting profundo, duplicação de fluxo e objetos que acumulam responsabilidades. Quando um método exige múltiplas condições de domínio, considerar extrair um Command/Strategy/Policy somente se a extração melhorar o modelo, não apenas a contagem de linhas.

# 8. Banco de dados e migrations

## 8.1 Regras obrigatórias

• Integridade crítica deve existir no PostgreSQL: FK, NOT NULL, CHECK e UNIQUE quando apropriado.

• Toda query operacional frequente precisa ter estratégia de índice conhecida e verificável.

• Constraints de autorização/ownership não devem existir somente no frontend.

• JSONB é usado para metadados/extensibilidade controlada, não como substituto de modelagem relacional crítica.

• Operações concorrentes usam transaction/locking/unique constraint/lease conforme o problema real.

• Evitar N+1 e carregar coleções não limitadas em requests interativos.

• Mudanças destrutivas de schema seguem expand-contract e são separadas do deploy que ainda depende da coluna antiga.

## 8.2 Migration Gate

| **Check**                                                          | **Obrigatório**                                          |
|--------------------------------------------------------------------|----------------------------------------------------------|
| É backward compatible com a versão anterior durante rollout?       | Sim, salvo janela de manutenção explicitamente aprovada. |
| Possui rollback ou plano de forward-fix documentado?               | Sim.                                                     |
| CREATE INDEX potencialmente pesado foi avaliado para produção?     | Sim.                                                     |
| Backfill está desacoplado de request/deploy quando o volume exige? | Sim.                                                     |
| DROP/rename destrutivo ocorre só após fase contract?               | Sim.                                                     |

# 9. APIs, Commands, Events e contratos

## 9.1 API

• Contratos externos são versionados e compatíveis dentro da política definida na Parte 9.

• Mutação assíncrona retorna/expõe operationId quando o trabalho não termina no request.

• Idempotency-Key é exigida/aceita nas operações definidas como repetíveis.

• Erros seguem envelope e códigos estáveis; mensagem humana não é o único identificador.

• Request ID e correlation/operation ID percorrem os boundaries necessários.

• Paginação é obrigatória em coleções potencialmente grandes.

## 9.2 Eventos

• Evento representa algo que ocorreu, não uma intenção disfarçada.

• Payload contém versionamento e IDs necessários para correlação.

• Consumidor deve tolerar redelivery quando o canal não garante exactly-once.

• Mudança de schema de evento segue compatibilidade explícita; não quebrar consumidores silenciosamente.

# 10. Dependências e supply chain

## 10.1 Dependency Gate

| **Critério** | **Pergunta obrigatória**                                                     |
|--------------|------------------------------------------------------------------------------|
| Necessidade  | Existe problema real da Story que justifica a dependência?                   |
| Alternativa  | Stack padrão ou biblioteca já instalada resolve suficientemente?             |
| Manutenção   | Projeto está mantido e possui release/security posture aceitável?            |
| Escopo       | A dependência é proporcional ao problema ou adiciona uma plataforma inteira? |
| Licença      | É compatível com a distribuição pretendida?                                  |
| Segurança    | Possui vulnerabilidades conhecidas críticas/altas sem mitigação?             |
| Lockfile     | Versão efetiva está registrada/reprodutível?                                 |

Toda nova dependência relevante deve aparecer no Story Report/PR com uma justificativa curta. Agentes não podem adicionar packages “por conveniência” sem verificar primeiro o que já existe.

# 11. Quality Gate local

## 11.1 O que deve rodar antes de declarar implementação pronta

| **Classe**       | **Gate mínimo**                                                           |
|------------------|---------------------------------------------------------------------------|
| Ruby/Rails       | formatter/lint + testes relacionados + checks de segurança aplicáveis.    |
| React/TypeScript | format/lint + typecheck + testes de componente/feature aplicáveis.        |
| Database         | migration validation + testes de integração + query/constraint relevante. |
| Infrastructure   | config validation + tests/fixtures/lab definidos para o recurso.          |
| Contracts        | contract/schema tests quando endpoint/event/provider mudou.               |

Ferramentas concretas podem ser congeladas no Implementation Pack. Exemplos compatíveis com a stack são RuboCop, Brakeman, bundler-audit, TypeScript typecheck e o lint/formatter adotado pelo frontend. A semântica do gate é normativa mesmo se a ferramenta mudar.

# 12. Pre-commit Gate

## 12.1 Objetivo

O pre-commit deve ser rápido o suficiente para rodar em toda Story e barato o suficiente para não incentivar bypass. Ele captura defeitos locais antes que o commit vire checkpoint do Autonomous Loop.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>PRE-COMMIT GATE<br />
<br />
[ ] format dos arquivos alterados<br />
[ ] lint dos arquivos alterados / módulos afetados<br />
[ ] typecheck incremental ou relevante<br />
[ ] testes rápidos relacionados<br />
[ ] secret scan<br />
[ ] nenhuma migration obviamente inválida<br />
[ ] nenhum arquivo gerado/temporário indevido<br />
[ ] diff dentro do escopo esperado<br />
<br />
FAIL =&gt; não commitar</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 12.2 Regras

• Hook local ajuda, mas CI repete checks críticos; hook local não é a única defesa.

• Não usar --no-verify automaticamente.

• Bypass manual exige motivo e o gate deve rodar antes do merge.

• Agente autônomo não possui permissão para desabilitar hooks para “destravar” a Story.

# 13. Commit policy

## 13.1 Unidade de commit

O commit é um checkpoint coerente e reversível. Uma Story pode ter um ou poucos commits, mas cada commit deve representar uma mudança compreensível. Não acumular múltiplas Stories independentes em um único commit.

| **Bom**                                                  | **Ruim**               |
|----------------------------------------------------------|------------------------|
| feat(service): persist desired state                     | feat: platform changes |
| feat(reconcile): create swarm service from desired state | fix stuff              |
| test(vault): cover version pin rollback                  | WIP final              |

## 13.2 Conteúdo proibido

• Secrets, tokens, chaves privadas, dumps ou fixtures com dados reais.

• Artefatos temporários, logs locais e binários não versionados intencionalmente.

• Mudanças fora de escopo sem explicação.

• Código comentado morto como mecanismo de backup.

# 14. Post-commit Gate

## 14.1 Por que existe

No Autonomous Development Loop, “commit criado” não significa “Story segura para ser marcada DONE”. O post-commit valida o checkpoint já gravado e impede que o agente avance carregando defeitos de uma Story para a seguinte.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>COMMIT<br />
|<br />
v<br />
POST-COMMIT GATE<br />
|<br />
+--&gt; Story acceptance criteria reconciliados<br />
+--&gt; module tests green<br />
+--&gt; automated diff review<br />
+--&gt; zero Critical / High<br />
+--&gt; architecture fitness checks<br />
+--&gt; no out-of-scope files<br />
+--&gt; tasks.json / report consistent<br />
|<br />
PASS ----&gt; Story DONE ----&gt; next Story<br />
FAIL ----&gt; fix ----&gt; new commit/fixup ----&gt; revalidate</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 14.2 Checks obrigatórios

| **Check**              | **Resultado esperado**                                   |
|------------------------|----------------------------------------------------------|
| git show / diff review | Mudanças correspondem à Story; sem surpresa.             |
| Acceptance mapping     | Cada critério aponta para implementação/teste/evidência. |
| Reviewer Agent         | Critical=0, High=0; Medium tratado conforme policy.      |
| Fitness Functions      | Todos os invariantes arquiteturais automatizados passam. |
| Tests                  | Suíte definida para a Story termina green.               |
| State                  | tasks.json, Story Report e commit hash coerentes.        |

# 15. Pull Request e CI Gate

## 15.1 PR Gate

| **Gate**         | **Exigência**                                                |
|------------------|--------------------------------------------------------------|
| Build            | Reprodutível e green.                                        |
| Lint/Format      | Zero erro.                                                   |
| Type safety      | Zero erro do typecheck definido.                             |
| Unit/Integration | Green.                                                       |
| Contract         | Green quando contratos mudam.                                |
| Security         | Sem Critical/High novo não aprovado.                         |
| Migration        | Checks de compatibilidade e estratégia de rollout aprovados. |
| Architecture     | Fitness Functions green.                                     |
| Acceptance       | Critérios da Story/Milestone cobertos.                       |
| Review           | Reviewer humano ou agent review conforme risco.              |

## 15.2 Merge Gate

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>MERGE ALLOWED ONLY IF<br />
<br />
[ ] branch base atualizada conforme política<br />
[ ] CI green<br />
[ ] Critical = 0<br />
[ ] High = 0<br />
[ ] migration rollout seguro<br />
[ ] rollback / forward-fix conhecido<br />
[ ] Story / Milestone status consistente<br />
[ ] documentação/ADR atualizada se contrato mudou<br />
[ ] required approvals satisfeitos</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

# 16. Architecture Fitness Functions

## 16.1 Objetivo

Fitness Functions transformam regras documentais em propriedades automaticamente verificáveis. Elas devem crescer à medida que o sistema amadurece, especialmente para impedir que loops autônomos corroam boundaries ao longo de centenas de Stories.

## 16.2 Fitness Functions iniciais

| **ID** | **Regra automatizável**                                                                   |
|--------|-------------------------------------------------------------------------------------------|
| AF-01  | Controllers públicos não importam cliente Docker/Bollard/socket adapter.                  |
| AF-02  | Somente o módulo Swarm Executor referencia docker.sock/Docker Engine client privilegiado. |
| AF-03  | Reconcilers não escrevem colunas de Desired State definidas como intenção do usuário.     |
| AF-04  | UI/React não importa código de banco, Docker ou infraestrutura server-only.               |
| AF-05  | MCP adapter não chama Swarm Executor diretamente; passa pela Application Layer/Commands.  |
| AF-06  | Secret plaintext não aparece em serializers, logs ou audit payloads.                      |
| AF-07  | Mutations críticas possuem Policy/authorization path server-side.                         |
| AF-08  | Events/Operations possuem correlation/operation identifiers.                              |
| AF-09  | Migrations destrutivas conhecidas exigem marker/ADR de fase contract.                     |
| AF-10  | Feature React não duplica primitive com mesmo contrato/nome visual sem waiver.            |

## 16.3 Waivers

Uma Fitness Function só pode ser ignorada através de waiver explícito, versionado e temporário, contendo motivo, owner e prazo/Story de remoção. O agente não pode editar o checker para fazer a Story passar sem uma decisão aprovada.

# 17. Automated Code Review

## 17.1 Checklist do Reviewer Agent

| **Dimensão**    | **Perguntas**                                                           |
|-----------------|-------------------------------------------------------------------------|
| Correção        | Comportamento atende a Story? Edge cases relevantes foram considerados? |
| Escopo          | Mudou somente o necessário? Implementou Story futura?                   |
| Arquitetura     | Respeita boundaries, Desired/Actual State e contratos?                  |
| Simplicidade    | Há abstração, camada ou dependency desnecessária?                       |
| Reuso           | Reaproveitou componentes/helpers existentes antes de criar novos?       |
| Segurança       | Authorization, secrets, SSRF, exec, input e privileges estão corretos?  |
| Concorrência    | Retries, idempotência, locks e races foram tratados onde necessário?    |
| Dados           | Constraints, índices, transações e migrations estão seguros?            |
| Observabilidade | É possível diagnosticar falha sem reproduzir localmente?                |
| Testes          | Os testes validam comportamento e falhas, ou apenas execução feliz?     |
| Operação        | Rollback/reconcile/retry continuam previsíveis?                         |

## 17.2 Severidades

| **Severidade** | **Exemplo**                                                                         | **Policy**                                 |
|----------------|-------------------------------------------------------------------------------------|--------------------------------------------|
| Critical       | Bypass de autorização, secret leak, perda de dados, acesso docker.sock indevido.    | Bloqueia commit/DONE/merge.                |
| High           | Race com efeito real, migration insegura, idempotência ausente em operação crítica. | Bloqueia DONE/merge.                       |
| Medium         | Design frágil, duplicação importante, observabilidade insuficiente.                 | Corrigir ou registrar waiver/Story.        |
| Low            | Naming, pequena simplificação, polish não funcional.                                | Pode virar follow-up se não acumular debt. |

# 18. Refatoração e dívida técnica

## 18.1 Três classes de refatoração

| **Classe**    | **Definição**                                                          | **Tratamento**                                      |
|---------------|------------------------------------------------------------------------|-----------------------------------------------------|
| Required      | Sem ela a Story não pode ser implementada corretamente/seguramente.    | Pode fazer dentro da Story; justificar no report.   |
| Opportunistic | Pequena, local, baixo risco e reduz complexidade imediatamente tocada. | Permitida se diff continua pequeno e testes cobrem. |
| Strategic     | Reestrutura módulo, boundary, dados ou abstrações de modo amplo.       | Criar Story/ADR próprio; não esconder na feature.   |

## 18.2 Tech debt registry

Dívida identificada mas não necessária para a Story deve ser registrada em backlog estruturado com impacto e evidência. Não usar TODO indefinido como substituto de backlog. O Autonomous Loop pode abrir a dívida, mas não deve iniciar sua implementação sem ela entrar no Milestone ou receber autorização.

# 19. Segurança, observabilidade e performance como gates

## 19.1 Segurança

• Nenhum segredo em log, exception payload, analytics ou snapshot de teste.

• Authorization test para cada nova mutação/escopo de recurso.

• Security scanners definidos no Anexo C e D fazem parte do CI conforme frequência.

• Ações privilegiadas exigem audit e contexto do ator/origem.

• Shell/exec e networking externo respeitam allowlists/policies do Threat Model.

## 19.2 Observabilidade mínima por operação

| **Campo**                   | **Uso**                               |
|-----------------------------|---------------------------------------|
| request_id                  | Correlação HTTP/UI/API.               |
| operation_id                | Lifecycle de mutações assíncronas.    |
| team_id                     | Boundary/tenant.                      |
| project_id / environment_id | Contexto do recurso quando aplicável. |
| service_id                  | Runtime/deploy/logs quando aplicável. |
| cluster_id / node_id        | Infra quando aplicável.               |
| actor_id / source           | Humano, MCP, CLI, system/reconciler.  |

## 19.3 Performance

Optimization não entra por intuição. Regressões em paths críticos precisam de benchmark/load evidence quando a Story toca query, loop de reconciliation, logs streaming, listagens grandes ou chamadas externas em massa. N+1, consultas sem paginação e polling agressivo são defects de qualidade, não “otimização futura”.

# 20. Política de reutilização além da UI

## 20.1 Backend e infraestrutura

• Antes de criar novo client/provider, verificar Adapter existente e capacidade de extensão coerente.

• Antes de criar novo retry helper, usar política comum de retries/timeouts.

• Antes de criar novo error envelope, usar taxonomy compartilhada.

• Antes de criar nova state machine, verificar se pertence a uma máquina existente ou se é um lifecycle independente.

• Não unificar duas coisas apenas porque parecem parecidas; reuse exige semântica compatível, não só código semelhante.

## 20.2 Regra de duplicação

Duplicação pequena pode ser preferível a uma abstração incorreta. O reviewer deve diferenciar duplicação acidental de dois conceitos distintos. Extrair apenas quando a abstração tem nome e responsabilidade claros e reduz custo real de manutenção.

# 21. Integração com o Autonomous Development Loop

## 21.1 Gates por estado da Story

| **Transição**              | **Gate necessário**                                        |
|----------------------------|------------------------------------------------------------|
| READY -\> IN_PROGRESS      | Story tem referências e critérios claros; workspace limpo. |
| IN_PROGRESS -\> REVIEW     | Local Quality Gate green.                                  |
| REVIEW -\> COMMIT_READY    | Critical/High zerados; acceptance mapping completo.        |
| COMMIT_READY -\> COMMITTED | Pre-commit green.                                          |
| COMMITTED -\> DONE         | Post-commit green + commit hash registrado.                |
| DONE -\> próxima Story     | tasks.json consistente e nenhum blocker herdado.           |

## 21.2 Regra para agentes

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th><p><strong>Sem manipular o gate</strong></p>
<p>Builder/Reviewer Agents podem corrigir código para satisfazer um gate; não podem silenciar teste, afrouxar threshold, alterar checker, desativar lint/security rule ou remover acceptance criterion apenas para obter green. Mudanças nos gates exigem Story/ADR próprio.</p></th>
</tr>
</thead>
<tbody>
</tbody>
</table>

# 22. Quality dashboard e métricas de engenharia

## 22.1 Métricas recomendadas

| **Métrica**                      | **Interpretação**                                                   |
|----------------------------------|---------------------------------------------------------------------|
| First-pass gate rate             | Percentual de Stories que passam review/gates sem ciclo extra.      |
| Escaped defects                  | Defeitos encontrados depois do merge/release.                       |
| Rework per Story                 | Commits/ciclos extras causados por erro de implementação vs polish. |
| Flaky test rate                  | Sinal de perda de confiança no pipeline.                            |
| Critical/High review findings    | Qualidade/riscos antes do merge.                                    |
| Dependency growth                | Detecta expansão de stack sem controle.                             |
| Component reuse ratio            | Novas telas construídas reutilizando primitives/shared existentes.  |
| Architecture waiver count        | Dívida explícita contra Fitness Functions.                          |
| Migration rollback/incident rate | Saúde da política expand-contract.                                  |

Métricas não viram targets cegos. Elas servem para detectar tendências e ajustar rules/gates. Cobertura de testes, por exemplo, não substitui testes de comportamento importantes.

# 23. Templates operacionais

## 23.1 Checklist de implementação

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>IMPLEMENTATION CHECKLIST<br />
<br />
[ ] Story lida e escopo confirmado<br />
[ ] componentes/abstrações existentes pesquisados<br />
[ ] autorização considerada<br />
[ ] dados/transaction/concurrency considerados<br />
[ ] observabilidade considerada<br />
[ ] testes adicionados/ajustados<br />
[ ] nenhuma dependência desnecessária<br />
[ ] nenhuma abstração especulativa<br />
[ ] Local Quality Gate green<br />
[ ] Reviewer Agent green<br />
[ ] Pre-commit Gate green</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 23.2 Checklist pós-commit

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>POST-COMMIT CHECKLIST<br />
<br />
[ ] commit representa mudança coerente<br />
[ ] diff final está dentro do escopo<br />
[ ] acceptance criteria mapeados<br />
[ ] module tests green<br />
[ ] fitness functions green<br />
[ ] Critical = 0 / High = 0<br />
[ ] Story Report atualizado<br />
[ ] tasks.json contém commit hash/status correto<br />
[ ] nenhuma pendência escondida em TODO/FIXME</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 23.3 Justificativa de nova dependência

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Dependency: &lt;nome&gt;<br />
Story: &lt;id&gt;<br />
Problema resolvido: &lt;1-2 linhas&gt;<br />
Alternativas avaliadas: &lt;stack existente / outras&gt;<br />
Por que não bastam: &lt;curto&gt;<br />
Maintenance/security/license: &lt;resultado&gt;<br />
Impacto de longo prazo: &lt;baixo/médio/alto&gt;</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

# 24. Rollout do playbook

| **Fase**           | **Aplicação**                                                                  |
|--------------------|--------------------------------------------------------------------------------|
| P0 - Bootstrap     | Criar scripts/gates básicos, lint/format, secret scan, templates e convenções. |
| P1 - M00/M01       | Aplicar Pre/Post Commit e Reviewer Agent em todas as Stories.                  |
| P2 - Core maduro   | Adicionar Fitness Functions AF-01..AF-10 e dependency/migration gates.         |
| P3 - Autonomous L2 | Stop Gate do Anexo H exige os gates deste playbook antes de MILESTONE READY.   |
| P4 - Production    | Quality dashboard, waivers auditáveis e regressão periódica do playbook.       |

# 25. Critérios de aceite do Engineering Playbook

| **\#** | **Critério**                                                                                                       |
|--------|--------------------------------------------------------------------------------------------------------------------|
| 1      | Existe uma regra canônica de precedência para arquitetura, Story e playbook.                                       |
| 2      | Backend possui boundaries explícitos para Controller, Command, Query, Policy, Job, Reconciler, Adapter e Executor. |
| 3      | Callbacks críticos/side effects ocultos são proibidos por regra.                                                   |
| 4      | Design patterns possuem critérios de uso e anti-pattern correspondente.                                            |
| 5      | UI React possui hierarquia e Reuse Gate antes de novos componentes.                                                |
| 6      | Migrations seguem expand-contract e possuem Migration Gate.                                                        |
| 7      | Novas dependências passam por Dependency Gate e justificativa.                                                     |
| 8      | Existe Local Quality Gate mínimo por classe de mudança.                                                            |
| 9      | Pre-commit Gate é executável e não pode ser bypassado automaticamente pelo agente.                                 |
| 10     | Cada commit passa por Post-commit Gate antes da Story virar DONE.                                                  |
| 11     | PR e Merge Gates estão definidos com critérios objetivos.                                                          |
| 12     | Fitness Functions iniciais protegem boundaries críticos da plataforma.                                             |
| 13     | Waivers de arquitetura são explícitos, versionados e temporários.                                                  |
| 14     | Reviewer Agent usa checklist de correção, escopo, arquitetura, segurança, reuso e operação.                        |
| 15     | Critical e High bloqueiam DONE/merge.                                                                              |
| 16     | Refatoração Strategic não entra escondida em feature Story.                                                        |
| 17     | Security, observability e performance fazem parte da qualidade da feature.                                         |
| 18     | Builder Agent não pode alterar gates/checkers para fazer a Story passar.                                           |
| 19     | Autonomous Loop integra gates às transições da state machine da Story.                                             |
| 20     | Métricas de qualidade são usadas para tendência, não para gaming.                                                  |
| 21     | Templates de implementação, post-commit e dependências ficam disponíveis no repositório.                           |
| 22     | O playbook é aplicado já no M00/M01, antes de escalar autonomia.                                                   |

# 26. Decisões finais

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th><p><strong>D1 - Qualidade é um sistema</strong></p>
<p>A qualidade do projeto será governada por processo + boundaries + testes + gates + review + fitness functions. Nenhum mecanismo isolado é suficiente.</p></th>
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
<th><p><strong>D2 - Reuso é obrigatório antes de criação</strong></p>
<p>Todo agente deve pesquisar o que já existe antes de introduzir componente, helper, abstraction ou dependency nova.</p></th>
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
<th><p><strong>D3 - Gates não são editáveis pela Story</strong></p>
<p>Falhar um gate significa corrigir implementação ou abrir decisão específica; não reduzir o gate para obter green.</p></th>
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
<th><p><strong>D4 - Simplicidade é requisito</strong></p>
<p>O menor design completo que respeita a arquitetura é preferível a extensibilidade especulativa.</p></th>
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
<th><p><strong>D5 - Post-commit faz parte do loop</strong></p>
<p>Uma Story só vira DONE depois que o checkpoint commitado foi revalidado, revisado e associado às evidências de aceite.</p></th>
</tr>
</thead>
<tbody>
</tbody>
</table>
