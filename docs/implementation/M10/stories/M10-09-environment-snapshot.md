# M10-09 — Logical Environment Snapshot

## Objective
Congelar o estado lógico de um Environment — o suficiente para recriá-lo — **sem** copiar plaintext de secret nem dados externos da aplicação.

## Outcome
Um snapshot registra Services, releases por digest, recursos, domínios, bindings de `SecretVersion` e configuração; ele referencia, não duplica.

## References
- `docs/architecture/05-backup-restore-dr.md` §9 (snapshots lógicos), §9.1 (Environment Snapshot), §9.3 (não congela secret plaintext)
- `docs/architecture/01-foundation.md` §13.1
- `docs/architecture/10-ui-use-cases.md` UC-037, §19.2

## Preconditions
M06 aceito.

## Scope
- `EnvironmentSnapshot`: environmentId, clusterId, `specJson`, createdBy, `protectedUntil`.
- Conteúdo do doc 05 §9.1: Services, release/image digest, resources, domains, **bindings de SecretVersion**, variáveis, placement, health, referência de cluster.
- **Referência, não cópia**: `SecretVersion` por ID; Artifact por digest.
- Aviso explícito na UI: dados de bancos gerenciados externos **não** estão incluídos.
- Proteção do snapshot (`protectedUntil`), integrando com a retenção de `M06-13` e `M10-15`.
- Criação manual e como parte de fluxos de risco (antes de restore, por exemplo).

## Out of Scope
- Restore do snapshot (`M10-12`).
- `ClusterSnapshot` (`M10-10`).
- Cópia de dados de aplicação — explicitamente fora (doc 05 §1.2).

## Domain Impact
**Invariante:** o snapshot **referencia** `SecretVersion` IDs; ele não duplica material sensível (doc 05 §9.3, regra explícita).

## Application Layer
- **Commands:** `CreateEnvironmentSnapshot`, `ProtectSnapshot`.
- **Queries:** `SnapshotsForEnvironment`, `SnapshotComposition`.

## Security Requirements
- **Não duplicar plaintext** preserva a auditoria e evita criar cópias adicionais de material sensível (doc 05 §9.3).
- Um snapshot protege os `SecretVersion` e `Artifact` que referencia: eles não podem ser apagados enquanto ele existir.
- O snapshot não contém dado de aplicação; a UI é explícita sobre isso, para não criar falsa sensação de proteção.
- Criar e proteger snapshot gera AuditLog.
- Snapshot respeita tenancy.

## Observability Requirements
Composição do snapshot visível: o que ele inclui e o que **não** inclui. Elegibilidade de restore calculada e exibida.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Operação em andamento no Environment | Avisar ou aguardar um ponto consistente (doc 10 UC-037). |
| `SecretVersion` referenciada apagada depois | Impossível: o snapshot protege a referência. |
| Artifact referenciado coletado | Impossível: proteção de retenção (`M06-13`). |
| Provider externo indisponível | O snapshot de configuração pode falhar parcialmente conforme o escopo; nunca marcar completo se faltou parte. |
| Usuário esperando backup de dados | A UI declara explicitamente o que não está incluído. |
| Snapshot muito grande | Paginação na composição; o snapshot é lógico, não volumoso. |

## Acceptance Criteria
1. `EnvironmentSnapshot` captura o conteúdo do doc 05 §9.1.
2. `SecretVersion` é referenciada **por ID**; nenhum plaintext é duplicado, provado com valor plantado.
3. Artifacts são referenciados por digest.
4. O snapshot **protege** as `SecretVersion` e os Artifacts que referencia contra remoção.
5. A UI declara explicitamente que dados de bancos gerenciados externos **não** estão incluídos.
6. Operação em andamento gera aviso ou aguarda um ponto consistente.
7. Snapshot parcial **nunca** é marcado como completo.
8. `protectedUntil` existe e integra com a retenção.
9. A composição e a elegibilidade de restore são visíveis.
10. Criar e proteger geram AuditLog; negativo cross-team passa.

## Required Tests
- **unit**: composição; elegibilidade de restore.
- **integration**: proteção de `SecretVersion` e Artifact referenciados; snapshot parcial não marcado completo.
- **security**: ausência de plaintext no snapshot; negativo cross-team.

## Quality Gates
Local Quality Gate + `bin/security`.

## Definition of Done
Os 10 Acceptance Criteria satisfeitos, referência em vez de cópia provada, proteção de dependências verificada, Critical/High = 0.
