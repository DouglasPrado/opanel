# M04-13 — Edge health reconciler and layered diagnostics

## Objective
Permitir localizar a camada exata onde o tráfego quebra — DNS, LB, TLS, router, backend ou Task — em vez de apresentar todo problema como um 502 genérico.

## Outcome
A tela de diagnóstico executa checks independentes e mostra o **primeiro ponto quebrado**, com o que observou e o que esperava.

## References
- `docs/architecture/08-networking-domains-edge.md` §23 (observabilidade de edge), §29.3 (diagnostics), §24 (estados derivados), §25 (falhas toleradas)
- `docs/architecture/10-ui-use-cases.md` §14.3 (Domain detail)
- `docs/annexes/E-operational-runbooks.md` RB-09, RB-11, RB-12

## Preconditions
`M04-06` e `M04-10` done.

## Scope
- `EdgeHealthReconciler`: probes de LB/entrada, Traefik, router aplicado, backend alcançável e Task saudável.
- Estados derivados de Domain e Ingress do doc 08 §24, calculados a partir de checks reais.
- Tela de diagnóstico executando, em ordem: resolução DNS → conectividade com o endpoint → TLS/SNI → router encontrado → backend service → Task health → resposta do origin.
- Cada check reporta observado × esperado.
- Sinais do doc 08 §23 coletados: requests, latência, conexões, handshakes/erros TLS, health de target, 5xx de origem, expiração de certificado, estado de verificação de DNS.

## Out of Scope
- Backend de métricas e retenção histórica (`M09-03`).
- Alertas formais (`M09-08`).
- Probe externa ao cluster (`M09`).

## Application Layer
- **Reconciler:** `EdgeHealthReconciler`.
- **Queries:** `DomainDiagnostics`, `EdgeOverview`.

## Async / Control Plane
Os estados de Domain e de Ingress são **derivados de probes reais**, nunca de uma coluna escrita pela API (doc 08 §24). Um domínio “ativo” no banco sem probe recente é apresentado como dado velho.

## UI Impact
Tela de Domain com routing, DNS, TLS, ingress e ações. Tela de diagnóstico mostrando a cadeia com o primeiro elo quebrado destacado. Tela de Cluster Edge com endpoint público, LB, gateways, certificados e domínios.

## Security Requirements
- O diagnóstico **não** vaza informação de outro Team: um hostname de outro tenant não revela detalhes.
- Os probes internos não se tornam um mecanismo de requisição arbitrária: os alvos são derivados do desired state, nunca fornecidos livremente pelo usuário (evita SSRF via diagnóstico).
- A resposta do origin exibida é truncada e sanitizada; ela é **dado não confiável** e nunca é renderizada como HTML ativo.
- O diagnóstico não expõe IPs internos nem topologia a quem não tem permissão de infraestrutura.

## Observability Requirements
- Cada check com resultado, observado, esperado e timestamp.
- Métrica por camada, para distinguir degradação de edge de degradação de aplicação.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| DNS não aponta para o endpoint esperado | Mostrar registro esperado × observado. |
| TLS falha | Identificar handshake/SNI/certificado, não “erro de rede”. |
| Router não encontrado | Apontar o binding e o estado da reconciliação. |
| Backend com porta errada | Diagnóstico de conexão ao origin, com a porta configurada e a observada. |
| Task unhealthy | Apontar o Service e o health, não o edge. |
| Probe falha por indisponibilidade do próprio checker | Estado indisponível com causa; nunca reportar “ok” por ausência de erro. |

## Acceptance Criteria
1. Os estados de Domain e Ingress são derivados de probes reais, não de colunas escritas pela API.
2. A tela de diagnóstico executa a cadeia completa e destaca o **primeiro** elo quebrado.
3. Cada check reporta observado × esperado.
4. Um 502 nunca é apresentado como “aplicação offline” sem verificar backend e Task.
5. Porta de backend errada é diagnosticada como conexão ao origin, com a porta configurada e a observada.
6. Um domínio sem probe recente é apresentado como dado velho, não como ativo.
7. O diagnóstico não revela informação de recurso de outro Team.
8. Os alvos dos probes vêm do desired state, nunca de entrada livre do usuário.
9. A resposta do origin exibida é truncada, sanitizada e nunca renderizada como HTML ativo.
10. Falha do próprio checker resulta em estado indisponível com causa, nunca em “ok”.
11. Os sinais de edge do doc 08 §23 são coletados e consultáveis.

## Required Tests
- **unit**: ordenação da cadeia de checks; derivação de estado; detecção de dado velho.
- **integration**: cada camada quebrada isoladamente produzindo o diagnóstico correto.
- **Docker/Swarm/E2E**: porta errada; Task unhealthy; router ausente; TLS inválido.
- **security**: ausência de vazamento cross-team; alvos não controlados pelo usuário; sanitização da resposta do origin.

## Quality Gates
Local Quality Gate + suíte Docker/Swarm + `bin/security`.

## Definition of Done
Os 11 Acceptance Criteria satisfeitos, cada camada testada isoladamente, ausência de SSRF via diagnóstico, Critical/High = 0.
