# M13-01 — Cross-team RBAC and IDOR regression suite

## Objective

Consolidar em uma suíte única e obrigatória a matriz de autorização de toda a plataforma, provando que nenhum papel lê ou muta recurso fora do seu escopo.

## Outcome

Uma execução verde da suíte é a evidência de que a matriz `papel × recurso × ação` do Anexo C §7.2 foi exercitada por inteiro — e não apenas nos endpoints que alguém lembrou de testar.

## References

- `docs/annexes/C-threat-model-security-hardening.md` §6 (T04), §7.2, §7.3, §21
- `docs/annexes/D-test-strategy.md` §17, §23
- `docs/architecture/04-identity-teams-security.md` — papéis, escopos e anti-IDOR

## Preconditions

- Policies implementadas desde M01 e estendidas por M11.
- Fixtures de dois Teams com recursos homônimos.

## Scope

- Matriz gerada a partir do **inventário de recursos e ações reais**, não de uma lista escrita à mão.
- Para cada combinação: papel autorizado obtém sucesso; papel não autorizado obtém negação; ator de outro Team obtém negação.
- Troca de identificadores entre Teams (IDOR) em **toda** rota que aceita ID de recurso.
- Escalação de papel: MEMBER tentando ação de ADMIN; ADMIN tentando ação de OWNER; usuário de Team tentando ação de INSTANCE_ADMIN.
- Sessão e token revogados: acesso após revogação é negado imediatamente.
- Invariantes de ownership: um recurso nunca muda de Team por manipulação de parâmetro.
- Cobertura das superfícies: UI (Inertia), API pública, MCP.
- Falha da suíte quando uma rota nova não aparece na matriz — a suíte é **completa por construção**.

## Out of Scope

- Correção de policy faltante: vira finding e volta para a Story de origem.
- Tenancy hostil (T2), fora do modelo de ameaça do MVP.

## Security Requirements

- Negação é `404` quando revelar existência já é vazamento; `403` quando a existência é legítima e conhecida.
- Nenhuma resposta de negação contém dado do recurso alheio, nem em mensagem de erro.
- A suíte roda em CI como gate bloqueante, não como job informativo.

## Observability Requirements

- Relatório com total de combinações, cobertura por superfície e rotas sem cobertura.
- Toda negação testada gera registro de audit verificado pela suíte.

## Failure Scenarios

| Cenário | Comportamento esperado |
|---|---|
| Rota nova sem entrada na matriz | Suíte falha com a lista das rotas descobertas e não cobertas. |
| Leitura cross-team bem-sucedida | Finding **Critical**; release bloqueado. |
| Negação que vaza nome do recurso | Finding **High**. |
| Token revogado ainda aceito | Finding **Critical**. |

## Acceptance Criteria

1. A matriz é **derivada** do inventário de rotas/ações; rota não coberta faz a suíte falhar.
2. Toda mutação tem teste negativo de autorização, incluindo cross-team.
3. IDOR é testado em toda rota que aceita ID de recurso.
4. Escalação de papel é negada em todos os níveis testados.
5. Sessão e token revogados são negados imediatamente.
6. Nenhum recurso muda de Team por manipulação de parâmetro.
7. UI, API e MCP são cobertas.
8. Negações não vazam dados do recurso.
9. Toda negação produz registro de audit.
10. A suíte é gate bloqueante em CI.

## Required Tests

- Integration com PostgreSQL real, sobre a matriz completa.
- Teste da própria completude da matriz (meta-teste).
- Contract tests para a superfície MCP.

## Quality Gates

Local Quality Gate; AF-07 (mutação crítica tem caminho de autorização server-side).

## Definition of Done

- [ ] 10 Acceptance Criteria com evidência.
- [ ] Suíte verde e bloqueante em CI.
- [ ] Nenhum finding Critical/High aberto.
- [ ] Self-review; `tasks.json` atualizado com commit.
