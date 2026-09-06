---
milestone: "M03"
name: "Vault, Encryption & Secret Distribution"
type: "milestone"
status: "pending"
---

# M03 — Vault, Encryption & Secret Distribution

## Identity

| Campo | Valor |
|---|---|
| **ID** | M03 |
| **Nome** | Vault, Encryption & Secret Distribution |
| **Objetivo** | Entregar o Vault próprio da plataforma: envelope encryption com Recovery Key, `SecretVersion` imutável, bindings pinados por Service e distribuição ao workload por Docker Swarm Secrets — sem que plaintext apareça em banco, log, evento, payload de Operation ou audit. |
| **Resultado observável** | Um OWNER cria uma Secret, gera e **verifica** a Recovery Key, cria uma versão, faz o binding a um Service e o container passa a ler o valor em `/run/secrets/`. Criar a versão seguinte **não** altera a produção. Um backup do banco, sozinho, não revela nada. |

## Why

Este é o Milestone que muda a natureza do produto: até aqui a plataforma manipula configuração pública; a partir daqui ela custodia credenciais.

Ele foi **antecipado** em relação ao Anexo A (ver SC-05) por uma razão técnica, não estética: a chave privada de `CertificateVersion` é criptografada com o mesmo envelope (doc 08 §13.2), e as credenciais de DNS provider e Registry vivem no Vault (doc 06 §11.2 e §12.2). Sem M03, os Milestones de Edge e de Build precisariam de um armazenamento de credenciais provisório — exatamente o antipadrão que o Anexo C §12 proíbe.

M03 desbloqueia M04 (TLS), M05 (Registry e Git), M10 (recuperação do Vault) e M11 (step-up em operações críticas).

## Scope

- Envelope encryption: Master Encryption Key protegida por KEK derivada da Recovery Key; `EncryptionKeyEnvelope` versionado.
- Recovery Key: geração, exibição única, download/impressão, **challenge de verificação**, fingerprint, rotação com rewrap.
- Step-up authentication (reautenticação) para ações de alto impacto.
- `Secret` e `SecretVersion` imutável, com `UNIQUE(secretId, versionNumber)`.
- `ServiceSecretBinding` com `targetName`, `injectionMode` e versão **pinada**.
- Materialização como Docker Swarm Secret, com least privilege: só o Service autorizado recebe.
- Promoção e rollback de versão por binding, com rollout controlado.
- Reveal como ação separada, permissionada, com step-up, TTL e audit.
- Boundary de redaction em API, logs, erros, eventos, payloads de Operation, audit e telemetria.
- `EnvironmentVariable` não sensível, com a fronteira explícita entre variável comum e secret.
- UI do Vault: lista, detalhe, versões, uso, “nova versão disponível”.
- Estado de recovery readiness (`READY`, `KEY_NOT_VERIFIED`, `BACKUP_STALE`, `UNRECOVERABLE_RISK`, `ROTATION_REQUIRED`).

## Out of Scope

| Deixado para | O quê |
|---|---|
| M04 | Uso do envelope para `CertificateVersion`. |
| M05 | Credenciais de Registry e tokens do Git provider como `ProviderCredentialBinding`. |
| M06 | `Release` referenciando `SecretVersion` IDs e materialização durante o deployment formal. |
| M10 | Backup do estado de criptografia, restore e drill de recuperação do Vault. |
| M11 | MFA como fator do step-up; permissões de Environment configuráveis. |
| Backlog | Dynamic database credentials e PKI (Anexo A §5 M8, fora de escopo). |

## Dependencies

- **Hard:** M01 (identidade, Operation, reconciler), M02 (rollout controlado e drift).
- **Soft:** nenhuma.

## User-visible Outcome

1. No onboarding, o OWNER gera a Recovery Key, salva, e **prova** que salvou respondendo a um challenge.
2. Cria uma Secret e uma primeira versão; o valor nunca reaparece na UI.
3. Faz o binding a um Service escolhendo o modo de injeção; o container passa a ler o valor.
4. Cria a versão 2; a produção continua na versão 1, e a UI mostra “nova versão disponível”.
5. Promove para produção deliberadamente, com rollout controlado.
6. Revela um valor apenas quando tem permissão, reautentica e sabe que ficou auditado.
7. Rotaciona a Recovery Key sem que nenhuma SecretVersion precise ser recriptografada.

## Technical Outcome

- AEAD com chave versionada; nenhum plaintext no PostgreSQL.
- Recovery Key não persistida de forma recuperável.
- Rotação = rewrap da MEK, não re-encrypt do Vault inteiro.
- Secret Reconciler materializando Swarm Secrets e mantendo bindings corretos.
- Redaction aplicada em **todos** os boundaries, com AF-06 avaliando código real.

## Architecture Impact

| Categoria | Impacto |
|---|---|
| Entities | `EncryptionKeyEnvelope`, `Secret`, `SecretVersion`, `ServiceSecretBinding`, `EnvironmentVariable`, `RecoveryKeyState`. |
| Commands | `InitializeEncryption`, `GenerateRecoveryKey`, `VerifyRecoveryKey`, `RotateRecoveryKey`, `CreateSecret`, `CreateSecretVersion`, `BindSecretVersion`, `PromoteSecretVersion`, `RevealSecret`. |
| Queries | `SecretsForTeam`, `SecretUsage`, `RecoveryReadinessView`. |
| Events | `secret.version.created.v1`, `secret.binding.changed.v1`, `recovery_key.verified`, `recovery_key.rotated`. |
| Operations | `ROTATE_SECRET_BINDING`, `MATERIALIZE_SECRET`. |
| Reconcilers | `SecretReconciler`. |
| Executor | `CreateSecret`, `RemoveSecret`, `UpdateServiceSpec` com referências de secret. |
| UI | Vault, Secret detail, binding dialog, reveal dialog, Recovery Key, Security. |

## Security

Este Milestone **é** um controle de segurança. As regras não negociáveis:

- **Nunca plaintext em repouso**: somente ciphertext + metadata no PostgreSQL (Anexo C §12).
- **`SecretVersion` é imutável**: alteração cria nova versão; versões antigas nunca são editadas.
- **Pinned por padrão em produção**: criar `vN+1` não altera automaticamente quem usa `vN` (doc 01 §9.4).
- **Least privilege na distribuição**: cada Service recebe apenas as secrets de que precisa (doc 01 §9.3).
- **Swarm Secrets por default** para valores sensíveis; `ENV` plaintext só por compatibilidade e **com aviso** (doc 01 §10.2).
- **Reveal não é necessário para deploy**: é ação separada, permissionada, com reauth e AuditLog.
- **Recovery Key**: exibida uma vez, nunca logada, nunca em backup do storage primário, verificável e rotacionável.
- **Backup do banco sozinho não revela secrets** (doc 01 §11.1).
- **Payload de Operation carrega apenas `SecretVersion` IDs** (doc 07 §21).
- Ameaças cobertas: T05 (vazamento de SecretVersion), T06 (roubo de Recovery Key).

## Observability

- Toda criação de versão, mudança de binding, reveal e rotação gera AuditLog **sem** o valor.
- `RecoveryReadinessView` exposta no dashboard de segurança.
- Métrica: secrets sem uso, versões não promovidas, idade da última verificação de recovery.
- Falha de criptografia é um erro classificado que **bloqueia** — nunca há fallback para plaintext.

## Testing

| Classe | Exigência |
|---|---|
| Unit | Propriedades e invariantes do envelope; imutabilidade; cálculo de readiness. |
| Integration | Crypto round-trip real; chave errada falhando sem revelar material; rotação com rewrap; binding pin. |
| Policy | Reveal negado sem permissão; rotação restrita a OWNER; negativos cross-team. |
| Docker/Swarm | Swarm Secret criada e anexada **somente** ao Service autorizado; Task movida de node recebendo a secret correta; rotação de versão. |
| E2E | Onboarding com Recovery Key verificada; criar → bindar → deployar → promover versão. |
| Security | Nenhum plaintext em log/DB/evento/audit/telemetria; reveal auditado; scanner de plaintext. |

## Acceptance Criteria

1. Nenhum valor de `SecretVersion` é persistido em plaintext no PostgreSQL.
2. Um backup do banco, sem a Recovery Key, **não** permite revelar secrets.
3. `SecretVersion` é imutável; `UNIQUE(secretId, versionNumber)` existe no banco.
4. Criar `vN+1` **não** altera automaticamente um Service pinado em `vN`.
5. Promover ou reverter binding altera apenas o binding alvo e causa rollout controlado quando necessário.
6. A secret é entregue **somente** ao Service autorizado, verificado contra Swarm real.
7. Uma Task movida para outro node recebe a versão correta da secret.
8. A Recovery Key é exibida uma única vez, verificada por challenge, e nunca aparece em log, audit ou backup do storage primário.
9. A rotação da Recovery Key faz rewrap da MEK **sem** recriptografar todas as SecretVersions.
10. Chave de recuperação incorreta falha com segurança, sem revelar material criptográfico parcial.
11. Reveal exige permissão dedicada, step-up authentication e gera AuditLog; não é necessário para deploy.
12. Nenhum plaintext aparece em log, erro, evento, payload de Operation, audit ou telemetria — provado com valores plantados e por AF-06.
13. Criptografia indisponível **bloqueia** a operação; nunca há fallback para plaintext.
14. `EnvironmentVariable` marcada como sensível é rejeitada e direcionada ao Vault.
15. O estado de recovery readiness é derivado e exibido.

## Exit Gate

M03 pode assumir `READY_FOR_HUMAN_ACCEPTANCE` quando:

- [ ] todas as Stories `required: true` estão `done` com commit;
- [ ] os 15 Acceptance Criteria têm evidência no `MILESTONE_REPORT.md`;
- [ ] o teste “backup do banco sem Recovery Key não revela secret” está verde;
- [ ] o teste de rotação com rewrap (sem re-encrypt geral) está verde;
- [ ] o teste de distribuição least privilege contra Swarm real está verde;
- [ ] o scanner de plaintext em logs/audit/eventos está verde;
- [ ] `bin/fitness` verde com **AF-06 avaliando serializers, logs e audit reais**;
- [ ] `bin/security` verde;
- [ ] Critical = 0 e High = 0;
- [ ] `MILESTONE_REPORT.md` gerado.

**Gate humano: Security Gate.** Este Milestone corresponde ao G1→G2 do Anexo C §22 e não pode ser aceito por evidência automatizada apenas — exige revisão humana do modelo de criptografia e do fluxo de recuperação.
