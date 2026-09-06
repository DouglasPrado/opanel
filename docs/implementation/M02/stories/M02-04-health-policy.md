# M02-04 — Configurable health policy and aggregated health model

## Objective
Deixar o usuário declarar o que significa “saudável” para o seu Service e combinar as camadas de sinal em um health agregado — reafirmando que **Running e Healthy são estados diferentes**.

## Outcome
O Service aceita health check HTTP, TCP, comando ou nenhum (com aviso); a plataforma combina o estado da Task, o health do container e a probe configurada em um status agregado.

## References
- `docs/architecture/03-runtime-observability.md` §3 (health model), §3.1 (camadas), §3.2 (configuração), §3.3 (readiness e liveness)
- `docs/architecture/02-build-deploy.md` §13 (health checks e elegibilidade para tráfego)
- `docs/architecture/09-data-model-apis-contracts.md` §5.3 (Service: healthcheck)

## Preconditions
`M02-01` done.

## Scope
- Health policy por Service: tipo (`HTTP`, `TCP`, `COMMAND`, `NONE`), path, porta, interval, timeout, start period, retries, status esperado.
- Respeitar o `HEALTHCHECK` da imagem quando existir; permitir override explícito pela plataforma.
- Health agregado combinando as camadas do doc 03 §3.1 disponíveis em M02: process/Task, container health e convergência desired × running.
- `NONE` permitido **apenas com aviso** explícito de que reduz a segurança do rollout.
- Distinção conceitual de readiness/liveness/startup registrada no modelo, mesmo que o Docker tenha um único conceito de health.

## Out of Scope
- Probe HTTP externa ao processo executada pela plataforma (doc 03 §3.1, camada “Application probe”) — depende de rede de observabilidade; entra em `M09`.
- Probe externa ao cluster (`M09`).
- Health de ingress (`M04-13`).
- Uso do health para gate de rollout com rollback automático (`M06-05`, `M06-06`).

## Application Layer
- **Commands:** `UpdateHealthPolicy`.
- **Queries:** `ServiceRuntimeView` com health agregado detalhado por camada.

## Async / Control Plane
Alterar a health policy é `ROLLOUT` quando muda a spec das Tasks. O reconciler aplica e re-inspeciona; o status agregado é recalculado a partir da observação.

## UI Impact
Formulário de health check com os campos do doc 03 §3.2 e explicação do impacto de `NONE`. O status mostra **por camada**, para diagnóstico: Task running? container healthy? réplicas convergiram?

## Security Requirements
- Health check do tipo `COMMAND` executa comando dentro do container — a entrada é validada e não pode ser usada para escapar do container nem alcançar o host.
- Health check `HTTP` aponta para porta interna do próprio Service; não é um mecanismo de requisição arbitrária (evita virar vetor de SSRF).
- Alterar health policy gera AuditLog.

## Observability Requirements
- O motivo de `DEGRADED` é explícito: qual camada falhou.
- Evento `HEALTH_DEGRADED` e `RECOVERED` emitidos conforme doc 03 §11.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Task running mas health falhando | `DEGRADED`, com a camada que falhou identificada. |
| Start period curto demais | A aplicação é marcada unhealthy durante a inicialização normal; a UI explica e sugere ajustar o start period. |
| `NONE` configurado | Permitido com aviso; o rollout perde a verificação e isso é dito explicitamente. |
| Comando de health inválido | Rejeitado na validação, antes de aplicar. |
| Health check apontando para host externo | Rejeitado — a probe é interna ao Service. |

## Acceptance Criteria
1. Health policy configurável por Service nos quatro tipos, com todos os campos do doc 03 §3.2.
2. O `HEALTHCHECK` da imagem é respeitado quando existe e pode ser sobrescrito explicitamente.
3. O health agregado combina as camadas disponíveis e identifica **qual** falhou.
4. Um Service com Task running e health falhando aparece como `DEGRADED`, nunca `HEALTHY`.
5. `NONE` é permitido apenas com aviso explícito registrado.
6. Comando de health inválido é rejeitado na validação.
7. Health check HTTP apontando para host externo é rejeitado.
8. Start period é respeitado: a aplicação não é marcada unhealthy durante a janela normal de inicialização.
9. Eventos `HEALTH_DEGRADED` e `RECOVERED` são emitidos.
10. Alterar a policy gera AuditLog e passa pelo negativo cross-team.

## Required Tests
- **unit**: agregação de health por camada; validação de configuração; start period.
- **integration**: eventos de degradação e recuperação.
- **Docker/Swarm**: health real falhando e recuperando; override do healthcheck da imagem.
- **security**: comando inválido rejeitado; probe para host externo rejeitada.

## Quality Gates
Local Quality Gate + suíte Docker/Swarm.

## Definition of Done
Os 10 Acceptance Criteria satisfeitos, `Running ≠ Healthy` provado com health real, probe externa rejeitada, Critical/High = 0.
