---
title: "Opanel — Platform Master Specification"
type: "index"
status: "approved"
---

# Opanel — Platform Master Specification

Este diretório contém a especificação técnica, funcional, operacional e de engenharia consolidada da plataforma Opanel.

Os arquivos Markdown são a versão otimizada para uso dentro do repositório por desenvolvedores e agentes de código. Os documentos DOCX permanecem como origem editorial aprovada.

## Regra de precedência

1. A arquitetura aprovada (Partes 01-10 e anexos normativos) define os invariantes do sistema.
2. A Story atual e os ADRs aceitos definem o escopo da mudança.
3. Os anexos de engenharia definem processo, qualidade, segurança e operação — em especial o Anexo I.
4. `docs/AGENT_RULES.md` define como a especificação vira código.
5. As instruções do harness (`CLAUDE.md`, `AGENTS.md`) adaptam a operação à ferramenta.
6. A preferência do agente só vale quando nada acima decide o assunto.

Um nível inferior pode especializar um superior; nunca contradizê-lo. Quando houver conflito real entre especificação e implementação, não redesenhe silenciosamente: registre o conflito e, quando necessário, crie um ADR. O detalhamento está em `AGENT_RULES.md`.

## Arquitetura principal

- [01 — Fundamentos da Plataforma e Arquitetura Cluster-First](architecture/01-foundation.md)
- [02 — Deploy & Build](architecture/02-build-deploy.md)
- [03 — Runtime, Observabilidade e Operações](architecture/03-runtime-observability.md)
- [04 — Identidade, Times e Segurança](architecture/04-identity-teams-security.md)
- [05 — Backup, Restore e Disaster Recovery](architecture/05-backup-restore-dr.md)
- [06 — Infraestrutura e Provisionamento](architecture/06-infrastructure-provisioning.md)
- [07 — Control Plane Interno](architecture/07-internal-control-plane.md)
- [08 — Networking, Domains & Edge](architecture/08-networking-domains-edge.md)
- [09 — Modelo de Dados, APIs e Contratos do Sistema](architecture/09-data-model-apis-contracts.md)
- [10 — UX/UI e Casos de Uso](architecture/10-ui-use-cases.md)

## Anexos

- [A — Roadmap de Implementação](annexes/A-implementation-roadmap.md)
- [B — Requisitos Não Funcionais e SLOs](annexes/B-nfr-slos.md)
- [C — Threat Model e Security Hardening](annexes/C-threat-model-security-hardening.md)
- [D — Estratégia Completa de Testes](annexes/D-test-strategy.md)
- [E — Runbooks Operacionais](annexes/E-operational-runbooks.md)
- [F — MCP da Plataforma e Agentes](annexes/F-mcp-platform-agents.md)
- [G — Desenvolvimento Orientado por Agentes e Implementation Pack](annexes/G-agent-oriented-development.md)
- [H — Autonomous Development Loop](annexes/H-autonomous-development-loop.md)
- [I — Engineering Playbook e Quality Gates](annexes/I-engineering-playbook-quality-gates.md)

## Execução por agentes

Este `MASTER.md` é o **mapa da especificação**: ele responde "qual documento decide este assunto?". Ele não contém as regras de implementação.

`docs/AGENT_RULES.md` é o conjunto de **regras normativas para implementação**: invariantes de arquitetura, disciplina de escopo, backend, frontend, banco, segurança, testes, dependências, gates e tratamento de conflitos. É agnóstico de ferramenta.

| Arquivo | Papel |
|---|---|
| [`MASTER.md`](MASTER.md) | Mapa da especificação e invariantes globais. |
| [`AGENT_RULES.md`](AGENT_RULES.md) | Regras normativas para qualquer agente de código. |
| [`../CLAUDE.md`](../CLAUDE.md) | Adapter do Claude Code. |
| [`../AGENTS.md`](../AGENTS.md) | Adapter do Codex e de agentes compatíveis. |
| [`decisions/`](decisions/) | ADRs e pendências documentais. |
| [`implementation/`](implementation/) | Implementation Pack: milestones e Stories. |

Antes de implementar uma Story:

1. leia este `MASTER.md`;
2. leia `AGENT_RULES.md`;
3. leia a Story por completo;
4. leia apenas os documentos referenciados pela Story;
5. inspecione a implementação existente antes de propor mudanças;
6. siga os Anexos G, H e I para processo de desenvolvimento, autonomia e quality gates;
7. siga os Anexos C e D para segurança e testes;
8. não invente arquitetura nova para resolver uma tarefa local;
9. registre qualquer decisão arquitetural nova em `docs/decisions/` como ADR.

Divergências conhecidas entre a especificação convertida e as decisões atuais estão registradas em [`decisions/pending-documentation-updates.md`](decisions/pending-documentation-updates.md). Consulte esse arquivo antes de tratar uma afirmação de stack de um documento antigo como vigente.

## Próxima camada

A próxima documentação a ser criada dentro do repositório será o **Implementation Pack**, começando por:

- `docs/implementation/M00/` — Foundation;
- `docs/implementation/M01/` — First Vertical Slice.
