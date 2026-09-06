# M14-05 — Full DR drill on new infrastructure

## Objective

Reconstruir a plataforma inteira em infraestrutura nova, a partir apenas dos backups e da Recovery Key, medindo RPO e RTO reais.

## Outcome

A prova final de que o backup serve para alguma coisa — que é a única prova que conta.

## References

- `docs/architecture/05-backup-restore-dr.md` — backup, restore e DR
- `docs/annexes/E-operational-runbooks.md` — RB-23, RB-24, RB-25
- `docs/implementation/M10/README.md`
- `docs/annexes/B-nfr-slos.md` §11, §11.1 (RPO/RTO e restore verification)

## Preconditions

- Backups produzidos pelo fluxo normal, não fabricados para o teste.
- Infraestrutura **nova**, sem nenhum estado herdado.
- `M14-04` concluída: runbooks exercitados.

## Scope

- Restauração completa: PostgreSQL do Control Plane, MEK via Recovery Key, configuração do cluster, certificados, rotas e Secrets.
- Reconstrução do Swarm e readmissão dos nós.
- Verificação de integridade: Desired State restaurado corresponde ao momento do backup; nada foi inventado.
- Convergência: os reconcilers levam o Actual State ao Desired restaurado.
- Verificação de que Services voltam a servir tráfego com os certificados corretos.
- Verificação de que Secrets decifram corretamente após o restore.
- **Medição de RPO** (quanto se perdeu) e **RTO** (quanto demorou), comparados com os alvos.
- Teste do caminho negativo: restore com Recovery Key errada falha de forma limpa, sem corromper nada.
- Registro de tudo o que não foi restaurado e por quê.

## Out of Scope

- Restore de produção: exige gate humano; nunca autônomo.

## Security Requirements

- A Recovery Key é fornecida pelo operador no momento do drill; ela não está no workspace nem no backup do store primário.
- Após o drill, o ambiente de laboratório é destruído; ele contém material sensível restaurado.
- O drill nunca usa backup de produção com dado real de cliente sem autorização explícita e ambiente equivalente em controles.

## Observability Requirements

- Relatório: linha do tempo, RPO, RTO, itens restaurados, itens não restaurados e desvios do runbook.
- Comparação item a item entre o Desired State do backup e o restaurado.

## Failure Scenarios

| Cenário | Comportamento esperado |
|---|---|
| Restore não reconstrói a plataforma | Finding **Critical**. |
| Secrets não decifram após restore | Finding **Critical**. |
| RPO ou RTO fora do alvo | Finding **High**; alvo revisto por decisão humana ou processo corrigido. |
| Recovery Key errada corrompe estado | Finding **Critical**. |
| Item não restaurado sem registro | Finding **High**. |

## Acceptance Criteria

1. A plataforma é reconstruída em infraestrutura nova, a partir de backups do fluxo normal.
2. A Recovery Key do operador destrava o MEK; Secrets decifram corretamente.
3. O Desired State restaurado corresponde ao momento do backup, sem invenção.
4. Os reconcilers convergem o Actual State ao Desired restaurado.
5. Services voltam a servir tráfego com certificados válidos.
6. RPO e RTO são medidos e comparados com os alvos.
7. Restore com Recovery Key errada falha de forma limpa, sem corrupção.
8. Tudo o que não foi restaurado é registrado com justificativa.
9. O ambiente do drill é destruído ao final.
10. O relatório é arquivado como evidência do gate.

## Required Tests

- Drill completo executado no laboratório de DR.
- Teste negativo com Recovery Key inválida.

## Quality Gates

Local Quality Gate.

## Definition of Done

- [ ] 10 Acceptance Criteria com evidência.
- [ ] RPO e RTO medidos e registrados.
- [ ] Ambiente do drill destruído.
- [ ] Self-review; `tasks.json` atualizado com commit.
