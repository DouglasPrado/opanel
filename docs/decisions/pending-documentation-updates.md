---
title: "Pending Documentation Updates"
type: "decision-log"
status: "open"
---

# Pendências de atualização documental

Registro das divergências entre a especificação aprovada (convertida dos DOCX) e as decisões mais recentes do projeto.

**Este arquivo não altera a especificação.** Ele existe para que nenhum agente leia um trecho antigo como decisão vigente e para que as correções sejam feitas depois de forma controlada, por Story ou ADR — nunca por substituição global automática.

Criado em 2026-09-06, durante o bootstrap de desenvolvimento orientado por agentes (`docs/AGENT_RULES.md`, `CLAUDE.md`, `AGENTS.md`).

## Decisões vigentes usadas como referência

| Assunto | Decisão atual |
|---|---|
| Nome do produto | **Opanel** |
| Backend | Ruby on Rails 8.1.x, PostgreSQL, Solid Queue |
| Frontend | React + TypeScript sobre Inertia.js, Vite, Tailwind — componentes React existentes são reaproveitados |
| Plataforma | Docker Engine, Docker Swarm, Traefik, Railpack, BuildKit, OCI Registry |

## 1. Conflitos de stack

Nestes casos o documento aprovado contradiz a decisão atual. A decisão atual prevalece; o texto do documento precisa ser corrigido.

| # | Arquivo | Trecho / conceito | Decisão antiga | Decisão atual |
|---|---|---|---|---|
| C1 | `docs/annexes/G-agent-oriented-development.md` §2, linhas 95 e 99-100 | "O baseline recomendado neste momento é Rails para o Control Plane e Next.js para a UI"; tabela de stack com `Web UI = Next.js + React + TypeScript` e `Control Plane = Ruby on Rails em modo API` | UI Next.js separada consumindo Rails em modo API | Aplicação Rails única servindo a UI por Inertia + React/TypeScript. Sem Next.js. |
| C2 | `docs/annexes/G-agent-oriented-development.md` §4, linhas 202-203 | Exemplo de `MASTER.md` com `- Backend: Rails API` e `- Frontend: Next.js` | idem C1 | idem C1 |
| C3 | `docs/annexes/G-agent-oriented-development.md` §17, linha 819 | "Dia 1: Criar repo; Rails; Next.js; PostgreSQL; ambiente local; CI..." | idem C1 | idem C1 |
| C4 | `docs/annexes/G-agent-oriented-development.md` §3, linhas 160-162 | Estrutura sugerida com `apps/api/` e `apps/web/` | Dois aplicativos separados no mesmo repositório | Aplicação Rails única; frontend React servido por Inertia + Vite. A estrutura final de diretórios será fixada no Implementation Pack M00. |
| C5 | `docs/architecture/07-internal-control-plane.md` §9.2, linha 437 | "A implementação inicial pode usar BullMQ + Redis gerenciado, alinhada ao ecossistema Node/TypeScript" | BullMQ + Redis, ecossistema Node/TypeScript | **Solid Queue** sobre PostgreSQL. O restante do parágrafo continua válido e normativo: a fila é mecanismo de entrega, o PostgreSQL continua sendo fonte de verdade da Operation e o sweep periódico recupera Operations sem lease. |
| C6 | `docs/annexes/D-test-strategy.md` §21, linha 563 | "Quando a linguagem do Control Plane for definida definitivamente (Rails ou Rust), o Implementation Pack deverá escolher runners/libraries concretos" | Linguagem do Control Plane em aberto | Rails 8.1.x está definido. O Implementation Pack ainda precisa escolher os runners/libraries concretos — essa parte da frase continua pendente e legítima. |

## 2. Referências informativas, sem conflito

Registradas apenas para evitar releitura como decisão pendente. **Nenhuma ação necessária.**

| # | Arquivo | Trecho | Situação |
|---|---|---|---|
| I1 | `docs/annexes/G-agent-oriented-development.md` §2, linha 103 | "Swarm Executor: Ruby inicialmente; extração para Rust somente se houver necessidade concreta" | Continua válido. Ruby é o baseline; Rust permanece condicionado a necessidade concreta e ADR. |
| I2 | `docs/annexes/E-operational-runbooks.md`, linha 20 | "a implementação pode ser Rails, Rust ou outra tecnologia sem alterar o procedimento operacional" | Agnosticismo deliberado dos runbooks. Não é uma decisão de stack. |
| I3 | `docs/annexes/C-threat-model-security-hardening.md` §21.1, linha 599 | "Dependency/SCA scanning em Ruby/JS/Rust conforme stack final" | Com a stack congelada, o escopo efetivo é Ruby + JS e imagens OCI. Texto genérico, baixo impacto. |
| I4 | `docs/CONVERSION_REPORT.md`, linha 40 | Já sinalizava a pendência `Next.js + Rails API` → `Rails + Inertia + React` | Este arquivo passa a ser o registro formal dessa pendência. |

## 3. Nomes de arquivo desatualizados no Anexo G

O Anexo G cita nomes ilustrativos de documento que não correspondem aos arquivos realmente convertidos. Aparecem dentro de blocos de exemplo, não como links Markdown — **nenhum link local está quebrado**. Ainda assim, um agente pode tentar abrir um path inexistente.

`docs/MASTER.md` é a fonte de roteamento correta e já usa os nomes reais.

Ocorrências em `docs/annexes/G-agent-oriented-development.md`, linhas 143-157, 214-222, 277, 280 e 530-534:

| Citado no Anexo G | Arquivo real |
|---|---|
| `architecture/04-identity-security.md` | `architecture/04-identity-teams-security.md` |
| `architecture/05-backup-dr.md` | `architecture/05-backup-restore-dr.md` |
| `architecture/06-infrastructure.md` | `architecture/06-infrastructure-provisioning.md` |
| `architecture/07-control-plane.md` | `architecture/07-internal-control-plane.md` |
| `architecture/08-networking-edge.md` | `architecture/08-networking-domains-edge.md` |
| `architecture/09-data-api-contracts.md` | `architecture/09-data-model-apis-contracts.md` |
| `annexes/A-roadmap.md` | `annexes/A-implementation-roadmap.md` |
| `annexes/C-security.md` | `annexes/C-threat-model-security-hardening.md` |
| `annexes/D-testing.md` | `annexes/D-test-strategy.md` |
| `annexes/E-runbooks.md` | `annexes/E-operational-runbooks.md` |
| `annexes/F-mcp.md` | `annexes/F-mcp-platform-agents.md` |
| `annexes/G-agent-development.md` | `annexes/G-agent-oriented-development.md` |

## 4. Nome do produto

Nenhuma ocorrência de `OpenEL` foi encontrada em `docs/` ou `README.MD`. `docs/MASTER.md` já usa **Opanel**. Nada a corrigir.

### Pendência de nomenclatura — não decidida neste Goal

`docs/architecture/07-internal-control-plane.md` §7 define o prefixo de labels de ownership dos recursos criados no Swarm:

```text
com.platform.managed=true
com.platform.team_id=...
com.platform.service_id=...
```

Com o nome do produto fixado em Opanel, cabe decidir se esse prefixo passa a `com.opanel.*`. **A decisão não foi tomada aqui e exige ADR**: o prefixo é a identidade de ownership dos recursos em runtime, e alterá-lo depois do primeiro deploy quebra a reconciliação e o drift detection de tudo que já estiver rodando. Decidir antes do M01.

## 5. Como aplicar estas correções

1. Não fazer substituição global automática em `docs/`.
2. Cada correção entra por uma Story do Implementation Pack ou por um ADR em `docs/decisions/`, conforme o impacto.
3. Conflitos de stack (seção 1) devem ser corrigidos no documento aprovado **antes** que o Implementation Pack M00 congele a estrutura do repositório — caso contrário o Anexo G continuará instruindo agentes a criar uma UI Next.js.
4. Ao corrigir um item, remova a linha correspondente desta tabela e cite o commit/ADR.
5. Enquanto um item continuar aberto aqui, ele prevalece sobre o texto do documento antigo para efeito de implementação.
