# M00-05 — Import and inventory the existing React component library

## Objective
Trazer a biblioteca de componentes React já existente para dentro da hierarquia do Anexo I §6.1 e produzir um **inventário versionado** que torne o Reuse Gate verificável em todas as Stories de UI seguintes.

## Outcome
`app/frontend/components/INVENTORY.md` lista cada componente disponível com nome, responsabilidade, props públicas, categoria e exemplo de uso. Uma página de galeria renderiza os componentes para inspeção visual.

## References
- `docs/goals/G01-create-implementation-pack.md` §17 (reutilizar componente existente do repositório `gba.dev`)
- `docs/AGENT_RULES.md` — “Component Reuse”
- `docs/annexes/I-engineering-playbook-quality-gates.md` §6.2, §6.3 (Reuse Gate)
- `docs/implementation/SPEC_CONFLICTS.md` SC-07

## Preconditions
`M00-04` done. **Acesso ao repositório `gba.dev`** com a biblioteca existente. Sem esse acesso, a Story é `BLOCKED_EXTERNAL_DEPENDENCY`.

## Scope
- Importar os componentes existentes preservando aparência e contratos.
- Classificar cada um em `ui/` (primitives), `shared/` (compostos reutilizados), `layouts/`.
- Adaptar tipagem para TypeScript onde faltar, **sem redesenhar** a API do componente.
- Produzir `INVENTORY.md` com uma linha por componente: nome, categoria, responsabilidade, props, quando usar, quando **não** usar.
- Página de galeria interna (rota de desenvolvimento) renderizando cada componente com seus estados principais.

## Out of Scope
- **Criar um design system novo.** Explicitamente proibido pelo Goal §17.
- Migrar componentes para outra tecnologia.
- Telas de domínio.
- Testes de componente completos (`M00-08` entrega o harness; a cobertura cresce com cada feature).

## UI Impact
Define o vocabulário visual de todo o produto. A partir daqui, o Reuse Gate do Anexo I §6.3 é avaliado **contra este inventário** — “não existia componente equivalente” passa a ser uma afirmação verificável, não uma opinião.

## Security Requirements
- Nenhum componente pode logar, persistir ou copiar automaticamente valor sensível para o clipboard (doc 10 §28: copiar secret exige confirmação visual explícita).
- Componentes de input de credencial/secret nascem com `type` protegido e sem autocomplete inadequado.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Repositório de origem indisponível | Story `BLOCKED_EXTERNAL_DEPENDENCY`; **não** substituir por design system novo. |
| Componente importado sem tipagem | Adaptar tipos preservando o contrato; se o contrato for ambíguo, registrar no inventário como “contrato a confirmar”, não inventar. |
| Dois componentes com o mesmo papel visual | Registrar ambos no inventário com a diferença explícita; se não houver diferença, consolidar e anotar a decisão. |

## Acceptance Criteria
1. Os componentes existentes estão em `app/frontend/components/{ui,shared,layouts}` conforme sua categoria.
2. `INVENTORY.md` existe, não está vazio e cobre **todos** os componentes importados.
3. Cada entrada do inventário tem nome, categoria, responsabilidade, props públicas e orientação de quando não usar.
4. A galeria renderiza cada componente do inventário sem erro de console.
5. `tsc` passa em toda a árvore de componentes.
6. Nenhum componente novo foi criado onde um importado resolvia.
7. Um teste falha se um componente existir em disco e não aparecer no `INVENTORY.md` (o inventário não pode envelhecer em silêncio).
8. Nenhum componente de entrada de secret copia valor para o clipboard sem confirmação explícita.

## Required Tests
- **unit (frontend)**: smoke render de cada componente da galeria.
- **unit**: consistência disco ↔ inventário.
- **security**: componente de secret não expõe valor em DOM de forma inadvertida e não auto-copia.

## Quality Gates
Local Quality Gate classe React/TypeScript. Reuse Gate documentado como aplicável a partir desta Story.

## Definition of Done
Os 8 Acceptance Criteria satisfeitos, inventário completo e testado contra o disco, nenhum design system paralelo criado, Critical/High = 0.
