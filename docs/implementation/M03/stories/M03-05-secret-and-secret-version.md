# M03-05 — Secret and immutable SecretVersion

## Objective
Criar a biblioteca central de secrets do Team, com versões **imutáveis** e cifradas, onde nenhuma alteração edita uma versão existente.

## Outcome
Um Secret existe com nome canônico e metadados; cada valor novo cria uma `SecretVersion` imutável cifrada; o plaintext nunca é persistido nem retornado em listagens.

## References
- `docs/architecture/01-foundation.md` §9 (Vault versionado), §9.2 (Secret e SecretVersion)
- `docs/architecture/09-data-model-apis-contracts.md` §6.2, §18 (`UNIQUE(secretId, versionNumber)`), §25 (retenção)
- `docs/annexes/C-threat-model-security-hardening.md` §12
- `docs/architecture/10-ui-use-cases.md` UC-028, UC-029

## Preconditions
`M03-01` done.

## Scope
- `Secret`: id, teamId, name canônico, scope, description, createdBy, timestamps. Metadados **editáveis com audit**.
- `SecretVersion`: id, secretId, versionNumber (inteiro monotônico por Secret), ciphertext, encryptionMetadata, createdBy, createdAt. **Imutável** após criada.
- Constraint `UNIQUE(secretId, versionNumber)`.
- Criação de versão cifra antes de persistir; o plaintext existe apenas em memória durante a operação.
- Listagens retornam **apenas metadados**: nome, contagem de versões, última versão, quem usa.
- Retenção: uma versão referenciada por binding, snapshot ou política de retenção **não** pode ser apagada (doc 09 §25).

## Out of Scope
- Bindings (`M03-06`) e materialização no Swarm (`M03-07`).
- Reveal (`M03-09`).
- Backup e recovery do Vault (`M10-06`).
- Limites de quantidade de secrets/versões (`M11-10`).

## Domain Impact
**Entidades:** `Secret`, `SecretVersion`.
**Invariante central:** `SecretVersion` é imutável. Nenhum `UPDATE` no ciphertext existe no código, verificado por teste.
**Tenancy:** o Secret pertence ao Team; toda query parte de `teamId`.

## Application Layer
- **Commands:** `CreateSecret`, `CreateSecretVersion`, `UpdateSecretMetadata`, `DeleteSecret` (bloqueado com bindings ativos).
- **Queries:** `SecretsForTeam`, `SecretVersions` (metadados apenas).
- **Policies:** `vault.create`, `vault.version.create`, `vault.read_metadata`, `vault.delete` (doc 04 §11).

## API Impact
Nenhum endpoint retorna plaintext. A criação de versão aceita o valor e devolve apenas os metadados da versão criada.

## Security Requirements
- **Somente ciphertext + metadata no PostgreSQL** (Anexo C §12).
- Criptografia indisponível → **bloquear**; nunca fallback para plaintext (doc 10 UC-029).
- O valor nunca aparece em listagem, resposta, log, evento, payload de Operation ou audit.
- `SecretVersion` nunca é editada; alteração cria versão nova.
- Deleção de Secret com bindings ativos é bloqueada; versões referenciadas não são apagadas.
- Nome do Secret é validado (chave de ambiente válida) e não aceita conteúdo que possa quebrar injeção posterior.
- Permissões distintas para ler metadados, criar Secret, criar versão e deletar (doc 04 §11).

## Observability Requirements
- `secret.version.created.v1` emitido **sem** o valor.
- AuditLog com actor, secretId, versionNumber e resultado — nunca o valor.
- Métrica: versões criadas por período, secrets sem uso.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Criptografia indisponível | Bloquear; nunca gravar em claro. |
| Valor vazio ou fora da política | Rejeitar na validação. |
| Tentativa de editar uma versão | Impossível: não existe caminho de `UPDATE`; teste comprova. |
| Deletar Secret com binding ativo | Bloqueado com a lista de quem usa. |
| Deletar versão referenciada | Bloqueado por retenção. |
| Nome inválido | Rejeitado com a regra explicada. |
| Duas versões criadas concorrentemente | `UNIQUE(secretId, versionNumber)` serializa; nenhuma numeração duplicada. |

## Acceptance Criteria
1. `Secret` e `SecretVersion` existem; o valor é persistido **apenas** cifrado.
2. `UNIQUE(secretId, versionNumber)` existe e é provado por teste concorrente.
3. Nenhum caminho edita uma `SecretVersion` existente, verificado por teste.
4. Nenhuma listagem, resposta de API, log, evento, payload de Operation ou AuditLog contém o valor, provado com valor plantado.
5. Criptografia indisponível bloqueia a criação; nenhum fallback para plaintext.
6. Metadados do Secret são editáveis com audit; o valor não.
7. Deletar Secret com binding ativo é bloqueado com a lista de consumidores.
8. Uma versão referenciada por binding ou snapshot não pode ser apagada.
9. O nome do Secret é validado e não aceita conteúdo perigoso para injeção posterior.
10. As permissões de metadata, create, version.create e delete são distintas e testadas.
11. Negativo cross-team passa em todas as operações.

## Required Tests
- **unit**: validação de nome; numeração monotônica; imutabilidade.
- **integration**: `UNIQUE` em teste concorrente; bloqueio de deleção; criptografia indisponível bloqueando.
- **policy**: matriz de permissões do Vault; negativo cross-team.
- **security**: valor plantado ausente de todos os sinks; ausência de caminho de edição.

## Quality Gates
Local Quality Gate + `bin/security` + `bin/fitness` (AF-06).

## Definition of Done
Os 11 Acceptance Criteria satisfeitos, imutabilidade e ausência de plaintext provadas, Critical/High = 0.
