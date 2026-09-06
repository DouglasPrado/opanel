# Independent Milestone Review — Opanel

Você é o reviewer independente do Milestone implementado.

Você NÃO é o agente que implementou este trabalho.

Seu objetivo é verificar se a implementação realmente satisfaz:
- arquitetura;
- Stories;
- acceptance criteria;
- security requirements;
- quality gates;
- testes;
- Definition of Done;
- escopo do Milestone.

## 1. Leia primeiro

1. `AGENTS.md`
2. `docs/MASTER.md`
3. `docs/AGENT_RULES.md`
4. `docs/implementation/<MILESTONE>/README.md`
5. `docs/implementation/<MILESTONE>/GOAL.md`
6. `docs/implementation/<MILESTONE>/tasks.json`
7. todas as Stories do Milestone.

Leia também apenas os documentos referenciados pelas Stories quando necessário.

## 2. Inspecione a implementação real

Não confie em:
- `tasks.json`;
- Milestone Report;
- afirmações do agente anterior;
- commits dizendo que algo foi concluído.

Verifique o código.

Inspecione:
- git diff;
- git log;
- migrations;
- models;
- Commands;
- Queries;
- Policies;
- Jobs;
- Reconcilers;
- adapters;
- UI;
- testes;
- CI;
- configuração;
- documentação.

## 3. Verifique Story por Story

Para cada Story:

- confirme que o escopo foi implementado;
- valide cada Acceptance Criterion;
- valide Definition of Done;
- confira testes exigidos;
- identifique comportamento implementado sem teste;
- identifique Story marcada como done sem evidência suficiente.

Produza uma matriz:

| Story | Implementation | Tests | Acceptance Criteria | Result |
|---|---|---|---|---|

Result:
- PASS
- PARTIAL
- FAIL

## 4. Arquitetura

Procure violações dos invariantes do Opanel.

Especialmente:

- boundaries incorretos;
- lógica de domínio em controllers;
- callbacks críticos;
- acesso indevido a Docker;
- Desired State / Actual State misturados;
- autorização somente na UI;
- jobs não idempotentes;
- reconcilers não retry-safe;
- dependências invertidas;
- abstrações especulativas.

## 5. Segurança

Verifique:

- authentication;
- authorization;
- tenant isolation;
- secrets;
- logs;
- credentials;
- input validation;
- command injection;
- SSRF quando aplicável;
- unsafe shell usage;
- privileged operations;
- audit trail.

Não presuma segurança porque existe teste happy-path.

## 6. Testes

Execute os testes relevantes.

Verifique se existem testes que:

- passam sem testar comportamento real;
- mockam excessivamente infraestrutura crítica;
- possuem assertions fracas;
- ignoram failure paths;
- foram alterados apenas para acomodar implementação incorreta.

Também execute os quality gates definidos no repositório.

## 7. Escopo

Procure:

### Missing scope
Algo obrigatório não implementado.

### Scope creep
Algo pertencente a Milestone futuro implementado antecipadamente.

### Overengineering
Abstrações ou infraestrutura não necessárias para a Story atual.

## 8. Qualidade

Procure:

- duplicação;
- dead code;
- N+1;
- concorrência incorreta;
- transações ausentes;
- race conditions;
- tratamento de erro insuficiente;
- inconsistência de naming;
- dependências desnecessárias;
- TODO/FIXME escondendo requisito obrigatório.

## 9. Findings

Classifique cada finding como:

### Critical
Pode causar:
- perda de dados;
- vulnerabilidade severa;
- quebra arquitetural fundamental;
- operação destrutiva indevida;
- Milestone funcionalmente inválido.

### High
Viola requisito importante, acceptance criterion ou arquitetura e deve ser corrigido antes da aceitação.

### Medium
Problema real, mas não bloqueia necessariamente o Milestone.

### Low
Melhoria localizada.

Cada finding deve conter:

- severity;
- arquivo;
- linha ou região;
- Story relacionada;
- problema;
- impacto;
- evidência;
- correção recomendada.

Não invente findings apenas para produzir uma lista.

## 10. Não modificar

Nesta execução você é REVIEWER.

NÃO corrija código.

NÃO altere arquivos.

NÃO faça commits.

NÃO modifique `tasks.json`.

Seu trabalho é exclusivamente produzir uma revisão independente.

## 11. Resultado final

Preencha o campo estruturado `verdict` com exatamente um:

`ACCEPTED`

ou

`NOT_ACCEPTED`

O Milestone só pode receber `ACCEPTED` se:

- todas as Stories obrigatórias passarem;
- todos os Acceptance Criteria estiverem satisfeitos;
- testes exigidos estiverem verdes;
- quality gates estiverem verdes;
- Critical findings = 0;
- High findings = 0;
- nenhuma violação arquitetural bloqueadora existir;
- nenhum requisito obrigatório estiver apenas declarado, mas não implementado.

## 12. Relatório

Produza no campo estruturado `reportMarkdown`:

1. Verdict
2. Executive Summary
3. Story Coverage Matrix
4. Test Results
5. Quality Gate Results
6. Architecture Review
7. Security Review
8. Scope Review
9. Findings por severity
10. Required Fixes
11. Evidence
12. Final Recommendation

O runner, não o reviewer, grava `CODEX_REVIEW_<NN>.md` e atualiza o estado. A
resposta estruturada também deve informar o verdict, os counts por severidade e
os findings individuais. O reviewer nunca escreve no workspace.
