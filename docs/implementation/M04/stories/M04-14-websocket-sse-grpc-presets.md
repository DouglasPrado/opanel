# M04-14 — WebSocket, SSE and gRPC edge compatibility presets

## Objective
Garantir que protocolos de longa duração e HTTP/2 atravessem o ingress corretamente, com timeouts compatíveis e sem buffering incompatível.

## Outcome
Uma aplicação com WebSocket ou SSE funciona através do ingress sem desconexões artificiais; um serviço gRPC funciona com HTTP/2 fim a fim quando configurado.

## References
- `docs/architecture/08-networking-domains-edge.md` §17 (WebSocket, SSE, streaming e gRPC)
- `docs/annexes/B-nfr-slos.md` §8 (WebSocket/SSE sem timeout arbitrário; gRPC HTTP/2 fim a fim)
- `docs/annexes/D-test-strategy.md` §9 (testes de WebSocket/SSE no edge)

## Preconditions
`M04-12` done.

## Scope
- Preset por `DomainBinding` declarando o perfil de protocolo: HTTP padrão, streaming (WebSocket/SSE) ou gRPC.
- Timeouts de idle e de leitura compatíveis com conexões longas, no ingress.
- Desabilitar buffering incompatível com streaming.
- HTTP/2 no edge e scheme/configuração de backend apropriados para gRPC.
- Documentação explícita dos limites: o timeout do Load Balancer externo (M08) também precisa ser compatível, e isso é responsabilidade do provider.

## Out of Scope
- gRPC-Web (opcional, sem requisito).
- TCP/UDP arbitrário (backlog, doc 08 §18 marca como advanced/experimental).
- Load Balancer externo (`M08-10`) — aqui apenas a documentação do requisito.

## Application Layer
- **Commands:** `UpdateBindingProtocolProfile`.
- **Reconciler:** `IngressReconciler` traduzindo o perfil em configuração do Traefik.

## Security Requirements
- Timeouts longos são um vetor de exaustão de recursos: o perfil de streaming vem com limite de conexões simultâneas por binding e com o mesmo backpressure de `M02-11`.
- Desabilitar buffering não pode desabilitar limites de tamanho nem validação de headers.
- O perfil é declarado por binding, nunca global — um serviço de streaming não relaxa a política dos demais.

## Observability Requirements
Métrica de conexões ativas de longa duração por binding e por ingress; taxa de desconexão. Sinal explícito quando conexões são cortadas por timeout do edge.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| WebSocket desconectando periodicamente | Diagnóstico aponta o timeout do edge ou do LB, com o valor configurado. |
| SSE com buffering | Perfil de streaming desabilita o buffering incompatível. |
| gRPC sem HTTP/2 no backend | Erro claro de protocolo, não 502 genérico. |
| Muitas conexões longas | Limite por binding aplicado; backpressure em vez de esgotar o ingress. |
| Rolling update durante conexão longa | Comportamento documentado: conexões existentes são drenadas conforme a política; o usuário sabe o que esperar. |

## Acceptance Criteria
1. O perfil de protocolo é declarado por `DomainBinding`, não globalmente.
2. WebSocket atravessa o ingress e permanece conectado além do timeout padrão de HTTP, provado por teste.
3. SSE funciona sem buffering incompatível, provado por teste.
4. gRPC funciona com HTTP/2 fim a fim quando configurado.
5. gRPC sem HTTP/2 no backend produz erro de protocolo claro, não 502 genérico.
6. O limite de conexões simultâneas por binding é aplicado no perfil de streaming.
7. Desabilitar buffering **não** desabilita limite de tamanho nem validação de headers.
8. Métricas de conexões longas e de desconexão por timeout estão disponíveis.
9. O comportamento durante rolling update com conexões longas está documentado e é observável.
10. O requisito de timeout compatível no Load Balancer externo está documentado para `M08-10`.

## Required Tests
- **unit**: tradução do perfil em configuração.
- **Docker/Swarm/E2E**: WebSocket de longa duração; SSE contínuo; gRPC HTTP/2; conexão durante rolling update.
- **security**: limite de conexões; validação de headers preservada com buffering desabilitado.

## Quality Gates
Local Quality Gate + suíte Docker/Swarm + testes de realtime do Anexo D §12.

## Definition of Done
Os 10 Acceptance Criteria satisfeitos, WebSocket e SSE provados através do ingress real, Critical/High = 0.
