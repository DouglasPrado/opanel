# M09-09 — Alert instances, deduplication and expiring mute

## Objective
Impedir tempestade de alertas: uma condição contínua gera **um** alerta ativo, e o silenciamento sempre expira.

## Outcome
A mesma condição não notifica a cada coleta; o operador silencia um alerta informando escopo e prazo; após o prazo, o alerta volta.

## References
- `docs/architecture/03-runtime-observability.md` §12 (evitar notificar repetidamente a cada coleta)
- `docs/architecture/10-ui-use-cases.md` §18.2 (mute com escopo e expiração obrigatórios, auditado)
- `docs/architecture/09-data-model-apis-contracts.md` §13.1

## Preconditions
`M09-08` done.

## Scope
- `AlertInstance`: estado atual de uma regra para um recurso específico, com `firstFiredAt`, `lastEvaluatedAt`, valor observado e contagem.
- **Deduplicação**: enquanto a condição persiste, a instância é atualizada, não recriada.
- Histerese: threshold de disparo e de resolução distintos, para evitar flapping.
- **Silenciamento com expiração obrigatória**, escopo definido e auditoria.
- Resolução automática quando a condição volta ao normal.
- Histórico de alertas resolvidos com duração.

## Out of Scope
- Incidentes (`M09-10`).
- Notificações (`M09-11`).
- Escalonamento e on-call (fora do escopo).

## Application Layer
- **Commands:** `MuteAlert`, `UnmuteAlert`.
- **Queries:** `ActiveAlerts`, `AlertHistory`.
- **Policies:** silenciar exige permissão; em produção pode exigir mais.

## Security Requirements
- **Mute sem expiração é um ponto cego permanente.** A expiração é obrigatória (doc 10 §18.2, regra explícita) e o silenciamento é auditado.
- Silenciar um alerta `CRITICAL` de segurança exige registro e é destacado — o alerta some da tela, mas não do histórico.
- O escopo do mute é explícito: uma regra, um recurso, um período. Não existe “silenciar tudo”.
- Alertas respeitam tenancy.

## Observability Requirements
Alertas ativos por severidade; alertas silenciados com quem silenciou e até quando; taxa de flapping por regra.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Condição oscilando no limiar | Histerese evita flapping; a taxa de flapping é medida. |
| Condição persistente | Uma instância atualizada, não N notificações. |
| Mute sem expiração | **Rejeitado**. |
| Mute expirado com condição ainda ativa | Alerta volta a ficar visível. |
| Regra desabilitada com alerta ativo | Alerta resolvido com o motivo “regra desabilitada”, não simplesmente sumindo. |
| Métricas indeterminadas | A instância não resolve às cegas; fica com estado indeterminado. |

## Acceptance Criteria
1. `AlertInstance` mantém o estado por regra e recurso, com `firstFiredAt` e valor observado.
2. Uma condição persistente atualiza a instância existente; **não** gera notificações repetidas a cada coleta, provado por teste.
3. Existe histerese entre disparo e resolução, evitando flapping.
4. O silenciamento **exige expiração**; mute sem prazo é rejeitado.
5. O escopo do mute é explícito; não existe “silenciar tudo”.
6. Mute expirado com condição ativa faz o alerta voltar.
7. Silenciar é auditado; silenciar `CRITICAL` é destacado.
8. A resolução automática ocorre quando a condição volta ao normal, com duração registrada.
9. Regra desabilitada resolve o alerta com o motivo explícito.
10. Métricas indeterminadas não resolvem o alerta às cegas; o estado fica indeterminado.
11. Alertas respeitam tenancy; negativo cross-team passa.
12. A taxa de flapping por regra é medida.

## Required Tests
- **unit**: deduplicação; histerese; expiração de mute.
- **integration**: condição persistente sem notificações repetidas; mute expirando; regra desabilitada.
- **policy**: permissão de mute; negativo cross-team.
- **security**: mute sem expiração rejeitado; auditoria de mute.

## Quality Gates
Local Quality Gate + `bin/security`.

## Definition of Done
Os 12 Acceptance Criteria satisfeitos, ausência de tempestade provada, mute sempre expirável, Critical/High = 0.
