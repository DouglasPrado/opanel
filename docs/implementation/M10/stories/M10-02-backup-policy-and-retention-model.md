# M10-02 — BackupPolicy with schedule, tiered retention and verification

## Objective
Modelar quando, o quê e por quanto tempo proteger — com retenção em camadas e verificação periódica como parte da política, não como atividade opcional.

## Outcome
Uma política define frequência, retenção em camadas, destino, criptografia e cadência de verificação; recovery points protegidos nunca expiram sozinhos.

## References
- `docs/architecture/05-backup-restore-dr.md` §12 (políticas de backup e retenção), §12.2 (retenção em camadas), §4.2 (RPO/RTO por perfil)
- `docs/annexes/B-nfr-slos.md` §11 (RPO/RTO por componente)

## Preconditions
`M10-01` done.

## Scope
- `BackupPolicy`: nome, escopo (platform/cluster/team), frequência, retenção em camadas, destino, política de criptografia, política de verificação, proteção (object lock quando disponível).
- Retenção em camadas do doc 05 §12.2: horária nas últimas 24 h, diária nos últimos 14 dias, semanal nas últimas 8 semanas, mensal nos últimos 12 meses, e “protegido” sem expiração automática.
- Perfis de RPO/RTO do doc 05 §4.2 como presets: Development, Standard, Production, Critical.
- Exibição do **RPO/RTO efetivamente alcançável** com a configuração atual — não o alvo desejado.
- Agendamento das execuções.

## Out of Scope
- Execução do backup (`M10-03`, `M10-05`).
- Aplicação da retenção (`M10-15`).
- Verificação em si (`M10-16`).

## Application Layer
- **Commands:** `CreateBackupPolicy`, `UpdateBackupPolicy`.
- **Queries:** `EffectiveRpoRto`.

## Security Requirements
- Alterar a política de retenção é **operação sensível** (doc 05 §20.1) e auditada: reduzir retenção pode destruir a capacidade de recuperar.
- Reduzir a retenção mostra **o que deixará de existir** antes de aplicar.
- A política não pode configurar um estado em que não sobra nenhum recovery point.
- Object lock, quando disponível, é recomendado para proteger contra apagamento malicioso.

## Observability Requirements
- **RPO/RTO alcançável** exibido junto ao alvo — a UI não promete o alvo (doc 05 §4.2, regra explícita).
- Próxima execução agendada e última execução com resultado.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Frequência incompatível com o RPO alvo | Exibir o RPO **alcançável**, não o desejado. |
| Retenção reduzida | Mostrar o que será perdido antes de aplicar; auditar. |
| Política sem verificação | Aviso: backup não verificado não conta como proteção. |
| Destino sem object lock | Aviso de risco de apagamento malicioso. |
| Política deixando zero recovery points | Rejeitada. |
| Escopo sobreposto entre políticas | Resolvido deterministicamente e explicado. |

## Acceptance Criteria
1. `BackupPolicy` existe com todos os campos do doc 05 §12.1.
2. A retenção em camadas do doc 05 §12.2 é representável, incluindo “protegido”.
3. Os quatro perfis de RPO/RTO do doc 05 §4.2 existem como presets.
4. A UI exibe o **RPO/RTO alcançável** com a configuração atual, distinto do alvo.
5. Reduzir a retenção mostra o que será perdido **antes** de aplicar.
6. Uma política que resultaria em zero recovery points é rejeitada.
7. Política sem verificação gera aviso explícito.
8. Destino sem object lock gera aviso de risco.
9. Escopos sobrepostos são resolvidos deterministicamente e explicados.
10. Alterar a política gera AuditLog; negativo cross-team passa.
11. O agendamento das execuções funciona e a próxima execução é visível.

## Required Tests
- **unit**: cálculo de RPO alcançável; retenção em camadas; sobreposição de escopo.
- **integration**: rejeição de política sem recovery point; aviso de redução de retenção.
- **policy**: negativo cross-team; permissão para alterar retenção.

## Quality Gates
Local Quality Gate + `bin/security`.

## Definition of Done
Os 11 Acceptance Criteria satisfeitos, RPO alcançável distinto do alvo, redução de retenção protegida, Critical/High = 0.
