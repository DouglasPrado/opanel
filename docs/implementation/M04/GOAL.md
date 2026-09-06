---
milestone: "M04"
type: "autonomous-goal"
---

# M04 — Autonomous Goal

## Completion condition

M04 está `READY` quando, com comando e exit code demonstrados:

1. Stories `required: true` `done` com `commit`; nenhuma `required` `blocked`; `bin/pack validate` verde.
2. Suítes unit, integration, request, policy e contract verdes.
3. Contract tests do `DnsProvider` e do cliente ACME verdes (create/update/delete de registro, propagação, conflito, challenge, renewal, falha/retry, ativação de versão).
4. Suíte Docker/Swarm verde: Traefik global nos ingress nodes; labels gerando router/service; attachment de rede reconciliado; request real alcançando o Service.
5. **E2E verde**: Service publicado responde por HTTPS no domínio default, com certificado emitido pela plataforma.
6. **Teste de renovação** verde: nova `CertificateVersion` distribuída, confirmada e ativada sem derrubar conexões existentes.
7. **Teste de segurança de chave**: a chave privada está cifrada em repouso; um dump do banco não a revela.
8. **Teste de SSRF** verde em todas as chamadas a provider e em toda URL fornecida.
9. **Teste de trusted proxies** verde: `X-Forwarded-*` de origem desconhecida não é confiado.
10. Teste comprovando que nenhum Service publica porta pública e que dashboard/exporters não são públicos.
11. Teste de WebSocket e SSE atravessando o ingress.
12. `bin/fitness` e `bin/security` verdes; Critical/High = 0 em `M04/review/`.
13. `MILESTONE_REPORT.md` gerado com evidência por Acceptance Criterion.

## Required proof

- request HTTPS real chegando ao Service pelo domínio default;
- ciclo de emissão DNS-01 com o registro TXT criado e removido;
- ACK de distribuição por ingress e a ativação condicionada ao quorum;
- prova de que a chave privada não é legível a partir do banco;
- saída dos testes de SSRF e de trusted proxies;
- um commit por Story.

## Constraints

- **Nenhuma porta de aplicação publicada diretamente**; o ingress é a única fronteira pública.
- Nenhum Traefik emite certificado por conta própria nem mantém `acme.json` gravável compartilhado.
- Chave privada de certificado **sempre** cifrada em repouso pelo envelope de M03.
- Credencial de DNS provider **sempre** no Vault, com escopo mínimo.
- Toda URL fornecida e toda chamada a provider passam pela política de SSRF.
- Não abrir 2375, não expor Docker API, não publicar dashboard do Traefik.
- Não implementar domínio customizado, HTTP-01, IPv6, rate limit por domínio (M07), LB provider nem multi-ingress real (M08).
- Não desabilitar teste, checker ou gate.

## Block policy

3 tentativas sem progresso → mudar estratégia uma vez → `blocked`. Zona DNS ou credencial de provider indisponível → `BLOCKED_EXTERNAL_DEPENDENCY` nas Stories de DNS/ACME; ingress HTTP interno pode ser validado em laboratório enquanto isso. Rate limit da CA atingido → `BLOCKED_EXTERNAL_DEPENDENCY` com registro; usar ambiente de staging da CA quando disponível.

## End state

Para o implementer: `READY_FOR_REVIEW`, `BLOCKED` ou `FAILED`. Nunca abandonar trabalho silenciosamente. Ao atingir `READY_FOR_REVIEW`, gerar `MILESTONE_REPORT.md`, atualizar `review-state.json` e devolver o controle ao orquestrador — **não iniciar M05 automaticamente**.

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
