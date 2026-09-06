# M04-12 — Edge policies: HTTPS redirect, TLS baseline, forwarded headers and trusted proxies

## Objective
Aplicar as políticas de borda seguras por padrão, sem expor toda a sintaxe do Traefik na UI e sem impor política própria às aplicações dos usuários.

## Outcome
HTTP redireciona para HTTPS; o TLS mínimo é aplicado; `X-Forwarded-*` só é aceito de proxies conhecidos; presets seguros substituem configuração manual.

## References
- `docs/architecture/08-networking-domains-edge.md` §16 (HTTP, HTTPS e políticas edge), §22 (segurança de rede)
- `docs/annexes/C-threat-model-security-hardening.md` §14 (networking, edge e Traefik)
- `docs/annexes/B-nfr-slos.md` §8 (TLS 1.2 mínimo, 1.3 preferencial)

## Preconditions
`M04-05` done.

## Scope
- Redirect permanente HTTP → HTTPS para serviços com TLS.
- Política de TLS versionada: mínimo 1.2, preferência 1.3, suites fracas desabilitadas.
- **Trusted proxies**: lista explícita; `X-Forwarded-*` só é confiável vindo dela.
- Normalização e preservação dos headers `X-Forwarded-*` no ingress.
- Geração/propagação de `Request-ID` quando ausente.
- Compressão configurável, evitando dupla compressão.
- Limite de tamanho de corpo configurável, sem impor um valor global baixo que quebre uploads.
- HSTS como opt-in inicialmente.
- `EdgePolicy` versionada e auditável.

## Out of Scope
- Rate limit e IP allowlist por domínio (`M07-07`).
- WAF/CDN (backlog).
- Políticas da aplicação do usuário — a plataforma configura o **painel** com headers próprios, não impõe às apps (Anexo C §14).

## Application Layer
- **Commands:** `UpdateEdgePolicy`.
- **Reconciler:** `IngressReconciler` aplicando middlewares referenciados pelos routers.

## Security Requirements
- **Trusted proxies é o controle central**: confiar em `X-Forwarded-For` de qualquer origem permite spoof de IP, o que corrompe rate limit, allowlist e audit (Anexo C §14).
- Suites fracas desabilitadas; a política é versionada, para que uma mudança seja auditável.
- HSTS opt-in, porque habilitá-lo por engano em domínio que ainda precisa de HTTP é irreversível para o cliente por meses.
- Headers de segurança do painel (CSP, frame-ancestors, referrer-policy) aplicados ao **painel**, não impostos às aplicações.
- Limite de corpo não pode ser tão baixo que quebre uploads legítimos, nem ausente.
- Alteração de política gera AuditLog.

## Observability Requirements
Métrica de handshakes e erros de TLS por domínio e por ingress. Redirects contabilizados separadamente de erros.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| `X-Forwarded-For` de origem desconhecida | Ignorado; o IP real usado é o da conexão. |
| Cliente TLS antigo | Rejeitado pela política mínima, com métrica registrada. |
| Dupla compressão | Evitada por configuração. |
| Upload maior que o limite | Erro claro de tamanho, não falha genérica. |
| HSTS habilitado por engano | Exige confirmação explícita, com aviso de que é difícil reverter. |
| Política inválida | Rejeitada na validação; a configuração anterior permanece. |

## Acceptance Criteria
1. HTTP redireciona permanentemente para HTTPS em serviços com TLS.
2. A política de TLS aplica mínimo 1.2 com preferência 1.3 e desabilita suites fracas.
3. `X-Forwarded-*` só é confiável vindo da lista de trusted proxies, provado por teste com origem desconhecida.
4. O `Request-ID` é gerado quando ausente e propagado.
5. Compressão é configurável e não ocorre em dobro.
6. O limite de tamanho de corpo é configurável e não impõe um valor global baixo.
7. HSTS é opt-in e exige confirmação explícita com aviso.
8. Headers de segurança do painel são aplicados ao painel e **não** impostos às aplicações.
9. A `EdgePolicy` é versionada; alteração gera AuditLog.
10. Política inválida é rejeitada e a anterior permanece ativa.
11. Métricas de TLS e de redirect estão disponíveis.

## Required Tests
- **unit**: validação de política; versionamento.
- **integration**: política inválida preservando a anterior.
- **Docker/Swarm/E2E**: redirect; handshake TLS com versão antiga rejeitado; `X-Forwarded-For` forjado ignorado; limite de corpo.
- **security**: spoof de forwarded header; suites fracas rejeitadas; headers do painel não vazando para as apps.

## Quality Gates
Local Quality Gate + suíte Docker/Swarm + `bin/security`.

## Definition of Done
Os 11 Acceptance Criteria satisfeitos, spoof de forwarded header comprovadamente bloqueado, Critical/High = 0.
