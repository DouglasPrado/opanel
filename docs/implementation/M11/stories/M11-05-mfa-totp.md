# M11-05 — MFA (TOTP) enrollment and enforcement

## Objective
Adicionar um segundo fator resistente a credencial vazada, e permitir exigi-lo dos papéis privilegiados.

## Outcome
O usuário cadastra TOTP com códigos de recuperação; a política pode exigir MFA de `INSTANCE_ADMIN` e `TEAM_OWNER`; o step-up de `M03-04` passa a aceitá-lo.

## References
- `docs/architecture/04-identity-teams-security.md` §8.1 (métodos), §8.3 (step-up)
- `docs/annexes/B-nfr-slos.md` §13 (MFA obrigatório para INSTANCE_ADMIN e TEAM_OWNER em production-ready)
- `docs/annexes/C-threat-model-security-hardening.md` §7.1

## Preconditions
M03 aceito (`M03-04` definiu o contrato de step-up preparado para um segundo fator).

## Scope
- Enrollment TOTP com verificação antes de ativar.
- Códigos de recuperação de uso único, exibidos uma vez.
- Política de exigência por papel: `INSTANCE_ADMIN`, `TEAM_OWNER` e, opcionalmente, ADMIN.
- Integração com o step-up: quando MFA está habilitada, o step-up a exige.
- Desativação exigindo o próprio fator, para que uma sessão sequestrada não a remova.
- Rate limit e proteção contra brute force no código.

## Out of Scope
- Passkeys/WebAuthn — evolução preferencial (doc 04 §8.1), sem requisito imediato.
- SMS como fator.
- OIDC/SAML (backlog).

## Application Layer
- **Commands:** `EnrollMfa`, `VerifyMfa`, `DisableMfa`, `RegenerateRecoveryCodes`.
- **Policies:** exigência por papel conforme a política da instalação.

## Security Requirements
- O segredo TOTP é armazenado **cifrado** pelo envelope da plataforma; nunca em claro.
- Códigos de recuperação são armazenados apenas como **hash**, de uso único, exibidos uma vez.
- **Desativar MFA exige o próprio fator** — caso contrário, uma sessão sequestrada removeria a proteção.
- Alterações de MFA invalidam sessões conforme a política (doc 04 §8.2).
- Rate limit e janela de tolerância mínima no TOTP, contra brute force.
- Ausência de MFA em papel que a exige **bloqueia** ações privilegiadas, não apenas avisa.
- Enrollment, desativação e uso de código de recuperação geram AuditLog.

## Observability Requirements
Adoção de MFA por papel no dashboard de segurança (`M11-13`). Falhas de MFA registradas — uma sequência anormal é sinal de ataque.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Código inválido | Rejeitado; rate limit aplicado. |
| Dispositivo perdido | Código de recuperação de uso único. |
| Todos os códigos de recuperação usados | Fluxo administrativo com verificação de identidade; nunca bypass automático. |
| Papel exige MFA e o usuário não a tem | Ações privilegiadas **bloqueadas** até o enrollment. |
| Relógio dessincronizado | Janela de tolerância mínima; erro explicativo. |
| Tentativa de desativar sem o fator | Rejeitada. |

## Acceptance Criteria
1. O enrollment TOTP exige verificação antes de ativar.
2. O segredo TOTP é armazenado **cifrado**, nunca em claro, provado por inspeção do banco.
3. Códigos de recuperação são de uso único, armazenados como hash e exibidos uma única vez.
4. A política pode exigir MFA de `INSTANCE_ADMIN` e `TEAM_OWNER`.
5. Papel que exige MFA sem enrollment tem ações privilegiadas **bloqueadas**.
6. O step-up de `M03-04` passa a exigir MFA quando ela está habilitada.
7. **Desativar MFA exige o próprio fator**, provado por teste.
8. Rate limit e janela de tolerância mínima protegem contra brute force.
9. Alterações de MFA invalidam sessões conforme a política.
10. Todos os códigos de recuperação usados levam a fluxo administrativo com verificação; **nunca** bypass automático.
11. Enrollment, desativação e uso de código de recuperação geram AuditLog.
12. Falhas de MFA são registradas e a adoção é observável.

## Required Tests
- **security**: segredo cifrado; desativação exigindo o fator; brute force limitado; ausência de bypass.
- **integration**: enrollment; código de recuperação de uso único; bloqueio por papel sem MFA.
- **policy**: exigência por papel; integração com step-up.

## Quality Gates
Local Quality Gate + `bin/security`. **Story crítica: exige plan mode.**

## Definition of Done
Os 12 Acceptance Criteria satisfeitos, segredo cifrado e desativação protegida, ausência de bypass verificada, Critical/High = 0.
