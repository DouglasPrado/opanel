# M01-06 — Application shell and authentication UI

## Objective
Entregar o shell da aplicação — navegação, contexto de Team e estados universais — reutilizando a biblioteca de componentes existente, sem criar um design system paralelo.

## Outcome
O usuário autentica, vê o app shell com team switcher e navegação, e a UI trata corretamente loading, empty, sem permissão e erro.

## References
- `docs/architecture/10-ui-use-cases.md` §3 (arquitetura de informação), §4 (app shell), §25 (estados universais), §28 (responsividade e acessibilidade)
- `docs/annexes/I-engineering-playbook-quality-gates.md` §6 (hierarquia, Reuse Gate, estado e dados)
- `docs/annexes/B-nfr-slos.md` §18 (NFRs de UX e acessibilidade)
- `app/frontend/components/INVENTORY.md` (produzido em `M00-05`)

## Preconditions
`M01-04` done. Inventário de componentes disponível.

## Scope
- Layout global: header com team switcher e user menu; sidebar orientada a produto (`Projects` antes de `Clusters`).
- Rotas do doc 10 §3.2 para o que existe em M01: `/t/:team/projects`, `/t/:team/clusters`, `/t/:team/audit` (placeholder), `/t/:team/settings`.
- Telas de sign in e sign up conectadas a `M01-01`.
- Componentes de **estado universal** reutilizáveis: loading (skeleton), empty com CTA, no permission, erro com `requestId`, offline/control plane inalcançável, stale (“last observed …”).
- Badge persistente de tipo de Environment, com destaque para `PRODUCTION` (usado a partir de `M01-11`).
- Acessibilidade: navegação por teclado, status nunca apenas por cor, foco preservado em dialogs.

## Out of Scope
- Operations Center e notificações (`M02-10`).
- Command palette (M11 ou posterior; não é requisito de M01).
- Telas de Project/Environment/Service (`M01-22`).
- Realtime via SSE (`M02-11`) — em M01 a atualização é por navegação e polling de baixa frequência.

## UI Impact
Define o esqueleto de **toda** tela do produto. A partir daqui, uma tela sem tratamento de loading/empty/error/forbidden é finding de review.

## Security Requirements
- A UI não mostra ação proibida como se estivesse disponível; e o backend nega de qualquer forma (doc 10 §1).
- Nenhum valor sensível em shared props, verificado desde `M00-04` e reforçado aqui.
- A tela de erro exibe `requestId` para suporte, **sem** stack trace, SQL ou caminho interno.
- Mensagem de “sem permissão” explica a restrição sem vazar dados do recurso (doc 10 §25).

## Observability Requirements
Erro de cliente é distinguível de erro de servidor no log; o `requestId` exibido ao usuário corresponde ao do log do servidor.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Control Plane inalcançável | Preserva a última leitura com timestamp quando possível; mutações bloqueadas com aviso claro. |
| Usuário sem permissão para a rota | Tela explicativa, sem vazar dados. |
| Dado velho | Badge “last observed …”; não declarar Healthy sem observação recente. |
| Falha de rede em navegação Inertia | Erro tratado, com retry; não tela em branco. |

## Acceptance Criteria
1. O usuário autenticado vê o app shell com team switcher, navegação e user menu.
2. A sidebar apresenta `Projects` antes de `Clusters`, refletindo que Project é produto e Cluster é infraestrutura.
3. Existem componentes reutilizáveis para loading, empty, no permission, erro, offline e stale, cobertos por teste.
4. A tela de erro mostra `requestId` e **não** mostra stack trace, SQL ou caminho interno.
5. O badge de Environment `PRODUCTION` é visualmente persistente.
6. Navegação principal e dialogs são operáveis por teclado; o foco retorna ao trigger ao fechar um dialog.
7. Nenhum status depende apenas de cor: há ícone e rótulo.
8. Nenhum componente novo foi criado onde o inventário resolvia; qualquer criação está justificada no Story Report pelo Reuse Gate.
9. A checagem de acessibilidade AA passa nas telas entregues.
10. Nenhum valor sensível aparece em shared props.

## Required Tests
- **unit (frontend)**: cada componente de estado universal; team switcher.
- **E2E**: login → shell renderizado → navegação entre seções; tela de erro exibindo `requestId`; acessibilidade AA.
- **security**: shared props sem valor sensível; tela de erro sem detalhe interno.

## Quality Gates
Local Quality Gate classe React/TypeScript + **Reuse Gate** (Anexo I §6.3) avaliado contra o `INVENTORY.md`.

## Definition of Done
Os 10 Acceptance Criteria satisfeitos, Reuse Gate documentado no Story Report, acessibilidade verificada, Critical/High = 0.
