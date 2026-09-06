---
milestone: "M02"
name: "Runtime Operations & Drift Control"
type: "milestone"
status: "pending"
---

# M02 — Runtime Operations & Drift Control

## Identity

| Campo | Valor |
|---|---|
| **ID** | M02 |
| **Nome** | Runtime Operations & Drift Control |
| **Objetivo** | Tornar o workload **operável** depois de criado: reiniciar, ajustar recursos e placement, declarar health, detectar e corrigir drift, encerrar recursos com limpeza, e acompanhar tudo pelo Operations Center em tempo real. |
| **Resultado observável** | O operador reinicia um Service, altera CPU/RAM, define health check, escala para zero e volta; um `docker service scale` manual é **revertido** pela plataforma e registrado como drift; a deleção de um Environment remove os recursos no Swarm; o Operations Center mostra operações em andamento ao vivo. |

## Why

M01 provou que a plataforma **cria** um workload. M02 prova que ela **opera** um. Sem isto, qualquer Milestone posterior empilha capacidade sobre um runtime que não se corrige, não se apaga direito e não pode ser diagnosticado enquanto a operação acontece.

Drift detection é o item mais importante daqui: o doc 07 §8 estabelece Platform Wins como política padrão, e sem ela o Desired State deixa de ser autoridade na prática — o que invalidaria a premissa central da arquitetura.

M02 também entrega a infraestrutura de **feedback assíncrono** (Operations Center + SSE) que todas as capacidades seguintes vão reutilizar.

## Scope

- Restart de Service como `FORCE_ROLLOUT` auditável.
- Limits/reservations de CPU e memória, com presets de UI e aviso para service sem limite.
- Placement: constraints, preferences, `max replicas per node` e labels de node gerenciadas pela plataforma.
- Health policy configurável (HTTP/TCP/command/none) e health agregado.
- Restart policy e detecção de crash loop com causa provável.
- **Drift detection** com política Platform Wins e `DriftRecord`.
- **Adopt runtime state** como operação explícita de `INSTANCE_ADMIN`, nunca automática.
- Pause e scale-to-zero preservando configuração.
- Lifecycle de deleção de Service, Environment e Project com limpeza de runtime e tombstone.
- Operations Center: lista, detalhe, timeline, cancelamento e supersession.
- Realtime por SSE com reconexão por cursor e fallback de polling.
- Docker Events como **acelerador** de reconcile, com sweeps periódicos como garantia.
- `Idempotency-Key` na borda HTTP para mutações repetíveis.

## Out of Scope

| Deixado para | O quê |
|---|---|
| M03 | Vault, secrets e step-up authentication. |
| M04 | Traefik, domínios, TLS. |
| M05/M06 | Build, Release, Deployment, rollback e promoção — inclusive a política formal de rolling update com verificação de health. |
| M08 | Drain, promote/demote e remoção de node. |
| M09 | Métricas, logs históricos, alertas, incidentes, autoscaling e terminal. |
| M11 | Quotas que limitam réplicas e recursos. |

## Dependencies

- **Hard:** M01.
- **Soft:** nenhuma.

## User-visible Outcome

O operador consegue, sem SSH:
1. reiniciar um Service e ver as Tasks serem recriadas;
2. mudar CPU/RAM e ver o rollout controlado;
3. definir um health check e ver `Running ≠ Healthy` refletido;
4. identificar um crash loop com exit code, OOM e o que mudou antes;
5. escalar para zero e voltar sem perder configuração;
6. deletar um Environment e ver os recursos sumirem do Swarm;
7. ver uma alteração manual no Docker CLI ser **revertida** e registrada;
8. acompanhar toda operação em andamento no Operations Center, ao vivo.

## Technical Outcome

- `ServiceRuntimePolicy` com restart/health/resources/placement.
- `DriftRecord` com severidade e resolução.
- Diff classes completas: `NOOP`, `CREATE`, `UPDATE_SAFE`, `ROLLOUT`, `DELETE`, `BLOCKED`, `DRIFT`.
- Cancelamento e supersession expostos.
- Pipeline de eventos de produto → SSE, com histórico persistido reconstruindo a timeline após reload.
- `Idempotency-Key` com `UNIQUE(scope, idempotencyKey)` exercido na borda.

## Architecture Impact

| Categoria | Impacto |
|---|---|
| Entities | `ServiceRuntimePolicy`, `DriftRecord`, `RuntimeOperation`, `NodeMetadata` (labels), `inbox_events` (uso ampliado). |
| Commands | `RestartService`, `UpdateServiceResources`, `UpdateServicePlacement`, `UpdateHealthPolicy`, `PauseService`, `DeleteService`, `DeleteEnvironment`, `AdoptRuntimeState`, `CancelOperation`. |
| Queries | `OperationsFeed`, `ServiceRuntimeView` estendida, `DriftForResource`. |
| Events | `service.desired_state.changed.v1`, `service.drift.detected.v1`, `operation.status.changed.v1`. |
| Jobs | Ingestão de Docker Events, sweeps por cadência, detector de crash loop. |
| Reconcilers | Service Reconciler estendido com `DRIFT`, `DELETE` e `ROLLOUT`; Node Reconciler com labels. |
| UI | Operations Center, Runtime tab, Danger Zone, presets de recursos. |

## Security

- **Adopt runtime state** é operação privilegiada de `INSTANCE_ADMIN`, auditada, **nunca** automática (doc 07 §8.1).
- Toda ação de runtime — restart, scale, delete, mudança de resources — gera `AuditEvent` (doc 03 §18).
- Deleção usa confirmação proporcional ao risco; em `PRODUCTION`, confirmação reforçada com digitação do nome (doc 10 §26).
- Placement e labels de node são administrados pela plataforma, não strings arbitrárias vindas da UI (doc 03 §6).
- `Idempotency-Key` impede que retry de cliente vire mutação duplicada (Anexo C §16, “Duplicate delivery”).
- SSE respeita tenancy: um cliente só recebe eventos dos recursos que pode ler.
- Cancelamento é best-effort e **registrado**; nunca deixa o recurso em estado inconsistente sem sinalizar.

## Observability

- `DriftRecord` com `firstSeenAt`, `lastSeenAt`, severidade e resolução.
- Timeline de Operation completa e reconstruível após reload (histórico persistido, não só stream).
- Eventos de runtime do doc 03 §11 mapeados: `TASK_STARTED`, `TASK_FAILED`, `SERVICE_CONVERGED`, `OOM_DETECTED`, `HEALTH_DEGRADED`, `RECOVERED`.
- Crash loop expõe causa provável, último exit code, OOM quando detectável e o deployment/alteração que precedeu.
- Métrica: latência entre evento Docker e reconcile disparado (meta p95 ≤ 3 s, Anexo B §5).

## Testing

| Classe | Exigência |
|---|---|
| Unit | Diff `DRIFT`/`DELETE`/`ROLLOUT`; política de restart; detecção de crash loop; cadência de sweep. |
| Integration | `Idempotency-Key` concorrente; cancelamento; supersession; deleção com tombstone. |
| Contract | Envelope de eventos de produto no SSE; contrato de cancelamento. |
| Policy | Adopt runtime negado a não-`INSTANCE_ADMIN`; negativos cross-team em todas as novas mutações. |
| Docker/Swarm | Drift real via `docker service scale` manual; deleção real; restart real; health check real; eventos Docker. |
| E2E | Restart, mudança de recursos, scale-to-zero, deleção e drift revertido pela UI. |
| Security | Adopt auditado; ações destrutivas com confirmação; SSE respeitando tenancy. |

## Acceptance Criteria

1. Restart recria as Tasks sem alterar o artifact, como operação auditável.
2. Alterar CPU/RAM gera rollout controlado e converge.
3. Service sem limites explícitos é sinalizado.
4. Health policy configurável faz `Running ≠ Healthy` ser refletido corretamente.
5. Crash loop é detectado e apresenta causa provável, exit code e OOM quando disponível.
6. Uma alteração manual no Swarm é detectada como `DRIFT` e **revertida** por Platform Wins.
7. `DriftRecord` registra o que divergiu, desde quando, e como foi resolvido.
8. Adopt runtime state existe, exige `INSTANCE_ADMIN`, é auditado e **nunca** ocorre automaticamente.
9. Scale-to-zero preserva configuração, Release e bindings; voltar a N réplicas restaura o serviço.
10. Deletar Service/Environment remove os recursos correspondentes no Swarm e deixa tombstone; nenhum recurso órfão permanece.
11. Deleção com dependências ativas é bloqueada com explicação.
12. Operations Center lista operações running/failed/blocked com causa e permite cancelar quando seguro.
13. Cancelamento é best-effort, registrado, e nunca deixa estado inconsistente sem sinalização.
14. A UI recebe atualização por SSE em ≤ 2 s após a persistência, com fallback de polling.
15. Após reload, a timeline é reconstruída do histórico persistido, não do stream.
16. Docker Events aceleram o reconcile, e o sweep periódico continua corrigindo mesmo com o stream de eventos interrompido.
17. A mesma `Idempotency-Key` no mesmo escopo produz uma única operação lógica.
18. Todas as novas mutações têm negativo cross-team e AuditLog.

## Exit Gate

M02 pode assumir `READY_FOR_HUMAN_ACCEPTANCE` quando:

- [ ] todas as Stories `required: true` estão `done` com commit;
- [ ] os 18 Acceptance Criteria têm evidência no `MILESTONE_REPORT.md`;
- [ ] o teste de drift com alteração manual real no Swarm está verde;
- [ ] o teste de reconcile **com o stream de Docker Events desligado** está verde (prova que a corretude vem do sweep);
- [ ] a suíte Docker/Swarm e o E2E de operações estão verdes;
- [ ] `bin/fitness` verde, com AF-03 avaliando reconcilers reais;
- [ ] Critical = 0 e High = 0;
- [ ] `MILESTONE_REPORT.md` gerado.
