# M11-03 — Atomic team ownership transfer

## Objective
Transferir a propriedade de um Team de forma explícita, atômica, reautenticada e auditada — sem jamais permitir que o Team fique sem dono ou com dois.

## Outcome
O OWNER escolhe um ADMIN ativo, reautentica, confirma o impacto, e a troca acontece em uma única transação: o destino vira OWNER e o antigo vira ADMIN.

## References
- `docs/architecture/04-identity-teams-security.md` §4 (transferência de ownership), §4.1 (regra escolhida), §4.3 (regras transacionais), §16.1 (constraint de OWNER)
- `docs/architecture/10-ui-use-cases.md` UC-043, §20.3
- `docs/annexes/D-test-strategy.md` §5.1 (teste concorrente de transfer)

## Preconditions
`M11-02` done. Step-up de `M03-04` disponível.

## Scope
- Transferência **somente** para membership ACTIVE com papel ADMIN no mesmo Team.
- Transação única: destino ADMIN → OWNER; antigo OWNER → ADMIN; `Team.ownerUserId` atualizado; `ownershipTransferredAt`; AuditLog.
- Reautenticação obrigatória (step-up), com MFA quando habilitada.
- Confirmação com o impacto irreversível descrito.
- Lock/constraint impedindo duas transferências simultâneas.
- Notificação ao antigo e ao novo OWNER.
- Regra explícita: **não existe undo silencioso**; devolver a propriedade é uma nova transferência.

## Out of Scope
- Recuperação excepcional (`M11-04`).
- Transferência de `INSTANCE_ADMIN` — papel independente (doc 04 §7).
- Transferência de Team entre instalações.

## Domain Impact
**Invariante crítica:** antes e depois da operação existe **exatamente um** OWNER ativo. A garantia é da constraint de `M01-02` mais a transação.

## Application Layer
- **Commands:** `TransferOwnership`.
- **Queries:** `EligibleOwnershipTargets` — apenas ADMINs ativos.
- **Policies:** somente o OWNER atual.

## Security Requirements
- **Reautenticação obrigatória** (doc 04 §4.3): a transferência move privilégio máximo do Team.
- MFA exigida no step-up quando habilitada.
- O destino precisa ser ADMIN **ativo**; a verificação acontece **dentro** da transação — se ele deixar de ser ADMIN entre a leitura e o submit, a transação falha sem alterar nada (doc 10 UC-043).
- **Duas transferências concorrentes** não podem produzir dois OWNER nem Team sem OWNER: constraint + lock/transação serializável.
- AuditLog registra `oldOwnerId`, `newOwnerId`, `teamId`, IP/origem, `sessionId` e timestamp.
- Ambos são notificados imediatamente.
- Transferir `TEAM_OWNER` **não** altera `INSTANCE_ADMIN` (doc 04 §7, regra explícita).
- Não existe undo silencioso.

## Observability Requirements
`team.owner.transferred.v1` emitido no commit. Histórico de transferências por Team.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Destino não é ADMIN ativo | Rejeitado. |
| Destino deixou de ser ADMIN entre leitura e submit | Transação falha **sem alterar** o owner. |
| Duas transferências simultâneas | Uma sucede; a outra falha; nunca dois OWNER. |
| Reautenticação expirada | Exigida novamente. |
| Falha no meio da transação | Nada é gravado parcialmente. |
| Antigo OWNER também é `INSTANCE_ADMIN` | Continua `INSTANCE_ADMIN`. |

## Acceptance Criteria
1. A transferência ocorre **somente** para um membership ACTIVE com papel ADMIN.
2. Destino, promoção, rebaixamento, `ownerUserId` e AuditLog acontecem na **mesma transação**.
3. **Duas transferências concorrentes** não produzem dois OWNER nem Team sem OWNER, provado por teste com barreira.
4. O destino que deixou de ser ADMIN entre a leitura e o submit faz a transação falhar **sem alterar** o owner.
5. A operação exige reautenticação; MFA é exigida quando habilitada.
6. A UI lista **apenas** ADMINs ativos como destino.
7. A confirmação descreve o impacto irreversível.
8. O antigo OWNER vira ADMIN automaticamente.
9. Transferir `TEAM_OWNER` **não** altera `INSTANCE_ADMIN`, provado por teste.
10. AuditLog registra `oldOwnerId`, `newOwnerId`, origem, sessão e timestamp.
11. Ambos os usuários são notificados.
12. Não existe undo silencioso; devolver exige nova transferência.
13. Falha no meio não grava estado parcial.

## Required Tests
- **integration (concorrente, com barreira)**: duas transferências simultâneas; destino deixando de ser ADMIN no meio.
- **unit**: elegibilidade do destino; invariante de OWNER único.
- **policy**: apenas o OWNER pode transferir; ADMIN não consegue.
- **security**: step-up exigido; `INSTANCE_ADMIN` preservado; AuditLog completo.
- **E2E**: fluxo completo pela UI.

## Quality Gates
Local Quality Gate + `bin/security`. **Story crítica: exige plan mode** — invariante de segurança sob concorrência.

## Definition of Done
Os 13 Acceptance Criteria satisfeitos, teste concorrente determinístico verde, atomicidade provada, Critical/High = 0.
