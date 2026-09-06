# M06-08 — Redeploy of the current release

## Objective
Reaplicar a release corrente com a configuração atual, sem mudar o artifact — útil quando a configuração mudou ou quando é preciso forçar a reconvergência.

## Outcome
O usuário aciona Redeploy; um novo Deployment é criado com o mesmo artifact e a configuração vigente; a UI acompanha até o desfecho.

## References
- `docs/architecture/02-build-deploy.md` §5 (trigger Redeploy: reexecuta usando o mesmo Artifact e configuração atual)
- `docs/architecture/03-runtime-observability.md` §4.2 (restart × redeploy)

## Preconditions
`M06-05` done.

## Scope
- Redeploy criando um novo `Deployment` com o mesmo `artifactId` e a **configuração atual** (que pode diferir da configuração da release original).
- Diferença explícita em relação ao Restart de `M02-01`: restart não altera configuração; redeploy **reaplica a configuração vigente**.
- Nova `Release` quando a configuração vigente diverge da release corrente — para preservar a imutabilidade.
- Mesmo ciclo de verificação de health e mesma política de rollout.

## Out of Scope
- Restart (`M02-01`).
- Rollback (`M06-06`, `M06-07`).
- Rebuild — redeploy nunca reconstrói.

## Application Layer
- **Commands:** `Redeploy`.
- **Policies:** `deployment.create`.

## Security Requirements
- Redeploy **não** reconstrói e **não** troca o artifact; qualquer implementação que o faça quebra a cadeia de evidência.
- Se a configuração vigente inclui `SecretVersion` diferente da release corrente, isso é visível **antes** de confirmar — o usuário precisa saber que está mudando credencial.
- Redeploy exige permissão e gera AuditLog.

## Observability Requirements
A UI mostra o que muda em relação à release corrente: nada, apenas configuração, ou também bindings de secret.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Artifact indisponível no Registry | Bloquear com causa; não tentar rebuild. |
| Configuração vigente inválida | Bloquear antes de aplicar. |
| Redeploy sem nenhuma diferença | Permitido: força reconvergência; a UI informa que nada mudou além do rollout. |
| Redeploy durante outro rollout | Serializado ou supersede. |
| `SecretVersion` vigente diferente | Mostrado antes de confirmar. |

## Acceptance Criteria
1. Redeploy cria um novo Deployment com o **mesmo** artifact.
2. A configuração aplicada é a **vigente**, não necessariamente a da release original.
3. Quando a configuração vigente diverge, uma nova `Release` é criada, preservando a imutabilidade.
4. Redeploy **nunca** reconstrói o artifact.
5. Diferença de `SecretVersion` em relação à release corrente é mostrada antes de confirmar.
6. Artifact indisponível bloqueia com causa, sem tentar rebuild.
7. Configuração vigente inválida bloqueia antes de aplicar.
8. Redeploy sem diferenças é permitido e informa que apenas força a reconvergência.
9. Redeploy durante outro rollout é serializado ou supersede.
10. Redeploy exige permissão, gera AuditLog e passa no negativo cross-team.

## Required Tests
- **unit**: decisão de criar nova Release; cálculo da diferença.
- **integration**: artifact indisponível; configuração inválida; redeploy sem diferenças.
- **Docker/Swarm**: redeploy real convergindo.
- **policy**: negativo cross-team.

## Quality Gates
Local Quality Gate + suíte Docker/Swarm.

## Definition of Done
Os 10 Acceptance Criteria satisfeitos, ausência de rebuild provada, diferenças visíveis antes de confirmar, Critical/High = 0.
