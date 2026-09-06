# M10-11 — Restore Engine: plan, validate, execute, verify

## Objective
Tornar o restore uma **operação de primeira classe** com entidade própria, etapas, validação e resultado — em vez de um botão que executa scripts opacos.

## Outcome
Um restore tem plano gerado, validação prévia, execução por etapas observáveis e verificação final; a falha nunca esconde estado parcial.

## References
- `docs/architecture/05-backup-restore-dr.md` §13 (Restore Engine), §13.1 (restore é operação de primeira classe), §13.2 (restore seguro por padrão)
- `docs/architecture/09-data-model-apis-contracts.md` §14, §17 (RestoreJob state machine)
- `docs/annexes/E-operational-runbooks.md` RB-23

## Preconditions
`M10-05` done.

## Scope
- `RestoreOperation` com os estados do doc 05 §13.1: `PLANNED → VALIDATING → PREPARING → RESTORING → RECONCILING → VERIFYING → COMPLETED | FAILED`.
- `RestoreStep` por etapa, com início, fim, status e erro.
- **Plano sem executar** (dry-run): o que será restaurado, o que será substituído, o que não pode ser recuperado.
- Validação prévia: checksum, manifesto, compatibilidade de `schemaVersion` e disponibilidade da Recovery Key.
- Execução com progresso observável.
- **Restore seguro por padrão**: preferir restaurar em recurso novo antes de substituir o atual.
- Restore destrutivo exigindo reautenticação e confirmação explícita.

## Out of Scope
- Restore de Environment (`M10-12`), Clean Rebuild (`M10-13`) e Fast Restore (`M10-14`) — que **usam** este motor.
- Drills (`M10-16`).

## Domain Impact
**Invariante:** a falha **não** oculta estado parcial (doc 05 §13.1, regra explícita). O que foi feito fica registrado.

## Application Layer
- **Commands:** `PlanRestore`, `ExecuteRestore`, `AbortRestore`.
- **Queries:** `RestoreProgress`, `RestorePlan`.
- **Policies:** restore destrutivo exige permissão elevada + step-up.

## Security Requirements
- **Restore destrutivo exige reautenticação e confirmação explícita** (doc 05 §13.2, regra explícita).
- Preferir criar recurso novo antes de substituir o atual; o cutover é etapa **separada e auditada**.
- Validação prévia impede iniciar um restore que não pode terminar: chave ausente, checksum inválido ou schema incompatível **bloqueiam antes** de tocar qualquer coisa.
- Decifra com chave incorreta falha com segurança, sem plaintext parcial.
- O banco original é **preservado** para investigação quando o restore o substitui (RB-23).
- Cada restore gera AuditLog com o recovery point escolhido, o alvo e se era destrutivo.

## Observability Requirements
Progresso por etapa; RPO real do ponto escolhido; RTO medido ao final. Falha registra em qual etapa parou e o que já havia sido feito.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Checksum inválido | Bloqueado na validação; não iniciar. |
| `schemaVersion` incompatível | Bloqueado na validação. |
| Recovery Key ausente/incorreta | Bloqueado; falha segura. |
| Falha no meio | Estado parcial **registrado**, não escondido; plano de continuação ou rollback explícito. |
| Restore sobre recurso em uso | Exige confirmação explícita e preserva o original. |
| Operações posteriores ao ponto de restore | Mapeadas e apresentadas: elas existem no runtime mas não no banco restaurado (RB-23). |

## Acceptance Criteria
1. `RestoreOperation` existe com os sete estados do doc 05 §13.1 e `RestoreStep` por etapa.
2. É possível **gerar o plano sem executar**, mostrando o que será restaurado, substituído e o que não pode ser recuperado.
3. A validação prévia verifica checksum, manifesto, `schemaVersion` e disponibilidade da Recovery Key.
4. Checksum inválido, schema incompatível ou chave ausente **bloqueiam antes** de qualquer alteração.
5. Chave incorreta falha com segurança, sem plaintext parcial.
6. Restore destrutivo exige reautenticação e confirmação explícita.
7. O padrão é restaurar em recurso novo; o cutover é etapa separada e auditada.
8. O recurso original é preservado quando o restore o substitui.
9. Falha no meio **registra o estado parcial**; nada é escondido.
10. Operações posteriores ao ponto de restore são mapeadas e apresentadas.
11. O progresso por etapa é observável; RPO do ponto e RTO medido são registrados.
12. Cada restore gera AuditLog com ponto, alvo e caráter destrutivo.

## Required Tests
- **unit**: state machine; validação prévia; cálculo do plano.
- **integration**: checksum inválido; schema incompatível; chave incorreta; falha no meio com estado registrado.
- **policy**: step-up para restore destrutivo; negativo cross-team.
- **security**: ausência de plaintext parcial; preservação do original.

## Quality Gates
Local Quality Gate + `bin/security`. **Story crítica: operação destrutiva; exige plan mode.**

## Definition of Done
Os 12 Acceptance Criteria satisfeitos, bloqueio antes de alterar provado, estado parcial nunca escondido, Critical/High = 0.
