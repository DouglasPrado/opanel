# M10-08 — Swarm Raft state backup for Fast Restore

## Objective
Capturar o estado do Swarm que permite recuperar o cluster existente rapidamente, tratando esse artefato como material altamente sensível.

## Outcome
O estado do manager é capturado periodicamente, cifrado e armazenado fora do cluster, habilitando o Fast Swarm Restore de `M10-14`.

## References
- `docs/architecture/05-backup-restore-dr.md` §7 (estado do Docker Swarm), §7.1 (dois modos), §7.2 (Fast Swarm Restore)
- `docs/annexes/B-nfr-slos.md` §11 (estado Swarm/Raft: RPO ≤ 15 min)
- `docs/annexes/E-operational-runbooks.md` RB-25
- `docs/annexes/C-threat-model-security-hardening.md` §8.1

## Preconditions
`M10-04` done. M08 recomendado (cluster real torna o teste significativo).

## Scope
- Captura do estado do Swarm a partir de um manager, de forma consistente.
- Cifra pelo envelope e envio ao destino externo.
- Registro da versão do Docker no manifesto — restaurar em versão incompatível não funciona (RB-25).
- Alerta quando o backup do estado do Swarm está antigo em relação a uma mudança de topologia (doc 05 §17.2).
- Documentação explícita: este artefato **complementa**, não substitui, o Clean Rebuild.

## Out of Scope
- Execução do Fast Restore (`M10-14`).
- Recuperação de quorum perdido (RB-06, operacional).
- `force-new-cluster` — operação de desastre, jamais automatizada.

## Security Requirements
- O estado Raft contém **configuração do cluster e material protegido relacionado a secrets do Swarm** (doc 05 §7.2, regra explícita). Ele é tratado como artefato de segurança de primeira ordem.
- **Sempre cifrado e nunca em storage público.**
- A unlock key, quando autolock estiver habilitado, **não** entra junto do backup — mesmo princípio da Recovery Key.
- O acesso ao artefato é restrito e auditado.
- A captura não pode expor o estado em disco não protegido durante o processo.

## Observability Requirements
Idade do último backup do estado do Swarm; alerta quando desatualizado após mudança de topologia. Versão do Docker registrada.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Captura durante mudança de membership | Adiar ou marcar como potencialmente inconsistente; nunca capturar estado ambíguo em silêncio. |
| Manager indisponível | `FAILED` com causa; tentar outro manager quando houver. |
| Versão de Docker incompatível no restore | Detectada pelo manifesto **antes** de tentar. |
| Backup antigo após mudança de topologia | Alerta. |
| Storage público detectado | Bloquear o envio. |
| Autolock habilitado sem unlock key disponível | Sinalizado: o restore não será possível sem ela. |

## Acceptance Criteria
1. O estado do Swarm é capturado a partir de um manager, de forma consistente.
2. O artefato é **sempre cifrado** e enviado ao destino externo.
3. Envio para storage público é **bloqueado**.
4. A versão do Docker é registrada no manifesto e a incompatibilidade é detectada antes de um restore.
5. A unlock key **não** entra junto do backup.
6. Autolock habilitado sem unlock key disponível é sinalizado como restore impossível.
7. Captura durante mudança de membership é adiada ou marcada como potencialmente inconsistente.
8. Manager indisponível resulta em `FAILED` com causa, tentando outro quando houver.
9. Backup antigo após mudança de topologia gera alerta.
10. O acesso ao artefato é restrito e auditado.
11. A documentação registra que este artefato complementa, não substitui, o Clean Rebuild.

## Required Tests
- **Docker/Swarm**: captura real; manager indisponível; mudança de membership durante a captura.
- **security**: artefato cifrado; bloqueio de storage público; unlock key ausente do backup; acesso restrito.
- **integration**: versão incompatível detectada; alerta de backup antigo.

## Quality Gates
Local Quality Gate + suíte Docker/Swarm + `bin/security`.

## Definition of Done
Os 11 Acceptance Criteria satisfeitos, artefato protegido e cifrado, incompatibilidade detectável, Critical/High = 0.
