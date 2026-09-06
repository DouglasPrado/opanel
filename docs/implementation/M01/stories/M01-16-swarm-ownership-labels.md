# M01-16 — Ownership labels and deterministic naming for Swarm resources

## Objective
Marcar todo recurso criado pela plataforma no Swarm com labels de ownership suficientes para identificá-lo e reconciliá-lo mesmo após um restart completo do Control Plane — e derivar nomes técnicos de IDs estáveis, não de slugs humanos.

## Outcome
Todo Service, network, secret e config criado pela plataforma carrega o namespace de ownership decidido no `ADR-0001`; recursos sem ownership da plataforma **nunca** são adotados nem apagados automaticamente.

## References
- `docs/architecture/07-internal-control-plane.md` §7 (labels de ownership e boundary)
- `docs/architecture/08-networking-domains-edge.md` §5 (naming por IDs)
- `docs/architecture/09-data-model-apis-contracts.md` §5.3 (naming determinístico)
- `docs/decisions/ADR-0001-swarm-ownership-label-namespace.md`
- `docs/implementation/SPEC_CONFLICTS.md` SC-04, SC-09

## Preconditions
`M01-09` done. **`ADR-0001` precisa estar `Accepted`.** Enquanto estiver `Proposed`, esta Story fica `BLOCKED_FOR_PRODUCT_DECISION`.

## Scope
- Constante única com o namespace de ownership; **nenhuma** string literal repetida no código.
- Conjunto de labels do doc 07 §7 aplicado a todo recurso gerenciado: `managed`, `team_id`, `project_id`, `environment_id`, `service_id`, `release_id` (quando existir), `desired_revision`.
- Geração determinística de nomes técnicos a partir de **IDs** (SC-09): Service, network e demais recursos.
- Predicado de ownership: “este recurso é gerenciado por esta instalação?”, usado por reconcilers e pelo Clean Rebuild futuro.
- **Boundary explícito:** recursos sem ownership da plataforma nunca são adotados nem removidos automaticamente.

## Out of Scope
- Drift detection e Platform Wins (`M02-06`).
- Adopt runtime state (`M02-07`).
- Labels de placement de node (`M02-03`) — mesmo namespace, Story diferente.
- Migração de labels de uma instalação existente (não há instalação existente).

## Application Layer
Um único módulo de ownership expõe: `labels_for(resource)`, `technical_name_for(resource)` e `managed_by_platform?(runtime_resource)`. Reconcilers e executor consomem esse módulo; ninguém monta label à mão.

## Security Requirements
- As labels **não** carregam valor sensível: apenas IDs opacos e a revisão desejada. Nunca nome de secret, credencial ou dado de usuário.
- O predicado de ownership é a última barreira contra a plataforma apagar um workload de terceiro no mesmo Swarm (doc 07 §7). Um falso positivo aqui é destrutivo, então o predicado exige `managed=true` **e** consistência dos IDs, não apenas um campo.
- Renomear Project, Environment ou Service **não** muda o nome técnico — evita recriação desnecessária e perda de identidade de ownership.

## Observability Requirements
Toda criação de recurso registra as labels aplicadas e o nome técnico gerado, com `service_id`/`environment_id` correspondentes, para permitir auditoria posterior de ownership.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Recurso de terceiro no mesmo Swarm | Predicado retorna falso; a plataforma não adota nem apaga. |
| Recurso com `managed=true` mas IDs inconsistentes | Tratado como **não** gerenciado e registrado como anomalia para revisão humana — nunca apagado automaticamente. |
| Renomear Project | Nome técnico permanece; nenhum recurso é recriado. |
| Colisão de nome técnico | Impossível por construção (IDs opacos); um teste guarda a propriedade. |
| ADR-0001 ainda `Proposed` | Story `BLOCKED_FOR_PRODUCT_DECISION`; não escolher um prefixo por conta própria. |

## Acceptance Criteria
1. Existe uma constante única de namespace, e nenhuma string literal de label aparece fora desse módulo, verificado por teste.
2. Todo recurso criado pela plataforma no Swarm recebe o conjunto completo de labels de ownership.
3. Os nomes técnicos são derivados de IDs; renomear Project, Environment ou Service **não** altera o nome técnico, provado por teste.
4. O predicado de ownership retorna falso para um recurso criado fora da plataforma, provado contra Swarm real.
5. Um recurso com `managed=true` e IDs inconsistentes é tratado como não gerenciado e registrado como anomalia, **sem** remoção automática.
6. Nenhuma label contém valor sensível.
7. Uma instalação que perde todo o estado em memória consegue reidentificar seus recursos apenas pelas labels, provado por teste que recria o processo.
8. Colisão de nome técnico é impossível por construção, com teste que exercita a propriedade.
9. As labels aplicadas são registradas no log com os IDs correspondentes.

## Required Tests
- **unit**: geração de labels e de nome técnico; predicado de ownership com casos ambíguos.
- **Docker/Swarm**: criação real com labels; recurso de terceiro não reconhecido; reidentificação após reinício do processo.
- **security**: ausência de valor sensível em label; recurso ambíguo não removido.

## Quality Gates
Local Quality Gate + suíte Docker/Swarm. **Bloqueada por `ADR-0001`.**

## Definition of Done
`ADR-0001` aceito, os 9 Acceptance Criteria satisfeitos contra Swarm real, predicado de ownership provado com recurso de terceiro, Critical/High = 0.
