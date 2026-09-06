# M03-13 — Recovery readiness state and security dashboard signal

## Objective
Tornar a capacidade de recuperar o Vault um estado **derivado e visível**, em vez de uma suposição.

## Outcome
A plataforma calcula e exibe `READY`, `KEY_NOT_VERIFIED`, `BACKUP_STALE`, `UNRECOVERABLE_RISK` ou `ROTATION_REQUIRED`, com o que precisa ser feito para melhorar o estado.

## References
- `docs/architecture/05-backup-restore-dr.md` §5.3 (estado de recuperação na UI), §17.2 (condições que geram alerta)
- `docs/architecture/10-ui-use-cases.md` §21.1 (security dashboard), §21.2 (Recovery Key)
- `docs/annexes/B-nfr-slos.md` §11.1 (restore verification)

## Preconditions
`M03-03` done.

## Scope
- Cálculo derivado do estado de recovery readiness a partir de: existência do envelope, verificação da Recovery Key, idade da verificação, política de rotação e — quando `M10` existir — frescor do backup.
- Estados do doc 05 §5.3, com o **motivo** e a ação recomendada.
- Exibição no dashboard de segurança e como badge de atenção na navegação.
- Em M03, o componente de backup do cálculo é declarado como “não configurado”, não como “ok” — a plataforma **não** afirma proteção sem evidência (doc 05 §1.2, guardrail).
- Contrato de extensão para `M10` preencher os sinais de backup e de drill.

## Out of Scope
- Backup em si e verificação por restore (`M10-05`, `M10-16`).
- Alertas e notificações externas (`M09-08`, `M09-11`).
- Dashboard de segurança completo (`M11-13`) — aqui entra o sinal de recovery.

## Application Layer
- **Queries:** `RecoveryReadinessView`.
- Cálculo derivado, nunca coluna booleana gravada manualmente.

## UI Impact
Bloco de Recovery na área de Security: status, fingerprint, data de criação, data da última verificação, e ações (verificar, rotacionar). Nenhuma exibição da chave.

## Security Requirements
- O estado **nunca** afirma proteção sem evidência: sem backup configurado, o estado reflete isso explicitamente, não `READY`.
- `UNRECOVERABLE_RISK` é exibido com destaque quando não há caminho de recuperação validado (doc 05 §5.3).
- A view não expõe material criptográfico; apenas fingerprint e timestamps.
- Consultar o estado exige membership; o detalhe completo pode exigir role mais alta.

## Observability Requirements
- Estado derivado com o motivo, consultável por API e visível na UI.
- Métrica: idade da última verificação de Recovery Key.
- Condições de alerta do doc 05 §17.2 mapeadas para os estados, prontas para virarem AlertRule em `M09-08`.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Recovery Key gerada mas não verificada | `KEY_NOT_VERIFIED`, com ação de verificar. |
| Nenhum backup configurado (situação normal em M03) | Estado reflete a ausência; **não** `READY`. |
| Verificação antiga além da política | `ROTATION_REQUIRED` ou aviso conforme a política configurada. |
| Envelope ausente | `UNRECOVERABLE_RISK` com destaque. |
| Cálculo falha | Estado indisponível com causa; **nunca** default otimista. |

## Acceptance Criteria
1. O estado de recovery readiness é **derivado**, nunca uma coluna booleana gravada.
2. Os cinco estados do doc 05 §5.3 são calculáveis e exibidos com motivo e ação recomendada.
3. Recovery Key não verificada resulta em `KEY_NOT_VERIFIED`.
4. Sem backup configurado, o estado **não** é `READY`; a ausência é explícita.
5. Envelope ausente resulta em `UNRECOVERABLE_RISK` com destaque.
6. Verificação antiga além da política gera o estado correspondente.
7. Falha no cálculo resulta em estado indisponível com causa, nunca em default otimista.
8. A view expõe apenas fingerprint e timestamps; nenhum material criptográfico.
9. Existe um contrato de extensão para `M10` preencher backup e drill sem reescrever o cálculo.
10. Consultar o estado exige membership; negativo cross-team passa.
11. O badge de atenção aparece na navegação quando o estado não é `READY`.

## Required Tests
- **unit**: cálculo de cada estado; ausência de default otimista.
- **integration**: transição de estados após geração, verificação e rotação.
- **policy**: negativo cross-team.
- **security**: ausência de material criptográfico na view.
- **unit (frontend)**: badge e bloco de Recovery.

## Quality Gates
Local Quality Gate + `bin/security`.

## Definition of Done
Os 11 Acceptance Criteria satisfeitos, ausência de default otimista provada, contrato de extensão para M10 definido, Critical/High = 0.
