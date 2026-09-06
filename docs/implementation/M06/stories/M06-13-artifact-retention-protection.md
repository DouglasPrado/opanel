# M06-13 — Artifact retention protection against garbage collection

## Objective
Impedir que um artefato ainda necessário para rollback, release ativa ou snapshot seja coletado — porque descobrir isso durante um incidente é tarde demais.

## Outcome
Um Artifact referenciado por Release ativa, rollback candidate ou snapshot protegido **não pode** ser removido; o GC só toca o que não tem referência protegida.

## References
- `docs/architecture/05-backup-restore-dr.md` §8 (imagens são parte do recovery path), §8.1 (retenção mínima sugerida)
- `docs/architecture/09-data-model-apis-contracts.md` §25 (GC de Artifact), §27 (validação de GC)
- `docs/annexes/C-threat-model-security-hardening.md` §11 (proteção contra delete de artifact em uso)

## Preconditions
`M06-07` done.

## Scope
- `retentionClass` no Artifact e cálculo de **referências protegidas**: Release ativa, deployments dentro da janela de rollback, snapshots (quando `M10-09` existir), e proteção explícita.
- Bloqueio de remoção enquanto houver referência protegida.
- Janela de rollback configurável: últimas N releases ou janela temporal (doc 05 §8.1).
- Marcação explícita de “Protected Release”, que nunca expira sem remoção explícita da proteção.
- Verificação antes de qualquer GC, conforme doc 09 §27.

## Out of Scope
- Execução do GC de imagens no Registry propriamente dito — depende do provider; aqui a plataforma **protege** e informa.
- Retenção de backups (`M10-15`).
- Mirror de imagens críticas (doc 05 §8.1, opcional futuro).

## Application Layer
- **Queries:** `ProtectedArtifacts`, `ArtifactReferences`.
- **Commands:** `ProtectRelease`, `UnprotectRelease`.

## Security Requirements
- Esta é uma proteção de **recuperabilidade**: sem ela, o rollback de `M06-07` e o Clean Rebuild de `M10-13` falham silenciosamente até serem necessários.
- Remover uma proteção é ação explícita e auditada.
- O cálculo de referências é conservador: na dúvida, **proteger**. Um artefato protegido a mais custa storage; um coletado a menos custa um incidente.
- A UI mostra quantas releases estão na janela de rollback e o que aconteceria ao reduzi-la.

## Observability Requirements
- Alerta quando um digest necessário está indisponível no Registry (doc 05 §17.2, condição `CRITICAL`).
- Métrica: artefatos protegidos, artefatos elegíveis a GC, storage estimado.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Tentativa de remover artefato referenciado | Bloqueada com a lista de quem o referencia. |
| Digest necessário sumiu do Registry | Alerta `CRITICAL`; rollback e Clean Rebuild sinalizam a indisponibilidade **antes** de tentar. |
| Redução da janela de rollback | Mostrar o que deixará de ser protegido antes de aplicar. |
| Proteção removida por engano | Ação auditada; o artefato entra em elegibilidade, não é removido imediatamente. |
| Referência ambígua | Tratar como protegida. |

## Acceptance Criteria
1. `retentionClass` existe e o cálculo de referências protegidas cobre Release ativa, janela de rollback e proteção explícita.
2. Um Artifact referenciado **não pode** ser removido, provado por teste.
3. A janela de rollback é configurável por N releases ou por tempo.
4. “Protected Release” nunca expira sem remoção explícita da proteção.
5. Remover proteção é ação explícita e auditada.
6. Referência ambígua é tratada como protegida.
7. Reduzir a janela mostra o que deixará de ser protegido **antes** de aplicar.
8. Digest necessário indisponível no Registry dispara alerta `CRITICAL`.
9. Rollback e futuros restores sinalizam a indisponibilidade antes de tentar.
10. Métricas de artefatos protegidos e elegíveis estão disponíveis.
11. A verificação roda **antes** de qualquer operação de GC.

## Required Tests
- **unit**: cálculo de referências; janela de rollback; caso ambíguo.
- **integration**: remoção bloqueada; redução de janela mostrando impacto; proteção explícita.
- **contract**: detecção de digest ausente no Registry.
- **security**: auditoria da remoção de proteção.

## Quality Gates
Local Quality Gate + contract tests.

## Definition of Done
Os 11 Acceptance Criteria satisfeitos, bloqueio de remoção provado, alerta de digest ausente verificado, Critical/High = 0.
