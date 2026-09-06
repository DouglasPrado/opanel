# M10-10 — Cluster configuration snapshot

## Objective
Capturar a configuração lógica do cluster necessária para reconstruí-lo, complementando o Environment Snapshot no caminho de Clean Rebuild.

## Outcome
Um `ClusterSnapshot` registra inventário de nodes, labels, ingress, configuração do Traefik administrada pela plataforma, versões de certificado ativas, networks e políticas.

## References
- `docs/architecture/05-backup-restore-dr.md` §9.2 (Cluster Configuration Snapshot), §18
- `docs/architecture/06-infrastructure-provisioning.md` §18 (modelo de dados)

## Preconditions
`M10-09` done.

## Scope
- `ClusterSnapshot`: clusterId, `configSpec`, `nodeInventory`, `certificateVersions`.
- Conteúdo do doc 05 §9.2: inventário e roles de nodes, labels e convenções de placement, configuração de ingress e targets do LB, configuração do Traefik administrada pela plataforma, versões de certificado ativas, definições de network e relações entre services, políticas e quotas do cluster.
- Snapshot automático antes de mudanças de topologia relevantes.
- Uso pelo Clean Rebuild (`M10-13`) como referência da topologia alvo.

## Out of Scope
- Estado Raft (`M10-08`) — é outro artefato, com outra natureza.
- Restore do cluster (`M10-13`, `M10-14`).
- Provisionamento dos hosts.

## Security Requirements
- O snapshot registra **configuração**, não credenciais: tokens de provider, join tokens e chaves ficam fora (eles vivem no Vault e são protegidos por `M10-06`).
- O inventário de nodes contém endereços internos: o acesso ao snapshot exige permissão de infraestrutura.
- Versões de certificado são **referenciadas**, não duplicadas — o material vem de `M10-07`.
- Criar snapshot gera AuditLog.

## Observability Requirements
Idade do último `ClusterSnapshot`; alerta quando está desatualizado em relação à topologia atual.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Mudança de topologia sem snapshot recente | Alerta; snapshot automático antes da mudança quando possível. |
| Node inalcançável durante a captura | Registrar o que foi observado e marcar a lacuna; não inventar. |
| Snapshot com credencial capturada por engano | Impossível por construção; teste guarda a propriedade. |
| Cluster degradado | Snapshot ainda é capturado, com o estado marcado. |
| Divergência com a realidade após o snapshot | Esperado: o snapshot é uma fotografia; a data está sempre visível. |

## Acceptance Criteria
1. `ClusterSnapshot` captura o conteúdo do doc 05 §9.2.
2. **Nenhuma credencial** é capturada — tokens e chaves ficam fora, provado com valor plantado.
3. Versões de certificado são referenciadas, não duplicadas.
4. Um snapshot automático é criado antes de mudanças de topologia relevantes.
5. Node inalcançável durante a captura produz lacuna **marcada**, não dado inventado.
6. Cluster degradado ainda é capturado, com o estado marcado.
7. A data do snapshot é sempre visível; divergência posterior é esperada e explicada.
8. O acesso ao snapshot exige permissão de infraestrutura.
9. Snapshot desatualizado em relação à topologia gera alerta.
10. Criar snapshot gera AuditLog; negativo cross-team passa.
11. O Clean Rebuild consome o snapshot como referência da topologia alvo.

## Required Tests
- **unit**: composição; detecção de lacuna.
- **integration**: snapshot automático antes de mudança; cluster degradado.
- **security**: ausência de credencial no snapshot; permissão de infraestrutura.
- **Docker/Swarm**: captura com node inalcançável.

## Quality Gates
Local Quality Gate + suíte Docker/Swarm + `bin/security`.

## Definition of Done
Os 11 Acceptance Criteria satisfeitos, ausência de credencial provada, lacunas marcadas, Critical/High = 0.
