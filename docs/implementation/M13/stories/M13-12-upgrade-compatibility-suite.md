# M13-12 — N/N-1 upgrade compatibility suite

## Objective

Provar que a plataforma pode ser atualizada sem janela de manutenção não planejada: schema, contratos, payloads e workers da versão anterior convivem com a nova durante o rollout.

## Outcome

Uma matriz de combinações suportadas, testada — não presumida.

## References

- `docs/annexes/D-test-strategy.md` §16, §16.1
- `docs/annexes/I-engineering-playbook-quality-gates.md` §16.2 (AF-09)
- `docs/architecture/07-internal-control-plane.md` — `schemaVersion` de payload

## Preconditions

- Migrações expand-contract adotadas desde M00.

## Scope

- **Schema**: migrações da versão N aplicadas com código N-1 ainda rodando; verificação de que nada quebra.
- **Contract**: API pública e eventos da versão N consumidos por cliente N-1 e vice-versa.
- **Payload**: Operation com `schemaVersion` antiga executada por worker novo; Operation nova recusada de forma explícita por worker antigo, sem aplicar efeito parcial.
- **Worker misto**: workers N e N-1 processando a mesma fila simultaneamente.
- **UI/assets**: sessão aberta com bundle antigo contra backend novo.
- Rollback do código sem rollback do schema: a versão N-1 volta a funcionar após um deploy N revertido.
- Verificação de que nenhuma migração destrutiva ocorre fora da fase de contract.
- Declaração explícita das combinações suportadas e das não suportadas.

## Out of Scope

- Upgrade real em staging com runbook: `M14-03`.
- Compatibilidade N-2: fora do compromisso; declarada como não suportada.

## Security Requirements

- Um worker antigo nunca aplica um payload que não entende; recusar é o comportamento correto.
- Downgrade não reabre permissão removida nem restaura secret revogado.

## Observability Requirements

- Relatório com a matriz de combinações e o resultado de cada célula.
- Log explícito quando um componente recusa por incompatibilidade de versão.

## Failure Scenarios

| Cenário | Comportamento esperado |
|---|---|
| Migração N quebra código N-1 | Finding **Critical**. |
| Worker antigo aplica payload novo parcialmente | Finding **Critical**. |
| Downgrade reabre permissão removida | Finding **Critical**. |
| Cliente N-1 quebra com API N | Finding **High**. |
| Migração destrutiva fora da fase de contract | Finding **High**; AF-09 falha. |

## Acceptance Criteria

1. Migrações N são aplicadas com código N-1 rodando, sem quebra.
2. API e eventos são compatíveis nas duas direções dentro de N/N-1.
3. Worker novo executa payload antigo; worker antigo recusa payload novo sem efeito parcial.
4. Fila com workers mistos é processada corretamente.
5. Bundle antigo contra backend novo degrada de forma controlada.
6. Rollback do código sem rollback do schema mantém N-1 funcional.
7. Nenhuma migração destrutiva ocorre fora da fase de contract.
8. Downgrade não reabre permissão nem restaura secret revogado.
9. As combinações suportadas e não suportadas são declaradas.

## Required Tests

- Integration com dois conjuntos de binários/versões.
- Contract tests bidirecionais.
- Verificação automatizada de fase de migração (AF-09).

## Quality Gates

Local Quality Gate; AF-09 (migração destrutiva exige marcador de contract/ADR).

## Definition of Done

- [ ] 9 Acceptance Criteria com evidência.
- [ ] Matriz de compatibilidade publicada.
- [ ] Self-review; `tasks.json` atualizado com commit.
