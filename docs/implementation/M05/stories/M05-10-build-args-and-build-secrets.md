# M05-10 — Build args versus build secrets

## Objective
Separar claramente valores que podem acabar na imagem (build args) de valores que **nunca** podem persistir nela (build secrets), entregando os últimos como mount temporário.

## Outcome
Um `NPM_TOKEN` é entregue ao BuildKit como secret mount e descartado; ele não aparece em layer, em `history`, em stdout/stderr, em metadata nem em log.

## References
- `docs/architecture/02-build-deploy.md` §6.3 (build args × build secrets × runtime secrets)
- `docs/annexes/C-threat-model-security-hardening.md` §10.1 (build secrets)
- `docs/annexes/D-test-strategy.md` §8, §17 (secrets)

## Preconditions
`M05-08` e `M05-09` done.

## Scope
- **Build args**: valores **não sensíveis**, podem acabar em metadata/layers dependendo do Dockerfile. A UI diz isso explicitamente.
- **Build secrets**: entregues ao BuildKit como **secret mount**, disponíveis apenas durante a instrução que os usa, descartados ao final.
- Origem dos build secrets: `SecretVersion` do Vault, referenciada por binding de build (não pelo binding de runtime).
- Regra normativa: **secret de runtime nunca é necessário para construir a imagem** (doc 02 §6.3).
- Verificação automatizada pós-build: o valor do build secret **não** está na imagem publicada.
- Redaction dos logs de build para os valores conhecidos.

## Out of Scope
- Secrets de runtime (`M03`) — explicitamente **não** participam do build.
- Credencial de push ao Registry (`M05-11`).
- Assinatura de imagem e SBOM (M13/backlog).

## Application Layer
- **Commands:** `BindBuildSecret`, `UpsertBuildArg`.
- **Queries:** `BuildInputsForService`.

## Security Requirements
Esta Story é o principal controle contra vazamento de credencial por imagem:
- Build secret **nunca** vira ENV permanente da imagem (Anexo C §10.1).
- **Nunca** escrito em layer, em `docker history`, em stdout/stderr ou em metadata do BuildKit.
- O valor vem do Vault, é decifrado no boundary autorizado e entregue como mount efêmero.
- A UI **avisa explicitamente** que build args podem acabar na imagem — chamá-los de “variável” sem esse aviso induziria o usuário a colocar credencial ali.
- Verificação pós-build automatizada: inspecionar a imagem publicada procurando o valor plantado. Encontrar é finding Critical.
- Redaction: o valor é registrado no scanner de `M03-10` como valor conhecido.
- Um build secret marcado como sensível **não** pode ser convertido em build arg.

## Observability Requirements
A UI mostra, por build, quais args e quais secrets (por **identidade**, nunca valor) foram usados. O `buildConfigHash` inclui a identidade dos secrets.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Usuário coloca credencial em build arg | Aviso explícito; heurística de detecção registra; a decisão é do usuário mas fica rastreável. |
| Build secret aparecendo na imagem | Verificação pós-build falha o build como incidente de segurança; a imagem **não** é promovida a Artifact utilizável. |
| Dockerfile ecoando o secret | Redaction no log; a verificação pós-build ainda é a garantia real. |
| Secret indisponível no Vault | Build bloqueado antes de iniciar. |
| Tentativa de usar secret de runtime no build | Rejeitada; a regra é normativa. |

## Acceptance Criteria
1. Build args e build secrets são conceitos distintos na API e na UI.
2. A UI avisa explicitamente que build args podem acabar na imagem.
3. Build secrets vêm de `SecretVersion` do Vault e são entregues como **mount temporário** do BuildKit.
4. O valor do build secret **não** aparece em layer, `history`, stdout/stderr, metadata ou log, provado por verificação pós-build com valor plantado.
5. Encontrar o valor na imagem publicada falha o build como incidente de segurança, e o Artifact não é considerado utilizável.
6. Secret de runtime **não** participa do build; a tentativa é rejeitada.
7. Um build secret não pode ser convertido em build arg.
8. Secret indisponível no Vault bloqueia o build antes de iniciar.
9. Heurística detecta credencial em build arg e registra o aviso.
10. O `buildConfigHash` inclui a identidade dos build secrets, nunca o valor.
11. A UI mostra args e a identidade dos secrets usados por build.

## Required Tests
- **security**: verificação pós-build com valor plantado em imagem (layers, history, metadata); Dockerfile ecoando o secret; tentativa de usar secret de runtime.
- **Build Lab**: build com secret mount funcionando; secret indisponível bloqueando.
- **unit**: separação de conceitos; heurística de detecção; `buildConfigHash`.

## Quality Gates
Local Quality Gate + Build Lab + `bin/security`. **Story crítica: exige plan mode.**

## Definition of Done
Os 11 Acceptance Criteria satisfeitos, verificação pós-build com valor plantado verde, ausência do secret na imagem provada, Critical/High = 0.
