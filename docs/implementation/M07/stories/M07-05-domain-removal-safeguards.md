# M07-05 — Domain removal safeguards

## Objective
Remover um domínio avaliando o impacto antes de executar: certificado, SAN, registro de DNS gerenciado e tráfego em curso.

## Outcome
O usuário vê o que vai acontecer — rota removida, certificado afetado, registro de DNS removido — e confirma; nada é apagado além do que a plataforma criou.

## References
- `docs/architecture/09-data-model-apis-contracts.md` §27 (remover domínio: avaliar impacto de certificate/SAN e DNS gerenciado)
- `docs/architecture/10-ui-use-cases.md` §26 (ações destrutivas)
- `docs/architecture/08-networking-domains-edge.md` §14 (versões e grace period)

## Preconditions
`M07-04` done.

## Scope
- Cálculo de impacto antes da remoção: rota que será removida, certificado dedicado que ficará órfão, SAN que precisará de nova versão, registro de DNS gerenciado que será removido.
- Confirmação proporcional: em `PRODUCTION`, exige digitar o hostname.
- Remoção da rota primeiro, depois do registro de DNS (se gerenciado), depois a retirada do certificado após o grace period.
- Certificado dedicado sem domínio ativo: retirado, **não** apagado imediatamente, para permitir recuperação (doc 05 §6).
- Nenhum registro de DNS que a plataforma não criou é removido.

## Out of Scope
- Remoção de `Domain` com múltiplos bindings — o modelo permite; a ordem é remover bindings antes.
- Revogação de certificado na CA — sem requisito.
- Restauração de domínio removido (`M10-12` cobre restore de configuração).

## Application Layer
- **Commands:** `RemoveDomainBinding`, `RemoveDomain`.
- **Queries:** `DomainRemovalImpact`.

## Security Requirements
- Remover domínio é ação destrutiva com efeito imediato no tráfego: a confirmação é proporcional ao risco (doc 10 §26).
- Apenas registros de DNS criados pela plataforma são removidos (`M07-03`).
- O certificado é **retirado**, não apagado, respeitando o grace period — apagar cedo impede recuperação e pode derrubar handshakes.
- A remoção gera AuditLog com o inventário do que foi removido.
- Um domínio removido libera o hostname para a unicidade global; a UI avisa que outro Team poderá reivindicá-lo (com verificação de posse própria).

## Observability Requirements
Timeline da remoção por etapa. Métrica de domínios removidos.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Domínio é o único do SAN | Retirar o certificado após o grace period; não apagar imediatamente. |
| Domínio faz parte de SAN maior | Emitir nova versão sem ele; a anterior permanece até o grace period. |
| Registro de DNS não gerenciado | **Não** removido; a UI informa que o cliente precisa removê-lo. |
| Provider de DNS indisponível | Remover a rota mesmo assim; o registro fica pendente com causa. |
| Remoção durante tráfego | A rota some; a UI avisa que o hostname deixa de responder imediatamente. |
| Remoção parcial | Estado `DELETING` com o que falta; nunca marcar removido sem confirmação. |

## Acceptance Criteria
1. O impacto é calculado e exibido **antes** da remoção: rota, certificado, SAN e registro de DNS.
2. Em `PRODUCTION`, a confirmação exige digitar o hostname.
3. A rota é removida e o hostname deixa de responder, provado contra runtime real.
4. Apenas registros de DNS criados pela plataforma são removidos.
5. Um registro não gerenciado é reportado ao usuário, não removido.
6. Certificado dedicado é **retirado após o grace period**, não apagado imediatamente.
7. Domínio que faz parte de um SAN maior gera nova versão sem ele.
8. Provider de DNS indisponível não impede a remoção da rota; o registro fica pendente com causa.
9. Remoção parcial mantém `DELETING` com o que falta.
10. A UI avisa que o hostname fica liberado e poderá ser reivindicado por outro Team, com verificação de posse própria.
11. A remoção gera AuditLog com o inventário; negativo cross-team passa.

## Required Tests
- **unit**: cálculo de impacto; decisão sobre SAN.
- **integration**: remoção parcial; provider indisponível; registro não gerenciado.
- **Docker/Swarm**: hostname deixando de responder após a remoção.
- **security**: nenhum registro alheio removido; AuditLog completo.

## Quality Gates
Local Quality Gate + suíte Docker/Swarm.

## Definition of Done
Os 11 Acceptance Criteria satisfeitos, impacto exibido antes de executar, boundary de registros respeitado, Critical/High = 0.
