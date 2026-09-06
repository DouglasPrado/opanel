# M13-08 — Edge load testing, separate from application capacity

## Objective

Medir a capacidade do Traefik e do caminho de ingress **como camada da plataforma**, sem confundir o limite do edge com o limite das aplicações servidas por ele.

## Outcome

Números que respondem “o edge aguenta?” separadamente de “a aplicação aguenta?”, permitindo diagnosticar saturação no lugar certo.

## References

- `docs/architecture/08-networking-domains-edge.md`
- `docs/annexes/B-nfr-slos.md` §8, §17
- `docs/annexes/D-test-strategy.md` §9, §13

## Preconditions

- `M13-06` concluída; ingress redundante de M08 disponível.

## Scope

- Backend de referência **trivial e constante** (eco), para que a variável medida seja o edge.
- Perfis: muitas rotas com pouco tráfego; poucas rotas com muito tráfego; muitas conexões TLS novas; keep-alive sustentado; requisições grandes; WebSocket/streaming.
- Medição de: latência adicionada pelo edge, throughput, handshakes TLS por segundo, uso de CPU/memória do Traefik e tempo de recarga de configuração sob carga.
- Escala de rotas: tempo de propagação de uma rota nova com N rotas já existentes.
- Comportamento com um ingress fora do ar durante a carga (redundância sob estresse).
- Separação explícita no relatório entre latência do edge e latência do backend.

## Out of Scope

- Otimização do Traefik: se o limite for insuficiente, vira finding e Story própria.

## Security Requirements

- Certificados de laboratório; nenhum certificado de produção.
- Rate limits do edge são exercitados em `M13-11`, não relaxados aqui.

## Observability Requirements

- Relatório separa claramente as duas latências e nomeia o componente saturado.
- Comparação com a baseline de `M13-06`.

## Failure Scenarios

| Cenário | Comportamento esperado |
|---|---|
| Latência do edge indistinguível da do backend | Teste inválido; refazer com backend trivial. |
| Recarga de config causa queda de requisições | Finding **High**. |
| Propagação de rota degrada além do alvo com N rotas | Finding **High**. |
| Queda de um ingress causa indisponibilidade global | Finding **Critical**. |

## Acceptance Criteria

1. O backend de referência é trivial, garantindo que a medição isole o edge.
2. Todos os perfis listados são executados.
3. A latência adicionada pelo edge é reportada separadamente da do backend.
4. Handshakes TLS por segundo e uso de recurso do Traefik são medidos.
5. O tempo de propagação de rota é medido com escala de rotas crescente.
6. A recarga de configuração sob carga não derruba requisições em curso.
7. A perda de um ingress durante a carga não causa indisponibilidade global.
8. O resultado é comparado com a baseline e respeita a margem de regressão.

## Required Tests

- Testes de carga do edge com o harness.
- Teste de recarga de configuração sob carga.

## Quality Gates

Local Quality Gate; comparação contra baseline.

## Definition of Done

- [ ] 8 Acceptance Criteria com evidência.
- [ ] Capacidade do edge documentada separadamente.
- [ ] Self-review; `tasks.json` atualizado com commit.
