# M08-09 — Network profile, port readiness and connectivity diagnostics

## Objective
Verificar que a rede entre os nodes atende aos requisitos do Swarm e diagnosticar problemas de conectividade antes que eles virem falhas inexplicáveis de aplicação.

## Outcome
A plataforma valida as portas do Swarm entre os nodes, o MTU e a reachability da overlay, e reporta o que está faltando com precisão.

## References
- `docs/architecture/06-infrastructure-provisioning.md` §4 (portas e firewall), §5 (rede privada e endereçamento), §14.1 (cluster readiness: overlay, MTU)
- `docs/architecture/08-networking-domains-edge.md` §3 (planos de rede), §22 (segurança de rede)
- `docs/annexes/E-operational-runbooks.md` RB-07 (overlay degradada)

## Preconditions
`M08-03` done.

## Scope
- `NetworkProfile`: clusterId, `advertiseCIDR`, `dataPathPort`, `overlayEncrypted` (intenção), versão da política de firewall.
- Verificação de reachability entre nodes nas portas do Swarm: 2377/TCP, 7946/TCP+UDP, 4789/UDP.
- Validação de MTU da overlay.
- Preferência por rede privada como advertise address quando o provider oferecer.
- Diagnóstico de conectividade com resultado por par de nodes.
- Registro da intenção de overlay encryption, com aviso de impacto em performance.

## Out of Scope
- Configuração automática de firewall no host — a plataforma **verifica** e orienta; alterar firewall do host é responsabilidade do operador.
- VPN/peering entre redes (backlog).
- IPAM próprio com CIDR previsível (doc 08 §5 marca como evolução).

## Application Layer
- **Queries:** `NetworkReadinessCheck`, `NodeConnectivityMatrix`.

## Security Requirements
- **4789/UDP é crítico**: VXLAN não autentica tráfego por si só. O firewall deve aceitar esse tráfego **apenas** de IPs/CIDRs do cluster (doc 06 §4.1, regra explícita). A verificação detecta e **alerta** quando a porta está exposta além do esperado.
- 2377/TCP e 7946 restritos à rede confiável.
- A plataforma nunca abre portas por conta própria; ela verifica e orienta.
- Rede privada preferida para o data path; o IP público serve para entrada pública e bootstrap, não como substituto de rede confiável (doc 06 §5.1).
- Overlay encryption é registrada como intenção com aviso de custo de performance; a decisão é do operador.

## Observability Requirements
Matriz de conectividade por par de nodes e por porta, com o resultado e a data do check. Estado de rede consumido pelo readiness (`M08-12`).

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Porta do Swarm bloqueada entre nodes | Reportada nominalmente, com o par de nodes e a porta. |
| 4789/UDP acessível fora do cluster | **Alerta de segurança** com destaque. |
| MTU incompatível | Detectado; a overlay pode “funcionar” e falhar em pacotes grandes — o diagnóstico evita a caça ao fantasma. |
| Advertise address em IP público quando há rede privada | Avisado. |
| Rede privada degradada | Cluster `DEGRADED`; evitar mudanças que dependam da overlay (doc 06 §21). |
| Check indisponível | Estado indisponível com causa; nunca “ok” por ausência de erro. |

## Acceptance Criteria
1. `NetworkProfile` existe com os campos do doc 06 §18.
2. A reachability das portas 2377/TCP, 7946/TCP+UDP e 4789/UDP é verificada entre os nodes.
3. Porta bloqueada é reportada nominalmente, com o par de nodes e a porta.
4. **4789/UDP acessível fora do cluster gera alerta de segurança com destaque.**
5. O MTU da overlay é validado e a incompatibilidade é detectada.
6. Advertise address em IP público quando há rede privada disponível gera aviso.
7. A plataforma **não** altera o firewall do host; ela verifica e orienta.
8. Rede privada degradada marca o cluster `DEGRADED` e evita mudanças dependentes da overlay.
9. A intenção de overlay encryption é registrada com aviso de impacto em performance.
10. A matriz de conectividade por par de nodes é consultável, com data do check.
11. Check indisponível resulta em estado indisponível com causa, nunca “ok”.

## Required Tests
- **Docker/Swarm**: reachability real entre nodes; porta bloqueada detectada; MTU incompatível.
- **security**: detecção de 4789/UDP exposto; ausência de alteração de firewall pela plataforma.
- **unit**: matriz de conectividade; derivação do estado de rede.

## Quality Gates
Local Quality Gate + suíte Docker/Swarm + `bin/security`.

## Definition of Done
Os 11 Acceptance Criteria satisfeitos, alerta de 4789 exposto provado, diagnóstico por par de nodes verificado, Critical/High = 0.
