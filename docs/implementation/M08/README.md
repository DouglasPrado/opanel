---
milestone: "M08"
name: "Cluster Expansion, Node Lifecycle & HA"
type: "milestone"
status: "pending"
---

# M08 — Cluster Expansion, Node Lifecycle & HA

## Identity

| Campo | Valor |
|---|---|
| **ID** | M08 |
| **Nome** | Cluster Expansion, Node Lifecycle & HA |
| **Objetivo** | Introduzir **alta disponibilidade**: expandir a instalação de um node para um cluster real por enrollment seguro, administrar o ciclo de vida dos nodes com guardrails de quorum, e derivar o status HA da redundância efetivamente verificada. |
| **Resultado observável** | Um operador adiciona worker, ingress e manager por comando de bootstrap com token de uso único; drena um node sem perder workload; perde um manager de três e o cluster continua gerenciável; perde um ingress e o tráfego continua. A UI distingue **“cluster funcional”** de **“HA Ready”**. |

## Why

Até aqui a plataforma opera um Swarm de um node. M08 é o Milestone que a torna operável em produção séria — e, principalmente, o que impede a plataforma de **mentir sobre HA**.

O Anexo B §2 é explícito: “Replicas > 1” não transforma um cluster single-node em alta disponibilidade. O status precisa ser derivado da redundância real dos componentes controlados (doc 01 §12.1). Essa honestidade é o produto deste Milestone.

M08 também é pré-requisito real de M13: sem cluster multi-node, não há chaos de quorum, de ingress nem de node.

## Scope

- `EnrollmentToken` próprio: uso único, TTL curto, apenas hash persistido — escondendo o join token real do Swarm.
- Script de bootstrap de node com preflight, obtido por HTTPS e versionado.
- Enrollment de Worker; Ingress e Builder como Workers com labels; Manager como operação privilegiada.
- Promote/demote com **guardrails de quorum** e simulação do resultado antes de aplicar.
- Drain, activate e pause com análise de impacto e lista de workloads bloqueados.
- Remoção segura e `force remove` como operação privilegiada e auditada.
- Rotação do join token do Swarm.
- `NetworkProfile`, verificação de portas e diagnóstico de conectividade entre nodes.
- `LoadBalancerProvider` com ciclo de vida de targets.
- Ingress HA: múltiplos gateways, targets no LB e distribuição de certificado com quorum real.
- `ClusterReadinessView` derivada, distinguindo Operational de HA Ready.
- Contabilidade de capacidade e headroom; reação a perda de node.
- UI de Cluster, Nodes, Add Node e fluxos de manutenção.

## Out of Scope

| Deixado para | O quê |
|---|---|
| M09 | Métricas de host e de cluster no backend histórico; alertas formais. |
| M10 | Backup do estado do Swarm e Clean Rebuild (que **usam** o que M08 entrega). |
| M13 | Chaos de quorum, de ingress e de node sob carga. |
| Backlog | Provisionamento automático por cloud provider, multi-cluster remoto/federação, OpenTofu como executor. |

## Dependencies

- **Hard:** M02 (operações de runtime e drift), M04 (Traefik e distribuição de certificado, que agora precisam de quorum real).
- **Soft:** M05 (builder node dedicado provisionado por enrollment).
- **Externas:** hosts adicionais acessíveis; rede privada entre eles; provider de LB quando o modo for `MANAGED`.

## User-visible Outcome

O operador gera um comando de enrollment com validade curta, executa no host novo, e vê o node aparecer `READY`. Ele coloca um node em manutenção sabendo exatamente quais workloads não podem sair e por quê. Ele promove um manager sabendo o que acontece com o quorum. E ele vê, sem ambiguidade, se o cluster está apenas funcional ou realmente pronto para produção.

## Technical Outcome

- Expansão sem alterar o modelo de aplicação: os Services continuam iguais.
- Quorum protegido por construção: nenhuma operação de membership o compromete sem bloqueio explícito.
- Ingress redundante com certificados distribuídos e confirmados por N gateways.
- Readiness derivada de checks reais.

## Architecture Impact

| Categoria | Impacto |
|---|---|
| Entities | `EnrollmentToken`, `NodeOperation`, `NetworkProfile`, `LoadBalancer`, `LoadBalancerTarget`, `IngressGateway` (estendido), `ClusterObservation`. |
| Commands | `CreateEnrollmentToken`, `RevokeEnrollmentToken`, `DrainNode`, `ActivateNode`, `PromoteNode`, `DemoteNode`, `RemoveNode`, `ForceRemoveNode`, `RotateJoinToken`, `EnsureLoadBalancerTargets`. |
| Queries | `ClusterReadinessView`, `NodeImpactAnalysis`, `ClusterCapacity`. |
| Events | `node.joined.v1`, `node.drained`, `node.removed`, `cluster.readiness.changed`. |
| Reconcilers | `NodeReconciler`, `LoadBalancerReconciler`, `CertificateDistributionReconciler` (quorum real). |
| Providers | `LoadBalancerProvider`. |
| UI | Cluster overview, Nodes, Node detail, Add Node, Maintenance. |

## Security

- **Enrollment Token esconde o join token real**: token próprio, uso único, TTL curto, apenas hash persistido (doc 06 §6.1).
- O join token do Swarm **nunca** aparece em log, UI ou AuditLog, e é rotacionável (doc 04 §14.2).
- Criar Manager é operação de alto risco: exige `INSTANCE_ADMIN`/OWNER, reautenticação e confirmação explícita (doc 06 §6.3).
- Portas internas do Swarm (2377, 7946, 4789) restritas à rede confiável; **4789/UDP nunca aberto indiscriminadamente** — VXLAN não autentica tráfego (doc 06 §4.1).
- Docker API **nunca** exposta; sem 2375.
- Bootstrap script obtido por HTTPS, com versão explícita.
- `force remove` é privilegiado e auditado; remover manager sem avaliar quorum é bloqueado.
- Credenciais de provider de LB no Vault, com escopo mínimo.
- Ao remover um node, revogar material de enrollment e credenciais associadas.
- Ameaças cobertas: T15 (manager quorum/supply compromise), join token vazado.

## Observability

- `ClusterObservation`: quorum, managers, workers, ingress, builders, metadata do Swarm.
- Readiness por check, com o motivo de cada um.
- Impacto calculado **antes** de qualquer operação de manutenção.
- Métrica de capacidade e headroom; distinção entre falta de capacidade e falha da aplicação.
- Eventos de node no timeline operacional.

## Testing

| Classe | Exigência |
|---|---|
| Unit | Cálculo de quorum; análise de impacto de drain; readiness derivada. |
| Integration | Token de uso único; expiração; revogação; rotação de join token. |
| Contract | `LoadBalancerProvider`: add/remove/health de target, idempotência, erro de provider. |
| Docker/Swarm | Join e remoção de worker; promote/demote preservando quorum; drain com evacuação; kill de worker sob tráfego; kill de manager em cluster de 3; kill de ingress com health check no LB. |
| E2E | Adicionar node pela UI até `READY`; manutenção guiada; HA Ready derivado. |
| Security | Token expirado/reutilizado rejeitado; join token fora de log; portas do Swarm não públicas; force remove auditado. |

## Acceptance Criteria

1. Um node entra no cluster por token temporário de **uso único** e aparece `READY`.
2. Token expirado ou reutilizado é **rejeitado**.
3. O join token real do Swarm nunca aparece em log, UI ou AuditLog, e é rotacionável.
4. Ingress e Builder são Workers com labels; Manager é operação privilegiada com reautenticação.
5. Drain move workloads compatíveis e **lista explicitamente** os bloqueados e o porquê.
6. Promote/demote simula o efeito no quorum antes de aplicar e bloqueia quando o comprometeria.
7. Remoção de node exige drain quando ele está acessível; `force remove` é privilegiado e auditado.
8. Um cluster com 3 managers tolera a perda de um mantendo o gerenciamento.
9. Múltiplos ingress atrás do LB mantêm o tráfego quando um falha.
10. Worker perdido tem Tasks stateless reagendadas em nodes elegíveis.
11. A distribuição de certificado exige confirmação de **todos** os ingress saudáveis antes de ativar.
12. A UI distingue **“cluster funcional”** de **“HA Ready”**, com o motivo de cada check.
13. Portas internas do Swarm não são expostas publicamente; 4789/UDP restrito à rede do cluster.
14. Docker API não é exposta; nenhuma porta 2375.
15. Falta de capacidade é distinguida de falha da aplicação.

## Exit Gate

- [ ] Stories `required` `done`; 15 Acceptance Criteria com evidência.
- [ ] **Teste de perda de manager** em cluster de 3, verde, com gerenciamento preservado.
- [ ] **Teste de perda de ingress** sob tráfego, verde, com o LB removendo o target.
- [ ] **Teste de kill de worker sob tráfego**, verde, com Tasks reagendadas.
- [ ] Teste de token de enrollment expirado/reutilizado verde.
- [ ] Teste de bloqueio de promote/demote que comprometeria o quorum verde.
- [ ] Contract tests do `LoadBalancerProvider` verdes.
- [ ] `bin/fitness`, `bin/security` verdes; Critical = 0, High = 0.
- [ ] `MILESTONE_REPORT.md` gerado.

**Gate humano: HA Gate.** Corresponde ao gate do Anexo A §11 e ao G4 do Anexo C §22. A plataforma só pode **declarar** HA depois deste gate.
