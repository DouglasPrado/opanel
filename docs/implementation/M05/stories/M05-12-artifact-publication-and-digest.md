# M05-12 — Artifact publication and immutable digest

## Objective
Publicar a imagem construída e registrar o `Artifact` identificado por **digest** — a identidade imutável que deploy, rollback e promoção vão usar.

## Outcome
Ao final de um build bem-sucedido existe um `Artifact` com `registryRef` e `sha256:`; a tag é apenas um alias humano.

## References
- `docs/architecture/02-build-deploy.md` §9 (registry e artefatos imutáveis), §9.1 (naming), §9.2 (Artifact)
- `docs/architecture/09-data-model-apis-contracts.md` §8.2 (Artifact), §18 (`UNIQUE(registryRef, digest)`)
- `docs/annexes/C-threat-model-security-hardening.md` §11 (supply chain), T08

## Preconditions
`M05-10` e `M05-11` done.

## Scope
- Push da imagem para o Registry com tag amigável derivada do commit.
- **Resolução e persistência do digest** após o push.
- `Artifact`: id, registryRef, digest, platforms, sizeBytes, `createdByBuildId`, `retentionClass`, `sbomRef` (campo reservado).
- Constraint `UNIQUE(registryRef, digest)`.
- Verificação pós-push: o digest publicado é o mesmo que a plataforma registrou.
- Verificação pós-build de build secrets (`M05-10`) executada **antes** de o Artifact ser considerado utilizável.

## Out of Scope
- `Release` e `Deployment` (`M06`).
- GC e retenção (`M06-13`).
- SBOM e assinatura (backlog; o campo `sbomRef` fica reservado sem acoplar formato).
- Multi-arch (backlog).

## Domain Impact
**Entidade:** `Artifact`, imutável.
**Invariante:** o digest é a identidade do conteúdo; a tag é metadata de UX e **não** é fonte de verdade (doc 02 §9.1).

## Application Layer
- **Commands:** `PublishArtifact`.
- **Queries:** `ArtifactByDigest`, `ArtifactsForService`.

## Security Requirements
- **Deploy por digest** é a mitigação de T08 (imagem/tag trocada após aprovação). Nada no sistema pode implantar por tag mutável.
- O digest é resolvido a partir da resposta do Registry e **verificado** por consulta ao manifest — não assumido.
- A verificação de build secret de `M05-10` roda antes de o Artifact ficar disponível; falhar significa que o Artifact não pode ser usado.
- A credencial de push é a escopada de `M05-11`.
- `Artifact` é imutável: nenhum caminho o edita.
- A proveniência liga Artifact → Build → SourceRevision → repositório → commit (Anexo C §11).

## Observability Requirements
- Digest, tamanho e plataforma registrados; duração do push.
- A UI mostra o digest abreviado e permite copiar o completo.
- Métrica: artefatos publicados, falhas de push por classe.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Push falha | Build `FAILED`; nenhum Artifact criado; a release atual do Service não muda. |
| Digest divergente do esperado | Falha de integridade; **não** registrar o Artifact. |
| Registry indisponível durante o push | Retry com backoff; falha classificada após o limite. |
| Mesmo digest publicado novamente | Deduplicado pela constraint; não cria Artifact duplicado. |
| Verificação de build secret falha | Artifact marcado como inutilizável; incidente de segurança. |
| Tag colidindo | A tag é alias; a identidade é o digest, então não há ambiguidade real. |

## Acceptance Criteria
1. Um build bem-sucedido publica a imagem e registra um `Artifact` com `registryRef` e `digest`.
2. O digest é **verificado** contra o manifest do Registry, não assumido.
3. `UNIQUE(registryRef, digest)` existe; republicar o mesmo digest não duplica o Artifact.
4. `Artifact` é imutável; nenhum caminho o edita.
5. A tag é alias humano e **nenhuma** parte do sistema a usa como identidade.
6. Digest divergente do esperado falha por integridade e não registra o Artifact.
7. Push falho resulta em build `FAILED` sem alterar a release atual do Service.
8. A verificação de build secret roda antes de o Artifact ficar utilizável; falhar torna o Artifact inutilizável.
9. A proveniência Artifact → Build → SourceRevision → repositório → commit é consultável.
10. Registry indisponível leva a retry com backoff e falha classificada após o limite.
11. O digest completo é copiável na UI.
12. `sbomRef` existe como campo reservado, sem acoplar formato.

## Required Tests
- **unit**: imutabilidade; parsing e validação de digest.
- **integration**: dedup por constraint; push falho não alterando o Service; proveniência consultável.
- **contract**: manifest e resolução de digest no Registry.
- **security**: digest divergente rejeitado; verificação de build secret bloqueando o uso do Artifact.

## Quality Gates
Local Quality Gate + contract tests + Build Lab + `bin/security`.

## Definition of Done
Os 12 Acceptance Criteria satisfeitos, digest verificado contra o manifest, proveniência completa, Critical/High = 0.
