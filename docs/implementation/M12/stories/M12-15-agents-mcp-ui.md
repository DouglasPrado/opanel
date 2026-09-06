# M12-15 — Agents & MCP UI

## Objective
Dar ao usuário controle visível sobre o que os agentes podem fazer: conectar, limitar, aprovar, acompanhar e **revogar com um clique**.

## Outcome
A tela de Agents & MCP lista conexões com preset, boundary e modo de produção; mostra approvals pendentes e atividade; e a revogação tem efeito imediato.

## References
- `docs/annexes/F-mcp-platform-agents.md` §4.1 (tela Agents & MCP), §14 (UI detalhada), §14.2 (wizard), §14.3 (connection details), §22 (AC-MCP-20)
- `docs/architecture/10-ui-use-cases.md` §26 (ações destrutivas)

## Preconditions
`M12-09` e `M12-14` done.

## Scope
- **Lista de conexões**: nome, usuário, cliente, preset, Team, boundary, modo de produção, último uso, expiração e status.
- **Wizard** de nova conexão com os oito passos do Anexo F §14.2, terminando em `whoami` executado e capability report exibido.
- **Connection details** com as abas do Anexo F §14.3: Overview, Permissions, Resource Access, Approvals, Activity, OAuth/Security, Compatibility.
- **Approvals**: pendentes, aprovadas, negadas, expiradas, com ator e Operation resultante.
- **Atividade**: histórico de tool calls com Operation IDs, latência, erro e links de audit.
- **Revogar com um clique**, com efeito imediato visível.

## Out of Scope
- Marketplace de agentes.
- Edição de tools individuais além de allow/deny.

## UI Impact
Esta tela é onde o usuário entende o que concedeu. Se ela não for clara, o consentimento não é informado — e o modelo de segurança do Anexo F depende de consentimento informado.

## Security Requirements
- O wizard mostra explicitamente que capabilities sensíveis estão **off** e o que significa habilitá-las.
- O passo de verificação executa `whoami` e mostra o **capability report real**, não o preset nominal — o usuário vê o que o agente efetivamente pode.
- **Revogar com um clique**, e a UI mostra imediatamente que chamadas futuras falharão (Anexo F §14.3).
- Nenhum token é exibido após a criação.
- A atividade mostra `arguments_digest`, nunca os argumentos.
- Aprovar na UI mostra o **efeito real** da ação, com recursos afetados e risco.
- O nome do cliente exibido é sanitizado.

## Observability Requirements
Atividade por conexão com latência e resultado. Approvals pendentes com destaque.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Conexão expirada | Estado explícito; chamadas falham com a razão. |
| Approval pendente | Destaque na navegação. |
| Revogação | Efeito imediato visível. |
| Cliente com nome enganoso | Sanitizado. |
| Muitas tool calls | Paginação por cursor. |
| Sem permissão | Tela explicativa sem vazar. |

## Acceptance Criteria
1. A lista de conexões mostra as colunas do Anexo F §14.1.
2. O wizard segue os oito passos do Anexo F §14.2.
3. O passo de verificação executa `whoami` e mostra o **capability report real**.
4. O wizard mostra que capabilities sensíveis estão off e o que significa habilitá-las.
5. Connection details tem as abas do Anexo F §14.3.
6. Approvals pendentes aparecem com destaque e mostram o efeito real da ação.
7. **Revogar com um clique** funciona e a UI mostra imediatamente o efeito.
8. Nenhum token é exibido após a criação.
9. A atividade mostra `arguments_digest`, **nunca** os argumentos.
10. O nome do cliente é sanitizado.
11. Listas usam paginação por cursor; acessibilidade AA verificada.
12. Nenhum componente novo foi criado onde o inventário resolvia; Reuse Gate documentado.

## Required Tests
- **unit (frontend)**: lista; wizard; capability report; estado de revogação.
- **E2E**: conectar → verificar → aprovar uma ação → revogar e ver a chamada falhar.
- **security**: token não exibido; argumentos não exibidos; nome sanitizado; **negativo cross-team**: usuário de outro Team não lista, não abre e não revoga a conexão.

## Quality Gates
Local Quality Gate + Reuse Gate + E2E + `bin/security`.

## Definition of Done
Os 12 Acceptance Criteria satisfeitos, revogação com efeito imediato provada, capability report real exibido, Critical/High = 0.
