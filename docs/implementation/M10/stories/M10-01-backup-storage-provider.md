# M10-01 — BackupStorageProvider (S3-compatible)

## Objective
Enviar backups para um destino **fora do cluster protegido**, através de uma interface comum que permita mais de um provider sem alterar a lógica de backup.

## Outcome
A plataforma escreve, lê e apaga objetos em um bucket S3-compatible, com credencial no Vault e verificação de conectividade.

## References
- `docs/architecture/05-backup-restore-dr.md` §10 (Backup Storage Providers), §10.1 (credenciais)
- `docs/annexes/C-threat-model-security-hardening.md` §20 (credenciais de backup não dão acesso ao cluster)
- `docs/annexes/D-test-strategy.md` §6.3 (Object Storage contract)

## Preconditions
M03 e M06 aceitos.

## Scope
- Contrato `BackupStorageProvider`: put, get, delete, list, checksum de objeto, multipart para artefatos grandes.
- `StorageProvider` no modelo: tipo, endpoint, bucket, prefix, credencial por `ProviderCredentialBinding`, status.
- Capacidades opcionais detectadas: versioning, object lock, lifecycle, criptografia server-side.
- Teste de conectividade escrevendo e lendo um objeto de verificação.
- Regra: o destino precisa estar **fora** do cluster protegido; a plataforma avisa quando detecta o contrário.

## Out of Scope
- Políticas e retenção (`M10-02`, `M10-15`).
- Criptografia do payload (`M10-04`).
- Destino secundário/replicação (doc 05 §17.2 menciona; sem requisito imediato).

## Application Layer
- **Providers:** `BackupStorageProvider`.
- **Commands:** `ConnectBackupStorage`, `TestBackupStorage`.

## Security Requirements
- **Credenciais de backup não podem dar acesso administrativo ao cluster** (Anexo C §20): escopo mínimo, apenas ao bucket/prefix necessário.
- A credencial vive no Vault e **nunca** aparece em manifest ou log de backup (doc 05 §10.1, regra explícita).
- O endpoint passa pela política de SSRF.
- Criptografia server-side do provider é **desejável, mas não substitui** a criptografia client-side de `M10-04`.
- Object lock e versioning são detectados e recomendados, porque protegem contra apagamento malicioso.
- O destino dentro do cluster protegido é sinalizado como risco — um snapshot preso ao mesmo provider pode desaparecer junto (doc 05 §2).

## Observability Requirements
Estado do destino: alcançável, última verificação, capacidades detectadas. Alerta quando indisponível (doc 05 §17.2, `CRITICAL`).

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Destino indisponível | Alerta `CRITICAL`; backups falham com causa; recovery points anteriores preservados. |
| Credencial inválida | Erro classificado; a UI oferece reconectar. |
| Escopo insuficiente | Erro distinto de autenticação. |
| Endpoint apontando para rede interna | Bloqueado por SSRF. |
| Bucket dentro do cluster protegido | Sinalizado como risco. |
| Objeto grande | Multipart; falha de parte é retomável. |

## Acceptance Criteria
1. `BackupStorageProvider` existe com put, get, delete, list, checksum e multipart.
2. A credencial vive no Vault e **não** aparece em manifest nem em log, provado com valor plantado.
3. A credencial tem escopo mínimo e **não** concede acesso administrativo ao cluster.
4. O endpoint passa pela política de SSRF.
5. O teste de conectividade escreve e lê um objeto de verificação.
6. Versioning, object lock e lifecycle são detectados quando disponíveis e recomendados.
7. Destino dentro do cluster protegido é **sinalizado como risco**.
8. Destino indisponível gera alerta `CRITICAL` e preserva recovery points anteriores.
9. Falha de autenticação, escopo e indisponibilidade são erros distintos.
10. Multipart é usado para artefatos grandes e falha de parte é retomável.
11. Conectar e testar geram AuditLog; negativo cross-team passa.

## Required Tests
- **contract**: put/get/delete/list/checksum/multipart; objeto inexistente; falha de parte.
- **security**: SSRF; credencial ausente de manifest e log; escopo mínimo.
- **integration**: destino indisponível; detecção de capacidades.

## Quality Gates
Local Quality Gate + contract tests + `bin/security`.

## Definition of Done
Os 11 Acceptance Criteria satisfeitos, credencial protegida e sem acesso ao cluster, Critical/High = 0.
