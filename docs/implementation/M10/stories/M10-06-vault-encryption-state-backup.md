# M10-06 — Vault encryption state backup and recovery path

## Objective
Garantir que o Vault seja recuperável em infraestrutura nova — e **somente** com a Recovery Key, mantendo a separação entre backup do banco e material de recuperação.

## Outcome
O estado de criptografia é protegido junto do backup; restaurar exige a Recovery Key; um backup do banco sozinho **não** revela secrets.

## References
- `docs/architecture/05-backup-restore-dr.md` §5 (Vault e chaves de recuperação), §5.1, §5.2 (propriedades obrigatórias)
- `docs/architecture/01-foundation.md` §11.1 (objetivos do envelope)
- `docs/annexes/C-threat-model-security-hardening.md` §12.1, §20, T06
- `docs/annexes/E-operational-runbooks.md` RB-19

## Preconditions
`M10-04` done. M03 aceito.

## Scope
- Inclusão do `EncryptionKeyEnvelope` (material **embrulhado**) no escopo de proteção.
- Verificação criptográfica no restore **antes** de ativar secrets em workloads (doc 05 §5.2).
- Teste canário: um secret de verificação recuperável com o fluxo de Recovery Key, usado nos drills.
- Registro explícito da separação: **Recovery Key e backup do banco não são o mesmo ativo** e não devem ficar no mesmo domínio de confiança.
- Estado de recuperação alimentando o `RecoveryReadinessView` de `M03-13`.

## Out of Scope
- Rotação da Recovery Key (`M03-03`).
- Drill completo (`M10-16`).
- Escrow de chave por terceiros — sem requisito.

## Security Requirements
Esta é a Story que sustenta a promessa central do doc 01 §11.1:
- **Backup do banco sozinho não revela secrets.** Provado por teste que restaura sem a Recovery Key e falha ao decifrar.
- **A Recovery Key não entra no backup** (doc 05 §5.1, regra explícita) e não fica no mesmo domínio de confiança do dump.
- SecretVersions são imutáveis; o restore **não** altera versões antigas.
- O restore exige verificação criptográfica antes de ativar secrets em workloads.
- Chave incorreta falha com segurança, sem plaintext parcial e sem oráculo.
- Perda da Recovery Key é risco operacional **explícito** na UI (doc 05 §5.2): sem caminho alternativo definido, secrets históricos podem se tornar irrecuperáveis.

## Observability Requirements
Estado de recuperação do Vault no Protection Readiness; data do último teste canário; alerta quando a Recovery Key não está verificada (doc 05 §17.2, `CRITICAL` para recovery readiness).

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Restore sem Recovery Key | Secrets permanecem irrecuperáveis; a plataforma **diz isso**, não falha de forma obscura. |
| Recovery Key incorreta | Falha segura, sem plaintext parcial. |
| Envelope ausente no backup | Backup marcado como não restaurável para o Vault. |
| Canário não recuperável | Drill `FAIL` com destaque. |
| Recovery Key perdida | Risco crítico exibido; sem caminho alternativo. |
| Backup e Recovery Key no mesmo lugar | Sinalizado como risco. |

## Acceptance Criteria
1. O `EncryptionKeyEnvelope` (embrulhado) faz parte do escopo protegido.
2. **A Recovery Key não entra no backup**, provado por varredura do conteúdo protegido.
3. Restaurar o banco **sem** a Recovery Key **não** permite revelar secrets, provado por teste.
4. Recovery Key incorreta falha com segurança, sem plaintext parcial e sem oráculo.
5. O restore exige verificação criptográfica antes de ativar secrets em workloads.
6. SecretVersions permanecem imutáveis após o restore.
7. Existe um secret canário recuperável usado nos drills.
8. Envelope ausente marca o backup como não restaurável para o Vault.
9. A UI expõe o risco de perda da Recovery Key explicitamente.
10. Backup e Recovery Key no mesmo domínio de confiança é sinalizado como risco.
11. O estado de recuperação alimenta o `RecoveryReadinessView`.

## Required Tests
- **security**: restore sem Recovery Key; chave incorreta; varredura confirmando ausência da chave no backup.
- **integration**: canário recuperável; envelope ausente; verificação antes de ativar.
- **unit**: estado de recuperação derivado.

## Quality Gates
Local Quality Gate + `bin/security`. **Story crítica: exige plan mode.**

## Definition of Done
Os 11 Acceptance Criteria satisfeitos, isolamento criptográfico do backup provado, Critical/High = 0.
