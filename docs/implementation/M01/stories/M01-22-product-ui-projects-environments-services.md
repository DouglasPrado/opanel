# M01-22 — Product UI: Projects, Environments and Services

## Objective
Entregar as telas que tornam o vertical slice utilizável, mostrando desired state, actual state e operações em andamento sem esconder divergência.

## Outcome
O usuário navega Projects → Environment → Service, cria recursos, vê status derivado com a idade da observação, e acompanha operações em andamento sem falso sucesso.

## References
- `docs/architecture/10-ui-use-cases.md` §7 (Projects), §8 (Environments), §9 (Services), §12 (runtime e scaling), §25 (estados universais), §26 (ações destrutivas)
- `docs/annexes/I-engineering-playbook-quality-gates.md` §6 (Reuse Gate, estado e dados)
- `docs/annexes/B-nfr-slos.md` §4 (latência de leitura), §18 (UX e acessibilidade)
- `app/frontend/components/INVENTORY.md`

## Preconditions
`M01-06`, `M01-19` e `M01-21` done.

## Scope
- **Projects**: lista com status de produção e último deploy; criação com fluxo curto.
- **Project Overview**: agregador de Environments.
- **Environment**: header com switcher, badge de tipo, link para o Cluster, health agregado; tabs de Overview e Services (as demais tabs chegam com seus Milestones).
- **Service**: lista com status, réplicas `running/desired`, imagem e última ação; página com Overview, Runtime (tasks, nós, distribuição) e Logs.
- Ações: criar Service, scale. Cada ação assíncrona mostra o estado da operação.
- Estados universais aplicados em todas as telas: loading, empty com CTA, no permission, erro com `requestId`, stale, operação em andamento, falha parcial.
- Paginação por cursor em todas as listas.

## Out of Scope
- Operations Center global (`M02-10`) — aqui o feedback é por recurso.
- Realtime por SSE (`M02-11`) — em M01 usa polling de baixa frequência com indicação explícita.
- Tabs de Deployments, Domains, Variables & Secrets, Observability, Snapshots (Milestones correspondentes).
- Command palette e busca global.

## UI Impact
Consolida o mental model do produto: `Team → Project → Environment → Service`, com Clusters como infraestrutura paralela (doc 10 §3.2). Toda tela nova a partir daqui herda esses padrões.

## Security Requirements
- A UI não oferece ação proibida; e o backend nega independentemente.
- Nenhuma tela exibe valor sensível; a área de variáveis sensíveis só existe a partir de M03 e já nasce sem plaintext.
- Ação destrutiva em `PRODUCTION` usa confirmação reforçada proporcional ao risco (doc 10 §26) — em M01 a única destrutiva possível é arquivar Project.
- `requestId` visível no erro para suporte, sem detalhe interno.

## Observability Requirements
- Cada tela que mostra estado de runtime exibe a idade da observação.
- A UI distingue: falha de plataforma, falha da aplicação e dado indisponível.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Actual state velho | Badge “last observed …”; não declarar Healthy. |
| Operação em andamento | Ação principal desabilitada ou substituída, com link para o progresso. |
| Falha parcial de réplicas | `7/8 healthy`, com detalhamento por Task. |
| Sem permissão | Tela explicativa sem vazar dados. |
| Control Plane inalcançável | Última leitura preservada com timestamp; mutações bloqueadas. |
| Lista grande | Cursor estável; sem carregamento não paginado. |

## Acceptance Criteria
1. O usuário navega Projects → Project → Environment → Service e cria recursos em cada nível.
2. O status exibido é derivado, com a idade da observação visível.
3. Um Service com actual state velho **não** aparece como `HEALTHY`.
4. Falha parcial aparece como `n/m healthy` com detalhamento por Task.
5. Uma operação em andamento desabilita ou substitui a ação conflitante e mostra o progresso.
6. Nenhuma tela mostra “concluído” antes da confirmação do runtime.
7. Todas as listas usam paginação por cursor.
8. Todos os estados universais estão implementados nas telas entregues.
9. Erros mostram `requestId` sem stack trace, SQL ou caminho interno.
10. Ações proibidas não aparecem como disponíveis, e o backend nega de qualquer forma.
11. Nenhum componente novo foi criado onde o inventário resolvia; qualquer criação está justificada pelo Reuse Gate no Story Report.
12. Acessibilidade AA verificada nas telas entregues.

## Required Tests
- **unit (frontend)**: componentes de status derivado, badge de dado velho, estado de operação em andamento.
- **E2E**: navegação completa; criação de Project, Environment e Service; estados de erro e sem permissão; acessibilidade.
- **policy**: a UI não expõe ação proibida; o backend nega mesmo quando a requisição é forjada.

## Quality Gates
Local Quality Gate classe React/TypeScript + **Reuse Gate** contra o inventário + checagem de acessibilidade.

## Definition of Done
Os 12 Acceptance Criteria satisfeitos, ausência de falso sucesso verificada por E2E, Reuse Gate documentado, Critical/High = 0.
