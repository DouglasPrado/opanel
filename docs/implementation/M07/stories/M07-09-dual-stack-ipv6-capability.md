# M07-09 — IPv4/IPv6 as a detected capability

## Objective
Tratar IPv6 como **capability detectada** do cluster e do provider, nunca como suposição — e jamais anunciar AAAA antes de o caminho funcionar de ponta a ponta.

## Outcome
A plataforma detecta se o caminho IPv6 funciona; só então oferece dual-stack e publica AAAA.

## References
- `docs/architecture/08-networking-domains-edge.md` §20 (IPv4 e IPv6), regra: “não anunciar AAAA antes de o caminho IPv6 estar funcional ponta a ponta”
- `docs/architecture/06-infrastructure-provisioning.md` §5 (endereçamento)

## Preconditions
M04 aceito.

## Scope
- Detecção de capability IPv6 por cluster e por provider de LB: endereço público, rede dos nodes, configuração do Docker/host.
- Modos do doc 08 §20: `IPv4 only`, `Dual-stack`, `IPv6 only`.
- Publicação de AAAA **apenas** quando a capability é confirmada por probe real.
- Health check em ambas as famílias quando dual-stack está ativo.
- Estado explícito na UI: “IPv6 não disponível neste cluster” em vez de silêncio.

## Out of Scope
- IPv6 interno da overlay do Swarm — depende de configuração do Docker; fora do escopo do produto agora.
- Migração de IPv4 para IPv6-only.

## Application Layer
- **Queries:** `ClusterNetworkCapabilities`.
- **Reconciler:** `DnsReconciler` respeitando a capability ao criar registros.

## Security Requirements
- Um AAAA quebrado causa **falhas intermitentes difíceis de diagnosticar** em clientes que preferem IPv6 (doc 08 §20). Publicar sem verificar é criar um incidente silencioso.
- A detecção usa probe real, não configuração declarada.
- Quando dual-stack está ativo, o health check cobre as **duas** famílias; considerar saudável testando só uma é um falso positivo.
- Políticas de edge (allowlist, rate limit) precisam funcionar corretamente com endereços IPv6 — a validação de formato aceita ambos.

## Observability Requirements
Capability por cluster com o resultado do probe e a data. Métrica de tráfego por família quando disponível.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Provider anuncia IPv6 mas o caminho não funciona | Probe detecta; AAAA **não** é publicado. |
| Dual-stack com uma família degradada | Health reflete a degradação por família; não declarar saudável globalmente. |
| Allowlist com CIDR IPv6 | Aceito e aplicado corretamente. |
| Cluster sem IPv6 | Estado explícito na UI; o domínio funciona em IPv4. |
| AAAA preexistente do cliente | Detectado e reportado; a plataforma não o remove (`M07-03`). |

## Acceptance Criteria
1. A capability IPv6 é **detectada por probe real**, não por configuração declarada.
2. AAAA só é publicado quando a capability é confirmada, provado por teste com caminho quebrado.
3. Os três modos (`IPv4 only`, `Dual-stack`, `IPv6 only`) são representáveis.
4. `IPv6 only` só é aceito quando **todos** os componentes críticos suportam o caminho completo.
5. Com dual-stack, o health check cobre as duas famílias.
6. Uma família degradada é refletida no health; não se declara saudável globalmente.
7. Políticas de edge aceitam e aplicam CIDR IPv6 corretamente.
8. Cluster sem IPv6 mostra o estado explicitamente na UI.
9. AAAA preexistente do cliente é detectado e reportado, não removido.
10. A capability é registrada com o resultado do probe e a data.

## Required Tests
- **unit**: representação dos modos; validação de CIDR IPv6.
- **integration**: capability detectada; AAAA não publicado com caminho quebrado.
- **Docker/Swarm**: health nas duas famílias quando disponível no laboratório.
- **security**: allowlist com IPv6 funcionando.

## Quality Gates
Local Quality Gate + suíte Docker/Swarm.

## Definition of Done
Os 10 Acceptance Criteria satisfeitos, regra de não anunciar AAAA sem caminho funcional provada, Critical/High = 0.
