# M07-08 — HTTP-01 fallback challenge

## Objective
Emitir certificado para domínios simples quando o cliente **não** delega DNS, sem abrir mão do modelo centralizado de Certificate Manager.

## Outcome
Um domínio sem automação de DNS obtém certificado por HTTP-01, com o challenge respondido de forma consistente por **qualquer** ingress que receba a requisição.

## References
- `docs/architecture/08-networking-domains-edge.md` §13.1 (HTTP-01 como fallback), §15
- `docs/architecture/01-foundation.md` §8.1 (preferência por DNS-01)
- `docs/annexes/D-test-strategy.md` §6.3 (Certificate/ACME contract)

## Preconditions
`M07-02` done. `M04-09` entregou o Certificate Manager.

## Scope
- Suporte a HTTP-01 quando não há `DnsProvider` para a zona.
- **Distribuição do token de challenge para todos os ingress**, para que qualquer um responda corretamente — o mesmo problema que o DNS-01 evita (doc 08 §13.1).
- Pré-condição: o domínio precisa resolver para o endpoint e a rota HTTP precisa existir.
- Limitação explícita: HTTP-01 **não** emite wildcard.
- Escolha automática da estratégia: DNS-01 quando há provider; HTTP-01 como fallback; com override manual.

## Out of Scope
- Wildcard (exige DNS-01, `M07-10`).
- TLS-ALPN-01 — sem requisito.
- Substituir DNS-01 como preferência.

## Application Layer
- **Commands:** parte de `IssueCertificateForDomain`, com seleção de estratégia.

## Security Requirements
- O token de challenge é servido apenas no caminho específico do ACME e **apenas** enquanto a ordem está ativa; expirada, o caminho deixa de responder.
- O caminho de challenge **não** é um caminho arbitrário controlável pelo usuário: ele é fixo e gerenciado pela plataforma.
- A posse na plataforma continua sendo provada por `M07-06`; o HTTP-01 prova controle para a **CA**, não substitui a verificação interna.
- A distribuição do token para os ingress reutiliza o mecanismo protegido de `M04-10`.
- HTTP-01 exige porta 80 acessível — a implicação de segurança (redirect e exposição) é documentada.

## Observability Requirements
Estratégia de challenge escolhida registrada com o certificado. Métrica de emissões por estratégia e por resultado.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Ingress que recebeu a requisição sem o token | Impossível: o token é distribuído para todos antes de finalizar a ordem. |
| Domínio não resolve | HTTP-01 não é tentado; o estado permanece em `PENDING_DNS`. |
| Rota HTTP inexistente | Bloquear a tentativa com causa. |
| Pedido de wildcard com HTTP-01 | Rejeitado com a explicação de que exige DNS-01. |
| Redirect HTTP→HTTPS interferindo | O caminho de challenge é excluído do redirect enquanto a ordem está ativa. |
| Ordem expira | Token removido; nova tentativa com backoff. |

## Acceptance Criteria
1. HTTP-01 é usado como fallback quando não há `DnsProvider` para a zona.
2. O token é distribuído para **todos** os ingress antes de finalizar a ordem, provado por teste com múltiplos gateways.
3. O caminho de challenge é fixo e gerenciado pela plataforma; não é controlável pelo usuário.
4. O caminho de challenge é excluído do redirect HTTP→HTTPS enquanto a ordem está ativa.
5. Expirada a ordem, o caminho deixa de responder e o token é removido.
6. Pedido de wildcard com HTTP-01 é rejeitado com a explicação correta.
7. Domínio que não resolve não tenta HTTP-01.
8. Rota HTTP inexistente bloqueia a tentativa com causa.
9. A escolha automática prefere DNS-01 quando há provider, com override manual disponível.
10. A verificação de posse de `M07-06` continua sendo pré-condição independente.
11. A estratégia usada é registrada com o certificado.

## Required Tests
- **contract**: ordem HTTP-01 contra CA de staging.
- **Docker/Swarm**: challenge respondido por ingress diferentes; exclusão do redirect; token removido após expirar.
- **unit**: seleção de estratégia; rejeição de wildcard.
- **security**: caminho de challenge não controlável; posse ainda exigida.

## Quality Gates
Local Quality Gate + contract tests + suíte Docker/Swarm.

## Definition of Done
Os 11 Acceptance Criteria satisfeitos, challenge consistente entre ingress provado, Critical/High = 0.
