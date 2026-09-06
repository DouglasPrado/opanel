---
milestone: "M10"
name: "Backup, Restore & Disaster Recovery"
type: "milestone"
status: "pending"
---

# M10 — Backup, Restore & Disaster Recovery

## Identity

| Campo | Valor |
|---|---|
| **ID** | M10 |
| **Nome** | Backup, Restore & Disaster Recovery |
| **Objetivo** | Introduzir **DR**: proteger o estado da própria plataforma em storage externo cifrado, e provar que ela pode ser reconstruída em infraestrutura nova a partir de Platform DB + Vault + Registry — com RPO e RTO **medidos**, não configurados. |
| **Resultado observável** | Um drill executa o Clean Rebuild em infraestrutura vazia: restaurar o banco, fornecer a Recovery Key, reconectar Registry e providers, inicializar um Swarm novo, recriar networks, secrets, services e ingress, e validar health — com o tempo cronometrado. |

## Why

HA mantém o serviço disponível durante falhas; **DR recupera o estado após perda**. São mecanismos independentes e ambos obrigatórios (doc 05, decisão central).

O objetivo deste Milestone não é “restaurar uma VPS”: é conseguir recriar a plataforma e seus workloads em infraestrutura nova, preservando identidade, configuração, secrets, releases e roteamento (doc 05, princípio).

Ele depende de M03 (recuperação do Vault) e de M06 (Clean Rebuild recria Services a partir de Releases por digest). Sem esses dois, não há de onde reconstruir.

## Scope

- `BackupStorageProvider` S3-compatible, com credenciais no Vault e destino **fora do cluster protegido**.
- `BackupPolicy` com schedule, retenção em camadas e verificação.
- `BackupRun`, `BackupArtifact` e `BackupManifest` com checksums e metadados de criptografia.
- **Envelope encryption client-side** dos payloads de backup, com data key por backup.
- Backup do Platform Database, com consciência de PITR quando o provider oferecer.
- Backup do estado de criptografia do Vault e o caminho de recuperação com Recovery Key.
- Export e restore de `CertificateVersion`.
- Backup do estado Raft do Swarm para Fast Restore.
- `EnvironmentSnapshot` **lógico**, referenciando `SecretVersion` sem duplicar plaintext.
- `ClusterSnapshot` de configuração.
- Restore Engine com plano, validação, execução e verificação.
- Restore de Environment em ambiente novo, preferindo criação paralela a sobrescrita.
- **Clean Rebuild** completo.
- **Fast Swarm Restore** como caminho alternativo.
- Retention engine com proteção de recovery points referenciados.
- Drills de verificação e `RecoveryVerification`.
- Protection Readiness dashboard e alertas.
- **Migração de Environment entre Clusters** (UC-011), reusando o Restore Engine em vez de criar um segundo motor.

## Out of Scope

| Deixado para | O quê |
|---|---|
| M13 | Chaos e DR sob condições adversas; medição sob carga. |
| M14 | Drill final em infraestrutura vazia como gate de release e o exercício completo dos runbooks. |
| Fora do produto | Backup dos bancos gerenciados dos clientes (doc 05 §1.2); volumes persistentes de aplicação. |

## Dependencies

- **Hard:** M03 (envelope e Recovery Key), M06 (Release por digest).
- **Soft:** M08 (Raft e ClusterSnapshot ficam mais fortes com cluster real), M04 (certificados).
- **Externas:** bucket S3-compatible fora do cluster; infraestrutura vazia para o drill.

## User-visible Outcome

O operador configura o destino de backup, vê o Protection Readiness com RPO real × alvo, executa um restore drill e recebe `PASS`/`FAIL` com evidência. Em um desastre, ele segue um fluxo de produto — não um script improvisado.

## Technical Outcome

- Backup independente do cluster que protege.
- Recuperação do Vault exigindo Recovery Key; **backup do banco sozinho não revela secrets**.
- Clean Rebuild recriando runtime a partir do Desired State e de artefatos por digest.
- RPO/RTO medidos por restore real, não declarados.

## Architecture Impact

| Categoria | Impacto |
|---|---|
| Entities | `BackupPolicy`, `BackupRun`, `BackupArtifact`, `BackupManifest`, `EnvironmentSnapshot`, `ClusterSnapshot`, `RestoreOperation`, `RestoreStep`, `RecoveryVerification`, `StorageProvider`. |
| Commands | `CreateBackupPolicy`, `RunBackup`, `CreateSnapshot`, `PlanRestore`, `ExecuteRestore`, `RunVerification`. |
| Queries | `RecoveryPoints`, `ProtectionReadinessView`, `RestoreProgress`. |
| Events | `backup.verified.v1`, `backup.failed`, `restore.completed`. |
| Providers | `BackupStorageProvider`. |
| UI | Protection dashboard, políticas, snapshots, restore, verificação. |

## Security

- **Destino externo ao cluster protegido** (doc 05 §10): um backup que morre junto com o cluster não é backup.
- **Criptografia client-side** com data key por backup; o manifest carrega apenas material embrulhado (doc 05 §11).
- **Recovery Key fora do backup principal**; backup do banco sozinho **não** revela secrets (doc 01 §11.1).
- Credenciais de backup são secrets da plataforma e **não** dão acesso administrativo ao cluster (Anexo C §20).
- Snapshot referencia `SecretVersion` IDs; **não** duplica plaintext (doc 05 §9.3).
- Restore destrutivo exige reautenticação e confirmação explícita; preferir restaurar em recurso novo antes de substituir (doc 05 §13.2).
- Restore com Recovery Key incorreta **falha com segurança**, sem plaintext parcial.
- Estado Raft do Swarm é artefato sensível: criptografado e nunca em storage público (doc 05 §7.2).
- Retenção nunca apaga o último recovery point válido nem um ponto protegido.
- Clean Rebuild é o caminho preferido após suspeita de comprometimento profundo (Anexo C §20).

## Observability

- Protection Readiness com RPO real × alvo, verificação da Recovery Key, idade do último drill e saúde do destino.
- Condições de alerta do doc 05 §17.2.
- Cada `RestoreOperation` com etapas, progresso e resultado; falha **não** esconde estado parcial.
- RPO e RTO **medidos** nos drills e registrados como evidência.

## Testing

| Classe | Exigência |
|---|---|
| Unit | Manifesto e checksums; política de retenção; elegibilidade de recovery point. |
| Integration | Backup e restore do banco; envelope; proteção de retenção. |
| Contract | `BackupStorageProvider`: put/get/delete, checksum, multipart. |
| Docker/Swarm | Clean Rebuild recriando networks, secrets e services; Fast Swarm Restore. |
| E2E | Drill completo com RPO/RTO medidos. |
| Security | Restore com chave errada; backup do banco sem Recovery Key; backup corrompido detectado; credencial de backup sem acesso ao cluster. |

## Acceptance Criteria

1. O backup **não** depende exclusivamente do mesmo cluster que protege.
2. O payload é cifrado client-side, com data key por backup; o manifest carrega apenas material embrulhado.
3. Backup do banco **sem** Recovery Key **não** permite revelar secrets.
4. Restore do banco + Recovery Key recupera Vault e metadata.
5. Restore com Recovery Key incorreta **falha com segurança**, sem plaintext parcial.
6. Existem os dois caminhos: **Fast Swarm Restore** e **Clean Rebuild**.
7. O Clean Rebuild recria Services a partir do Desired State e de Artifacts existentes.
8. Backup corrompido ou incompleto é detectado por checksum/manifest e **não** é marcado como restaurável.
9. Certificados são restaurados e redistribuídos após o restore.
10. `EnvironmentSnapshot` referencia `SecretVersion` sem duplicar plaintext.
11. O restore drill gera status verificável no painel.
12. Backups têm checksum, criptografia e retenção definidos.
13. A retenção **nunca** apaga o último recovery point válido nem um ponto protegido.
14. Restore destrutivo exige reautenticação e confirmação explícita.
15. RPO e RTO são **medidos** em restore real e registrados.
16. Digest necessário indisponível no Registry é detectado **antes** do rebuild.
17. UC-011 é executável: um Environment migra de Cluster com plano revisável, corte de tráfego só após health no destino e limpeza da origem.

## Exit Gate

- [ ] Stories `required` `done`; 17 Acceptance Criteria com evidência.
- [ ] **Drill de Clean Rebuild em infraestrutura vazia** verde, com RPO/RTO medidos.
- [ ] Teste de restore com Recovery Key incorreta verde (falha segura).
- [ ] Teste de backup do banco sem Recovery Key verde (secrets irrecuperáveis).
- [ ] Teste de backup corrompido verde (não marcado como restaurável).
- [ ] Teste de retenção protegendo o último recovery point verde.
- [ ] `bin/fitness`, `bin/security` verdes; Critical = 0, High = 0.
- [ ] `MILESTONE_REPORT.md` gerado com `Status: READY_FOR_REVIEW`.

**Gate humano: DR Gate.** Corresponde ao gate do Anexo A §11. O drill precisa ser executado seguindo o runbook, **sem** conhecimento privilegiado do operador (Anexo D §15.1).
