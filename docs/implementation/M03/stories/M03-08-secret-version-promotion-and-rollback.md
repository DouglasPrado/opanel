# M03-08 — Secret version promotion and binding rollback

## Objective
Tornar a atualização de uma secret em produção uma ação **explícita e auditável**, com rollout controlado e possibilidade de reverter o binding.

## Outcome
O ADMIN promove `v8` para produção; os Services afetados fazem rollout controlado; se algo falhar, o binding volta para `v7` sem editar nenhuma versão.

## References
- `docs/architecture/01-foundation.md` §9.4 (pinned por padrão; promoção como ação explícita)
- `docs/architecture/10-ui-use-cases.md` UC-031, §15.4
- `docs/architecture/05-backup-restore-dr.md` §21 (SecretVersion alterada incorretamente → rollback de binding)
- `docs/annexes/A-implementation-roadmap.md` §5 M8 (critérios de aceite)

## Preconditions
`M03-07` done.

## Scope
- Promoção: alterar o binding de produção para uma versão específica, com revisão do impacto antes de confirmar.
- Rollback de binding: voltar para a versão anterior; **nunca** editar uma versão existente.
- Operação composta quando múltiplos Services usam a mesma secret: status parcial por Service, sem mascarar falha.
- Rollout controlado por Service afetado, serializado pelo lease de cada um.
- Comparação entre Environments mostrando apenas **versões**, nunca valores.

## Out of Scope
- Promoção de Release (`M06-09`) — mecanismo diferente, mesmo vocabulário.
- Rotação da secret na origem (o provider externo) — RB-20, `M11`.
- Política de auto-promoção — `autoPromoteSecrets` permanece `false` em produção.

## Application Layer
- **Commands:** `PromoteSecretVersion`, `RollbackSecretBinding`.
- **Queries:** `SecretUsageAcrossEnvironments`.
- **Policies:** `vault.secret.promote`, tipicamente ADMIN; produção pode exigir mais.

## Async / Control Plane
A promoção é uma **operação composta**: uma Operation por Service afetado, agrupadas para acompanhamento. Falha em um Service **não** é mascarada pelo sucesso dos outros (doc 10 UC-031).

## UI Impact
Tela mostrando quem usa qual versão e o que mudará. Após confirmar, status por Service. Se um falhar, oferecer rollback daquele binding especificamente.

## Security Requirements
- A promoção **não** copia plaintext: altera apenas a referência de versão (doc 10 UC-031).
- Exige permissão específica; produção pode exigir role mais alta.
- AuditLog por Service afetado, com versão anterior e nova.
- Um Service que falha não fica em estado ambíguo: ou está na versão nova e saudável, ou é revertido, ou está visivelmente falho.

## Observability Requirements
- Operação composta com status por Service.
- AuditLog por binding alterado.
- Métrica: promoções por período, falhas parciais.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Múltiplos Services afetados, um falha | Status parcial explícito; **não** mascarar; oferecer rollback por Service. |
| Versão promovida quebra a aplicação | Rollback de binding para a anterior; nenhuma versão é editada. |
| Versão alvo indisponível | Bloquear antes de iniciar qualquer rollout. |
| Promoção concorrente com deploy | Serializada pelo lease do Service. |
| Rollback para versão apagada | Impossível: retenção impede apagar versão referenciada (`M03-05`). |

## Acceptance Criteria
1. Promover altera **somente** o binding alvo; nenhum plaintext é copiado.
2. A promoção gera rollout controlado nos Services afetados.
3. Com múltiplos Services, o status é **parcial e explícito**; a falha de um não é mascarada.
4. Rollback de binding volta para a versão anterior sem editar nenhuma `SecretVersion`.
5. Versão alvo indisponível bloqueia antes de qualquer rollout.
6. Promoção concorrente com outra operação no mesmo Service é serializada.
7. A comparação entre Environments mostra apenas versões, nunca valores.
8. Cada binding alterado gera AuditLog com versão anterior e nova.
9. A permissão de promoção é distinta de bind, e produção pode exigir mais.
10. Um Service que falha fica visivelmente falho ou revertido, nunca ambíguo.
11. Negativo cross-team passa.

## Required Tests
- **unit**: operação composta; status parcial.
- **integration**: falha em um Service com sucesso em outro; rollback de binding; versão indisponível bloqueando.
- **Docker/Swarm**: rollout real com troca de versão de secret; workload lendo o novo valor.
- **policy**: permissão de promoção; negativo cross-team.
- **security**: ausência de plaintext em toda a operação.

## Quality Gates
Local Quality Gate + suíte Docker/Swarm + `bin/security`.

## Definition of Done
Os 11 Acceptance Criteria satisfeitos, status parcial não mascarado, rollback provado sem editar versões, Critical/High = 0.
