# M06-01 — Immutable Release

## Objective
Criar a unidade imutável que pode ser implantada e promovida: um Artifact por digest somado à fotografia da configuração necessária para reproduzir aquela execução.

## Outcome
Uma `Release` existe referenciando digest, `runtimeSpecHash`, `SourceRevision` e as `SecretVersion` usadas — **sem** plaintext.

## References
- `docs/architecture/02-build-deploy.md` §10 (Release: configuração pronta para implantação)
- `docs/architecture/09-data-model-apis-contracts.md` §8.3 (Release)
- `docs/architecture/07-internal-control-plane.md` §13.1 (release imutável)
- `docs/annexes/C-threat-model-security-hardening.md` §11 (supply chain)

## Preconditions
M05 aceito.

## Scope
- `Release`: id, serviceLineageId, artifactId, sourceRevisionId, `runtimeSpecHash`, snapshot de configuração não sensível, referências de `SecretVersion`, createdAt, createdBy. **Imutável**.
- Snapshot da configuração: replicas, recursos, env não sensíveis, healthcheck, portas, placement, política de rollout.
- Referência a `SecretVersion` por **ID**, nunca valor.
- `runtimeSpecHash` cobrindo o spec não sensível, para detectar mudança de configuração entre releases.
- Criação de Release a partir de um Artifact, com a configuração atual do Service no Environment alvo.

## Out of Scope
- Deployment (`M06-02`).
- Promoção (`M06-09`).
- `serviceLineage` (`M06-14`) — o campo existe aqui, a lógica lá.

## Domain Impact
**Entidade:** `Release`, imutável.
**Invariante:** uma Release nunca muda. Configuração diferente → Release nova.

## Application Layer
- **Commands:** `CreateRelease`.
- **Queries:** `ReleasesForService`, `ReleaseDetail`.

## Security Requirements
- **Sem plaintext**: a Release registra `SecretVersion` IDs (doc 02 §10, regra explícita).
- O Artifact é referenciado por **digest**; nenhuma referência por tag.
- `Release` é imutável; nenhum caminho a edita.
- A proveniência liga Release → Artifact → Build → SourceRevision → commit (Anexo C §11).
- Criar Release exige permissão e gera AuditLog.

## Observability Requirements
Release visível com digest abreviado, commit curto, autor e data. `runtimeSpecHash` permite mostrar “configuração idêntica” ou “configuração mudou” entre releases.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Artifact inexistente ou inutilizável | Bloquear a criação com causa (inclui o caso de build secret detectado em `M05-10`). |
| `SecretVersion` referenciada indisponível | Bloquear a criação. |
| Tentativa de editar uma Release | Impossível; teste comprova. |
| Configuração idêntica à Release anterior | Permitido; a Release nova existe, mas a UI mostra que o spec não mudou. |
| Artifact de outro Team | Negado sem revelar existência. |

## Acceptance Criteria
1. `Release` existe com todos os campos do doc 09 §8.3 e é **imutável**.
2. O Artifact é referenciado por digest; nenhuma referência por tag.
3. As secrets são referenciadas por `SecretVersion` ID; nenhum plaintext, provado com valor plantado.
4. `runtimeSpecHash` cobre o spec não sensível e distingue mudanças de configuração.
5. Nenhum caminho edita uma Release existente.
6. Artifact inexistente, inutilizável ou de outro Team bloqueia a criação.
7. `SecretVersion` indisponível bloqueia a criação.
8. A proveniência Release → Artifact → Build → SourceRevision → commit é consultável.
9. Criar Release exige permissão, gera AuditLog e passa no negativo cross-team.

## Required Tests
- **unit**: imutabilidade; cálculo de `runtimeSpecHash`.
- **integration**: bloqueio por Artifact/SecretVersion indisponível; proveniência consultável.
- **security**: ausência de plaintext; ausência de referência por tag; Artifact cross-team.
- **policy**: negativo cross-team.

## Quality Gates
Local Quality Gate + `bin/security` + `bin/fitness` (AF-06).

## Definition of Done
Os 9 Acceptance Criteria satisfeitos, imutabilidade e ausência de plaintext provadas, Critical/High = 0.
