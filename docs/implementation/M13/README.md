---
milestone: "M13"
name: "Hardening, Performance, Chaos & SLO Validation"
type: "milestone"
status: "pending"
---

# M13 — Hardening, Performance, Chaos & SLO Validation

## Identity

| Campo | Valor |
|---|---|
| **ID** | M13 |
| **Nome** | Hardening, Performance, Chaos & SLO Validation |
| **Objetivo** | **Provar** o comportamento da plataforma sob abuso, carga, falha e concorrência — consolidando as suítes que os Milestones anteriores criaram e adicionando as que só fazem sentido com o sistema completo. |
| **Resultado observável** | As suítes de segurança, carga, chaos e upgrade rodam contra o sistema inteiro e produzem evidência arquivável; nenhuma delas encontra Critical ou High sem mitigação. |

## Why

Este Milestone **não introduz controles de segurança** — eles nasceram junto das capacidades, como o Goal §18 exige. M13 **valida**.

A diferença importa: se um controle só aparecer aqui, é sinal de que uma Story anterior ficou incompleta, e a correção vai para lá. M13 consolida, mede e prova.

Ele também é o único lugar onde certos testes são possíveis: chaos de quorum precisa de cluster real (M08), DR drill precisa de backup (M10), e carga do Control Plane precisa de todas as superfícies existindo.

## Scope

- Consolidação da matriz RBAC/IDOR cross-team em suíte única e obrigatória.
- Suíte de SSRF cobrindo **todas** as features que aceitam URL.
- Suíte adversarial de isolamento de builder, estendendo o corpus de `M05-16`.
- Scanner consolidado de vazamento de secret em logs, erros, eventos, audit e telemetria.
- Suíte de concorrência e idempotência com fault injection determinística.
- Performance Lab com topologia registrada e baseline por versão.
- Testes de throughput do Operation Engine e dos reconcilers.
- Teste de carga do edge, **separado** da capacidade das aplicações.
- Dataset com os pisos de teste GA do Anexo B §9.1.
- Suíte de chaos cobrindo node, manager, quorum, Traefik, DB, Registry e executor.
- Validação dos controles de abuso: rate limits, quotas, backpressure.
- Suíte de compatibilidade de upgrade N/N-1.
- Validação da instrumentação de SLO e da política de error budget.

## Out of Scope

| Deixado para | O quê |
|---|---|
| M14 | E2E de aceitação final, runbooks exercitados, upgrade da plataforma em staging, DR drill final e o gate de Production Readiness. |
| Fora do produto | Pentest externo — não substituível por automação (Anexo D §17.1); é atividade humana agendada antes do GA. |
| Backlog | Tenancy hostil (T2), que exige arquitetura de isolamento diferente e novo threat model. |

## Dependencies

- **Hard:** M05, M06, M08, M10.
- **Soft:** M09, M11, M12.
- **Externas:** Performance Lab e Chaos/DR Lab provisionáveis por código; cluster multi-node.

## User-visible Outcome

Nenhum diretamente. O resultado é a **evidência** que permite a um operador decidir se a plataforma pode ir para produção — e o conhecimento de onde ela quebra antes de ela quebrar sozinha.

## Technical Outcome

- Envelope de capacidade conhecido e testado, em vez de “escala ilimitada”.
- Modos de degradação documentados por experimento.
- Regressão detectável: cada release candidate comparado com uma baseline compatível.
- Waivers explícitos, temporais e auditados para o que não puder ser resolvido.

## Architecture Impact

| Categoria | Impacto |
|---|---|
| Infrastructure | Performance Lab, Chaos/DR Lab, dataset de referência, harness de fault injection. |
| CI | Novos estágios: nightly ampliado e Release Candidate. |
| Observability | Relatórios de performance, chaos, security e upgrade como evidência de release. |
| Código | Correções pontuais; **nenhuma capacidade nova de produto**. |

## Security

M13 é a validação sistemática do Anexo C §21:

- **Auth/RBAC/IDOR**: troca de IDs entre Teams, escalação de papel, sessão/token revogados, invariantes de ownership.
- **Secrets**: redaction, controle de acesso, varredura de plaintext, tentativas de exfiltração.
- **SSRF**: metadata endpoints, loopback, ranges privados, DNS rebinding quando aplicável.
- **Webhooks**: assinatura inválida, replay, timestamp antigo, payload enorme.
- **Terminal/exec**: permissão, audit, timeout, isolamento de sessão.
- **Builder isolation**: docker.sock, rede de manager, Vault, metadata e host mounts.
- **Supply chain**: digest pinning, tag mutation, proteção de GC, promoção sem rebuild.
- **Rate/abuse**: login, token, webhook, build, deploy, logs e consultas caras.
- **Network**: portas do Swarm não expostas; restrições de acesso ao manager e ao executor.
- **Crypto/Recovery**: rotação, chave errada, tamper, backup + restore.

Regra do Milestone: **um finding Critical ou High sem mitigação bloqueia o GA da feature** (Anexo C §25).

## Observability

Cada suíte produz um relatório arquivável com o conteúdo exigido pelo Anexo D §24: commit, ambiente, topologia, parâmetros, resultado e disposição. Sem esses metadados, o resultado não é comparável e não conta como evidência.

## Testing

Este Milestone **é** testes. As classes e cadências seguem o Anexo D §20 e §24.

## Acceptance Criteria

1. Nenhum endpoint externo acessa a Docker API arbitrariamente.
2. Operações concorrentes críticas **não** corrompem o Desired State.
3. A API suporta a carga operacional alvo sem a fila colapsar.
4. A perda de um Worker, Ingress ou Manager dentro da tolerância **não** causa indisponibilidade global indevida.
5. Workload de build **não** compromete Manager nem Control Plane pelos mecanismos testados.
6. Rate limits e quotas impedem abuso óbvio de build, deploy e log streaming.
7. A recuperação de operação após restart é **determinística**.
8. A matriz cross-team/environment **não** encontra leitura ou mutação indevida.
9. A bateria de SSRF cobre **todas** as features que aceitam URL.
10. O scanner de plaintext não encontra secret em log, erro, evento, audit ou telemetria.
11. Os pisos de teste GA do Anexo B §9.1 são exercitados.
12. Chaos cobre node, manager/quorum, Traefik, DB, Registry e processo de deploy.
13. A compatibilidade N/N-1 é testada e as combinações suportadas são declaradas.
14. Os SLOs do Anexo B viram thresholds mensuráveis e automatizados.
15. Cada suíte produz relatório arquivável com topologia, dataset, versão e parâmetros.
16. `Critical = 0` e `High = 0`, ou waiver explícito, temporal, com dono e mitigação.

## Exit Gate

- [ ] Stories `required` `done`; 16 Acceptance Criteria com evidência.
- [ ] Todas as suítes de segurança verdes.
- [ ] Performance com margem definida aprovada contra a baseline.
- [ ] Chaos com invariantes preservadas em todos os experimentos.
- [ ] Upgrade N/N-1 verde.
- [ ] Relatórios arquivados como evidência de release.
- [ ] Critical = 0, High = 0 (ou waiver auditado e expirável).
- [ ] `MILESTONE_REPORT.md` com `Status: READY_FOR_REVIEW`.

**Gate humano: Scale Gate** (Anexo A §11).
