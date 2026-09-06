# M09-14 — Audited terminal and exec into a specific Task

## Objective
Oferecer acesso interativo a um container específico como **capacidade privilegiada, temporária e auditada** — nunca como recurso casual.

## Outcome
Um usuário autorizado abre um terminal em uma Task escolhida, com reautenticação em produção, TTL e sessão registrada; `VIEWER` nunca consegue, e o shell do host jamais é exposto.

## References
- `docs/architecture/03-runtime-observability.md` §14 (terminal e exec), §14.1 (regras)
- `docs/annexes/C-threat-model-security-hardening.md` §15 (terminal, exec e ações interativas), T10
- `docs/architecture/10-ui-use-cases.md` §13.2 (terminal/exec)
- `docs/architecture/07-internal-control-plane.md` §21 (exec é caminho separado, permissionado e auditado)

## Preconditions
M02 aceito; `M03-04` (step-up) disponível. Independente das demais Stories de M09.

## Scope
- Sessão de terminal sobre WebSocket, do navegador ao Control Plane, e do Control Plane à Task pelo caminho autorizado.
- **Seleção explícita da Task**: o usuário escolhe; a plataforma não promete que o mesmo container existirá depois.
- Permissão dedicada por Environment/Service; `VIEWER` **nunca** recebe.
- Step-up em produção ou conforme policy.
- TTL e idle timeout; encerramento automático ao perder permissão ou sessão.
- `TerminalSession`: actor, Team, Environment, Service, Task, início, fim, origem.
- Feature flag `terminal.enabled`, restrita até o hardening (Anexo A §10).

## Out of Scope
- Transferência de arquivo — feature separada e auditada (Anexo C §15), fora do escopo.
- Gravação do conteúdo completo do terminal por padrão (doc 03 §14.1: apenas metadata, salvo política explícita e documentada).
- Exec via MCP (`M12-12`, desabilitado por padrão).

## Application Layer
- **Commands:** `StartTerminalSession`, `EndTerminalSession`.
- **Policies:** permissão dedicada por Environment/Service.
- O exec é um **caminho separado** do Swarm Executor de operações tipadas (doc 07 §21) — ele não é uma operação genérica do executor.

## Security Requirements
Esta é a capacidade de maior risco do produto (T10):
- **Nunca expor shell do host** através desta funcionalidade (doc 03 §14.1, regra explícita).
- **Nunca** permitir exec em containers do Control Plane, do executor ou de infraestrutura da plataforma.
- Permissão dedicada; `VIEWER` nunca recebe (Anexo C §15).
- Step-up em produção ou conforme policy.
- Alvo é uma **Task específica**, não “o Service”.
- TTL e idle timeout; a sessão encerra ao perder permissão ou ao ser revogada.
- Auditoria obrigatória: quem, Team, Environment, Service, Task, início, fim e origem.
- Conteúdo completo **não** é armazenado por padrão; se a política exigir, isso é documentado explicitamente.
- Rate limit de sessões simultâneas por usuário/Team.
- Feature flag restrita até o hardening.

## Observability Requirements
Sessões ativas visíveis para administradores. Métrica de sessões por período e por ator — uma sequência anormal é sinal de investigação.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| `VIEWER` tentando exec | Negado e auditado. |
| Step-up ausente em produção | Negado até reautenticar. |
| Task some durante a sessão | Sessão encerra com causa; a plataforma não promete continuidade. |
| Permissão revogada durante a sessão | Sessão encerra imediatamente. |
| Tentativa de exec em container da plataforma | Bloqueada. |
| Idle além do timeout | Encerrada. |
| Muitas sessões simultâneas | Rate limit. |
| Reconexão silenciosa após fechar | Impossível: fechar encerra no backend (doc 10 §13.2). |

## Acceptance Criteria
1. O usuário autorizado abre terminal em uma **Task específica** escolhida explicitamente.
2. `VIEWER` **nunca** obtém exec, provado por teste.
3. Produção exige step-up authentication.
4. **Nenhum caminho expõe shell do host**, provado por teste.
5. Exec em containers do Control Plane, do executor ou de infraestrutura é **bloqueado**.
6. TTL e idle timeout encerram a sessão.
7. Perder permissão ou ter a sessão revogada encerra o terminal imediatamente.
8. Fechar a sessão a encerra no backend; não há reconexão silenciosa.
9. Cada sessão gera AuditLog com actor, Team, Environment, Service, Task, início, fim e origem.
10. O conteúdo completo **não** é armazenado por padrão.
11. Rate limit de sessões simultâneas é aplicado.
12. A feature flag `terminal.enabled` existe e é restrita por padrão.
13. Task que some durante a sessão a encerra com causa.

## Required Tests
- **security**: `VIEWER` negado; step-up exigido; shell do host inacessível; exec em container da plataforma bloqueado; permissão revogada encerrando.
- **integration**: TTL e idle timeout; rate limit; fechar encerrando no backend.
- **Docker/Swarm**: exec real em Task; Task removida durante a sessão.
- **policy**: matriz de permissões por Environment.

## Quality Gates
Local Quality Gate + suíte Docker/Swarm + `bin/security`. **Story crítica: exige plan mode** — mitiga T10.

## Definition of Done
Os 13 Acceptance Criteria satisfeitos, ausência de acesso ao host provada, auditoria completa de sessão, Critical/High = 0.
