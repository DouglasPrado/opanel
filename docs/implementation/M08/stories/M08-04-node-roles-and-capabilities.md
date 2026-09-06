# M08-04 — Node roles and capabilities: ingress, builder, workloads

## Objective
Materializar os papéis lógicos da plataforma — ingress, builder, workloads, system — como labels gerenciadas sobre Workers do Swarm, com efeito real no placement.

## Outcome
Marcar um node como ingress faz o Traefik ser agendado nele; marcar como builder o coloca no pool de builds; nenhum papel lógico exige role nativa do Swarm além de Manager.

## References
- `docs/architecture/06-infrastructure-provisioning.md` §1.2 (papéis lógicos), §9.1 (labels gerenciadas), §15.2 (aumentar ingress), §15.3 (aumentar builders)
- `docs/architecture/03-runtime-observability.md` §6 (placement e topologia)
- `docs/decisions/ADR-0001-swarm-ownership-label-namespace.md`

## Preconditions
`M08-03` done. `M02-03` entregou as labels gerenciadas.

## Scope
- Capabilities atribuíveis a um Worker: `ingress`, `builder`, `workloads`, `system`.
- Aplicação reconciliada das labels correspondentes, no namespace do `ADR-0001`.
- Efeito real: ingress recebe Traefik (`M04-01`); builder entra no pool (`M05-07`); `workloads=false` exclui o node de workload de usuário.
- Fluxo de `M08` §15.2: enroll como worker → aplicar label de ingress → Traefik global cria a instância → validar TLS/config → adicionar target no LB (`M08-11`).
- Remoção de capability com verificação de impacto: retirar o último ingress ou o último builder é bloqueado ou avisado.

## Out of Scope
- Manager (`M08-05`).
- LB targets (`M08-10`, `M08-11`).
- Node pools dedicados por Team (Anexo C §9.1 Tier T1; exige decisão de produto).

## Application Layer
- **Commands:** `AssignNodeCapability`, `RemoveNodeCapability`.
- **Reconciler:** `NodeReconciler` aplicando labels; `IngressReconciler` e o scheduler de builds reagindo.

## Security Requirements
- **Separação de funções é isolamento** (Anexo C §9.1): builders executam código não confiável e não devem coexistir com ingress ou manager em produção.
- A plataforma **avisa** quando uma combinação de capabilities é insegura — por exemplo, builder junto de manager (doc 02 §7.1 proíbe builds em managers).
- Alterar capability é ação privilegiada e auditada.
- Remover a última capability de ingress derruba o tráfego: bloqueado ou com confirmação reforçada.

## Observability Requirements
Capabilities por node visíveis; efeito no placement observável. Contagem de ingress e builders saudáveis, consumida pelo readiness (`M08-12`).

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Builder em node manager | Bloqueado ou avisado com destaque; builds não devem rodar em managers. |
| Remoção do último ingress | Bloqueada ou com confirmação reforçada e aviso de perda de tráfego. |
| Remoção do último builder | Avisada; builds ficam na fila até haver capacidade. |
| Label removida fora da plataforma | Drift detectado e reaplicado (`M02-06`). |
| Capability aplicada em node `DEGRADED` | Aceita, mas sem efeito até o node ficar `READY`. |

## Acceptance Criteria
1. As capabilities `ingress`, `builder`, `workloads` e `system` são atribuíveis a Workers.
2. As labels correspondentes são aplicadas no namespace do `ADR-0001` e reconciliadas.
3. Marcar `ingress` faz o Traefik ser agendado no node, provado contra cluster real.
4. Marcar `builder` inclui o node no pool de builds.
5. `workloads=false` exclui o node de workload de usuário.
6. Builder em node manager é bloqueado ou avisado com destaque.
7. Remover a última capability de ingress é bloqueado ou exige confirmação reforçada com aviso de impacto.
8. Remover o último builder avisa que builds ficarão na fila.
9. Label removida fora da plataforma é detectada como drift e reaplicada.
10. Capability em node `DEGRADED` só tem efeito quando ele fica `READY`.
11. Alterar capability exige permissão e gera AuditLog; negativo cross-team passa.

## Required Tests
- **Docker/Swarm**: Traefik agendado após label de ingress; builder entrando no pool; `workloads=false` excluindo placement.
- **integration**: bloqueio de remoção do último ingress; drift de label reaplicado.
- **security**: aviso/bloqueio de builder em manager.
- **policy**: negativo cross-team; permissão.

## Quality Gates
Local Quality Gate + suíte Docker/Swarm.

## Definition of Done
Os 11 Acceptance Criteria satisfeitos, efeito real no placement provado, combinações inseguras sinalizadas, Critical/High = 0.
