# M05-05 — SourceRevision: resolving a branch to an immutable commit

## Objective
Congelar a identidade do código: no instante do trigger, a branch é resolvida para um commit SHA, e o build fica permanentemente ligado a ele.

## Outcome
Um build de `main` registra o SHA exato; um push posterior **não** altera builds anteriores.

## References
- `docs/architecture/02-build-deploy.md` §3.1 (branch resolvida para commit imutável)
- `docs/architecture/09-data-model-apis-contracts.md` §7 (SourceRevision)
- `docs/annexes/C-threat-model-security-hardening.md` §11 (supply chain: registrar provider, repo, ref, commit e ator)
- `docs/annexes/D-test-strategy.md` §8 (commit pinning)

## Preconditions
`M05-02` e `M05-03` done.

## Scope
- `SourceRevision`: repositório, `commitSha`, branch/tag de origem, autor do commit, mensagem truncada, timestamp.
- Resolução no momento do trigger, com o token de curta duração.
- Registro da proveniência completa exigida pelo Anexo C §11: provider, repo, ref, commit SHA e identidade do webhook/ator.
- Suporte a trigger manual escolhendo branch **ou** commit específico.
- Submodules quando habilitado, com a mesma disciplina de credencial.

## Out of Scope
- Checkout e build (`M05-08`, `M05-09`).
- Dedup de build por revisão + configuração (`M05-06`).
- Assinatura de commit e verificação de autor (backlog de supply chain).

## Domain Impact
**Entidade:** `SourceRevision`, imutável.
**Invariante:** o `commitSha` é a identidade real da revisão (doc 09 §7). Branch e tag são referências móveis.

## Application Layer
- **Commands:** `ResolveSourceRevision`.
- **Queries:** `SourceRevisionForBuild`.

## Security Requirements
- A resolução usa o token de curta duração de `M05-03`; nunca uma credencial persistente.
- O `commitSha` recebido do provider é **validado** como hash no formato esperado — nunca usado bruto em um comando.
- A mensagem de commit é **dado não confiável**: truncada, sanitizada e nunca renderizada como HTML ativo nem interpretada como instrução por um agente (Anexo F §17.1).
- A proveniência registrada é a base da cadeia de supply chain: sem ela, não é possível responder “de onde veio esta imagem”.
- A resolução por ref fornecida pelo usuário valida o formato do ref.

## Observability Requirements
Log com repositório, ref, `commitSha` e origem do trigger (manual, webhook, API). A UI mostra o commit curto e o autor.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Branch inexistente | Erro classificado; nenhum build criado. |
| Repositório inacessível | Erro distinguindo credencial de permissão de existência. |
| Push posterior à resolução | Não afeta o build já resolvido; teste obrigatório. |
| Ref malformado | Rejeitado por validação. |
| Mensagem de commit com payload de injeção | Sanitizada; nunca executada nem renderizada como ativo. |
| Provider indisponível | Retry com backoff; o trigger fica pendente com causa. |

## Acceptance Criteria
1. A branch é resolvida para um `commitSha` no momento do trigger.
2. Um push posterior **não** altera um build já resolvido, provado por teste.
3. A proveniência registrada inclui provider, repositório, ref, `commitSha` e a origem do trigger.
4. O `commitSha` é validado como hash no formato esperado antes de qualquer uso.
5. O ref fornecido pelo usuário é validado.
6. A mensagem de commit é truncada e sanitizada; nunca renderizada como HTML ativo.
7. Branch inexistente produz erro classificado sem criar build.
8. Repositório inacessível distingue credencial, permissão e existência.
9. A resolução usa o token de curta duração; nenhuma credencial persistente é utilizada.
10. Trigger manual permite escolher branch ou commit específico.
11. `SourceRevision` é imutável.

## Required Tests
- **unit**: validação de SHA e de ref; sanitização de mensagem.
- **integration**: push posterior não alterando build; branch inexistente; repositório inacessível.
- **contract**: resolução de commit no provider.
- **security**: injeção via mensagem de commit; SHA malformado rejeitado.

## Quality Gates
Local Quality Gate + contract tests + `bin/security`.

## Definition of Done
Os 11 Acceptance Criteria satisfeitos, pinning de commit provado, sanitização de conteúdo do repositório verificada, Critical/High = 0.
