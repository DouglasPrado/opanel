# M11-04 — Exceptional ownership recovery

## Objective
Oferecer um caminho para um Team que perdeu o acesso ao seu OWNER, sem transformar isso em uma alternativa conveniente à transferência normal.

## Outcome
Um `INSTANCE_ADMIN` executa a recuperação com evidência, notificação aos administradores do Team, e registro destacado como `OWNERSHIP_RECOVERY`.

## References
- `docs/architecture/04-identity-teams-security.md` §4.4 (recuperação excepcional), §3.2 (`OWNERSHIP_RECOVERY_REQUIRED`)
- `docs/annexes/C-threat-model-security-hardening.md` §7.2 (ações privilegiadas)

## Preconditions
`M11-03` done.

## Scope
- Fluxo excepcional executável **somente** por `INSTANCE_ADMIN`.
- Pré-condição: o Team está em `OWNERSHIP_RECOVERY_REQUIRED` ou o OWNER está comprovadamente inacessível.
- Escolha do novo OWNER entre os ADMINs ativos; se não houver, promoção explícita de um membro, registrada como parte da recuperação.
- Step-up obrigatório e confirmação com o impacto.
- **Notificação a todos os membros administrativos** do Team.
- AuditLog marcado explicitamente como `OWNERSHIP_RECOVERY`, distinto de uma transferência normal.

## Out of Scope
- Alteração de ownership por SQL direto — explicitamente **inaceitável** na operação normal (doc 04 §4.4).
- Recuperação de conta do usuário (fluxo de identidade, `M11-06`).
- Recuperação do Vault (`M10-06`).

## Application Layer
- **Commands:** `RecoverOwnership`.
- **Policies:** exclusivamente `INSTANCE_ADMIN` + step-up.

## Security Requirements
- Este é um **mecanismo de emergência** e não substitui a transferência normal (doc 04 §4.4, regra explícita).
- Exige `INSTANCE_ADMIN` **e** step-up.
- **Notificação obrigatória** a todos os administradores do Team: uma troca de dono sem aviso é indistinguível de um sequestro de conta.
- O AuditLog marca `OWNERSHIP_RECOVERY` de forma distinta, para que uma auditoria posterior consiga separar os dois caminhos.
- A evidência da necessidade é registrada — não basta “achar” que o OWNER sumiu.
- A operação preserva a invariante de OWNER único e usa a mesma transação atômica de `M11-03`.
- Um `INSTANCE_ADMIN` não pode usar a recuperação para tornar a si mesmo OWNER sem que isso fique evidente e notificado.

## Observability Requirements
Evento distinto de recuperação; a UI de segurança do Team mostra que houve uma recuperação e quando.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Team não está em estado que justifique | Bloqueado; exigir a transferência normal. |
| Sem ADMIN ativo disponível | A promoção explícita é registrada como parte da recuperação. |
| `INSTANCE_ADMIN` recuperando para si | Permitido, mas notificado e destacado no audit. |
| Step-up ausente | Exigido. |
| Falha no meio | Transação atômica; nada parcial. |
| Recuperação repetida | Registrada; um padrão de recuperações é sinal de investigação. |

## Acceptance Criteria
1. A recuperação é executável **somente** por `INSTANCE_ADMIN` com step-up.
2. Ela é bloqueada quando o Team não está em estado que a justifique.
3. O novo OWNER é escolhido entre ADMINs ativos; sem eles, a promoção é registrada como parte da recuperação.
4. A operação usa a mesma transação atômica e preserva a invariante de OWNER único.
5. **Todos os administradores do Team são notificados.**
6. O AuditLog marca `OWNERSHIP_RECOVERY`, distinto de uma transferência normal.
7. A evidência da necessidade é registrada.
8. `INSTANCE_ADMIN` recuperando para si é permitido, mas destacado e notificado.
9. Falha no meio não grava estado parcial.
10. Recuperações repetidas são registradas e visíveis como padrão.
11. A UI de segurança do Team mostra que houve recuperação e quando.
12. Nenhum caminho de alteração de ownership fora deste fluxo e do de `M11-03` existe, verificado por teste.

## Required Tests
- **policy**: apenas `INSTANCE_ADMIN`; step-up exigido; OWNER e ADMIN negados.
- **integration**: bloqueio sem estado justificável; promoção registrada; atomicidade.
- **security**: notificação obrigatória; audit distinto; ausência de caminho alternativo de alteração de ownership.

## Quality Gates
Local Quality Gate + `bin/security`. **Story crítica: exige plan mode.**

## Definition of Done
Os 12 Acceptance Criteria satisfeitos, notificação e audit distinto provados, ausência de caminho alternativo verificada, Critical/High = 0.
