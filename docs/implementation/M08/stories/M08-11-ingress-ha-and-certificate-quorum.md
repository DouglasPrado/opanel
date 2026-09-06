# M08-11 — Ingress HA and certificate distribution quorum

## Objective
Tornar a entrada pública realmente redundante: múltiplos gateways atrás do LB, com certificados distribuídos e **confirmados** por todos antes de qualquer ativação.

## Outcome
Com três ingress, derrubar um mantém o tráfego; uma nova versão de certificado só vira `ACTIVE` quando todos os ingress saudáveis confirmam.

## References
- `docs/architecture/01-foundation.md` §6 (ingress HA com múltiplos Traefiks), §12 (o que significa HA real)
- `docs/architecture/08-networking-domains-edge.md` §7, §13.3 (distribuição), §25 (falhas toleradas)
- `docs/annexes/B-nfr-slos.md` §8 (100% dos ingress saudáveis confirmam antes de ativar)
- `docs/architecture/06-infrastructure-provisioning.md` §15.2 (aumentar ingress)

## Preconditions
`M08-10` done. `M04-10` entregou o mecanismo de distribuição com ACK.

## Scope
- Múltiplos ingress nodes com Traefik global, targets sincronizados no LB.
- **Quorum real de distribuição**: agora com N > 1, a política de `M04-10` passa a ter efeito prático.
- Health check de ingress consumido pelo LB; target unhealthy é retirado.
- Fluxo completo de adicionar ingress: enroll → label → Traefik cria a instância → validar TLS/config → `addTarget`.
- Remoção de ingress: `removeTarget` → drain → encerrar.
- Comportamento sob falha: um Traefik cai e os demais continuam servindo o mesmo domínio.

## Out of Scope
- Chaos de ingress sob carga (`M13-10`).
- CDN/WAF upstream (backlog).
- Anycast/multi-region (backlog).

## Application Layer
- **Reconciler:** `CertificateDistributionReconciler` com quorum real; `LoadBalancerReconciler`.

## Security Requirements
- **Uma versão de certificado não é ativada sem confirmação de todos os ingress saudáveis** (Anexo B §8). Ativar antes significaria declarar o domínio seguro enquanto parte dos gateways serve o certificado antigo — ou nenhum.
- Cada ingress recebe apenas os certificados dos domínios que serve; a chave privada é materializada em filesystem protegido (doc 08 §13.2).
- Um ingress `DEGRADED` é retirado do LB antes de virar fonte de erro para o usuário.
- Adicionar um ingress não pode expor um gateway ainda não configurado ao tráfego: o target só entra depois da validação.

## Observability Requirements
Por ingress: health, versão de certificado ativa, requisições, erros de TLS. Divergência de versão entre gateways visível — é o sinal de distribuição incompleta.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Um Traefik cai | LB remove o target; os demais continuam servindo. |
| Um ingress não confirma o certificado | A versão **não** é promovida globalmente. |
| Ingress volta depois | Reconciliação distribui e confirma; a ativação acontece então. |
| Gateway servindo versão antiga | Divergência visível; a distribuição é reconciliada. |
| Todos os ingress caem | Incidente de indisponibilidade; a plataforma reporta o edge como indisponível, sem mascarar. |
| Adicionar ingress mal configurado | Não entra no LB até validar. |

## Acceptance Criteria
1. Múltiplos ingress nodes servem o mesmo domínio simultaneamente.
2. Derrubar um ingress sob tráfego mantém o serviço pelos demais, provado por teste.
3. O LB retira automaticamente o target unhealthy.
4. Uma nova versão de certificado **não** é ativada enquanto um ingress saudável não confirmar, provado por teste.
5. Ingress que volta recebe a versão e confirma; a ativação acontece então.
6. Divergência de versão entre gateways é visível.
7. Adicionar ingress segue a ordem: enroll → label → instância criada → validar → `addTarget`.
8. Remover ingress segue a ordem: `removeTarget` → drain → encerrar.
9. Cada ingress recebe apenas os certificados dos domínios que serve.
10. A chave privada é materializada em filesystem protegido, inacessível a workload de usuário.
11. Todos os ingress caindo é reportado como indisponibilidade do edge, sem mascarar.
12. Métricas por ingress (health, versão ativa, erros de TLS) estão disponíveis.

## Required Tests
- **Docker/Swarm**: três ingress servindo; kill de um sob tráfego; ingress que não confirma bloqueando a ativação; ingress voltando.
- **integration**: ordem de adicionar e remover; divergência de versão.
- **security**: certificados limitados aos domínios servidos; filesystem protegido.

## Quality Gates
Local Quality Gate + suíte Docker/Swarm + `bin/security`.

## Definition of Done
Os 12 Acceptance Criteria satisfeitos, kill de ingress sob tráfego provado, quorum de certificado verificado com N > 1, Critical/High = 0.
