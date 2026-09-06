---
title: "Opanel — Coverage Mapping"
type: "implementation-coverage"
status: "ready-for-human-review"
---

# Opanel — Coverage Mapping

Este documento é a **prova de cobertura** do Implementation Pack: cada requisito obrigatório da especificação aprovada tem um dono explícito — uma Story, um teste ou um gate.

A regra que governa este arquivo é simples: **requisito sem dono é defeito de planejamento**. Um item que não pode ser implementado agora não desaparece; ele aparece aqui com o motivo e o destino.

## Como ler

| Coluna | Significado |
|---|---|
| **Dono** | A Story que **implementa** ou **prova** o requisito. Várias Stories podem colaborar; a primeira listada é a principal. |
| **Milestone** | Onde o requisito passa a existir de forma observável. |
| **Validação** | Onde o requisito é **provado** quando a prova não é a própria Story — tipicamente M13 (suítes) ou M14 (gate). |

Referências para as Stories usam o ID (`M06-09`); o arquivo correspondente está em `M06/stories/`.

---

## 1. Documentos de arquitetura → Milestones

Mapeamento macro. As tabelas seguintes descem ao requisito individual.

| Documento | Conteúdo | Milestones que o realizam |
|---|---|---|
| `01-foundation.md` | Fundação, Cluster, bootstrap, Traefik, Recovery Key | M00, M01, M03, M04, M08 |
| `02-build-deploy.md` | Source, Railpack, BuildKit, Registry, Release, Deployment | M05, M06 |
| `03-runtime-observability.md` | Runtime, logs, métricas, alertas, incidentes, autoscaling | M01, M02, M09 |
| `04-identity-teams-security.md` | User, Team, RBAC, Vault, quotas, audit | M01, M03, M11 |
| `05-backup-restore-dr.md` | Backup, snapshots, restore, DR | M10 |
| `06-infrastructure-provisioning.md` | Providers de DNS, LB, Registry, Backup; quorum e nodes | M04, M05, M08, M10 |
| `07-internal-control-plane.md` | Operations, outbox, locks, fencing, reconcilers, MCP | M01, M02, M12 |
| `08-networking-domains-edge.md` | Ingress, domains, certificados, políticas de borda | M04, M07 |
| `09-data-model-apis-contracts.md` | Modelo de dados, API pública, contratos, eventos | distribuído por Milestone; contratos consolidados em M11 e M14-07 |
| `10-ui-use-cases.md` | Telas e Use Cases UC-001..UC-050 | M01-22, M02-10, M03-12, M04-13, M06-12, M08-14, M09-04, M11-11, M12-15 |

---

## 2. Use Cases UC-001..UC-050

| UC | Descrição | Dono | Milestone | Validação |
|---|---|---|---|---|
| UC-001 | Criar conta e primeiro Team | `M01-01`, `M01-02`, `M01-06` | M01 | `M14-01` |
| UC-002 | Gerar e verificar Recovery Key | `M03-02` | M03 | `M13-04`, `M14-02` |
| UC-003 | Inicializar primeiro cluster Swarm | `M01-08` | M01 | `M14-02` |
| UC-004 | Adicionar Worker ao cluster | `M08-01`, `M08-02`, `M08-03` | M08 | `M14-01` |
| UC-005 | Adicionar Ingress node | `M04-01`, `M08-04` | M04, M08 | `M13-08` |
| UC-006 | Colocar node em Drain | `M08-06` | M08 | `M13-10` |
| UC-007 | Promover Worker a Manager | `M08-05` | M08 | `M13-10` |
| UC-008 | Remover node com segurança | `M08-07` | M08 | `M14-01` |
| UC-009 | Criar Project | `M01-07` | M01 | `M14-01` |
| UC-010 | Criar Environment | `M01-11` | M01 | `M14-01` |
| UC-011 | Mover Environment para outro Cluster | `M10-18` | M10 | `M14-01` |
| UC-012 | Criar Service via Git + Railpack | `M05-02`, `M05-08` | M05 | `M14-01` |
| UC-013 | Criar Service via Docker image | `M01-12`, `M01-22` | M01 | `M01-23`, `M14-01` |
| UC-014 | Configurar recursos/healthcheck | `M02-02`, `M02-04` | M02 | `M13-09` |
| UC-015 | Fazer deploy manual | `M06-02`, `M06-05` | M06 | `M14-01` |
| UC-016 | Auto-deploy por webhook | `M06-11`, `M05-04` | M06 | `M13-11` |
| UC-017 | Cancelar deployment | `M06-10` | M06 | `M13-05` |
| UC-018 | Rollback para release anterior | `M06-07` | M06 | `M14-01` |
| UC-019 | Promover HML para Production | `M06-09` | M06 | `M14-01` |
| UC-020 | Escalar manualmente | `M01-21` | M01 | `M01-23` |
| UC-021 | Configurar autoscaling | `M09-12`, `M09-13` | M09 | `M13-07` |
| UC-022 | Restart Service | `M02-01` | M02 | `M14-01` |
| UC-023 | Abrir terminal em Task | `M09-14` | M09 | `M13-01` |
| UC-024 | Adicionar domínio customizado | `M07-01` | M07 | `M14-01` |
| UC-025 | Validar DNS e emitir certificado | `M07-02`, `M04-09` | M04, M07 | `M14-01` |
| UC-026 | Renovar e distribuir certificado | `M04-10`, `M04-11` | M04 | `M13-10` |
| UC-027 | Remover domínio | `M07-05` | M07 | `M14-01` |
| UC-028 | Criar Secret | `M03-05` | M03 | `M13-04` |
| UC-029 | Criar nova SecretVersion | `M03-05` | M03 | `M13-04` |
| UC-030 | Bind SecretVersion a Service | `M03-06`, `M03-07` | M03 | `M13-04` |
| UC-031 | Promover SecretVersion HML→PROD | `M03-08` | M03 | `M14-01` |
| UC-032 | Reveal secret | `M03-09`, `M03-04` | M03 | `M13-01`, `M13-04` |
| UC-033 | Consultar logs | `M01-20`, `M09-05`, `M09-06` | M01, M09 | `M13-11` |
| UC-034 | Consultar métricas | `M09-03`, `M09-04` | M09 | `M13-13` |
| UC-035 | Criar Alert Rule | `M09-08` | M09 | `M13-13` |
| UC-036 | Acknowledge/resolve Incident | `M09-10` | M09 | `M14-04` |
| UC-037 | Criar Environment Snapshot | `M10-09` | M10 | `M14-05` |
| UC-038 | Restaurar Snapshot | `M10-12` | M10 | `M14-05` |
| UC-039 | Executar backup da plataforma | `M10-02`, `M10-03`, `M10-05` | M10 | `M14-05` |
| UC-040 | Executar recovery verification | `M10-16` | M10 | `M14-05` |
| UC-041 | Convidar membro | `M11-01` | M11 | `M13-01` |
| UC-042 | Alterar role de membro | `M11-02` | M11 | `M13-01` |
| UC-043 | Transferir ownership | `M11-03` | M11 | `M14-01` |
| UC-044 | Remover membro | `M11-02` | M11 | `M13-01` |
| UC-045 | Criar/revogar API token | `M11-07` | M11 | `M13-01` |
| UC-046 | Consultar Audit Log | `M11-11` | M11 | `M13-01` |
| UC-047 | Configurar DNS Provider | `M04-07` | M04 | `M13-02` |
| UC-048 | Configurar LB Provider | `M08-10` | M08 | `M13-08` |
| UC-049 | Configurar Registry Provider | `M05-11` | M05 | `M13-02` |
| UC-050 | Configurar Backup Storage | `M10-01` | M10 | `M14-05` |

**50 de 50 com dono.**

---

## 3. Use Cases de agente MCP-01..MCP-20

Todos passam pela Application Layer; nenhum fala com Docker (AF-05).

| MCP | Descrição | Dono | Fase de rollout | Milestone |
|---|---|---|---|---|
| MCP-01 | Conectar agente via OAuth | `M12-01`, `M12-02`, `M12-04` | — | M12 |
| MCP-02 | Descobrir projetos/ambientes | `M12-06` | F1 | M12 |
| MCP-03 | Criar Project + HML Environment | `M12-08` | F2 | M12 |
| MCP-04 | Criar Service por image | `M12-08` | F2 | M12 |
| MCP-05 | Conectar Git e disparar build | `M12-10` | F3 | M12 |
| MCP-06 | Deploy em HML | `M12-10` | F3 | M12 |
| MCP-07 | Promover release para PROD | `M12-10`, `M12-09` | F3 + approval | M12 |
| MCP-08 | Rollback PROD | `M12-10`, `M12-09` | F3 + approval | M12 |
| MCP-09 | Criar secret e bindar | `M12-11`, `M12-09` | F4 | M12 |
| MCP-10 | Adicionar domínio custom | `M12-11` | F4 | M12 |
| MCP-11 | Escalar Service | `M12-08` | F2 | M12 |
| MCP-12 | Diagnosticar service unhealthy | `M12-07` | F1 | M12 |
| MCP-13 | Investigar build failed | `M12-07` | F1 | M12 |
| MCP-14 | Acompanhar Operation longa | `M12-06` | F1 | M12 |
| MCP-15 | Drain de Worker | `M12-11`, `M12-09` | F4 + approval | M12 |
| MCP-16 | Criar snapshot/backup | `M12-11` | F4 | M12 |
| MCP-17 | Planejar restore | `M12-11` | F4 (read-only) | M12 |
| MCP-18 | Executar restore | `M12-12`, `M12-09` | F5 + approval | M12 |
| MCP-19 | Consultar auditoria | `M12-07`, `M12-14` | F1 | M12 |
| MCP-20 | Revogar conexão do agente | `M12-04`, `M12-15` | — | M12 |

**20 de 20 com dono.** Auditoria, métricas e rate limiting de todas as chamadas: `M12-14`; validação sob abuso: `M13-11`.

---

## 4. Ameaças T01..T15 (Anexo C §6)

| Ameaça | Severidade | Controle implementado por | Validado por |
|---|---|---|---|
| T01 — Comprometimento do docker.sock / Executor | CRITICAL | `M01-09` (executor tipado, allowlist, manager-only), `M08-09` | `M13-03`, `M14-06`, AF-01/AF-02 |
| T02 — Escape de container de workload | HIGH | `M02-02` (limites), `M02-03` (placement), hardening de host em `M08-02` | `M13-03`; risco residual declarado em `M14-08` |
| T03 — Build malicioso acessa infraestrutura | CRITICAL | `M05-07` (builder isolado), `M05-10` (build secrets), `M05-15` | `M05-16`, `M13-03` |
| T04 — RBAC bypass / IDOR entre Teams | HIGH | `M01-04` (deny by default, tenancy scoping), `M11-08` | `M13-01` |
| T05 — Vazamento de SecretVersion | HIGH | `M03-01`, `M03-07`, `M03-09`, `M03-10` | `M13-04`, AF-06 |
| T06 — Roubo da Recovery Key | HIGH | `M03-02`, `M03-03`, `M03-04` | `M13-04`, `M14-05` |
| T07 — Webhook forjado / replay | HIGH | `M05-04` (assinatura, janela, dedup) | `M13-11` |
| T08 — Imagem/tag trocada após aprovação | HIGH | `M05-12` (digest), `M06-01`, `M06-09`, `M06-13` | `M13-12`, `M14-09` |
| T09 — SSRF para metadata/serviços internos | CRITICAL | guarda em `M04-07`, `M05-11`, `M09-11`, `M11-12`, `M12-04` | `M13-02` |
| T10 — Exec/terminal abusado | HIGH | `M09-14` (RBAC, step-up, audit, timeout) | `M13-01` |
| T11 — DNS token comprometido | HIGH | `M04-07` + Vault (`M03-05`), rotação em `M11-12` | `M13-04` |
| T12 — Cert private key exfiltrada | HIGH | `M04-08` (cifrada), `M04-10` (distribuição mínima), `M10-07` | `M13-04` |
| T13 — DoS por builds/log streams/deploys | HIGH | `M11-09`, `M11-10`, `M11-14`, `M05-15` | `M13-11` |
| T14 — SQL injection / query scope bypass | HIGH | `M01-04`, `M00-10` (scanners), queries parametrizadas | `M13-01`, `M14-06` |
| T15 — Manager quorum / supply compromise | HIGH | `M08-05`, `M08-08`, `M08-09`, `M10-08`, `M00-10` | `M13-10`, `M14-06` |

**15 de 15 com controle e validação.**

---

## 5. Security gates G1..G6 (Anexo C §22)

| Gate | Exigência | Satisfeito por |
|---|---|---|
| G1 — Internal Alpha | Sem Docker API pública; RBAC básico testado; Vault ciphertext; builders separados | `M01-09`, `M01-04`, `M03-01`, `M05-07` |
| G2 — Private Beta | Cross-team isolation; webhook signatures; rate limits; AuditLog; backup/restore | `M13-01`, `M05-04`, `M11-14`, `M01-05`, `M10` |
| G3 — Production | Executor hardened; manager network privada; secret redaction; security monitoring; incident runbook | `M01-09`, `M08-09`, `M03-10`, `M09-08`, `M14-04` |
| G4 — HA Production | 3 managers; ingress HA; autolock/recovery testados; node lifecycle validado | `M08-05`, `M08-11`, `M08-12`, `M08-08`, `M13-10` |
| G5 — Public Multi-Team | Pentest externo; quotas; abuse controls; supply-chain scanning; suporte | `M11-09`/`M11-10`, `M13-11`, `M00-10`; **pentest externo declarado como `PENDING_HUMAN` em `M14-06`** |
| G6 — Hostile Multi-Tenant | **Não liberar** com Docker compartilhado; exige nova arquitetura de isolamento | Fora do escopo do MVP; declarado em `M14-08` |

---

## 6. Checklist de go-live (Anexo C §23)

Cada classe do checklist tem uma fonte de evidência executável. O checklist completo é executado item a item em `M14-06`.

| Classe | Evidência | Dono |
|---|---|---|
| Auth, RBAC, IDOR | Suíte de matriz derivada do inventário de rotas | `M13-01` |
| Secrets e redaction | Canários em todas as superfícies observáveis | `M13-04` |
| SSRF | Corpus contra todas as features que aceitam URL | `M13-02` |
| Webhooks | Assinatura, replay, dedup, tamanho | `M05-04`, `M13-11` |
| Terminal/exec | Permissão, audit, timeout, isolamento | `M09-14`, `M13-01` |
| Builder isolation | Corpus adversarial | `M05-16`, `M13-03` |
| Supply chain | Digest pinning, proteção de GC, promoção sem rebuild | `M06-13`, `M13-12`, `M14-09` |
| Rate/abuse | Login, token, webhook, build, deploy, logs | `M13-11` |
| Network | Portas do Swarm, acesso a manager e executor | `M08-09`, `M14-06` |
| Crypto/Recovery | Rotação, chave errada, tamper, backup + restore | `M03-03`, `M10-06`, `M14-05` |
| Fitness functions | AF-01..AF-10 verdes | `M00-13`, `M14-06` |
| Credenciais no repositório | Scan de histórico | `M00-10`, `M14-06` |

---

## 7. Architecture Fitness Functions AF-01..AF-10 (Anexo I §16.2)

Definidas e automatizadas em `M00-13`; executadas em todo Pre-commit e Merge Gate; auditadas em `M14-06`.

| AF | Regra | Milestone em que passa a ter alvo real |
|---|---|---|
| AF-01 | Controllers públicos não importam cliente Docker | M01 (`M01-09`) |
| AF-02 | Somente o Swarm Executor referencia o socket | M01 (`M01-09`) |
| AF-03 | Reconcilers não escrevem Desired State de intenção do usuário | M01 (`M01-18`), M02 (`M02-06`), M10 (`M10-18`) |
| AF-04 | React não importa código server-only | M00 (`M00-04`), M01 (`M01-22`) |
| AF-05 | MCP adapter não chama o executor diretamente | M12 (`M12-03`) |
| AF-06 | Secret plaintext ausente de serializers, logs e audit | M03 (`M03-10`) |
| AF-07 | Mutação crítica tem authorization path server-side | M01 (`M01-04`) |
| AF-08 | Events/Operations carregam correlation IDs | M01 (`M01-13`) |
| AF-09 | Migration destrutiva exige marcador de contract/ADR | M00 (`M00-02`), validada em `M13-12` |
| AF-10 | Feature React não duplica primitive sem waiver | M00 (`M00-05`) |

---

## 8. NFRs e SLOs (Anexo B)

| Seção | Requisito | Implementado por | Provado por |
|---|---|---|---|
| §3 | SLOs de disponibilidade | `M09-15` | `M13-13` |
| §3.1 | Error budget mensal | `M09-15` | `M13-13` |
| §4 | SLOs de latência e responsividade | `M09-15`, `M01-22` | `M13-07`, `M13-13` |
| §5 | Convergência de desired state | `M01-18`, `M02-06`, `M02-12` | `M13-07` |
| §6 | Deploy, rollback e promotion | `M06-04`, `M06-05`, `M06-07`, `M06-09` | `M13-13`, `M14-01` |
| §7 | Build e Railpack/BuildKit | `M05-08`, `M05-09`, `M05-13` | `M13-06` |
| §8 | Edge, Traefik, LB, DNS e TLS | `M04-05`, `M04-09`, `M07-02`, `M08-10` | `M13-08` |
| §9 | Capacidade e escalabilidade | `M13-06` | `M13-09` |
| §9.1 | Piso de qualificação GA | `M13-09` | `M13-09`, `M14-10` |
| §10 | Resource isolation e scheduling | `M02-02`, `M02-03` | `M13-09` |
| §11 | Durabilidade, backup, RPO e RTO | `M10-02`, `M10-11` | `M10-16`, `M14-05` |
| §11.1 | Restore verification | `M10-16` | `M14-05` |
| §12 | Retenção de dados e observabilidade | `M09-05`, `M10-15` | `M13-09` |
| §13 | Segurança não funcional | `M01-01`, `M11-05`, `M03-10` | `M13-04`, `M14-06` |
| §14 | Dependências externas e degradação | `M04-13`, `M09-11`, `M08-10` | `M13-10` |
| §15 | Error budget e política de mudança | `M09-15` | `M13-13` |
| §16 | Alertas e severidade operacional | `M09-08`, `M09-09`, `M09-10` | `M14-04` |
| §17 | Perfil mínimo de testes de performance e resiliência | `M13-06` | `M13-07`, `M13-08`, `M13-10` |
| §18 | NFRs de UX e acessibilidade | `M00-08`, `M01-22` | `M14-01` |
| §19 | Gate de Production Readiness | `M14-10` | `M14-10` |
| §20 | Critérios de aceite do Anexo B | consolidados | `M14-10` |

---

## 9. Runbooks operacionais RB-01..RB-30 (Anexo E)

Cada runbook tem a capacidade que o torna executável e é **exercitado** em `M14-04`.

| RB | Situação | Capacidade que o suporta |
|---|---|---|
| RB-01 | Control Plane API indisponível | `M00-15`, `M09-07` |
| RB-02 | PostgreSQL indisponível ou degradado | `M00-02`, `M10-05` |
| RB-03 | Fila/Operation Engine parado | `M01-14`, `M02-10` |
| RB-04 | Worker indisponível | `M08-13` |
| RB-05 | Manager indisponível com quorum preservado | `M08-05` |
| RB-06 | Perda de quorum dos Managers | `M08-05`, `M10-14` |
| RB-07 | Overlay network degradada | `M01-17`, `M08-09` |
| RB-08 | Docker daemon travado em node | `M08-13` |
| RB-09 | Traefik/Ingress indisponível | `M04-13`, `M08-11` |
| RB-10 | Load Balancer externo degradado | `M08-10` |
| RB-11 | Certificado não emite/renova | `M04-11`, `M04-13` |
| RB-12 | Domain custom não resolve | `M07-02` |
| RB-13 | Registry indisponível | `M05-11` |
| RB-14 | Builder/BuildKit preso ou saturado | `M05-15` |
| RB-15 | Deployment preso ou falhando | `M06-10` |
| RB-16 | Service em crash loop | `M02-05` |
| RB-17 | Disco ou inodes esgotando | `M05-13`, `M09-02` |
| RB-18 | Pressão de memória/CPU no node | `M02-02`, `M09-02` |
| RB-19 | Recovery Key perdida ou exposta | `M03-03`, `M10-06` |
| RB-20 | Token/credential comprometido | `M11-06`, `M11-07` |
| RB-21 | Suspeita de comprometimento de Manager/Executor | `M01-09`, `M08-08` |
| RB-22 | Backup falhando ou fora do RPO | `M10-17` |
| RB-23 | Restore do banco da plataforma | `M10-05`, `M10-11` |
| RB-24 | Clean Rebuild completo | `M10-13` |
| RB-25 | Restore do estado do Swarm | `M10-08`, `M10-14` |
| RB-26 | Adicionar Worker | `M08-03` |
| RB-27 | Adicionar ou substituir Manager | `M08-05` |
| RB-28 | Remover ou drenar Node | `M08-06`, `M08-07` |
| RB-29 | Upgrade do Control Plane | `M14-03` |
| RB-30 | Upgrade Docker/Traefik/BuildKit | `M14-03` |

**30 de 30 com capacidade de suporte e exercício planejado.**

---

## 10. Classes de teste (Anexo D) → onde nascem

| Classe | Harness criado em | Cobertura contínua |
|---|---|---|
| Static checks, lint, typecheck | `M00-09` | todo Milestone |
| Unit | `M00-07` | todo Milestone |
| Integration com PostgreSQL real | `M00-07` | todo Milestone |
| Contract (API, eventos, providers) | `M00-11` | M04, M05, M08, M10, M12 |
| Docker/Swarm integration | `M00-17` | M01, M02, M04, M06, M08, M10 |
| Frontend component | `M00-08` | M01, M02, M03, M04, M06, M08, M09, M11, M12 |
| E2E de jornada | `M00-08` | `M01-23`, `M14-01` |
| Segurança | `M00-10` | `M13-01`..`M13-04`, `M14-06` |
| Performance e carga | `M13-06` | `M13-07`, `M13-08`, `M13-09` |
| Chaos e resiliência | `M13-10` | `M13-10` |
| Backup/restore/DR | `M10-16` | `M14-05` |
| Upgrade e compatibilidade | `M13-12` | `M14-03` |
| Concorrência e idempotência | `M02-13`, `M13-05` | `M13-05` |
| Observabilidade e diagnóstico | `M09-07` | `M13-13` |

---

## 11. Requisitos sem dono

**Nenhum requisito obrigatório está sem dono.**

Os itens abaixo são **conscientemente adiados ou não automatizáveis**, e existem aqui para que não sejam confundidos com cobertura:

| Item | Origem | Situação | Registro |
|---|---|---|---|
| Pentest externo | Anexo C §21.1, G5 | Atividade humana agendada; não substituível por automação | `M14-06` como `PENDING_HUMAN` |
| Tenancy hostil (G6) | Anexo C §22 | Fora do escopo do MVP; exige nova arquitetura de isolamento e novo threat model | `M14-08` |
| Escala além dos pisos GA | Anexo B §9.1 | Declarada como **não testada**, nunca como suportada | `M13-09`, `M14-08` |
| Chaos em produção | Anexo D §14 | Fora do MVP; exige gate humano e maturidade operacional | `M13-10` |
| Migração de dados de aplicação entre Clusters | UC-011 | A plataforma move intenção e configuração; volumes e bancos do cliente não | `M10-18` |
| Backlog pós-core | Anexo A §12 | Capacidades explicitamente fora do core | `ROADMAP.md` |

Além destes, duas decisões arquiteturais permanecem **abertas** e bloqueiam Stories específicas até serem aceitas:

| Conflito | Bloqueia | ADR |
|---|---|---|
| SC-04 — namespace de labels de ownership | `M01-16` | `ADR-0001` (`Proposed`) |
| SC-08 — estratégia de identificadores | `M01-01` | `ADR-0002` (`Proposed`) |

Detalhes em `SPEC_CONFLICTS.md`.

---

## 12. Como reverificar esta cobertura

Esta tabela é verificável, não declaratória:

```text
1. todo ID citado como "Dono" existe em M<XX>/stories/ e em M<XX>/tasks.json
2. todo caminho docs/... citado nas Stories existe
3. toda citação "Anexo X §N" resolve para uma seção real
4. todo UC, MCP, T, RB e AF da especificação aparece exatamente uma vez nas tabelas acima
```

Os quatro checks são executáveis e devem rodar como parte de `bin/pack validate` (`M00-14`). Uma Story nova que não apareça em nenhuma tabela de cobertura é um sinal de escopo não rastreado, não de trabalho extra.
