# M08-07 — Safe node removal and force remove

## Objective
Remover um node do cluster preservando workload e integridade, e oferecer `force remove` apenas para o caso de node definitivamente perdido — como operação privilegiada e auditada.

## Outcome
A remoção normal exige drain e verificação; o `force remove` existe, é restrito, avisa o que não pode ser garantido, e é registrado.

## References
- `docs/architecture/06-infrastructure-provisioning.md` §7.2 (Remove, Force Remove), §16.1 (remoção segura de worker), §16.2 (manager)
- `docs/architecture/03-runtime-observability.md` §13.3 (remoção de node)
- `docs/annexes/E-operational-runbooks.md` RB-28

## Preconditions
`M08-06` done.

## Scope
- Fluxo do doc 06 §16.1: marcar `DECOMMISSIONING` → drain → aguardar tasks = 0 → remover integrações especiais (target do LB, pool de builders) → remover do Swarm → revogar material de enrollment e metadata de runtime.
- Validações antes de remover: quorum (se manager), capacidade restante de workers e de ingress.
- `force remove` para node inacessível: privilegiado, auditado, com aviso explícito do que não pode ser garantido.
- Registro de quem removeu, motivo e impacto previsto (doc 03 §13.3).
- Node removido tem suas credenciais e enrollment associados revogados.

## Out of Scope
- Deleção do servidor no provider de cloud (backlog).
- Substituição automática de node.
- Recuperação de node perdido (RB-04, operacional).

## Application Layer
- **Commands:** `RemoveNode`, `ForceRemoveNode`.
- **Policies:** remoção exige ADMIN/`INSTANCE_OPERATOR`; `force remove` exige `INSTANCE_ADMIN` + step-up.

## Security Requirements
- **Drain antes de remover sempre que o node estiver acessível** (doc 03 §13.3).
- Remover um manager sem avaliar o quorum é **bloqueado** (doc 06 §16.2).
- `force remove` é operação privilegiada: exige `INSTANCE_ADMIN`, step-up e confirmação, e é auditada com destaque.
- Ao remover, **revogar credenciais e material de enrollment associados** — um node descartado que ainda pode voltar ao cluster é uma porta aberta (Anexo C §8.1).
- Ingress precisa sair do LB antes de ser removido.
- A remoção registra impacto previsto, para que a decisão fique documentada.

## Observability Requirements
Timeline da remoção por etapa; capacidade antes e depois; evento de node removido.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Tasks ainda no node | Remoção bloqueada até a evacuação ou decisão explícita. |
| Manager cujo quorum ficaria inseguro | Bloqueado. |
| Node inacessível | `force remove` disponível, com aviso do que não pode ser garantido. |
| Ingress ainda no LB | Bloqueado até o target sair. |
| Capacidade restante insuficiente | Avisado com o cálculo; a decisão é explícita. |
| Node volta depois de removido | Não reingressa: material de enrollment e credenciais foram revogados. |

## Acceptance Criteria
1. A remoção normal segue a ordem: `DECOMMISSIONING` → drain → tasks zero → remover integrações → remover do Swarm → revogar material.
2. Remoção com tasks ainda no node é bloqueada até evacuação ou decisão explícita.
3. Remover manager com quorum inseguro é **bloqueado**.
4. Ingress ainda no LB bloqueia a remoção.
5. Capacidade restante insuficiente é avisada com o cálculo antes de confirmar.
6. `force remove` exige `INSTANCE_ADMIN` + step-up e avisa o que não pode ser garantido.
7. `force remove` é auditado com destaque.
8. Ao remover, o material de enrollment e as credenciais associadas são **revogados**, provado por teste com tentativa de reingresso.
9. A remoção registra quem, quando, motivo e impacto previsto.
10. A timeline da remoção é observável por etapa.
11. Um node removido que tente reingressar é rejeitado.

## Required Tests
- **Docker/Swarm**: remoção real de worker após drain; tentativa de reingresso rejeitada; remoção de manager bloqueada por quorum.
- **integration**: bloqueio por tasks; bloqueio por target no LB; aviso de capacidade.
- **policy**: `force remove` exigindo `INSTANCE_ADMIN` + step-up.
- **security**: revogação de material; AuditLog de `force remove`.

## Quality Gates
Local Quality Gate + suíte Docker/Swarm + `bin/security`. **Story crítica: operação destrutiva; exige plan mode.**

## Definition of Done
Os 11 Acceptance Criteria satisfeitos, revogação de material provada por tentativa de reingresso, Critical/High = 0.
