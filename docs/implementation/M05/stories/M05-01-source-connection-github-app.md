# M05-01 — SourceConnection via GitHub App

## Objective
Conectar repositórios através de um GitHub App instalado pelo Team, em vez de Personal Access Tokens permanentes.

## Outcome
O Team instala o App, concede acesso a repositórios específicos, e a plataforma passa a listar apenas esses repositórios.

## References
- `docs/architecture/02-build-deploy.md` §4 (GitHub App e autenticação), §4.1 (permissões mínimas)
- `docs/architecture/09-data-model-apis-contracts.md` §7 (source connections)
- `docs/annexes/C-threat-model-security-hardening.md` §13 (integrações externas), T-Git tokens

## Preconditions
M03 aceito. GitHub App registrado com App ID, private key e webhook secret.

## Scope
- `SourceConnection`: teamId, provider, installationId, account/login, status, timestamps.
- Fluxo de instalação e callback, com `state`/nonce e allowlist rígida de redirect.
- Listagem dos repositórios acessíveis pela instalação.
- Permissões mínimas do doc 02 §4.1: `Contents: Read`, `Metadata: Read`, Webhooks; Pull Requests e Checks opcionais.
- Private key do App e webhook secret armazenados no Vault.
- Desconexão revogando o acesso e invalidando material derivado.

## Out of Scope
- Tokens de instalação de curta duração (`M05-03`).
- Webhook em si (`M05-04`).
- Git genérico por URL e GitLab — o modelo permite; cada provider é Story própria.
- Preview environments por Pull Request (backlog).

## Domain Impact
`SourceConnection` pertence ao Team; toda query parte de `teamId`.

## Application Layer
- **Commands:** `ConnectSource`, `DisconnectSource`, `RefreshRepositoryList`.
- **Queries:** `RepositoriesForConnection`.
- **Policies:** conectar exige ADMIN.

## Security Requirements
- **GitHub App em vez de PAT**: o PAT permanente é credencial de longa duração com escopo amplo (doc 02 §4).
- Private key do App e webhook secret **no Vault**, nunca em configuração em claro.
- Callback com `state`/nonce e **allowlist rígida** de redirect; proteção contra open redirect (Anexo C §13).
- A busca de metadados do provider passa pela política de SSRF.
- Nenhum material de credencial é retornado ao frontend após a criação.
- Desconectar revoga o acesso e invalida material derivado imediatamente.
- Conexão e desconexão geram AuditLog.

## Observability Requirements
Estado da conexão observável: instalação válida, repositórios acessíveis, último refresh. Falha de autenticação distinguível de falha de permissão.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Instalação removida no provider | Conexão marcada como inválida; builds futuros bloqueiam com causa; builds por artefato existente continuam possíveis (Anexo B §14). |
| Permissão insuficiente | Erro distinto de autenticação, indicando o que falta. |
| Callback com `state` inválido | Rejeitado. |
| Redirect fora da allowlist | Rejeitado. |
| Provider indisponível | Erro classificado; a UI oferece “reconectar”. |

## Acceptance Criteria
1. Um Team instala o GitHub App e a plataforma persiste `SourceConnection` com `installationId`.
2. Apenas os repositórios concedidos aparecem na listagem.
3. As permissões solicitadas são as mínimas do doc 02 §4.1.
4. Private key do App e webhook secret vivem no Vault; nenhum aparece em configuração em claro nem na resposta.
5. O callback valida `state`/nonce e a allowlist de redirect, provado por casos negativos.
6. A busca de metadados do provider passa pela política de SSRF.
7. Desconectar revoga o acesso e invalida material derivado imediatamente.
8. Instalação removida no provider marca a conexão como inválida com causa.
9. Falha de permissão é distinguível de falha de autenticação.
10. Conectar e desconectar exigem ADMIN, geram AuditLog e passam no negativo cross-team.

## Required Tests
- **contract**: listagem de repositórios; instalação inválida; permissão insuficiente.
- **integration**: callback com `state` inválido; redirect fora da allowlist; desconexão revogando acesso.
- **security**: SSRF na busca de metadados; ausência de credencial na resposta.
- **policy**: negativo cross-team; role sem permissão.

## Quality Gates
Local Quality Gate + contract tests + `bin/security`.

## Definition of Done
Os 10 Acceptance Criteria satisfeitos, open redirect e SSRF cobertos, credenciais no Vault, Critical/High = 0.
