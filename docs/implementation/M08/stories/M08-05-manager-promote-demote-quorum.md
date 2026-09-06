# M08-05 — Manager promote/demote with quorum guardrails

## Objective
Permitir alterar a topologia de managers **sem nunca** comprometer o quorum acidentalmente, simulando o resultado antes de aplicar.

## Outcome
Antes de promover ou demover, a plataforma mostra o quorum atual e o resultante; operações que o comprometeriam são bloqueadas.

## References
- `docs/architecture/06-infrastructure-provisioning.md` §7.2 (promote/demote), §8.2 (manutenção de manager), §16.2 (remoção de manager bloqueada se ameaçar quorum)
- `docs/annexes/E-operational-runbooks.md` RB-05, RB-06, RB-27
- `docs/annexes/C-threat-model-security-hardening.md` §8.1 (3 ou 5 managers, número ímpar), T15

## Preconditions
`M08-04` done.

## Scope
- Promote de Worker para Manager e demote de Manager para Worker.
- **Simulação obrigatória**: calcular managers atuais, alcançáveis, quorum atual e quorum resultante; exibir antes de confirmar.
- Bloqueio quando a operação levaria o quorum a um estado inseguro.
- Recomendação de número **ímpar** de managers (3 ou 5).
- **Uma mudança de membership por vez** (RB-27); operações simultâneas são serializadas.
- Exigência de `INSTANCE_ADMIN`/OWNER, reautenticação e confirmação explícita para promote (doc 06 §6.3).
- Ordem correta na substituição: adicionar o novo manager e aguardar `Reachable` **antes** de remover o antigo.

## Out of Scope
- Recuperação de quorum perdido (RB-06, `M10-14` e runbook operacional).
- `force-new-cluster` — operação de desastre, **nunca** de troubleshooting.
- Autolock do Swarm — mencionado no Anexo C §8; sem requisito imediato, registrado como evolução.

## Application Layer
- **Commands:** `PromoteNode`, `DemoteNode`.
- **Queries:** `QuorumImpactSimulation`.
- **Policies:** exige `INSTANCE_ADMIN` ou OWNER + step-up.

## Security Requirements
- Um Manager tem acesso ao control plane do Swarm: promover é **conceder privilégio de infraestrutura** (Anexo C §8).
- Exige reautenticação (`M03-04`) e confirmação explícita.
- Nunca promover/demover em lote sem simular o novo quorum (doc 06 §8.2, regra explícita).
- Nunca remover um manager apenas porque a máquina não responde — calcular o efeito primeiro (doc 06 §16.2).
- Toda operação de promote/demote gera AuditLog com o quorum antes e depois.
- Managers devem ser hosts estáveis; a plataforma avisa quando um node efêmero é promovido.

## Observability Requirements
Quorum atual e alcançável sempre visível. Simulação registrada com a operação. Métrica: número de managers, alcançáveis, e eventos de mudança de membership.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Demote que quebraria o quorum | **Bloqueado**, com o cálculo exibido. |
| Promote em node instável/efêmero | Avisado com destaque. |
| Duas mudanças de membership simultâneas | Serializadas; uma por vez. |
| Manager inalcançável | Não remover automaticamente; calcular o efeito e exigir decisão. |
| Número par de managers resultante | Avisado; o ímpar é recomendado. |
| Substituição de manager | Adicionar primeiro, aguardar `Reachable`, só então remover o antigo. |

## Acceptance Criteria
1. Promote e demote existem e são aplicados via Executor.
2. A simulação de quorum é exibida **antes** de confirmar, com valores atual e resultante.
3. Operação que comprometeria o quorum é **bloqueada** com o cálculo exibido.
4. Promote exige `INSTANCE_ADMIN`/OWNER **e** step-up authentication.
5. Apenas **uma** mudança de membership por vez; simultâneas são serializadas.
6. Manager inalcançável **não** é removido automaticamente.
7. Número par de managers resultante gera aviso.
8. Na substituição, o novo manager é adicionado e fica `Reachable` antes de o antigo ser removido.
9. Promover node instável/efêmero gera aviso com destaque.
10. Promote/demote geram AuditLog com quorum antes e depois.
11. Nenhum caminho do código executa `force-new-cluster`.

## Required Tests
- **unit**: cálculo de quorum; simulação; detecção de número par.
- **Docker/Swarm**: promote e demote reais em cluster de 3; bloqueio de demote que quebraria o quorum; serialização de duas mudanças.
- **policy**: step-up exigido; role insuficiente negada.
- **security**: ausência de `force-new-cluster` no código; AuditLog completo.

## Quality Gates
Local Quality Gate + suíte Docker/Swarm + `bin/security`. **Story crítica: exige plan mode.**

## Definition of Done
Os 11 Acceptance Criteria satisfeitos, bloqueio de quorum provado com o cálculo, Critical/High = 0.
