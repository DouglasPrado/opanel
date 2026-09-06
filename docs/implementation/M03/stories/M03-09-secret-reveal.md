# M03-09 — Secret reveal as a separate, audited, step-up protected action

## Objective
Permitir revelar o valor de uma secret **apenas** como ação deliberada, permissionada, reautenticada e auditada — deixando claro que revelar nunca é necessário para deployar.

## Outcome
Um usuário com `vault.reveal` reautentica, revela o valor por tempo limitado, e o evento fica registrado. Um DEVELOPER sem a permissão em produção **não** consegue, mesmo tendo deploy.

## References
- `docs/architecture/04-identity-teams-security.md` §11 (Vault e autorização), §11.1 (Production como boundary adicional)
- `docs/annexes/C-threat-model-security-hardening.md` §12 (Reveal), T05
- `docs/architecture/10-ui-use-cases.md` §15.2 (reveal como ação explícita com reautenticação e audit)
- `docs/annexes/F-mcp-platform-agents.md` §7.6 (regra write-only para agentes)

## Preconditions
`M03-04` e `M03-05` done.

## Scope
- Permissão dedicada `vault.reveal`, **separada** de criar, versionar e bindar.
- Step-up authentication obrigatório antes de revelar.
- TTL curto da revelação; a UI não mantém o valor exposto indefinidamente.
- AuditLog obrigatório com actor, secretId, versionNumber, escopo e resultado — **sem** o valor.
- `PRODUCTION` como boundary adicional: mesmo ADMIN pode ter reveal negado por policy de Environment.
- Regra de produto explícita na UI: **reveal não é necessário para deploy**.

## Out of Scope
- Reveal via MCP (`M12-10`) — a capability nasce desabilitada por padrão (Anexo F §13.1).
- Exportação em massa de secrets — não existe e não deve existir.
- Cópia automática para o clipboard (doc 10 §28 proíbe).

## Application Layer
- **Commands:** `RevealSecretVersion`.
- **Policies:** `vault.reveal` avaliada por Team **e** por Environment.

## API Impact
Endpoint dedicado, nunca um campo opcional em um `GET` de listagem. Nenhum outro endpoint retorna plaintext em nenhuma circunstância.

## UI Impact
Diálogo de reveal com: aviso, step-up, valor exibido por tempo limitado, botão de copiar **com confirmação visual explícita** (doc 10 §28), e indicação de que a ação foi auditada.

## Security Requirements
- Reveal é **capability separada**, negada por padrão a DEVELOPER em produção (doc 04 §6.2).
- Exige step-up authentication (`M03-04`).
- TTL curto; após expirar, é necessário revelar novamente.
- AuditLog **sempre**, inclusive nas negações (`result: DENIED`).
- O valor **não** entra em log de acesso, telemetria, trace, cache do navegador ou histórico de resposta.
- Não copiar automaticamente para o clipboard; a cópia é ação explícita com confirmação visual.
- Rate limit no reveal: uma sequência anormal de revelações é um sinal de comprometimento e precisa ser detectável.
- A resposta não é cacheável.

## Observability Requirements
- `secret.revealed` no AuditLog com actor, recurso e resultado.
- Métrica: revelações por período e por ator — insumo para a visão de segurança de `M11-13`.
- Sequência anormal registrada de forma consultável.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Usuário sem `vault.reveal` | Negado e auditado como `DENIED`; a API **não** retorna plaintext em nenhuma rota alternativa. |
| Step-up ausente ou expirado | Exigir novamente. |
| DEVELOPER com deploy em produção | Reveal negado por padrão; deploy continua funcionando. |
| Sequência anormal de revelações | Rate limit e registro; sinal para investigação. |
| Decifra falha | Erro classificado sem revelar material parcial. |
| Tentativa de obter o valor por outro endpoint | Nenhum outro endpoint retorna plaintext, verificado por teste abrangente. |

## Acceptance Criteria
1. Existe uma permissão `vault.reveal` distinta de criar, versionar e bindar.
2. Revelar exige step-up authentication válido.
3. O valor é exibido por tempo limitado e a revelação expira.
4. DEVELOPER com permissão de deploy em produção **não** revela secret de produção por padrão.
5. Toda revelação e toda negação geram AuditLog, sem o valor.
6. **Nenhum outro endpoint da API retorna plaintext**, provado por teste que varre as rotas.
7. O valor não aparece em log de acesso, telemetria, trace ou cache; a resposta não é cacheável.
8. Não há cópia automática para o clipboard; a cópia exige ação explícita com confirmação visual.
9. Rate limit é aplicado e sequência anormal fica registrada e consultável.
10. Falha de decifra produz erro classificado sem material parcial.
11. A UI declara que reveal não é necessário para deploy.
12. Negativo cross-team passa.

## Required Tests
- **unit**: TTL da revelação; avaliação de policy por Environment.
- **integration**: step-up exigido; expiração; rate limit; resposta não cacheável.
- **policy**: matriz completa — quem pode e quem não pode, por Environment; negativo cross-team.
- **security**: varredura de rotas comprovando que nenhuma outra retorna plaintext; ausência do valor em log/telemetria/trace.

## Quality Gates
Local Quality Gate + `bin/security` + `bin/fitness` (AF-06). **Story crítica: exige plan mode.**

## Definition of Done
Os 12 Acceptance Criteria satisfeitos, varredura de rotas verde, audit de negação verificado, Critical/High = 0.
