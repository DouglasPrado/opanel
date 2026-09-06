---
milestone: "M11"
type: "autonomous-goal"
---

# M11 — Autonomous Goal

## Completion condition

M11 está `READY` quando, com comando e exit code demonstrados:

1. Stories `required: true` `done` com `commit`; nenhuma `required` `blocked`; `bin/pack validate` verde.
2. Suítes unit, integration, request, policy e contract verdes.
3. **Teste concorrente de transferência de ownership** verde: duas tentativas simultâneas não produzem dois OWNER nem Team sem OWNER.
4. **Teste negativo de promoção** verde: ADMIN não consegue tornar a si mesmo nem outro membro OWNER por nenhum caminho.
5. Teste verde: OWNER não consegue sair nem reduzir o próprio papel sem transferir.
6. Teste verde: transferir `TEAM_OWNER` **não** altera `INSTANCE_ADMIN`.
7. **Teste de token** verde: armazenado apenas como hash; exibido em plaintext uma única vez; expirado/revogado rejeitado.
8. **Teste de boundary de produção** verde: DEVELOPER com deploy em homologação **não** obtém secret de produção.
9. **Teste de varredura de rotas** verde: nenhuma rota retorna plaintext de secret a quem não tem `vault.reveal`.
10. Teste de quota sob concorrência verde: o limite não é ultrapassado por requisições simultâneas.
11. Teste de rate limit verde em login, recuperação de conta, webhooks e endpoints caros.
12. Matriz completa de RBAC verde, com negativos cross-team em todas as rotas de mutação.
13. Teste de audit verde: eventos obrigatórios registrados, sem plaintext sensível.
14. E2E verde: convidar → aceitar → alterar papel → transferir ownership → revogar token.
15. `bin/fitness` e `bin/security` verdes; Critical/High = 0 em `M11/review/`.
16. `MILESTONE_REPORT.md` gerado com `Status: READY_FOR_REVIEW`.

## Required proof

- saída do teste concorrente de transferência;
- saída dos testes negativos de promoção e de saída do OWNER;
- saída da varredura de rotas por plaintext;
- saída do teste de quota concorrente;
- matriz de RBAC completa com os resultados;
- um commit por Story.

## Constraints

- **Exatamente um OWNER ativo por Team**, garantido no banco, não só na aplicação.
- ADMIN **nunca** promove a OWNER; a única via é a transferência explícita pelo OWNER.
- Transferir `TEAM_OWNER` **não** transfere `INSTANCE_ADMIN`.
- Token **nunca** armazenado em plaintext; exibido uma única vez.
- Nenhuma rota retorna plaintext de secret sem `vault.reveal`.
- Convite expira e é de uso único.
- Membership suspenso perde acesso imediatamente.
- Audit Log **nunca** contém plaintext sensível.
- Quotas são proteção operacional: `safety limit` não pode ser ultrapassado nem por OWNER.
- Não implementar SSO enterprise, SCIM nem billing completo.
- Não implementar OAuth do MCP (M12).
- Não desabilitar teste, checker ou gate.

## Block policy

3 tentativas sem progresso → mudar estratégia uma vez → `blocked`. Se qualquer teste demonstrar que é possível obter dois OWNER ativos, promover a OWNER sem transferência, ou obter plaintext de secret sem `vault.reveal`, **parar**: são violações de invariante, não bugs de ajuste.

## End state

Para o implementer: `READY_FOR_REVIEW`, `BLOCKED` ou `FAILED`. Nunca abandonar trabalho silenciosamente. Ao atingir `READY_FOR_REVIEW`, gerar `MILESTONE_REPORT.md`, atualizar `review-state.json` e devolver o controle ao orquestrador — **não iniciar M12 automaticamente**.

## Final Handoff

Quando todas as condições do Milestone estiverem satisfeitas:

1. marque todas as Stories obrigatórias como `done`;
2. execute todos os testes e Quality Gates finais;
3. gere `MILESTONE_REPORT.md`;
4. o relatório deve conter explicitamente:

   `Status: READY_FOR_REVIEW`

5. altere `review-state.json.status` de `implementing` ou `fixing` para `ready_for_review`;
6. não inicie o próximo Milestone;
7. encerre a execução.

O review independente posterior é responsabilidade exclusiva do Codex. Claude
não deve executar nem substituir o Codex Review e nunca pode declarar o estado
`accepted` ou `human_acceptance`.
