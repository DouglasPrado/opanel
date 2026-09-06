# M10-04 — Client-side envelope encryption of backup payloads

## Objective
Cifrar o backup **antes** de ele sair da plataforma, com uma data key por backup, para que o destino nunca veja conteúdo em claro.

## Outcome
Cada `BackupRun` tem sua própria data key; o payload é cifrado antes do upload; o manifest carrega apenas a chave embrulhada.

## References
- `docs/architecture/05-backup-restore-dr.md` §11 (criptografia dos backups), §11.1 (envelope encryption)
- `docs/annexes/C-threat-model-security-hardening.md` §20 (backups criptografados e off-site)
- `docs/architecture/01-foundation.md` §11 (envelope encryption da plataforma)

## Preconditions
`M10-03` done. Envelope de `M03-01` disponível.

## Scope
- Data key aleatória **por backup**; payload cifrado com ela.
- Data key embrulhada pelo envelope da plataforma e armazenada no manifest.
- Cifra antes do upload; o destino nunca recebe conteúdo em claro.
- Checksums calculados sobre o conteúdo cifrado e validados após o upload.
- Caminho de recuperação: desembrulhar a data key → decifrar o payload.
- Regra: criptografia server-side do provider é **camada adicional**, não substituta.

## Out of Scope
- Recuperação do Vault em si (`M10-06`).
- Rotação de chave de backup — cada backup tem a sua; rotacionar a Recovery Key (`M03-03`) já rewrapa o envelope.

## Application Layer
Reuso do módulo único de criptografia de `M03-01`; nenhuma primitiva criptográfica nova.

## Security Requirements
- **Data key por backup**: comprometer um backup não compromete os demais (doc 05 §11.1).
- O payload é cifrado **antes de sair da plataforma**.
- O manifest contém apenas material **embrulhado** e metadados não sensíveis.
- Logs de backup **nunca** contêm secrets nem chaves descriptografadas (doc 05 §11.1, regra explícita).
- A criptografia usa o módulo único de `M03-01`; nenhuma implementação paralela.
- Sem o envelope disponível, o backup **falha**; nunca envia em claro.
- Criptografia server-side do provider não dispensa a client-side.

## Observability Requirements
Metadados de criptografia por artefato: algoritmo, versão do envelope, sem material. Falha de cifra é erro classificado.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Envelope indisponível | Backup **falha**; nunca envia em claro. |
| Data key não embrulhável | Falha antes do upload. |
| Checksum pós-upload divergente | Run `FAILED`. |
| Manifest sem material de chave | Backup irrecuperável: detectado na validação e marcado `FAILED`. |
| Decifra falha no restore | Erro seguro, sem plaintext parcial (`M10-11`). |

## Acceptance Criteria
1. Cada backup usa uma data key **própria e aleatória**.
2. O payload é cifrado **antes** do upload; o destino nunca recebe conteúdo em claro, provado por inspeção do objeto armazenado.
3. A data key é embrulhada pelo envelope da plataforma e vive no manifest.
4. O manifest contém apenas material embrulhado e metadados não sensíveis.
5. Sem envelope disponível, o backup **falha**; nenhum caminho envia em claro.
6. Checksums são calculados sobre o conteúdo cifrado e validados após o upload.
7. Logs de backup não contêm secrets nem chaves descriptografadas, provado com valor plantado.
8. A criptografia usa o módulo único de `M03-01`; nenhuma primitiva paralela, verificado estaticamente.
9. Manifest sem material de chave é detectado na validação e o run é `FAILED`.
10. Criptografia server-side do provider é tratada como camada adicional, não substituta.

## Required Tests
- **integration**: objeto armazenado ilegível sem a chave; envelope indisponível bloqueando; checksum pós-upload.
- **security**: valor plantado ausente dos logs; ausência de primitiva criptográfica fora do módulo; manifest sem chave detectado.
- **unit**: geração e embrulho da data key.

## Quality Gates
Local Quality Gate + `bin/security`.

## Definition of Done
Os 10 Acceptance Criteria satisfeitos, objeto no destino comprovadamente ilegível sem a chave, Critical/High = 0.
