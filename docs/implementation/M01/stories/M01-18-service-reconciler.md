# M01-18 — Service Reconciler: inspect → diff → apply → verify

## Objective
Converter um Service persistido em um **Docker Swarm Service real** e manter desired e actual state convergentes, de forma idempotente e retomável.

## Outcome
Criar um Service com imagem existente resulta em um Swarm Service rodando com labels de ownership; repetir a operação não duplica nada; uma resposta perdida do Docker leva a reobservação, nunca a repetição cega.

## References
- `docs/architecture/07-internal-control-plane.md` §11 (reconcilers), §11.3 (algoritmo), §11.4 (classes de diff), §13 (fluxo de deploy)
- `docs/architecture/02-build-deploy.md` §11 (criação/atualização do Swarm Service)
- `docs/architecture/03-runtime-observability.md` §2 (modelo de runtime), §5 (recursos)
- `docs/annexes/D-test-strategy.md` §7 (Docker/Swarm integration), §7.1 (teste do reconciler)

## Preconditions
`M01-17` done.

## Scope
- **Service Reconciler** com o mesmo algoritmo de `M01-17`, agora sobre o recurso central.
- Tradução do Desired State em Service Spec do Swarm: image por **digest**, env não sensível, networks (overlay do Environment), replicas, resources, placement básico, healthcheck, update policy, labels de ownership.
- Classes de diff: `NOOP`, `CREATE`, `UPDATE_SAFE`, `ROLLOUT`, `BLOCKED`. (`DELETE` entra em `M02-09`; `DRIFT` em `M02-06`.)
- Idempotência do doc 07 §6.2: `Create` procura primeiro por labels de ownership; `Update` aplica a revisão desejada, não uma sequência imperativa cega.
- Tratamento de `Unknown outcome`: **observar o actual state antes de repetir** qualquer efeito não idempotente.
- Trigger por Operation; sweep periódico como garantia de corretude.

## Out of Scope
- Rolling update com verificação de health e rollback automático (`M06-04`, `M06-05`, `M06-06`) — em M01 o Service é criado e escala; a política de rollout formal é de M06.
- Drift detection ativa (`M02-06`).
- Secrets (`M03-07`) e domínios (`M04`).
- Deleção (`M02-09`).
- Restart e mudança de resources pela UI (`M02-01`, `M02-02`).

## Application Layer
- **Reconciler:** `ServiceReconciler`.
- **Commands:** os de `M01-12` passam a gerar Operations que este reconciler consome.
- O reconciler **não** altera intenção do usuário (AF-03) e não decide autorização.

## Async / Control Plane
Fluxo completo, pela primeira vez de ponta a ponta:
```text
UI → Command → Desired State + Operation + Outbox (1 transação)
   → Dispatcher → Worker → Lease + Fencing
   → Reconciler: inspect → diff → apply (Executor) → re-inspect
   → appliedRevision + Operation SUCCEEDED
```
Nenhuma etapa mantém requisição HTTP aberta.

## Security Requirements
- Todo acesso ao Docker passa pelo Swarm Executor (AF-01, AF-02).
- O Service criado **não** publica porta pública: exposição só existe a partir de M04, via ingress.
- O Service não recebe montagem de socket, host mount nem privilégio elevado (Anexo C §9: `privileged` DENY, host mounts DENY, docker socket DENY por padrão).
- Nenhum valor sensível vai para env do Service nesta Story — variáveis sensíveis são Vault (M03).
- Labels de ownership obrigatórias; sem elas o recurso não é reconciliável.

## Observability Requirements
- `ReconciliationRun` com diff, ações, resultado e `nextCheckAt` quando ainda não convergiu.
- Logs com `service_id`, `environment_id`, `operation_id` e a revisão alvo.
- Cadência do doc 07 §23: rápida durante rollout, minutos quando estável.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Imagem inexistente no registry | `BLOCKED`/falha contextual com causa; **não** retry agressivo. |
| Placement impossível | `BLOCKED` com diagnóstico do que impede o agendamento. |
| Resposta do Docker perdida | Re-inspeção antes de qualquer repetição. Teste obrigatório. |
| Conflito de `Version.Index` no update | `CONFLICT`; reobservar e recalcular o diff. |
| Reconciler reiniciado no meio | Retomada idempotente; nenhum Service duplicado. |
| Desired state mudou durante a aplicação | A revisão antiga vira `SUPERSEDED`; reconcilia direto para a mais nova. |
| Service já existe com ownership | `NOOP` ou `UPDATE_SAFE`, nunca `CREATE` duplicado. |

## Acceptance Criteria
1. Criar um Service com imagem existente resulta em um **Docker Swarm Service real**, com labels de ownership.
2. A imagem é referenciada por **digest**, não apenas por tag.
3. O Service é anexado à overlay network do seu Environment e **não** publica porta pública.
4. Executar o reconciler duas vezes é idempotente: a segunda resulta em `NOOP`.
5. Uma resposta perdida do Docker leva a **reobservação** antes de qualquer repetição, provado por teste com fault injection.
6. Conflito de versão no update resulta em `CONFLICT`, reobservação e recálculo do diff.
7. Reiniciar o reconciler no meio da operação não duplica recurso, provado contra Swarm real.
8. Uma revisão mais nova durante a execução marca a anterior `SUPERSEDED` e converge para a mais nova.
9. Imagem inexistente ou placement impossível resultam em `BLOCKED` com causa observável, sem retry agressivo.
10. `appliedRevision` avança apenas após re-inspeção confirmar o estado.
11. Nenhum acesso ao Docker acontece fora do Executor (AF-01, AF-02).
12. O Service não recebe `privileged`, host mount nem docker socket.
13. Cada execução persiste `ReconciliationRun` com diff, ações e resultado.

## Required Tests
- **unit**: cálculo de diff por classe; tradução Desired State → Service Spec; supersession.
- **integration**: `appliedRevision` após confirmação; `ReconciliationRun`.
- **Docker/Swarm**: create real; idempotência; update com conflito de versão; reconciler reiniciado no meio; imagem inexistente; placement impossível; **resposta perdida do Docker**.
- **security**: AF-01/AF-02; ausência de porta pública, `privileged`, host mount e socket.

## Quality Gates
Local Quality Gate + `bin/fitness` + suíte Docker/Swarm completa. **Story crítica: exige plan mode** — é o coração da reconciliação.

## Definition of Done
Os 13 Acceptance Criteria satisfeitos contra Swarm real, os quatro cenários de falha distribuída provados (resposta perdida, conflito, restart, supersession), Critical/High = 0.
