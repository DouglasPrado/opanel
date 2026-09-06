# M05-03 — Short-lived installation tokens for repository access

## Objective
Acessar o repositório com credenciais **temporárias**, geradas sob demanda e descartadas, em vez de um segredo permanente da aplicação.

## Outcome
Cada operação de clone usa um token de curta duração gerado no momento; o token nunca aparece em build log, deployment log ou frontend.

## References
- `docs/architecture/02-build-deploy.md` §4.2 (tokens temporários)
- `docs/annexes/C-threat-model-security-hardening.md` §10.1 (build secrets), §13 (OAuth/installation tokens)
- `docs/annexes/D-test-strategy.md` §6.3 (clone credential lifecycle)

## Preconditions
`M05-01` done.

## Scope
- Geração de installation token de curta duração a partir da private key do App (que vive no Vault).
- Escopo mínimo: apenas o repositório necessário, apenas leitura de conteúdo.
- Entrega ao builder como **credencial efêmera**, com o menor tempo de vida compatível com a operação.
- Descarte imediato após o uso; nenhum armazenamento persistente do token.
- Redaction específica: o token é registrado como valor conhecido no scanner de `M03-10`.

## Out of Scope
- Credencial de push ao Registry (`M05-11`).
- Rotação da private key do App (`M11`, RB-20).
- Clone em si (`M05-05`, `M05-08`).

## Application Layer
- **Commands:** `IssueRepositoryAccessToken` (interno, não exposto na API pública).

## Security Requirements
- O token **nunca** é tratado como secret permanente da aplicação (doc 02 §4.2).
- **Nunca** aparece em build log, deployment log, frontend, evento, audit ou payload de Operation — regra explícita do doc 02 §4.2, verificada com valor plantado.
- Escopo mínimo: apenas o repositório da operação.
- Vida curta: o tempo de vida é o menor compatível com a operação, e é renovado em vez de estendido.
- O token não é persistido em nenhum lugar; existe em memória e na entrega efêmera ao builder.
- Um builder comprometido que capture o token tem uma janela mínima e um escopo mínimo — o dano é limitado por construção, não por confiança.
- Se o clone falhar, o token é invalidado quando o provider permitir.

## Observability Requirements
Log da emissão com repositório e validade — **sem** o token. Métrica de tokens emitidos e de falhas de emissão.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Emissão falha | Build bloqueia com causa; não tentar credencial alternativa de longa duração. |
| Token expira durante o clone | Reemitir; o build não falha por isso quando é recuperável. |
| Token vazado em log | Impossível: redaction + valor plantado no scanner; se ocorrer, é finding Critical. |
| Private key do App indisponível | Bloquear; nunca cair para PAT. |
| Repositório removido | Erro classificado, distinto de falha de credencial. |

## Acceptance Criteria
1. Cada operação de clone usa um token gerado sob demanda a partir da private key do Vault.
2. O token tem escopo mínimo (apenas o repositório) e vida curta.
3. O token **não** é persistido em nenhum armazenamento.
4. O token não aparece em build log, deployment log, frontend, evento, audit ou payload de Operation, provado com valor plantado.
5. Falha de emissão bloqueia o build; **nenhum** fallback para credencial de longa duração.
6. Token expirado durante o clone é reemitido quando recuperável.
7. Private key indisponível bloqueia; nunca cai para PAT.
8. A emissão é registrada sem o token.
9. Repositório removido produz erro classificado, distinto de falha de credencial.

## Required Tests
- **unit**: escopo e validade do token.
- **integration**: emissão, uso e descarte; expiração durante a operação; falha de emissão bloqueando.
- **security**: valor plantado ausente de todos os sinks; ausência de persistência do token; ausência de fallback para PAT.
- **contract**: ciclo de vida da credencial de clone.

## Quality Gates
Local Quality Gate + `bin/security` + `bin/fitness` (AF-06).

## Definition of Done
Os 9 Acceptance Criteria satisfeitos, ausência do token em todos os sinks provada, ausência de fallback verificada, Critical/High = 0.
