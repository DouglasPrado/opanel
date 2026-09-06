# M00-12 — Local, pre-commit and post-commit gate scripts

## Objective
Materializar em scripts executáveis os três gates locais do Anexo I — Local Quality Gate, Pre-commit Gate e Post-commit Gate — para que “pronto” deixe de ser opinião.

## Outcome
`bin/gate local`, `bin/gate pre-commit` e `bin/gate post-commit` existem, são rápidos o suficiente para rodar em toda Story e falham com razão objetiva.

## References
- `docs/annexes/I-engineering-playbook-quality-gates.md` §11 (Local), §12 (Pre-commit), §13 (commit policy), §14 (Post-commit), §23 (templates)
- `docs/annexes/H-autonomous-development-loop.md` §4 (Stop Gates determinísticos)
- `docs/AGENT_RULES.md` — “Quality Gates”

## Preconditions
`M00-11` done.

## Scope
- `bin/gate local`: format, lint, typecheck, testes relacionados, migration validation, contract tests quando contrato mudou, e checks de segurança aplicáveis às classes de código tocadas.
- `bin/gate pre-commit`: a checklist do Anexo I §12.1 — format do diff, lint dos módulos afetados, typecheck incremental, testes rápidos relacionados, secret scan, migration não obviamente inválida, nenhum arquivo gerado indevido, **diff dentro do escopo esperado**.
- `bin/gate post-commit`: a checklist do §14.2 — review do diff contra a Story, mapeamento de acceptance criteria, resultado do Reviewer, fitness functions, testes do módulo, consistência de `tasks.json` e commit hash.
- Hook de git instalando o pre-commit, com a regra de que `--no-verify` nunca é automático.
- Verificação de **boundary de diff**: arquivos alterados fora do escopo declarado da Story reprovam.
- Saída legível por humano **e** parseável por máquina (para o Stop Gate de `M00-14`).

## Out of Scope
- Stop Gate do Autonomous Loop e validação de `tasks.json` (`M00-14`).
- Fitness functions em si (`M00-13`) — o gate apenas as invoca.
- Reviewer Agent (é processo, não script).

## Security Requirements
- Secret scan é obrigatório no pre-commit e não pode ser pulado pelo agente.
- O script não pode imprimir o segredo detectado.
- Bypass manual exige motivo registrado e o gate roda de novo antes do merge; o agente autônomo **não** tem permissão para desabilitar hook (Anexo I §12.2).

## Observability Requirements
Cada gate reporta, por check: nome, resultado, duração e razão da falha. A razão precisa ser específica o suficiente para o loop autônomo agir sem adivinhar.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Pre-commit lento demais | Escopo incremental por diff; check pesado migra para CI, nunca é removido. |
| Diff fora do boundary da Story | Pre-commit reprova apontando os arquivos inesperados. |
| `tasks.json` inconsistente com o commit | Post-commit reprova. |
| Agente tenta `--no-verify` | Post-commit detecta ausência de execução do pre-commit e reprova. |

## Acceptance Criteria
1. `bin/gate local` executa a checklist do Anexo I §11.1 e retorna exit code 0 apenas com tudo verde.
2. `bin/gate pre-commit` executa os 8 itens do §12.1 e reprova quando qualquer um falha, provado por caso negativo por item.
3. `bin/gate post-commit` executa os 6 checks do §14.2 e reprova com razão objetiva.
4. O hook de git está instalado por `bin/setup` e roda o pre-commit.
5. A verificação de boundary de diff reprova alteração fora do escopo declarado, provado por caso negativo.
6. `--no-verify` não é usado por nenhum script do repositório; o post-commit detecta commit que não passou pelo pre-commit.
7. A saída de cada gate é parseável por máquina e inclui nome, resultado, duração e razão.
8. Nenhum gate imprime valor sensível.
9. O tempo de `bin/gate pre-commit` num diff típico é medido e registrado, com um orçamento explícito documentado.

## Required Tests
- **unit**: parser de saída dos gates; verificação de boundary de diff.
- **integration**: caso negativo por item do pre-commit; post-commit com `tasks.json` inconsistente; commit sem pre-commit detectado.

## Quality Gates
Esta Story **é** o gate local. Todas as Stories anteriores de M00 devem ser revalidadas por `bin/gate local` antes do fechamento do Milestone.

## Definition of Done
Os 9 Acceptance Criteria satisfeitos, um caso negativo por item do pre-commit, Stories anteriores de M00 revalidadas, Critical/High = 0.
