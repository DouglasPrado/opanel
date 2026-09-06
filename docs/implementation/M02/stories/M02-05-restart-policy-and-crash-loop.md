# M02-05 — Restart policy and crash loop detection

## Objective
Expor a restart policy do Swarm como política de produto e detectar padrões de crash loop, apresentando causa provável em vez de obrigar o usuário a correlacionar dezenas de Tasks antigas.

## Outcome
O usuário configura condition, delay, maxAttempts, window e stopGracePeriod; quando um Service entra em crash loop, a UI mostra o padrão, o último exit code, OOM quando detectável e a alteração que o precedeu.

## References
- `docs/architecture/03-runtime-observability.md` §4 (restart, self-healing e convergência), §4.1 (restart policy), §4.3 (crash loop), §11 (eventos de runtime)
- `docs/architecture/09-data-model-apis-contracts.md` §5.3

## Preconditions
`M02-04` done.

## Scope
- Restart policy configurável: `condition`, `delay`, `maxAttempts`, `window`, `stopGracePeriod`.
- Detecção de crash loop: N reinícios em janela configurável.
- Diagnóstico agregado: último exit code, `OOMKilled` quando disponível, contagem de restarts, nodes envolvidos e a última alteração de desired state anterior ao início do padrão.
- Eventos `TASK_FAILED`, `OOM_DETECTED` e a marcação do padrão de crash loop.
- Regra explícita: a plataforma **não** constrói um supervisor paralelo — o Swarm continua reconciliando; a plataforma observa, agrega e explica.

## Out of Scope
- Alertas e incidentes formais (`M09-08`, `M09-10`).
- Aumentar limite de memória automaticamente após OOM — proibido sem política explícita (doc 03 §17).
- Rollback automático por crash loop (`M06-06`).

## Application Layer
- **Commands:** `UpdateRestartPolicy`.
- **Queries:** `ServiceCrashDiagnosis`.

## Async / Control Plane
A detecção roda sobre as observações de `M01-19` e sobre os eventos de `M02-12`. É derivada e reconstruível; nenhum estado vive só em memória de processo.

## UI Impact
Bloco de diagnóstico na página do Service quando há crash loop: padrão detectado, exit code, OOM, e link para a alteração/deployment que precedeu.

## Security Requirements
- O diagnóstico não expõe conteúdo de variáveis de ambiente nem de secrets, mesmo quando eles são a causa provável — indica **que** a configuração mudou, com a referência de versão, nunca o valor.
- Alterar restart policy exige permissão e gera AuditLog.

## Observability Requirements
- Evento `OOM_DETECTED` quando o runtime fornecer o sinal.
- Contagem de restarts por janela disponível como métrica base para `M09`.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Crash loop iniciado após mudança de configuração | O diagnóstico aponta a alteração anterior ao padrão. |
| OOM recorrente | Alertar; **não** aumentar limite automaticamente. |
| Falha só em um node | O diagnóstico distingue “problema do workload” de “problema daquele host”. |
| `maxAttempts` atingido | O Swarm para de tentar; a plataforma explica que a política foi exaurida, não que “sumiu”. |
| Sinal de OOM indisponível no runtime | O diagnóstico diz que o sinal não está disponível, em vez de omitir. |

## Acceptance Criteria
1. Restart policy é configurável nos cinco campos e aplicada ao Service.
2. Crash loop é detectado por N reinícios em janela configurável.
3. O diagnóstico apresenta último exit code, OOM quando disponível, contagem de restarts e nodes envolvidos.
4. O diagnóstico aponta a última alteração de desired state anterior ao início do padrão.
5. Falha concentrada em um único node é distinguida de falha do workload.
6. `maxAttempts` exaurido é explicado explicitamente na UI.
7. OOM recorrente **não** aumenta o limite automaticamente.
8. O diagnóstico nunca expõe valor de variável de ambiente ou secret.
9. Sinal de OOM indisponível é reportado como indisponível, não omitido.
10. Alterar a policy gera AuditLog; negativo cross-team passa.

## Required Tests
- **unit**: detecção de padrão por janela; correlação com a última alteração; distinção por node.
- **integration**: diagnóstico agregado a partir de observações e eventos.
- **Docker/Swarm**: container que falha repetidamente; container morto por OOM quando o ambiente permitir simular.
- **security**: ausência de valor de env/secret no diagnóstico.

## Quality Gates
Local Quality Gate + suíte Docker/Swarm.

## Definition of Done
Os 10 Acceptance Criteria satisfeitos, diagnóstico correlacionando a alteração anterior, nenhum valor sensível exposto, Critical/High = 0.
