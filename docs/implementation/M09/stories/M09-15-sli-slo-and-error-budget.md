# M09-15 — SLIs, SLOs and error budget

## Objective
Medir objetivamente a qualidade de serviço da plataforma e expor o error budget, para que a política de mudança do Anexo B §15 tenha um número por trás.

## Outcome
Os SLIs do Anexo B são calculados por superfície; os SLOs têm janela definida; o error budget é visível e a política de rollout pode reagir a ele.

## References
- `docs/annexes/B-nfr-slos.md` §3 (SLOs de disponibilidade), §4 (latência), §5 (reconciliation), §15 (error budget e política de mudança), §20 (critérios de aceite)
- `docs/architecture/03-runtime-observability.md` §16 (SLI e SLO)
- `docs/annexes/D-test-strategy.md` §23 (SLO → threshold automatizado)

## Preconditions
`M09-03` e `M09-08` done.

## Scope
- `SloDefinition`: superfície, SLI, alvo, janela, exclusões documentadas.
- SLIs por superfície do Anexo B §3: Control Plane API, leitura crítica de UI/API, ingress público, Operation Engine, submissão de build, gestão de certificados.
- Cálculo com denominador registrado e exclusões **explícitas** (4xx esperados, cancelamentos do usuário, falhas de dependência externa classificadas separadamente).
- Error budget por superfície, com consumo visível.
- Dashboard de error budget e a política de consumo do Anexo B §15 como **sinal**, não como bloqueio automático nesta fase.
- Thresholds exportáveis para a suíte de performance de `M13-13`.

## Out of Scope
- Bloqueio automático de release por error budget — a política é definida; a aplicação automática é decisão operacional de M14.
- SLA contratual (Anexo B §1: SLA não é derivado automaticamente de SLO).
- SLOs das aplicações dos clientes.

## Application Layer
- **Queries:** `SloStatus`, `ErrorBudgetView`.

## Security Requirements
- **Exclusões nunca são silenciosas** (Anexo B §1, regra explícita): requests inválidos, cancelamentos e falhas externas podem ser classificados separadamente, mas jamais removidos sem registro. Um SLO que se “melhora” escondendo denominador é pior que não ter SLO.
- O cálculo é auditável: a definição, a janela e as exclusões são versionadas.
- Reduzir um SLO é uma **mudança de política**, registrada — não um ajuste silencioso (Anexo B §15: “não resolver reduzindo silenciosamente o SLO”).
- Consultas respeitam tenancy quando o SLI é por Team.

## Observability Requirements
- SLI calculado com denominador visível.
- Error budget consumido, restante e projeção.
- Separação por superfície: um incidente no builder **não** consome o budget do ingress (Anexo B §15).

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Dados insuficientes na janela | SLI marcado como indeterminado, não otimista. |
| Exclusão aplicada | Registrada e visível no cálculo. |
| Error budget esgotado | Sinalizado com destaque; a política de mudança é informada ao operador. |
| Backend de métricas degradado | SLI indisponível com causa; não presumir 100%. |
| SLO alterado | Versionado e registrado como mudança de política. |
| Incidente em uma superfície | Consome apenas o budget daquela superfície. |

## Acceptance Criteria
1. `SloDefinition` existe com superfície, SLI, alvo, janela e exclusões documentadas.
2. Os SLIs das seis superfícies do Anexo B §3 são calculáveis.
3. O denominador é registrado e visível no cálculo.
4. Exclusões são **explícitas e registradas**; nenhuma remoção silenciosa, provado por teste.
5. O error budget é calculado por superfície e o consumo é visível.
6. Um incidente em uma superfície **não** consome o budget de outra.
7. Dados insuficientes produzem SLI indeterminado, nunca otimista.
8. Backend degradado produz SLI indisponível com causa; nunca 100% presumido.
9. Alterar um SLO é versionado e registrado como mudança de política.
10. A política de consumo do Anexo B §15 é apresentada ao operador como sinal.
11. Os thresholds são exportáveis para a suíte de performance de `M13-13`.
12. Consultas respeitam tenancy quando aplicável.

## Required Tests
- **unit**: cálculo de SLI com e sem exclusões; error budget; estado indeterminado.
- **integration**: dados insuficientes; backend degradado; alteração de SLO versionada.
- **security**: exclusão registrada; ausência de remoção silenciosa do denominador.

## Quality Gates
Local Quality Gate + `bin/security`.

## Definition of Done
Os 12 Acceptance Criteria satisfeitos, exclusões auditáveis, ausência de otimismo por falta de dado, Critical/High = 0.
