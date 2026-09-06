---
milestone: "M07"
type: "autonomous-goal"
---

# M07 — Autonomous Goal

## Completion condition

M07 está `READY` quando, com comando e exit code demonstrados:

1. Stories `required: true` `done` com `commit`; nenhuma `required` `blocked`; `bin/pack validate` verde.
2. Suítes unit, integration, request, policy e contract verdes.
3. Contract tests verdes: `DnsProvider` para zona do cliente; ACME com HTTP-01.
4. **E2E verde**: adicionar domínio customizado → verificar DNS → verificar posse → emitir certificado → `ACTIVE` → request HTTPS real chegando ao Service.
5. **Teste de apropriação** verde: um Team **não** consegue reivindicar hostname de outro Team.
6. **Teste de posse** verde: sem verificação de posse, nem a rota é ativada nem o certificado é emitido.
7. Teste de remoção verde: impacto em certificado/SAN/DNS avaliado antes de executar.
8. Teste de políticas por domínio verde: rate limit, IP allowlist, headers e body size aplicados.
9. Teste de IPv6 verde: AAAA **não** é anunciado sem caminho funcional.
10. Teste de SSRF verde em todas as chamadas a provider.
11. Teste de diagnóstico verde: cada camada quebrada isoladamente produz o diagnóstico correto.
12. `bin/fitness` e `bin/security` verdes; Critical/High = 0 em `M07/review/`.
13. `MILESTONE_REPORT.md` gerado com evidência por Acceptance Criterion.

## Required proof

- request HTTPS real no domínio customizado;
- registro de verificação de posse e o bloqueio quando ela falha;
- saída do teste de apropriação cross-team;
- saída dos testes de rate limit e allowlist;
- prova de que o wildcard da plataforma não é usado para domínio de cliente;
- um commit por Story.

## Constraints

- **Nunca** emitir certificado nem ativar rota para um domínio cuja posse não foi verificada.
- **Nunca** usar o wildcard da plataforma para domínio de cliente.
- Credencial de DNS do cliente sempre no Vault, com escopo mínimo por zona.
- Toda chamada a provider e toda URL fornecida passam pela política de SSRF.
- Não anunciar AAAA sem caminho IPv6 funcional de ponta a ponta.
- Não implementar WAF, CDN, TCP/UDP arbitrário nem path routing avançado.
- Não implementar LB provider nem multi-ingress (M08).
- Não desabilitar teste, checker ou gate.

## Block policy

3 tentativas sem progresso → mudar estratégia uma vez → `blocked`. Domínio de teste ou zona delegada indisponível → `BLOCKED_EXTERNAL_DEPENDENCY`; usar zona de laboratório quando possível. Rate limit da CA → `BLOCKED_EXTERNAL_DEPENDENCY`; usar staging. Se for possível emitir certificado sem verificação de posse, **parar**: é falha de segurança, não bug de ajuste.

## End state

Para o implementer: `READY_FOR_REVIEW`, `BLOCKED` ou `FAILED`. Nunca abandonar trabalho silenciosamente. Ao atingir `READY_FOR_REVIEW`, gerar `MILESTONE_REPORT.md`, atualizar `review-state.json` e devolver o controle ao orquestrador — **não iniciar M08 automaticamente**.

## Final Handoff

Quando todas as condições do Milestone estiverem satisfeitas:

1. marque todas as Stories obrigatórias como `done`;
2. execute todos os testes e Quality Gates finais;
3. gere `MILESTONE_REPORT.md`;
4. o relatório deve conter explicitamente:

   `Status: READY_FOR_REVIEW`

5. altere `review-state.json.status` de `implementing` ou `fixing` para `ready_for_review`;
6. não inicie o próximo Milestone;
7. encerre a execução.

O review independente posterior é responsabilidade exclusiva do Codex. Claude
não deve executar nem substituir o Codex Review e nunca pode declarar o estado
`accepted` ou `human_acceptance`.
