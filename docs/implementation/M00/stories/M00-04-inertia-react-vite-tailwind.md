# M00-04 — Inertia + React + TypeScript + Vite + Tailwind integration

## Objective
Servir a interface do Control Plane a partir da própria aplicação Rails usando Inertia com React/TypeScript, bundle por Vite e estilo por Tailwind — resolvendo o conflito SC-01 em código.

## Outcome
Uma rota Rails renderiza uma página Inertia; a página é um componente React tipado; o build de produção gera assets versionados; o dev server tem HMR.

## References
- `docs/AGENT_RULES.md` — “Frontend Rules”, “Inertia and the public API”
- `docs/annexes/I-engineering-playbook-quality-gates.md` §6 (hierarquia, estado e dados)
- `docs/architecture/10-ui-use-cases.md` §3 (arquitetura de informação), §25 (estados universais)
- `docs/implementation/SPEC_CONFLICTS.md` SC-01

## Preconditions
`M00-01` done.

## Scope
- Adapter Inertia no lado Rails: middleware, shared props, tratamento de redirect e de erro.
- Entry point React/TypeScript com resolução de páginas a partir de `app/frontend/pages/`.
- Vite integrado ao Rails para dev (HMR) e para build de produção com digest.
- Tailwind configurado, incluindo dark/light e tokens base.
- Uma página de exemplo que exercita: props vindas do servidor, estado local de UI e um estado de erro.
- `README.md` em `app/frontend/` com a regra: props server-driven primeiro, sem store global para estado de uma página, nunca importar código server-only na árvore React.

## Out of Scope
- Biblioteca de componentes existente (`M00-05`).
- Testes de frontend (`M00-08`).
- App shell real com navegação e team switcher (`M01-06`).
- Qualquer tela de domínio.

## UI Impact
Cria a fundação de renderização. A partir daqui, **toda** tela do produto é uma página Inertia; nenhuma Story pode criar endpoint REST apenas para alimentar a própria UI (`docs/AGENT_RULES.md`, “Inertia and the public API”).

## Security Requirements
- Proteção CSRF ativa no fluxo Inertia.
- Headers de segurança do painel definidos (CSP, HSTS quando houver TLS, frame-ancestors, referrer-policy) — sem impor política às aplicações dos usuários (Anexo C §14).
- Shared props **nunca** carregam segredo, token ou credencial; a regra vira teste aqui e fitness function AF-06 em `M00-13`.

## Observability Requirements
Erro de renderização no cliente precisa ser distinguível de erro do servidor no log — não colapsar os dois em “500”.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Asset não compilado em produção | Boot falha explicitamente; não serve página quebrada. |
| Página Inertia inexistente | Erro claro identificando o componente ausente, não tela em branco. |
| Erro no servidor durante request Inertia | Resposta de erro tratada pelo adapter, com página de erro renderizada e `request_id` visível. |

## Acceptance Criteria
1. Uma rota Rails renderiza uma página Inertia com um componente React em TypeScript.
2. `tsc` typecheck passa sem erro na árvore `app/frontend/`.
3. Dev server aplica HMR ao editar o componente.
4. O build de produção gera assets com digest e a aplicação os serve corretamente.
5. Tailwind aplica estilos e a configuração inclui os caminhos de `app/frontend/`.
6. A página de exemplo demonstra props do servidor, estado local e estado de erro.
7. Requisição sem token CSRF válido é rejeitada.
8. Um teste prova que shared props não contêm chaves marcadas como sensíveis.
9. Não existe nenhum arquivo Next.js, nem rota REST criada só para a UI.

## Required Tests
- **integration (request)**: rota renderiza página Inertia; CSRF inválido é rejeitado; erro de servidor produz página de erro com `request_id`.
- **unit (frontend)**: o componente de exemplo renderiza props e estado de erro — harness completo vem em `M00-08`, aqui basta o smoke.
- **security**: shared props sem valor sensível.

## Quality Gates
Local Quality Gate classes Ruby/Rails e React/TypeScript (format + lint + typecheck).

## Definition of Done
Os 9 Acceptance Criteria satisfeitos, typecheck limpo, build de produção verificado, Critical/High = 0.
