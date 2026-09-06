# M10-03 — BackupRun, BackupArtifact and BackupManifest

## Objective
Registrar cada execução de backup como entidade auditável, com artefatos identificáveis, checksums e um manifesto que descreve exatamente o que foi protegido.

## Outcome
Um `BackupRun` produz artefatos com checksum e um manifesto com versões, dependências e metadados de criptografia; o run só é `SUCCEEDED` após a validação.

## References
- `docs/architecture/05-backup-restore-dr.md` §3.1 (componentes), §4.1 (checksum e manifesto antes de marcar SUCCESS), §18 (modelo de dados)
- `docs/architecture/09-data-model-apis-contracts.md` §14 (BackupRun, BackupArtifact)

## Preconditions
`M10-02` done.

## Scope
- `BackupRun`: policyId, tipo, status (`QUEUED → RUNNING → VERIFYING → SUCCEEDED | FAILED`), startedAt, completedAt, `recoveryPointAt`, bytes, erro.
- `BackupArtifact`: runId, kind, storageKey, checksum, tamanho cifrado, metadados.
- `BackupManifest`: versão da plataforma, **schemaVersion do banco**, dependências (incluindo digests necessários), metadados de criptografia, checksums.
- Validação obrigatória antes de `SUCCEEDED`: checksum de cada artefato e coerência do manifesto.
- Registro dos digests de artifact necessários para reconstrução (doc 05 §8.1).

## Out of Scope
- Criptografia (`M10-04`).
- Adapters por fonte (`M10-05`..`M10-08`).
- Retenção (`M10-15`).

## Domain Impact
**Invariante:** um `BackupRun` só é `SUCCEEDED` depois que checksum e manifesto foram validados (doc 05 §4.1, regra explícita).

## Application Layer
- **Commands:** `RunBackup`, `ValidateBackupRun`.
- **Queries:** `RecoveryPoints`.

## Security Requirements
- O manifesto **não** contém credenciais nem material sensível — apenas metadados e material embrulhado (doc 05 §11.1).
- Checksums são calculados e validados **antes e depois** do upload (doc 05 §11.1).
- O `schemaVersion` no manifesto é obrigatório: restaurar em uma versão incompatível de aplicação é uma falha silenciosa perigosa (doc 05 §4.1).
- Os digests necessários são registrados, para que a indisponibilidade seja detectável antes do rebuild.
- Um run que falha **não** é apresentado como recovery point.

## Observability Requirements
Recovery points listáveis com data, tamanho, status e verificação. `recoveryPointAt` é o dado que alimenta o cálculo de RPO.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Checksum divergente | Run `FAILED`; artefato **não** vira recovery point. |
| Upload interrompido | Retomável por multipart; se não, `FAILED` com causa. |
| Manifesto incompleto | Run `FAILED`. |
| Destino indisponível no meio | `FAILED` com causa; runs anteriores preservados. |
| Backup parcial | **Nunca** marcado como `SUCCEEDED`. |
| Digest necessário já ausente | Registrado no manifesto como dependência faltante e sinalizado. |

## Acceptance Criteria
1. `BackupRun`, `BackupArtifact` e `BackupManifest` existem com os campos do doc 05 §18.
2. O run só é `SUCCEEDED` após checksum de cada artefato **e** validação do manifesto.
3. Checksums são calculados antes e depois do upload.
4. O manifesto registra versão da plataforma, `schemaVersion` do banco e dependências, incluindo digests necessários.
5. O manifesto **não** contém credenciais nem material sensível, provado com valor plantado.
6. Checksum divergente resulta em `FAILED` e o artefato não vira recovery point.
7. Backup parcial **nunca** é `SUCCEEDED`.
8. Upload interrompido é retomável ou falha com causa.
9. Destino indisponível no meio preserva runs anteriores.
10. Digest necessário ausente é registrado como dependência faltante e sinalizado.
11. `recoveryPointAt` é registrado e alimenta o cálculo de RPO.

## Required Tests
- **unit**: validação de manifesto; cálculo de checksum.
- **integration**: checksum divergente; backup parcial; upload interrompido; destino indisponível.
- **security**: manifesto sem material sensível.

## Quality Gates
Local Quality Gate + `bin/security`.

## Definition of Done
Os 11 Acceptance Criteria satisfeitos, ausência de sucesso parcial provada, manifesto completo, Critical/High = 0.
