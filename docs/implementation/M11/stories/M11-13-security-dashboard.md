# M11-13 — Security dashboard

## Objective
Reunir em um lugar a postura de segurança do Team: MFA, Recovery Key, sessões, tokens e eventos sensíveis recentes.

## Outcome
O OWNER abre a área de Security e vê o que está protegido, o que está pendente e o que aconteceu de sensível recentemente.

## References
- `docs/architecture/10-ui-use-cases.md` §21.1 (security dashboard), §21.2 (Recovery Key)
- `docs/architecture/09-data-model-apis-contracts.md` §23 (`SecurityOverview`)
- `docs/architecture/04-identity-teams-security.md` §12

## Preconditions
`M11-05`, `M11-07` e `M11-11` done. Integra com `M03-13`.

## Scope
- Itens do doc 10 §21.1: MFA (configurada/recomendada/exigida), Recovery Key (verificada/não verificada/data de rotação), sessões ativas, tokens de API ativos e último uso, reveals recentes de secret.
- Reuso do estado de recovery de `M03-13` e do Protection Readiness de `M10-17` quando existirem.
- Ações rápidas: rotacionar Recovery Key, revogar sessões, revogar tokens.
- Badge de atenção na navegação quando há item pendente.

## Out of Scope
- Detecção automática de anomalia — “sem automação opaca no core” (doc 10 §21.1).
- SIEM.
- Postura de segurança da instalação (`M11-12`).

## Application Layer
- **Queries:** `SecurityOverview`.

## Security Requirements
- O painel **não** exibe valores: nem Recovery Key, nem token, nem secret — apenas estados, fingerprints e metadados (doc 10 §21.2).
- Eventos sensíveis recentes mostram **que** aconteceram, com actor e recurso, não o conteúdo.
- O acesso é restrito a OWNER/ADMIN conforme a policy.
- Rotacionar a Recovery Key a partir daqui exige step-up, como em `M03-03`.
- Um item que não pôde ser avaliado é `indisponível`, nunca `ok`.

## Observability Requirements
Adoção de MFA por papel; tokens ociosos; idade da última verificação de Recovery Key. Cada item com o que fazer para melhorar.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Recovery Key não verificada | Destaque `CRITICAL` para recovery readiness. |
| MFA não configurada em papel que a exige | Destaque com a ação de configurar. |
| Token ocioso há muito tempo | Sinalizado como candidato a revogação. |
| Reveal recente de secret de produção | Listado como evento sensível. |
| Item não avaliável | `indisponível` com causa. |
| Sem permissão | Tela explicativa sem vazar. |

## Acceptance Criteria
1. O painel mostra os itens do doc 10 §21.1.
2. **Nenhum valor é exibido**: nem Recovery Key, nem token, nem secret — apenas estados e fingerprints.
3. Recovery Key não verificada aparece com destaque `CRITICAL`.
4. MFA ausente em papel que a exige aparece com destaque e ação.
5. Tokens ociosos são sinalizados como candidatos a revogação.
6. Reveals recentes de secret aparecem como eventos sensíveis, sem o conteúdo.
7. Item não avaliável é `indisponível` com causa, nunca `ok`.
8. Rotacionar a Recovery Key a partir do painel exige step-up.
9. As ações rápidas (revogar sessão, revogar token) funcionam.
10. O badge de atenção aparece quando há item pendente.
11. O acesso é restrito conforme a policy; negativo cross-team passa.
12. Cada item mostra o que fazer para melhorar.

## Required Tests
- **unit (frontend)**: itens do painel; badge; estado indisponível.
- **security**: ausência de valores; permissão; step-up para rotação.
- **integration**: integração com o estado de recovery e com o audit.

## Quality Gates
Local Quality Gate + Reuse Gate + `bin/security`.

## Definition of Done
Os 12 Acceptance Criteria satisfeitos, ausência de valores no painel provada, Critical/High = 0.
