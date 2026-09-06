# M06-10 — Deployment concurrency, supersession and cancellation

## Objective
Garantir que deploys concorrentes no mesmo Service nunca se sobreponham, e que uma revisão mais nova supere a anterior em vez de aplicar configuração obsoleta.

## Outcome
Dois pushes rápidos resultam em um único rollout, o da revisão mais nova; o anterior aparece como `SUPERSEDED` com link para quem o substituiu.

## References
- `docs/architecture/02-build-deploy.md` §16 (concorrência, locks e idempotência)
- `docs/architecture/07-internal-control-plane.md` §4 (revisions), §16 (cancelamento e supersession)
- `docs/annexes/D-test-strategy.md` §18 (dois deploys rápidos; scale durante deploy)

## Preconditions
`M06-04` done.

## Scope
- **Um deployment mutável por Service por vez**, garantido pelo lease de `M01-15`.
- Política de fila: enfileirar, superar ou rejeitar, conforme a configuração do Service.
- `SUPERSEDED` com link para o deployment que substituiu.
- Cancelamento: `QUEUED` cancela direto; em rollout, só no ponto seguro, e a intenção fica registrada.
- Interação com outras operações: scale durante deploy tem ordem definida e resultado final válido, sem lost update.
- Coalescing: uma rajada de triggers para o mesmo Service não gera N rollouts.

## Out of Scope
- Auto-deploy por webhook (`M06-11`) — que **usa** esta política.
- Cancelamento de build (`M05-15`).
- Quotas de deploy por Team (`M11-10`).

## Async / Control Plane
Esta Story resolve o cenário do doc 02 §16: fila com `#200 active`, `#201 queued`, `#202 queued` → ao terminar `#200`, reavaliar: superar `#201` e executar `#202`. A regra é **nunca aplicar configuração obsoleta**.

## Security Requirements
- A serialização é um controle de **integridade**: dois rollouts simultâneos no mesmo Service podem deixar o Swarm em estado que não corresponde a nenhuma revisão aprovada.
- Cancelar exige a mesma permissão de criar.
- Supersession é registrada; um deploy que “sumiu” sem explicação é indistinguível de um deploy perdido.

## Observability Requirements
Estado de fila por Service visível. Motivo de supersession explícito. Métrica: deploys superados, tempo em fila.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Dois deploys rápidos | O mais novo vence; o anterior fica `SUPERSEDED` com link. |
| Scale durante deploy | Ordem definida; estado final combina uma revisão válida, sem lost update. |
| Cancelamento em rollout | Intenção registrada; corte no ponto seguro; estado final consistente. |
| Rajada de triggers | Coalescing; não gerar N rollouts. |
| Lease expira no meio | Sucessor reobserva antes de agir. |
| Deploy enfileirado cuja Release virou inválida | Rejeitado ao ser desenfileirado, com causa. |

## Acceptance Criteria
1. Existe **um** deployment mutável por Service por vez, garantido por lease.
2. Um segundo deploy emitido **antes de o primeiro atingir estado terminal** resulta em um único rollout — o do mais novo; o anterior termina `SUPERSEDED` com link para quem o superou.
3. `SUPERSEDED` é sempre acompanhado do motivo e do substituto.
4. Scale durante deploy produz estado final válido sem lost update, provado por teste concorrente.
5. Cancelamento em `QUEUED` encerra sem efeito no runtime.
6. Cancelamento durante rollout registra a intenção e corta no ponto seguro.
7. Rajada de triggers é coalescida.
8. Lease expirado leva o sucessor a reobservar antes de agir.
9. Deploy enfileirado com Release inválida é rejeitado ao ser desenfileirado, com causa.
10. Cancelar exige a mesma permissão de criar.
11. Métricas de deploys superados e tempo em fila estão disponíveis.

## Required Tests
- **integration (concorrente, com barreira)**: dois deploys rápidos; scale durante deploy; lease expirado.
- **Docker/Swarm**: cancelamento durante rollout real.
- **unit**: política de fila; coalescing; elegibilidade de cancelamento.
- **policy**: permissão de cancelamento.

## Quality Gates
Local Quality Gate + suíte de concorrência + suíte Docker/Swarm.

## Definition of Done
Os 11 Acceptance Criteria satisfeitos, testes concorrentes determinísticos (com barreira, não repetição), Critical/High = 0.
