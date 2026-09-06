# M08-10 — LoadBalancerProvider abstraction and target lifecycle

## Objective
Integrar o Load Balancer externo L4 como provider desacoplado, mantendo os targets de ingress sincronizados com o estado real dos gateways.

## Outcome
Adicionar um ingress node adiciona o target no LB **após** o Traefik ficar saudável; remover um ingress retira o target **antes** de derrubar o workload.

## References
- `docs/architecture/01-foundation.md` §7 (integração com Load Balancer), §7.1 (health checks), §7.2 (abstração de provider)
- `docs/architecture/06-infrastructure-provisioning.md` §10 (Load Balancer Provider), §10.3 (modos)
- `docs/architecture/08-networking-domains-edge.md` §8 (LB externo em L4), §8.2 (interface)
- `docs/annexes/D-test-strategy.md` §6.3 (contract de Load Balancer)

## Preconditions
`M08-04` done.

## Scope
- Contrato `LoadBalancerProvider`: `ensureLoadBalancer`, `addTarget`, `removeTarget`, `listTargets`, `configureListener`, `configureHealthCheck`, `health`, `delete`.
- Modos do doc 06 §10.3: `MANAGED`, `EXTERNAL`, `MANUAL`, `SINGLE-NODE`.
- `LoadBalancer` e `LoadBalancerTarget` no modelo.
- **Ordem obrigatória**: adicionar target só depois de o Traefik estar saudável; remover target **antes** de encerrar o workload (doc 01 §7.1).
- Reconciliação de targets: o conjunto no provider converge para o conjunto de ingress saudáveis.
- Credencial do provider no Vault, com escopo mínimo.
- Modo `MANUAL`: a plataforma **mostra** os targets esperados em vez de aplicá-los.

## Out of Scope
- Ingress HA e quorum de certificado (`M08-11`).
- Providers adicionais além do primeiro — o contrato permite; cada um é Story própria.
- DNS failover por mudança de endpoint (doc 06 §11.1; sem requisito imediato).

## Application Layer
- **Providers:** `LoadBalancerProvider`.
- **Reconciler:** `LoadBalancerReconciler`.
- **Commands:** `EnsureLoadBalancerTargets`.

## Security Requirements
- Credencial do provider no Vault, escopo mínimo, nunca retornada ao frontend.
- Todas as chamadas passam pela política de SSRF de `M04-07`.
- **O LB opera em L4/TCP**: o TLS termina no Traefik, mantendo a gestão de certificados independente do provider (doc 01 §7). O provider **não** recebe chave privada.
- A ordem de add/remove é um controle de disponibilidade: inverter derruba conexões (doc 01 §7.1).
- Erros do provider são normalizados; a resposta bruta não vaza.
- Operações no LB geram AuditLog.

## Observability Requirements
Targets esperados × observados no provider; health de cada target; divergência visível. Métrica de operações no LB por resultado.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Provider indisponível | Targets atuais continuam atendendo; mudanças de membership ficam bloqueadas até reconciliar (doc 06 §21). |
| Target adicionado antes de o Traefik ficar saudável | Impossível pela ordem; o teste guarda a propriedade. |
| Ingress removido sem retirar o target | Impossível pela ordem; conexões seriam derrubadas. |
| Divergência entre plataforma e provider | Reconciliada; se não for possível, reportada com destaque. |
| Modo `MANUAL` | Mostrar targets esperados; não tentar aplicar. |
| Credencial inválida | Erro classificado; a UI oferece reconectar. |

## Acceptance Criteria
1. O contrato `LoadBalancerProvider` existe com as oito operações e um adapter concreto.
2. Os quatro modos (`MANAGED`, `EXTERNAL`, `MANUAL`, `SINGLE-NODE`) são representáveis.
3. O target é adicionado **somente após** o Traefik daquele node estar saudável, provado por teste.
4. O target é removido **antes** de o workload de ingress ser encerrado, provado por teste.
5. O conjunto de targets converge para o conjunto de ingress saudáveis por reconciliação.
6. Provider indisponível não derruba targets existentes; mudanças ficam bloqueadas com causa.
7. Divergência entre plataforma e provider é reconciliada ou reportada com destaque.
8. Modo `MANUAL` mostra os targets esperados sem tentar aplicá-los.
9. A credencial vive no Vault, com escopo mínimo, e não é retornada ao frontend.
10. Todas as chamadas passam pela política de SSRF.
11. O provider **não** recebe chave privada de certificado; o TLS termina no Traefik.
12. Operações no LB geram AuditLog; negativo cross-team passa.

## Required Tests
- **contract**: add/remove/list/health de target; idempotência; erro de provider; rate limit.
- **integration**: ordem de add após health e remove antes de encerrar; provider indisponível; divergência reconciliada.
- **security**: SSRF; credencial protegida; ausência de chave privada no provider.

## Quality Gates
Local Quality Gate + contract tests + `bin/security`.

## Definition of Done
Os 12 Acceptance Criteria satisfeitos, ordem de add/remove provada, TLS mantido no Traefik, Critical/High = 0.
