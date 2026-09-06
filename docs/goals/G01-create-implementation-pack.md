# G01 — Criar Implementation Pack e Milestones do Opanel

## Objetivo

Transformar toda a especificação aprovada do **Opanel** em um Implementation Pack completo, ordenado, rastreável e executável posteriormente por agentes autônomos.

Esta execução é exclusivamente de planejamento.

NÃO implementar código do produto.

NÃO criar migrations reais.

NÃO instalar dependências.

NÃO alterar infraestrutura.

NÃO iniciar M00.

O resultado deste Goal será o plano executável que governará a implementação futura.

---

# 1. Contexto obrigatório

Antes de planejar qualquer Milestone, leia nesta ordem:

1. `CLAUDE.md`
2. `docs/MASTER.md`
3. `docs/AGENT_RULES.md`

Depois leia toda a documentação principal e anexos referenciados por `docs/MASTER.md`.

Dê atenção especial a:

* arquitetura;
* Control Plane;
* modelo de dados;
* UX/UI e Use Cases;
* roadmap;
* NFRs/SLOs;
* Threat Model;
* Test Strategy;
* Runbooks;
* MCP;
* desenvolvimento orientado por agentes;
* Autonomous Development Loop;
* Engineering Playbook e Quality Gates.

Não construa o roadmap usando apenas o antigo Anexo A.

O Implementation Pack deve refletir a especificação consolidada atual.

---

# 2. Decisões atuais

Em caso de documentação antiga conflitante, respeite as decisões atuais registradas em `CLAUDE.md`, `docs/AGENT_RULES.md` e decisões posteriores aprovadas.

O projeto chama-se:

`Opanel`

Stack atual:

Backend:

* Ruby on Rails 8.1.x
* PostgreSQL
* Solid Queue

Frontend:

* React
* TypeScript
* Inertia.js
* Vite
* Tailwind
* componentes React existentes devem ser reutilizados

Não planejar Next.js como frontend principal.

Infraestrutura principal:

* Docker Engine
* Docker Swarm
* Traefik
* Railpack
* BuildKit
* OCI Registry

Preservar os invariantes arquiteturais definidos nas regras do projeto.

---

# 3. Estrutura a ser criada

Criar:

```text
docs/implementation/
├── README.md
├── ROADMAP.md
├── DEPENDENCIES.md
├── COVERAGE.md
├── SPEC_CONFLICTS.md
│
├── M00/
│   ├── README.md
│   ├── GOAL.md
│   ├── tasks.json
│   └── stories/
│
├── M01/
│   ├── README.md
│   ├── GOAL.md
│   ├── tasks.json
│   └── stories/
│
└── MXX/
```

Determine a quantidade necessária de Milestones a partir da especificação.

Não existe obrigação de manter a quantidade definida em roadmaps antigos caso uma decomposição melhor seja encontrada.

---

# 4. Filosofia dos Milestones

Cada Milestone deve representar uma capacidade significativa, demonstrável e testável.

Prefira vertical slices.

Um Milestone deve produzir um resultado observável.

Evite Milestones que sejam apenas:

* camada de banco;
* camada de controllers;
* refatoração;
* infraestrutura isolada sem resultado verificável.

Exceção: `M00 — Foundation`, cuja finalidade é preparar a base de engenharia.

---

# 5. M00 obrigatório — Foundation

M00 deve preparar o repositório para desenvolvimento real.

Considere:

* Rails 8.1.x;
* PostgreSQL;
* Solid Queue;
* Inertia;
* React;
* TypeScript;
* Vite;
* Tailwind;
* integração/reuso dos componentes existentes;
* ambiente local;
* testes;
* lint;
* formatter;
* security scans;
* CI;
* quality gates;
* architecture fitness functions iniciais;
* hooks do Autonomous Development Loop;
* infraestrutura de evidence/report;
* configuração necessária para desenvolvimento por agentes.

M00 NÃO deve implementar funcionalidades reais do domínio do Opanel.

---

# 6. M01 obrigatório — First Vertical Slice

M01 deve validar a espinha dorsal da arquitetura utilizando uma OCI Image já existente.

O resultado deve cobrir aproximadamente:

```text
Authentication
      ↓
Team
      ↓
Project
      ↓
Cluster
      ↓
Environment
      ↓
Service
      ↓
Desired State
      ↓
Operation
      ↓
Swarm Executor
      ↓
Docker Swarm Service
      ↓
Actual State
      ↓
Healthy
      ↓
Logs
      ↓
Scale 1 → 3
      ↓
3/3 Healthy
```

M01 deve provar que o Control Plane consegue administrar um workload real no Swarm.

Não introduzir Git/Railpack/BuildKit antes desse fluxo, salvo dependência técnica inevitável e documentada.

---

# 7. Milestones seguintes

Derive a sequência restante a partir das dependências reais.

A especificação deverá eventualmente cobrir capacidades como:

* Git integrations;
* SourceConnection;
* webhooks;
* Railpack;
* BuildKit;
* Registry;
* Build;
* Artifact;
* Release;
* Deployment;
* rollback;
* promotion entre environments;
* Traefik;
* networking;
* default domains;
* custom domains;
* DNS providers;
* Certificate Manager;
* TLS;
* Vault;
* SecretVersion;
* secret bindings;
* Swarm Secrets;
* cluster enrollment;
* Workers;
* Managers;
* Ingress nodes;
* Builders;
* expansão de cluster;
* HA;
* Load Balancer;
* logs históricos;
* metrics;
* observability;
* alerts;
* incidents;
* autoscaling;
* backups;
* snapshots;
* restore;
* Disaster Recovery;
* RBAC completo;
* Instance Admin;
* providers;
* audit;
* Operations Center;
* MCP;
* agent connections;
* approvals;
* security hardening;
* performance validation;
* Production Readiness.

Essa lista NÃO define a ordem.

Determine a ordem através das dependências arquiteturais e de produto.

---

# 8. README de cada Milestone

Cada `MXX/README.md` deve conter:

## Identity

* ID;
* nome;
* objetivo;
* resultado observável.

## Why

Explique por que este Milestone existe e o que desbloqueia.

## Scope

Capacidades incluídas.

## Out of Scope

Capacidades explicitamente deixadas para Milestones futuros.

## Dependencies

Diferencie:

* hard dependencies;
* soft dependencies.

## User-visible Outcome

Explique o que usuário ou operador será capaz de fazer.

## Technical Outcome

Explique o que passa a existir internamente.

## Architecture Impact

Liste quando aplicável:

* entities;
* modules;
* Commands;
* Queries;
* Events;
* Jobs;
* Operations;
* Reconcilers;
* Providers;
* UI;
* infrastructure.

## Security

Liste controles relevantes.

## Observability

Defina sinais mínimos necessários.

## Testing

Defina classes de testes exigidas.

## Acceptance Criteria

Critérios objetivos.

## Exit Gate

Defina exatamente quando o Milestone pode assumir:

`READY_FOR_HUMAN_ACCEPTANCE`

---

# 9. GOAL.md de cada Milestone

Cada Milestone deve possuir um `GOAL.md` pronto para execução futura via Claude Code `/goal`.

O Goal deve ser específico daquele Milestone e estabelecer condições verificáveis.

Exemplo conceitual:

```text
MXX está concluído quando:

- todas as Stories obrigatórias estão done;
- acceptance criteria estão satisfeitos;
- testes obrigatórios estão green;
- quality gates estão green;
- architecture fitness functions estão green;
- Critical findings = 0;
- High findings = 0;
- nenhuma Story obrigatória está blocked;
- documentação necessária foi atualizada;
- milestone report foi produzido;
- resultado funcional pode ser demonstrado.
```

Adapte ao Milestone.

---

# 10. tasks.json

Cada Milestone deve possuir um estado persistente para o Autonomous Development Loop.

Formato base:

```json
{
  "milestone": "M01",
  "name": "First Vertical Slice",
  "status": "pending",
  "dependencies": ["M00"],
  "stories": [
    {
      "id": "M01-01",
      "file": "stories/M01-01-example.md",
      "status": "pending",
      "dependsOn": [],
      "attempts": 0,
      "required": true
    }
  ]
}
```

Estados permitidos:

* `pending`
* `ready`
* `in_progress`
* `review`
* `fix_required`
* `done`
* `blocked`

Não adicionar estados sem razão concreta.

---

# 11. Estrutura obrigatória de Story

Cada Story deve conter:

# ID — Title

## Objective

Uma capacidade clara.

## Outcome

Resultado observável.

## References

Liste apenas os documentos necessários para implementar aquela Story.

Não referencie toda a documentação indiscriminadamente.

## Preconditions

Dependências que precisam existir.

## Scope

O que pertence à Story.

## Out of Scope

O que explicitamente não pertence.

## Domain Impact

Quando aplicável:

* entities;
* relationships;
* validations;
* state transitions.

## Application Layer

Quando aplicável:

* Commands;
* Queries;
* Policies.

## Async / Control Plane

Quando aplicável:

* Jobs;
* Operations;
* Outbox;
* Reconcilers;
* Executor.

## API Impact

Quando aplicável.

## UI Impact

Quando aplicável.

## Security Requirements

Quando aplicável:

* authentication;
* authorization;
* audit;
* isolation;
* secrets.

## Observability Requirements

Quando aplicável:

* structured logs;
* request IDs;
* operation IDs;
* metrics.

## Failure Scenarios

Principais falhas que precisam ser tratadas.

## Acceptance Criteria

Critérios objetivos, verificáveis e preferencialmente testáveis.

## Required Tests

Somente testes aplicáveis:

* unit;
* integration;
* request;
* policy;
* contract;
* Swarm;
* E2E;
* security;
* performance;
* chaos.

## Quality Gates

Referencie regras relevantes do Engineering Playbook.

## Definition of Done

Condição objetiva para `status = done`.

---

# 12. Tamanho das Stories

Uma Story deve ser pequena o suficiente para:

* caber em uma sessão razoável;
* gerar um diff revisável;
* produzir um commit coerente;
* ser entendida sem carregar toda a especificação.

Evite:

`Implementar deploy.`

Prefira decomposição adequada, por exemplo:

* persist Release;
* create Deployment;
* enqueue Operation;
* execute Swarm rollout;
* observe rollout;
* persist status;
* expose UI status;
* implement rollback.

Não fragmente artificialmente uma única transação simples.

---

# 13. Dependências

Criar:

`docs/implementation/DEPENDENCIES.md`

Documentar:

* DAG dos Milestones;
* hard dependencies;
* soft dependencies;
* caminho crítico;
* oportunidades de paralelização.

Não permitir dependências circulares.

Se surgir ciclo, reveja a decomposição.

---

# 14. ROADMAP.md

Criar uma visão consolidada.

Inclua pelo menos:

| Milestone | Capability | Depends On | Human Gate |
| --------- | ---------- | ---------- | ---------- |

Identifique explicitamente:

* primeiro vertical slice;
* introdução de Build Pipeline;
* introdução de Edge;
* introdução de Vault;
* introdução de HA;
* introdução de Observability;
* introdução de DR;
* introdução de MCP;
* Production Readiness.

---

# 15. COVERAGE.md

Este arquivo é obrigatório e deve demonstrar cobertura da especificação.

Criar mapeamentos:

```text
Architecture requirement
→ Milestone
→ Story
```

```text
Use Case
→ Milestone
→ Story
```

```text
Security requirement
→ Milestone
→ Story
```

```text
NFR / SLO
→ Milestone
→ Test / Gate
```

```text
Operational requirement
→ Milestone
→ Story / Runbook / Test
```

Nenhum requisito obrigatório pode ficar sem owner.

---

# 16. SPEC_CONFLICTS.md

Registrar conflitos encontrados durante a leitura da especificação.

Para cada conflito:

* documentos envolvidos;
* decisão antiga;
* decisão atual conhecida;
* impacto;
* resolução aplicada ou estado `unresolved`.

Não alterar decisões arquiteturais silenciosamente.

---

# 17. UI e Component Reuse

Stories relacionadas à UI devem assumir que componentes React já existem.

Antes de planejar criação de componente novo:

1. reutilizar componente existente que esta no repo gba.dev;
2. compor;
3. criar variante;
4. somente então criar novo componente.

Não planejar reimplementação do design system.

Não migrar React para HTMX.

---

# 18. Segurança desde o planejamento

Não criar um Milestone final chamado apenas "Security" para corrigir segurança depois.

Security requirements devem acompanhar as Stories responsáveis pelas capacidades.

O Milestone de hardening final pode existir para validação adicional, mas controles essenciais devem nascer junto da funcionalidade.

Exemplos:

* authorization junto de Team/Project/Service;
* webhook verification junto de webhooks;
* SSRF protection junto de Providers;
* secret isolation junto de Vault;
* privileged access junto de Executor;
* audit junto de ações críticas.

---

# 19. Observability desde o planejamento

Mesmo princípio da segurança.

Não adiar toda observabilidade para um Milestone tardio.

Cada capacidade relevante deve possuir sinais mínimos.

Observability avançada pode ser introduzida posteriormente, mas Operations devem ser diagnosticáveis desde cedo.

---

# 20. Testabilidade

Stories devem ser planejadas para permitir testes determinísticos.

Quando uma funcionalidade depende de infraestrutura real, diferencie:

* unit/integration test;
* Swarm Lab test;
* E2E;
* acceptance/manual demonstration.

Não substituir integração real com Docker/Swarm apenas por mocks em funcionalidades cujo comportamento depende do runtime.

---

# 21. Anti-overengineering

Não criar Milestones ou Stories para funcionalidades futuras não aprovadas.

Não introduzir prematuramente:

* Kubernetes;
* multi-region;
* marketplace;
* managed databases próprios;
* enterprise SSO;
* plugin system genérico;
* abstrações especulativas;
* billing avançado;
* novas runtimes sem necessidade.

Aplicar YAGNI.

---

# 22. Production Readiness

O roadmap deve terminar em um estado verificável de Production Readiness.

O último conjunto de Milestones deve cobrir os gates necessários da especificação:

* reliability;
* performance;
* security;
* backup/restore;
* DR;
* observability;
* upgrade;
* operational readiness;
* runbooks;
* load testing;
* chaos;
* SLO validation.

Production Ready não significa apenas "features completas".

---

# 23. Self-review obrigatório

Depois de gerar todos os arquivos, faça uma segunda passagem assumindo o papel de Reviewer.

Procure:

* requisito sem owner;
* Use Case sem Story;
* dependência circular;
* Story gigante;
* Story artificialmente pequena;
* duplicação;
* feature prematura;
* security gap;
* observability gap;
* test gap;
* inconsistência arquitetural;
* Milestone sem resultado demonstrável;
* acceptance criterion subjetivo.

Classifique findings:

* Critical
* High
* Medium
* Low

Corrija todos os Critical e High.

Medium só pode permanecer com justificativa.

---

# 24. Restrições de alteração

Durante este Goal, alterar somente:

```text
docs/implementation/**
```

Opcionalmente:

```text
docs/decisions/**
```

somente para registrar ADR/conflicto necessário.

NÃO alterar:

* código de aplicação;
* Gemfile;
* package files;
* migrations;
* CI;
* infraestrutura;
* testes de aplicação.

Qualquer necessidade descoberta deve virar Story.

---

# 25. Condições de conclusão

Este Goal só está concluído quando:

1. `docs/implementation/README.md` existe.
2. `ROADMAP.md` existe.
3. `DEPENDENCIES.md` existe.
4. `COVERAGE.md` existe.
5. `SPEC_CONFLICTS.md` existe.
6. M00 está completamente especificado.
7. M01 está completamente especificado.
8. Todos os Milestones necessários até Production Readiness estão definidos.
9. Todo Milestone possui `README.md`.
10. Todo Milestone possui `GOAL.md`.
11. Todo Milestone possui `tasks.json`.
12. Toda Story possui arquivo próprio.
13. Toda Story possui Acceptance Criteria.
14. Toda Story possui Definition of Done.
15. Dependências entre Stories estão explícitas.
16. Dependências entre Milestones estão explícitas.
17. Não existem ciclos.
18. Todos os Use Cases obrigatórios estão mapeados.
19. Security requirements críticos estão mapeados.
20. NFR/SLO críticos estão mapeados.
21. Observability está mapeada.
22. Backup/Restore/DR estão mapeados.
23. MCP está mapeado.
24. Production Readiness está mapeado.
25. Self-review foi executado.
26. Critical findings = 0.
27. High findings = 0.
28. Nenhum código do produto foi alterado.
29. O Implementation Pack está pronto para execução Story-by-Story por agente autônomo.

Enquanto qualquer condição estiver falsa, continue trabalhando.

---

# 26. Relatório final

Ao terminar, apresente:

* número total de Milestones;
* número total de Stories;
* lista resumida dos Milestones;
* caminho crítico;
* oportunidades de paralelização;
* conflitos encontrados;
* findings do self-review;
* arquivos criados;
* confirmação de cobertura dos Use Cases;
* confirmação de cobertura de Security/NFR/DR/MCP;
* confirmação de que nenhum código do produto foi alterado.

Não iniciar M00 automaticamente.

Pare quando o Implementation Pack estiver pronto para Human Review.
