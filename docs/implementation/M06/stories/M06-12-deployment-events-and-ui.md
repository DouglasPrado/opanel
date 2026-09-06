# M06-12 — Deployment events, timeline and UI separation

## Objective
Tornar o deployment diagnosticável na própria tela, separando claramente falha de build, falha de rollout e degradação de runtime.

## Outcome
A tela do deployment mostra a timeline com duração por etapa, link para os build logs e para os runtime events — e nunca mistura os dois.

## References
- `docs/architecture/02-build-deploy.md` §18 (eventos, logs e auditoria), §20.2 (tela de deployment)
- `docs/architecture/10-ui-use-cases.md` §11.1, §11.2 (build logs separados de runtime events), §35 (critério de aceite)
- `docs/architecture/07-internal-control-plane.md` §17.2 (timeline)

## Preconditions
`M06-05` done.

## Scope
- `DeploymentEvent` append-only com os tipos do doc 02 §18.
- Timeline por etapa com duração, reconstruída do histórico persistido.
- Lista de deployments com status, source, artifact, actor, timing, environment e ações elegíveis.
- Tela de detalhe com: gatilho, commit, artifact, actor, timeline, e **links separados** para build logs e runtime events.
- Ações contextuais: rollback quando elegível, cancel quando seguro, promote quando aplicável.
- Estados universais e paginação por cursor.

## Out of Scope
- Métricas agregadas de deployment (`M09-15`).
- Incidentes (`M09-10`).
- Comparação entre Environments completa (`M06-09` traz o diff de promoção).

## Application Layer
- **Queries:** `DeploymentTimeline`, `DeploymentsForEnvironment`.

## UI Impact
Cumpre um critério de aceite explícito do doc 10 §35: **“UI diferencia Build failure, Deployment failure, Runtime degradation e Edge/DNS/TLS failure.”**

## Security Requirements
- Os eventos registram `SecretVersion` IDs, nunca valores (doc 02 §18, `CONFIG_RESOLVED`).
- Build logs são conteúdo não confiável e já vêm sanitizados de `M05-14`; a tela não os renderiza como ativo.
- O acesso respeita tenancy; negativo cross-team obrigatório.
- Erros exibidos usam o código estável e o `requestId`, sem detalhe interno.

## Observability Requirements
A timeline é **reconstruível após reload** a partir dos eventos persistidos — o stream entrega apenas novidades (doc 02 §18.1).

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Reload durante o deployment | Timeline reconstruída do histórico; nada se perde. |
| Falha de build | Mostrada como falha de **build**, com link para os logs; não confundida com falha de container. |
| Falha de rollout | Mostrada como falha de **rollout**, com os runtime events; sem obrigar a vasculhar o log de build. |
| Degradação após deploy saudável | Mostrada como runtime, não como falha do deployment. |
| Muitos eventos | Paginação por cursor. |
| Deployment de outro Team | Não listado nem acessível. |

## Acceptance Criteria
1. `DeploymentEvent` é append-only e cobre os tipos do doc 02 §18.
2. A timeline mostra duração por etapa e é **reconstruída do histórico** após reload.
3. A UI separa visualmente build logs de runtime events.
4. Falha de build, falha de rollout e degradação de runtime são apresentadas como **categorias distintas**.
5. As ações contextuais (rollback, cancel, promote) aparecem apenas quando elegíveis.
6. Os eventos registram `SecretVersion` IDs, nunca valores, provado com valor plantado.
7. Build logs não são renderizados como conteúdo ativo.
8. Listas usam paginação por cursor.
9. Erros mostram código estável e `requestId`, sem detalhe interno.
10. Deployment de outro Team não é listado nem acessível, provado por teste cross-team.
11. Estados universais estão implementados.
12. Acessibilidade AA verificada.

## Required Tests
- **unit (frontend)**: separação de categorias; timeline; estados universais.
- **integration**: reconstrução após reload; paginação.
- **security**: ausência de plaintext nos eventos; conteúdo de log não renderizado como ativo.
- **policy**: negativo cross-team.
- **E2E**: acompanhar um deployment do início ao fim, incluindo uma falha de build e uma falha de rollout.

## Quality Gates
Local Quality Gate + Reuse Gate + E2E.

## Definition of Done
Os 12 Acceptance Criteria satisfeitos, separação de categorias provada com falhas reais de cada tipo, Critical/High = 0.
