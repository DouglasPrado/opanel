# M04-10 — Certificate distribution with acknowledgement before activation

## Objective
Distribuir a versão do certificado para os ingress nodes e só ativá-la depois que a política de confirmação for satisfeita — nunca por otimismo.

## Outcome
Uma nova `CertificateVersion` é materializada no file provider de cada ingress; cada node confirma; só então a versão vira `ACTIVE` e a anterior entra em grace period.

## References
- `docs/architecture/08-networking-domains-edge.md` §13.3 (distribuição), §14 (renovação e rotação), §25 (falhas toleradas)
- `docs/architecture/01-foundation.md` §8.2 (distribuição segura)
- `docs/annexes/B-nfr-slos.md` §8 (100% dos ingress saudáveis confirmam antes de ativar)

## Preconditions
`M04-09` done.

## Scope
- `CertificateDistributionReconciler`: garante que a versão correta esteja presente em todos os ingress nodes elegíveis.
- Materialização em diretório com permissões restritas e configuração dinâmica versionada, lida pelo file provider do Traefik.
- **ACK por node**: `CertificateDistribution` com `distributedAt` e `verifiedAt`.
- Ativação condicionada: a versão só vira `ACTIVE` quando a política de confirmação é satisfeita (todos os ingress saudáveis, conforme Anexo B §8).
- Grace period antes de remover a versão anterior.
- Reload do Traefik sem derrubar conexões existentes.

## Out of Scope
- Renovação agendada (`M04-11`).
- Multi-ingress real e quorum em cluster grande (`M08-11`) — a política é implementada aqui e exercida lá.
- Backup de certificados (`M10-07`).

## Application Layer
- **Reconciler:** `CertificateDistributionReconciler`.
- **Commands:** `DistributeCertificateVersion`, `ActivateCertificateVersion`.

## Async / Control Plane
A distribuição é reconciliação: desired (versão alvo em todos os ingress) × actual (o que cada node confirma). Retry por target, não por lote inteiro (doc 07 §15).

## Security Requirements
- A chave privada é decifrada **apenas** no distributor, em memória, e materializada somente nos ingress autorizados, em filesystem protegido (doc 08 §13.2).
- Permissões restritas no diretório de certificados do ingress; nenhum workload de usuário o alcança.
- Uma versão **não** é ativada sem confirmação — ativar antes significaria declarar um domínio seguro quando parte dos ingress ainda serve o certificado antigo ou nenhum.
- A versão anterior só é removida após a janela de segurança; remover cedo derruba handshakes em andamento.
- Nenhum log registra material do certificado.

## Observability Requirements
- Estado por ingress: distribuído, verificado, falho.
- Métrica: nodes com a versão ativa, tempo até quorum, falhas de distribuição.
- Falha em um de N ingress é visível como **degradação parcial**, não como sucesso.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Um ingress não confirma | A versão **não** é promovida globalmente (doc 08 §25). |
| Ingress volta depois | Reconciliação distribui e confirma; a ativação acontece então. |
| Reload do Traefik falha | Rollback para a versão anterior; a rota continua servindo. |
| Certificate Manager offline | Certificados já distribuídos continuam servindo; novas emissões aguardam. |
| Remoção prematura da versão anterior | Impedida pelo grace period. |
| Diretório com permissão frouxa | Detectado e corrigido; teste guarda a propriedade. |

## Acceptance Criteria
1. Uma nova versão é materializada em todos os ingress elegíveis, com permissões restritas.
2. Cada ingress confirma o recebimento; `CertificateDistribution` registra `distributedAt` e `verifiedAt`.
3. A versão só vira `ACTIVE` quando a política de confirmação é satisfeita, provado por teste com um ingress que não confirma.
4. A versão anterior entra em grace period e só é removida depois da janela.
5. O reload do Traefik não derruba conexões existentes.
6. Falha de reload provoca rollback para a versão anterior, sem interromper a rota.
7. Falha em um de N ingress aparece como degradação parcial, nunca como sucesso.
8. A chave privada é decifrada apenas no distributor e materializada apenas nos ingress autorizados.
9. O diretório de certificados tem permissões restritas e não é alcançável por workload de usuário.
10. Nenhum log contém material do certificado.
11. Certificate Manager offline não interrompe certificados já distribuídos.
12. Retry é por target, não por lote inteiro.

## Required Tests
- **unit**: política de ativação; grace period; retry por target.
- **integration**: ingress que não confirma bloqueando a ativação; rollback de reload.
- **Docker/Swarm**: distribuição real; reload sem queda de conexão; permissões do diretório.
- **security**: ausência de material em log; diretório inacessível ao workload.

## Quality Gates
Local Quality Gate + suíte Docker/Swarm + `bin/security`.

## Definition of Done
Os 12 Acceptance Criteria satisfeitos, ativação condicionada provada por caso negativo, reload sem downtime verificado, Critical/High = 0.
