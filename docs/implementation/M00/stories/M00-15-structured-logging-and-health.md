# M00-15 — Structured logging, correlation IDs and health endpoints

## Objective
Estabelecer a base de observabilidade que o Anexo I §19.2 exige de **toda** operação: log estruturado com identificadores de correlação e endpoints de health/readiness da própria plataforma.

## Outcome
Todo log é JSON estruturado com `request_id` e `correlation_id`; o ID gerado na borda HTTP atravessa até o job assíncrono; `GET /up` reporta o estado da aplicação, do banco e da fila.

## References
- `docs/annexes/I-engineering-playbook-quality-gates.md` §19.2 (observabilidade mínima por operação)
- `docs/architecture/09-data-model-apis-contracts.md` §19 (request/correlation id)
- `docs/annexes/C-threat-model-security-hardening.md` §17 (logs, métricas e audit), §17.1 (redaction)
- `docs/annexes/E-operational-runbooks.md` RB-01 (Control Plane indisponível)

## Preconditions
`M00-01` e `M00-03` done.

## Scope
- Logger estruturado JSON com campos obrigatórios: `timestamp` (UTC), `level`, `message`, `request_id`, `correlation_id`, `source`.
- Geração de `request_id` novo em cada boundary externo e propagação interna, incluindo para dentro do job assíncrono.
- Campos de correlação **reservados** para os Milestones seguintes, já previstos no contrato do logger: `operation_id`, `team_id`, `project_id`, `environment_id`, `service_id`, `cluster_id`, `node_id`, `actor_id`, `source`.
- **Camada de redaction** no sink de log: chaves e padrões conhecidos (authorization, cookie, password, token, private key) são mascarados antes de escrever.
- `GET /up`: health da aplicação, readiness do PostgreSQL e da fila, sem vazar versão, configuração ou detalhe interno.
- Erros retornados ao usuário não contêm stack trace, SQL, caminho interno nem material criptográfico.

## Out of Scope
- Métricas e backend de observabilidade (M09).
- Timeline de Operations (M02).
- Tracing distribuído (não é requisito da primeira fase, doc 03 §1.2).
- AuditLog (`M01-05`) — é outro sink, com outras regras.

## Observability Requirements
Esta Story **é** o requisito de observabilidade base. Contrato que ela fixa para o projeto inteiro: um erro operacional precisa ser diagnosticável a partir do log, sem reproduzir localmente. O `request_id` precisa aparecer também na resposta de erro ao usuário, para correlação em suporte (doc 09 §28).

## Security Requirements
- Redaction acontece **na origem e no sink**: quem conhece o segredo evita logá-lo, e o sink é a última barreira (Anexo C §17.1).
- `GET /up` é público o suficiente para health check de LB, mas não revela versão, hostname interno, string de conexão nem contagem de recursos.
- Nenhum header de autorização ou cookie é escrito em log.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| PostgreSQL indisponível | `/up` reporta readiness falsa com causa classificada; a aplicação não finge estar saudável (Anexo B §20). |
| Fila indisponível | `/up` reporta a degradação separadamente do banco. |
| Exceção não tratada | Resposta com `request_id` e mensagem segura; detalhe completo só no log do servidor. |
| Log com valor sensível | Redaction mascara; existe teste que planta o valor e verifica a máscara. |

## Acceptance Criteria
1. Todo log da aplicação é JSON com os campos obrigatórios preenchidos.
2. Um `request_id` gerado na borda HTTP aparece no log do controller **e** no log do job enfileirado por aquele request.
3. O contrato do logger aceita os campos de correlação reservados sem alteração de assinatura quando os Milestones seguintes os preencherem.
4. Um valor sensível plantado em um log é mascarado pelo sink, provado por teste.
5. Header de autorização e cookie nunca aparecem em log, provado por teste.
6. `GET /up` reporta aplicação, banco e fila, e distingue os três estados.
7. Com PostgreSQL fora, `/up` reporta readiness falsa com causa classificada em vez de timeout genérico.
8. `/up` não expõe versão, configuração, hostname interno nem string de conexão.
9. Uma resposta de erro ao usuário contém `request_id` e **não** contém stack trace, SQL ou caminho interno.

## Required Tests
- **unit**: formatação do logger; geração e propagação de correlation ID; redaction.
- **integration**: propagação request → job; `/up` com banco disponível e indisponível.
- **security**: valor sensível mascarado; header de autorização ausente do log; resposta de erro sem detalhe interno.

## Quality Gates
Local Quality Gate + AF-06 (secret não aparece em log) e AF-08 (identificadores de correlação) de `M00-13`.

## Definition of Done
Os 9 Acceptance Criteria satisfeitos, redaction provada por teste negativo, `/up` verificado nos dois estados, Critical/High = 0.
