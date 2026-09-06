# M02-03 — Placement constraints, preferences and platform-managed node labels

## Objective
Transformar a topologia física do cluster em regras de agendamento previsíveis, com labels **estruturadas e administradas pela plataforma** em vez de strings arbitrárias espalhadas pela UI.

## Outcome
A plataforma gerencia labels de node; o usuário escolhe políticas compreensíveis (“pool de produção”, “evitar builders”) e a plataforma gera as constraints internamente.

## References
- `docs/architecture/03-runtime-observability.md` §6 (placement e topologia), §6.1 (constraints x preferences)
- `docs/architecture/06-infrastructure-provisioning.md` §9 (labels e placement), §9.2 (constraints geradas)
- `docs/decisions/ADR-0001-swarm-ownership-label-namespace.md`

## Preconditions
`M02-02` done. `ADR-0001` aceito (o namespace de labels de node segue a mesma decisão).

## Scope
- Labels de node gerenciadas pela plataforma: `role.manager`, `role.ingress`, `role.builder`, `workloads`, `zone`, `provider`, `environment`, `capacity.class` — no namespace do `ADR-0001`.
- Aplicação e remoção de labels via Executor, com reconciliação.
- Placement por **política de produto**, com geração interna de constraints; a sintaxe crua do Swarm não é exposta por padrão.
- Preferences de spread (por zona) quando houver mais de um domínio de falha.
- Modo avançado para quem realmente precisa de constraint explícita, com validação.

## Out of Scope
- Criação de nodes com roles (`M08-04`).
- Managers dedicados em Drain (`M08-05`).
- Node pools dedicados por Team (Tier T1 do Anexo C §9.1) — exige decisão de produto e Story própria.

## Domain Impact
**Entidade:** `NodeMetadata` (labels lógicas, zona, capacidade, política de scheduling), separada da observação do runtime.

## Application Layer
- **Commands:** `UpdateNodeLabels`, `UpdateServicePlacement`.
- **Policies:** alterar label de node exige ADMIN/INSTANCE_OPERATOR; alterar placement de Service exige ADMIN.

## Async / Control Plane
Label de node é desired state reconciliado como qualquer outro recurso: a plataforma aplica e verifica. Divergência é drift (`M02-06`).

## UI Impact
Políticas legíveis em vez de sintaxe: “executar somente no pool de produção”, “evitar builders”, “espalhar entre zonas”. O modo avançado mostra a constraint gerada, para transparência.

## Security Requirements
- Placement é um mecanismo de **isolamento** (Anexo C §9.1, Tier T1): separar production de builders e de ingress reduz blast radius.
- Labels são administradas pela plataforma; o usuário não injeta chave arbitrária no namespace gerenciado.
- Validação estrita de valor de label; nenhum caractere que permita quebrar a expressão de constraint.
- Alteração de label de node gera AuditLog.

## Observability Requirements
Quando uma Task não pode ser agendada por constraint, a causa é explícita: qual constraint e quais nodes foram descartados.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Nenhum node satisfaz a constraint | Task `Pending` com diagnóstico nomeando a constraint; `BLOCKED`, sem retry agressivo. |
| Label removida fora da plataforma | Detectada como drift e reaplicada (`M02-06`). |
| Constraint com sintaxe inválida no modo avançado | Rejeitada na validação, antes de chegar ao Swarm. |
| Preference de spread sem múltiplas zonas | Aceita e sem efeito; a UI explica que não há domínio de falha suficiente. |

## Acceptance Criteria
1. As labels de node gerenciadas existem no namespace do `ADR-0001` e são aplicadas via Executor.
2. Políticas de produto geram constraints internamente; a sintaxe crua não é exigida do usuário.
3. O modo avançado mostra a constraint gerada e valida entrada manual.
4. Nenhum node elegível resulta em Task `Pending` com diagnóstico nomeando a constraint.
5. Preference de spread por zona é aplicada quando há mais de uma zona.
6. Label removida fora da plataforma é detectada como divergência (a reversão é de `M02-06`).
7. Valor de label é validado; caracteres que quebrariam a expressão são rejeitados.
8. Alterar labels de node exige permissão e gera AuditLog; negativo cross-team passa.
9. `max replicas per node` de `M02-02` continua respeitado junto com as constraints.

## Required Tests
- **unit**: geração de constraint a partir de política; validação de valor de label.
- **integration**: aplicação e reconciliação de labels.
- **Docker/Swarm**: Task `Pending` por constraint impossível; spread entre zonas simuladas; label removida manualmente.
- **policy**: negativo cross-team; role sem permissão.
- **security**: injeção em valor de label rejeitada.

## Quality Gates
Local Quality Gate + suíte Docker/Swarm.

## Definition of Done
Os 9 Acceptance Criteria satisfeitos, diagnóstico de constraint impossível verificado, injeção rejeitada, Critical/High = 0.
