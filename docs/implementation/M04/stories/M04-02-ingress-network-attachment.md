# M04-02 — Reconciled ingress network attachment

## Objective
Conectar o Traefik às overlays dos Environments que possuem Services publicados, mantendo a conectividade no mínimo necessário e reagindo a mudanças por reconciliação.

## Outcome
Quando um Service passa a ter domínio, o Traefik é anexado à overlay daquele Environment; quando o último domínio some, o attachment é removido.

## References
- `docs/architecture/08-networking-domains-edge.md` §4.2 (rede compartilhada de ingress), §27 (reconcilers)
- `docs/architecture/01-foundation.md` §5.3 (isolamento entre environments)

## Preconditions
`M04-01` done.

## Scope
- Cálculo do conjunto de overlays necessárias a partir dos `DomainBinding` ativos.
- Attachment e detachment reconciliados do Traefik às overlays.
- Preferência do doc 08 §4.2: conectar o Traefik diretamente às overlays dos Services públicos, evitando publicar portas internas.
- Detecção e correção de attachment perdido (drift de rede).
- Limite explícito: **somente** overlays com Service publicado; nunca “conectar a tudo”.

## Out of Scope
- Rotas e labels (`M04-05`).
- Criação das overlays (`M01-17`).
- IPAM e CIDR previsível.

## Application Layer
- **Reconciler:** parte do `IngressReconciler` responsável por network attachment.

## Async / Control Plane
Alterar o conjunto de redes do Traefik recria suas Tasks. A reconciliação precisa evitar churn: recalcular apenas quando o conjunto efetivamente muda, e aplicar em lote.

## Security Requirements
- **Conectividade mínima** (doc 08 §4.2): o Traefik só alcança as overlays que precisa. Conectar a todas seria eliminar o isolamento entre Environments pela porta dos fundos.
- Um Environment sem Service publicado **não** é alcançável pelo Traefik.
- Production e homologação continuam sem rota cruzada: o Traefik alcança as duas, mas os Services entre si não (Anexo C §14, “Prod acessando HML”).
- Attachment perdido é drift e é reaplicado (doc 08 §25).

## Observability Requirements
Log do conjunto de redes aplicado e da razão da mudança. Métrica: número de attachments e frequência de recálculo.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Attachment perdido | Detectado como drift e reaplicado. |
| Muitas mudanças em sequência | Coalescing: recalcular e aplicar em lote, evitando churn de Tasks do Traefik. |
| Overlay removida com binding ativo | `BLOCKED` com diagnóstico; a ordem correta é remover o binding antes. |
| Attachment falha | Domínio fica `DEGRADED` com causa; rotas existentes continuam. |
| Environment sem Service publicado | Sem attachment; verificado por teste. |

## Acceptance Criteria
1. O Traefik é anexado às overlays dos Environments com `DomainBinding` ativo.
2. O attachment é removido quando o último binding daquele Environment some.
3. Um Environment **sem** Service publicado não é alcançável pelo Traefik, provado contra Swarm real.
4. Services de Environments diferentes continuam sem rota entre si.
5. Attachment perdido é detectado como drift e reaplicado.
6. Mudanças em sequência são coalescidas para evitar churn de Tasks do Traefik.
7. Remover uma overlay com binding ativo é `BLOCKED` com diagnóstico.
8. Falha de attachment deixa o domínio `DEGRADED` sem derrubar rotas existentes.
9. Nenhuma porta interna de aplicação é publicada como alternativa ao attachment.

## Required Tests
- **unit**: cálculo do conjunto de redes; coalescing.
- **Docker/Swarm**: attachment e detachment reais; drift de rede reaplicado; isolamento entre Environments preservado.
- **security**: Environment sem publicação inalcançável; ausência de porta publicada.

## Quality Gates
Local Quality Gate + suíte Docker/Swarm.

## Definition of Done
Os 9 Acceptance Criteria satisfeitos, conectividade mínima e isolamento provados contra Swarm real, Critical/High = 0.
