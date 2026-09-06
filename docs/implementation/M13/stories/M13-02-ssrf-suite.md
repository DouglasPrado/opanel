# M13-02 — SSRF suite across every URL-accepting feature

## Objective

Provar que nenhuma feature que busca uma URL fornecida pelo usuário pode ser usada como ponte para a Docker API, para o metadata do cloud provider ou para serviços internos.

## Outcome

Um inventário vivo das features que aceitam URL, cada uma exercitada contra o mesmo corpus de alvos proibidos.

## References

- `docs/annexes/C-threat-model-security-hardening.md` §6 (T09), §13.1, §21
- `docs/annexes/D-test-strategy.md` §17
- `docs/architecture/06-infrastructure-provisioning.md` — registries, DNS e LB providers
- `docs/architecture/08-networking-domains-edge.md` — webhooks e integrações de borda

## Preconditions

- Guarda de SSRF implementada nas Stories de origem (M03, M05, M06, M07, M09, M11, M12).

## Scope

- **Inventário derivado** das features que aceitam URL: webhook de saída, health check externo, registry customizado, provider de DNS, notificação de alerta, importação de manifesto, avatar remoto e qualquer outra descoberta pelo scanner.
- Corpus de alvos proibidos: `127.0.0.0/8`, `::1`, `169.254.169.254`, `fd00::/8`, `10/8`, `172.16/12`, `192.168/16`, `.local`, socket unix e esquemas inesperados (`file:`, `gopher:`, `dict:`).
- DNS rebinding: hostname que resolve para IP público na validação e para IP privado na conexão.
- Redirect: cada redirect é uma **nova decisão de política**; cadeia com salto para alvo proibido é bloqueada.
- Casos de bypass conhecidos: IP decimal, octal, IPv6 mapeado, credenciais no host, unicode.
- Verificação de que a validação ocorre sobre o **IP final conectado**, não apenas sobre a string.

## Out of Scope

- Features que só aceitam URL de uma allowlist fechada e não configurável — documentadas como fora do corpus, com justificativa.

## Security Requirements

- Um bloqueio jamais retorna o corpo da resposta interna nem o tempo de resposta que permita inferência.
- Toda tentativa bloqueada é auditada com o alvo normalizado.
- A suíte falha se uma feature nova que aceita URL não estiver no inventário.

## Observability Requirements

- Relatório: features cobertas, alvos testados, bloqueios e qualquer sucesso indevido.
- Métrica de tentativas bloqueadas por feature, sem cardinalidade por URL.

## Failure Scenarios

| Cenário | Comportamento esperado |
|---|---|
| Metadata endpoint alcançado | Finding **Critical**; release bloqueado. |
| Redirect para alvo privado seguido | Finding **Critical**. |
| DNS rebinding bem-sucedido | Finding **Critical**. |
| Feature nova fora do inventário | Suíte falha. |
| Erro que revela conteúdo interno | Finding **High**. |

## Acceptance Criteria

1. O inventário é derivado do código; feature nova não coberta faz a suíte falhar.
2. Todos os alvos do corpus são bloqueados em todas as features.
3. Redirects são reavaliados a cada salto.
4. DNS rebinding é bloqueado pela validação do IP final.
5. Bypasses de notação (decimal, octal, IPv6 mapeado) são bloqueados.
6. Esquemas inesperados são rejeitados.
7. Bloqueios não vazam conteúdo nem timing explorável.
8. Toda tentativa bloqueada é auditada.
9. A suíte é gate bloqueante em CI.

## Required Tests

- Integration com servidor de teste que redireciona e com resolvedor DNS controlado.
- Meta-teste de completude do inventário.

## Quality Gates

Local Quality Gate; security checks aplicáveis.

## Definition of Done

- [ ] 9 Acceptance Criteria com evidência.
- [ ] Nenhum alvo proibido alcançado.
- [ ] Self-review; `tasks.json` atualizado com commit.
