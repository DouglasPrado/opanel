# M04-05 — Ingress Reconciler: bindings into Traefik routers and services

## Objective
Traduzir `DomainBinding` em labels do Swarm Service que o Traefik lê, mantendo o roteamento convergente por reconciliação.

## Outcome
Criar um binding faz o Service receber labels de router/service do Traefik; remover o binding remove as labels; drift de label é corrigido.

## References
- `docs/architecture/08-networking-domains-edge.md` §9 (modelo de roteamento do Traefik), §5 (naming de router/service), §27 (reconcilers)
- `docs/architecture/07-internal-control-plane.md` §11 (reconcilers)

## Preconditions
`M04-02` e `M04-04` done.

## Scope
- `IngressReconciler` traduzindo bindings em labels: `traefik.enable`, regra `Host(...)`, entrypoint, `tls`, service e `loadbalancer.server.port`.
- Nomes de router e de service do Traefik derivados de IDs (doc 08 §5), não de nomes humanos.
- **Porta explícita obrigatória**: o Swarm provider do Traefik não infere a porta interna, e a spec exige informá-la (doc 08 §7).
- Reconciliação: adicionar, atualizar e remover labels conforme o desired state; drift corrigido.
- Ordem: o router só fica ativo quando o backend é alcançável e — quando `tlsMode` exige — o certificado está `ACTIVE`.

## Out of Scope
- Emissão de certificado (`M04-09`) — aqui só o consumo do estado.
- Middlewares e políticas (`M04-12`, `M07-07`).
- Path routing.

## Application Layer
- **Reconciler:** `IngressReconciler`.
- **Executor:** `UpdateServiceSpec` com as labels.

## Async / Control Plane
Alterar labels de roteamento é `UPDATE_SAFE` sempre que possível — o objetivo é **não** recriar Tasks só para publicar um domínio. Quando o Swarm exigir rollout, a Story documenta e a UI avisa.

## Security Requirements
- Um Service só recebe labels de roteamento quando existe um `DomainBinding` autorizado; ninguém publica um serviço por engano.
- A regra `Host()` usa o hostname **normalizado** de `M04-04`; nenhum valor não sanitizado entra na expressão de roteamento.
- Nenhuma porta é publicada no host como alternativa.
- Remover o binding remove a rota imediatamente; o teste comprova que o hostname deixa de responder.
- Labels de roteamento não carregam valor sensível.

## Observability Requirements
Log da diferença de labels aplicada, com `domain_binding_id` e `service_id`. Estado do binding refletindo router aplicado ou não.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Porta de backend errada | Router fica `DEGRADED`/`FAILED` com diagnóstico explícito de conexão ao origin — não um 502 genérico (doc 08 §25). |
| Label removida manualmente | Drift detectado e reaplicado. |
| Dois bindings para o mesmo hostname | Impossível pela unicidade de `M04-04`. |
| Certificado ainda não ativo com `tlsMode` obrigatório | Router não é ativado; estado `PENDING_CERT`. |
| Update de labels falha | Binding `DEGRADED` com retry; rotas existentes preservadas. |

## Acceptance Criteria
1. Criar um binding faz o Service receber as labels corretas de router e service do Traefik.
2. A porta de backend é sempre explícita nas labels.
3. Os nomes de router e service são derivados de IDs, não de nomes humanos.
4. Remover o binding remove as labels e o hostname deixa de responder, provado contra runtime real.
5. Label de roteamento removida manualmente é detectada como drift e reaplicada.
6. O router só é ativado quando o backend é alcançável e, com TLS obrigatório, o certificado está `ACTIVE`.
7. Porta de backend errada produz diagnóstico de conexão ao origin, não 502 genérico.
8. O hostname usado na regra é o normalizado; nenhum valor não sanitizado entra na expressão.
9. Publicar um domínio não recria Tasks quando o Swarm permite `UPDATE_SAFE`.
10. Nenhuma porta é publicada no host como alternativa ao ingress.

## Required Tests
- **unit**: geração de labels; naming por IDs; sanitização do hostname na regra.
- **Docker/Swarm**: request real chegando ao Service; remoção do binding derrubando a rota; drift de label reaplicado; porta errada com diagnóstico.
- **security**: ausência de porta publicada; hostname sanitizado.

## Quality Gates
Local Quality Gate + suíte Docker/Swarm.

## Definition of Done
Os 10 Acceptance Criteria satisfeitos com request real atravessando o ingress, drift de label corrigido, Critical/High = 0.
