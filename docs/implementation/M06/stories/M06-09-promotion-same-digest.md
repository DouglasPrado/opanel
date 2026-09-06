# M06-09 — Promotion HML → PROD reusing the exact same digest

## Objective
Eliminar a classe de erro “o que testamos em homologação não é exatamente o que foi para produção”, promovendo o **mesmo artefato** em vez de reconstruir.

## Outcome
O usuário abre um deployment saudável em homologação, clica em Promote, revisa o diff de configuração, confirma — e produção passa a rodar **o mesmo digest**.

## References
- `docs/architecture/02-build-deploy.md` §15 (promoção HML → Produção), §15.1 (fluxo de UX)
- `docs/architecture/10-ui-use-cases.md` UC-019, §11.3
- `docs/annexes/C-threat-model-security-hardening.md` §11 (regra de promoção: rebuildar quebra a cadeia de evidência)
- `docs/annexes/B-nfr-slos.md` §6 (promotion não rebuilda)

## Preconditions
`M06-07` e `M06-14` done.

## Scope
- Promoção a partir de um deployment saudável de origem, escolhendo o Environment de destino.
- Correspondência de Service entre Environments por `serviceLineage` (`M06-14`).
- **Diff de configuração** apresentado antes de confirmar: replicas, recursos, `SecretVersion` por binding, domínios.
- **Valores específicos do destino são preservados por padrão** (doc 10 UC-019): produção mantém suas réplicas, seus recursos e suas versões de secret.
- Criação de `Release` no destino referenciando **o mesmo `artifactId`/digest**.
- `Promotion` ligando o deployment de origem ao de destino, para auditoria.
- Deployment no destino com sua própria política de rollout.

## Out of Scope
- Promoção de `SecretVersion` (`M03-08`) — mecanismo diferente, disparado separadamente.
- Approval humano formal antes de promover (`M12-09` traz o modelo de approval; a policy de produção fica pronta em `M11-08`).
- Promoção entre clusters diferentes — funciona por construção, mas a validação de compatibilidade é de M08.

## Application Layer
- **Commands:** `PromoteRelease`.
- **Queries:** `PromotionDiff`, `PromotionCandidates`.
- **Policies:** `deployment.promote`; produção pode exigir role mais alta.

## Security Requirements
- **Promoção nunca rebuilda** (Anexo C §11, regra explícita). Rebuildar cria um artefato novo e destrói a cadeia de evidência entre o que foi testado e o que está em produção.
- O digest promovido é **verificado** contra o de origem antes de criar a Release de destino; divergência é falha de integridade.
- Secrets de produção **não** são substituídas pelas de homologação: os bindings do destino são preservados por padrão.
- Promoção exige permissão específica; em produção pode exigir role mais alta e, futuramente, approval.
- A `Promotion` registra origem, destino, digest e actor — é a evidência de supply chain que liga os dois ambientes.
- AuditLog obrigatório.

## Observability Requirements
Evento de promoção com origem, destino e digest. Timeline do deployment de destino. Métrica de promoções por período e por resultado.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| `serviceLineage` ausente | Pedir target manual ou bloquear (doc 10 UC-019). |
| Digest divergente entre origem e destino | Falha de integridade; **parar**. |
| `SecretVersion` de produção indisponível | Bloquear antes do rollout. |
| Deployment de origem não saudável | Bloquear; só se promove o que foi validado. |
| Artifact não acessível pelo cluster de destino | Bloquear com o teste de pull por node (`M05-11`). |
| Policy de produção exige aprovação | Estado “aguardando aprovação” quando o recurso existir; hoje, bloqueio com causa. |

## Acceptance Criteria
1. A promoção usa **exatamente o mesmo digest** do artefato de origem, verificado antes de criar a Release de destino.
2. Nenhum rebuild ocorre durante a promoção, provado por teste que falha se um Build for criado.
3. O diff de configuração é apresentado antes de confirmar.
4. Valores específicos do destino (replicas, recursos, `SecretVersion`) são **preservados por padrão**.
5. A correspondência entre Services usa `serviceLineage`; sem ela, pede target manual ou bloqueia.
6. Deployment de origem não saudável bloqueia a promoção.
7. `SecretVersion` de produção indisponível bloqueia antes do rollout.
8. Artifact inacessível pelo cluster de destino bloqueia.
9. Digest divergente entre origem e destino é falha de integridade e interrompe a operação.
10. `Promotion` registra origem, destino, digest e actor.
11. O deployment de destino usa a **própria** política de rollout.
12. Promoção exige permissão; produção pode exigir mais; AuditLog e negativo cross-team passam.

## Required Tests
- **E2E**: promoção HML→PROD com comparação byte a byte do digest nos dois ambientes.
- **integration**: ausência de Build criado durante a promoção; preservação dos valores do destino; lineage ausente.
- **Docker/Swarm**: rollout no destino com a política própria.
- **security**: digest divergente interrompendo; secrets de produção preservadas.
- **policy**: negativo cross-team; permissão de produção.

## Quality Gates
Local Quality Gate + suíte Docker/Swarm + E2E + `bin/security`. **Story crítica: é a invariante central do Milestone.**

## Definition of Done
Os 12 Acceptance Criteria satisfeitos, digest idêntico comprovado nos dois ambientes, ausência de rebuild provada, Critical/High = 0.
