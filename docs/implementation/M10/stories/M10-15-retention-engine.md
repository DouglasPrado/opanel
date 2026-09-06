# M10-15 — Retention engine and protected recovery points

## Objective
Aplicar a retenção sem jamais destruir a capacidade de recuperação — nem o último ponto válido, nem um ponto protegido, nem uma dependência de outro recovery point.

## Outcome
A retenção expira o que pode expirar; recovery points protegidos, referenciados ou únicos permanecem; toda remoção é registrada.

## References
- `docs/architecture/05-backup-restore-dr.md` §12.2 (retenção em camadas), §12.3 (antes de apagar), §20.2 (audit de backup.deleted)
- `docs/architecture/09-data-model-apis-contracts.md` §25 (retenção e GC)

## Preconditions
`M10-03` done.

## Scope
- Motor de retenção aplicando a política em camadas de `M10-02`.
- Verificações obrigatórias do doc 05 §12.3 **antes** de apagar: o backup está referenciado por snapshot protegido? há dependências incrementais/PITR? há legal hold/object lock? é o último recovery point válido?
- Marcação de proteção manual e por snapshot.
- Registro no AuditLog de cada remoção, com a razão.
- Relatório do que expirará na próxima janela.

## Out of Scope
- Retenção de Artifacts (`M06-13`) — mecanismo análogo, escopo diferente.
- Retenção de logs (`M09-05`) e de audit (M13/M14).
- GC do Registry.

## Security Requirements
- **Nunca apagar o último recovery point válido** (doc 05 §12.3, regra explícita).
- Nunca apagar ponto protegido, referenciado por snapshot ou necessário como dependência incremental/PITR.
- Respeitar legal hold e object lock.
- Cada remoção é registrada com a razão — apagamento silencioso de backup é indistinguível de ataque.
- Reduzir retenção mostra o impacto antes (`M10-02`) e a execução é auditada.
- Remoção manual de recovery point protegido exige desproteger explicitamente, com step-up.

## Observability Requirements
Recovery points por camada; o que expira na próxima janela; removidos por período com razão.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Único recovery point válido | **Não** apagar, mesmo que a política mandasse. |
| Ponto referenciado por snapshot | Não apagar. |
| Dependência incremental/PITR | Não apagar a base. |
| Object lock ativo | Respeitar; registrar que não foi possível apagar. |
| Backup corrompido detectado | Não conta como recovery point válido para a regra do “último”. |
| Falha ao apagar no destino | Registrar; tentar novamente; nunca marcar como apagado sem confirmação. |

## Acceptance Criteria
1. A retenção em camadas de `M10-02` é aplicada.
2. **O último recovery point válido nunca é apagado**, provado por teste.
3. Ponto protegido, referenciado por snapshot ou base de dependência incremental **não** é apagado.
4. Legal hold e object lock são respeitados.
5. Backup corrompido **não** conta como recovery point válido para a regra do “último”.
6. Cada remoção é registrada em AuditLog com a razão.
7. Remover manualmente um ponto protegido exige desproteger explicitamente, com step-up.
8. Falha ao apagar no destino é registrada e o ponto **não** é marcado como apagado.
9. O relatório do que expirará na próxima janela está disponível.
10. As quatro verificações do doc 05 §12.3 acontecem **antes** de qualquer remoção.
11. Negativo cross-team passa.

## Required Tests
- **unit**: aplicação da política em camadas; identificação do último válido; dependências.
- **integration**: cada uma das quatro verificações bloqueando a remoção; falha ao apagar no destino.
- **security**: step-up para desproteger; AuditLog de remoção.

## Quality Gates
Local Quality Gate + `bin/security`.

## Definition of Done
Os 11 Acceptance Criteria satisfeitos, proteção do último ponto provada, todas as verificações prévias verificadas, Critical/High = 0.
