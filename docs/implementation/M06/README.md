---
milestone: "M06"
name: "Release, Deployment, Rollback & Promotion"
type: "milestone"
status: "pending"
---

# M06 — Release, Deployment, Rollback & Promotion

## Identity

| Campo | Valor |
|---|---|
| **ID** | M06 |
| **Nome** | Release, Deployment, Rollback & Promotion |
| **Objetivo** | Fechar o ciclo de entrega imutável: transformar um Artifact em `Release`, aplicá-lo por `Deployment` com rolling update verificado por health, e permitir rollback e promoção HML→PROD **sem rebuild**. |
| **Resultado observável** | Um `git push` chega a `HEALTHY` em produção; um deploy ruim é revertido para a release anterior em segundos; a mesma imagem testada em homologação é promovida para produção com o **mesmo digest**. |

## Why

M05 produziu artefatos que ninguém implanta. M06 é o Milestone que entrega a promessa central do produto: **build once, deploy many**.

Ele elimina a classe de erro “o que testamos em homologação não é exatamente o que foi para produção” (doc 02 §15.1) e estabelece o rollback como operação de segundos, não de reconstrução.

M06 desbloqueia M09 (há deployments para observar), M10 (Clean Rebuild recria Services a partir de Releases por digest) e M12 (tools de delivery do MCP).

## Scope

- `Release` imutável: Artifact por digest + snapshot da configuração de execução + referências de `SecretVersion` — **sem plaintext**.
- `Deployment` com state machine, gatilhos (manual, push, redeploy, rollback, promote, API) e proveniência.
- Resolução de configuração e materialização de secrets como etapas explícitas do deployment.
- Rolling update com política configurável: `order`, `parallelism`, `delay`, `monitor`, `failureAction`, `maxFailureRatio`.
- **Verificação de health** como condição de sucesso: Docker aceitar o update não é suficiente.
- Rollback automático por política e rollback manual para release anterior.
- Redeploy da release corrente.
- **Promoção HML→PROD reutilizando o mesmo digest**, com diff de configuração antes de confirmar.
- Serialização por Service, supersession e cancelamento.
- Auto-deploy a partir do webhook, com `watchPaths` e coalescing.
- `DeploymentEvent` e timeline, com build logs separados de runtime events.
- Proteção de retenção: um Artifact referenciado não pode ser coletado.
- `serviceLineage` para casar Services entre Environments na promoção.

## Out of Scope

| Deixado para | O quê |
|---|---|
| M07 | Domínios customizados. |
| M09 | Métricas, alertas e autoscaling reagindo a deployments. |
| M10 | Snapshots e Clean Rebuild que consomem Releases. |
| M12 | Tools MCP de deploy/rollback/promote. |
| Backlog | Canary, blue-green e traffic splitting avançados. |

## Dependencies

- **Hard:** M02 (rollout e drift), M03 (materialização de secrets), M05 (Artifact por digest).
- **Soft:** M04 — domínio ativo torna o resultado demonstrável de ponta a ponta.

## User-visible Outcome

1. `git push` → build → deploy → `HEALTHY`, com timeline mostrando cada etapa e sua duração.
2. Deploy ruim → rollback em segundos, sem rebuild.
3. Release validada em homologação → promoção para produção com o **mesmo digest**, com o diff de configuração visível antes de confirmar.
4. Dois pushes rápidos → o mais novo vence; o anterior fica `SUPERSEDED` e a UI explica.

## Technical Outcome

- Artifact → Release → Deployment com proveniência completa.
- Deployment converge só quando o runtime confirma; nunca por otimismo.
- Rollback e promoção operam sobre artefatos existentes; nenhum rebuild.
- Concorrência resolvida por lease, supersession e política de fila.

## Architecture Impact

| Categoria | Impacto |
|---|---|
| Entities | `Release`, `Deployment`, `DeploymentEvent`, `Promotion`, `ServiceLineage`, `ArtifactRetentionLock`. |
| Commands | `CreateRelease`, `RequestDeployment`, `Redeploy`, `Rollback`, `PromoteRelease`, `CancelDeployment`. |
| Queries | `DeploymentsForService`, `DeploymentDetail`, `PromotionDiff`, `RollbackCandidates`. |
| Events | `deployment.requested.v1`, `deployment.healthy.v1`, `deployment.failed`, `release.promoted`. |
| Operations | `DEPLOY`, `ROLLBACK`, `PROMOTE`. |
| Reconcilers | `DeploymentReconciler` confirmando rollout, health, timeout e rollback. |
| UI | Deployments list/detail, build logs × runtime events, promotion, rollback. |

## Security

- **Deploy por digest imutável** — mitigação de T08 (imagem/tag trocada após aprovação).
- **Promoção não rebuilda**: rebuildar cria artefato novo e quebra a cadeia de evidência (Anexo C §11, regra de promoção).
- `Release` referencia `SecretVersion` **IDs**, nunca plaintext (doc 02 §10).
- Deploy em produção exige permissão específica; a policy de Environment pode exigir mais (`M11-08`).
- Rollback e promoção geram AuditLog com origem e destino.
- Artifact referenciado por Release ativa, rollback candidate ou snapshot **não pode ser removido** pelo GC (doc 05 §8.1).
- Auto-deploy por webhook herda todas as defesas de `M05-04`; um webhook forjado não pode disparar deploy.
- Nenhuma requisição HTTP fica aberta durante o rollout.

## Observability

- Timeline do doc 07 §17.2 com marcos e duração por etapa.
- Eventos do doc 02 §18: `DEPLOYMENT_CREATED`, `BUILD_STARTED`, `ARTIFACT_PUBLISHED`, `CONFIG_RESOLVED`, `SERVICE_UPDATE_STARTED`, `TASK_HEALTHY`, `ROLLBACK_STARTED`, `DEPLOYMENT_HEALTHY`.
- Separação obrigatória: falha de build ≠ falha de rollout ≠ degradação de runtime (doc 10 §35).
- Métricas do Anexo B §6: deploy de artefato existente p95 ≤ 2 min até `HEALTHY`; rollback p95 ≤ 90 s; **nunca** ficar indefinidamente em `DEPLOYING`.
- Medição separada de “tempo de infraestrutura” e “tempo esperando a aplicação ficar saudável”.

## Testing

| Classe | Exigência |
|---|---|
| Unit | State machine de Deployment; política de rollout; elegibilidade de rollback; diff de promoção. |
| Integration | Boundary transacional de Release+Deployment+Operation+Outbox; supersession; retenção protegendo Artifact. |
| Contract | `deployment.requested.v1`, `deployment.healthy.v1`; API assíncrona retornando `operationId`. |
| Docker/Swarm | Rolling update com múltiplas réplicas; health falhando durante rollout; rollback automático e manual; restart do Control Plane no meio do rollout. |
| E2E | Push → deploy → healthy; rollback; promoção HML→PROD com mesmo digest. |
| Security | Deploy por digest; promoção sem rebuild; webhook forjado não dispara deploy; permissão de produção. |

## Acceptance Criteria

1. `Release` é imutável e referencia Artifact por digest, configuração e `SecretVersion` IDs — sem plaintext.
2. Deployment referencia Artifact digest imutável.
3. O rollout só conclui como saudável após o runtime/health confirmarem.
4. Docker aceitar o update **não** marca sucesso.
5. Falha no rollout leva a `FAILED` ou `ROLLED_BACK` conforme política, com causa observável.
6. Um deployment **nunca** fica indefinidamente em `DEPLOYING`: o watchdog o marca `STALLED`.
7. Rollback reaplica a release anterior **sem rebuild**.
8. Promoção HML→PROD usa **exatamente o mesmo digest**.
9. A promoção mostra o diff de configuração antes de confirmar e preserva os valores específicos do destino.
10. Webhook duplicado para o mesmo commit **não** gera deploys redundantes fora da política.
11. `watchPaths` evita deploy quando o commit não toca o Service.
12. Dois deploys rápidos: o mais novo vence; o anterior fica `SUPERSEDED`.
13. Restart do Control Plane no meio do rollout não perde a intenção nem duplica efeito.
14. A UI separa build logs de runtime events.
15. Um Artifact referenciado por Release, Deployment ou rollback candidate não pode ser coletado.
16. Deploy em produção exige permissão específica; negativo cross-team passa.

## Exit Gate

- [ ] Stories `required` `done`; 16 Acceptance Criteria com evidência.
- [ ] E2E de push → deploy → healthy verde.
- [ ] E2E de rollback verde, com tempo medido.
- [ ] E2E de promoção HML→PROD verde, com **prova de que o digest é idêntico**.
- [ ] Teste de health falhando durante rollout verde (sem falso sucesso).
- [ ] Teste de restart do Control Plane durante rollout verde.
- [ ] Teste de webhook duplicado/fora de ordem verde.
- [ ] `bin/fitness`, `bin/security` verdes; Critical = 0, High = 0.
- [ ] `MILESTONE_REPORT.md` gerado.

**Gate humano: Delivery Gate.** Corresponde ao gate do Anexo A §11.
