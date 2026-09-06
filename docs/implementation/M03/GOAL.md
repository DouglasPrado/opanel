---
milestone: "M03"
type: "autonomous-goal"
---

# M03 — Autonomous Goal

## Completion condition

M03 está `READY` quando todas as condições forem verdadeiras e demonstradas com comando e exit code:

1. Todas as Stories `required: true` estão `done` com `commit`; nenhuma `required` está `blocked`.
2. `bin/pack validate` verde para M03.
3. Suítes unit, integration, request, policy e contract verdes.
4. **Crypto round-trip real** verde: cifrar, decifrar, e falhar com chave errada sem revelar material.
5. **Teste de rotação**: nova Recovery Key faz rewrap da MEK e **nenhuma** `SecretVersion` é recriptografada; a chave antiga deixa de desbloquear.
6. **Teste de isolamento de backup**: um dump do banco, sem a Recovery Key, não permite revelar nenhum secret.
7. Suíte Docker/Swarm verde: Swarm Secret anexada **somente** ao Service autorizado; Task movida entre nodes recebendo a versão correta.
8. **Teste de pinning**: criar `vN+1` não altera o Service pinado em `vN`.
9. **Scanner de plaintext** verde: nenhum valor de secret aparece em log, erro, evento, payload de Operation, audit ou telemetria, provado com valores plantados.
10. `bin/fitness` verde com AF-06 avaliando serializers, formatadores de log e payloads de audit reais.
11. `bin/security` verde.
12. E2E verde: onboarding com Recovery Key verificada; criar Secret → versão → binding → workload lendo o valor → nova versão → promoção deliberada.
13. Nenhum finding Critical/High aberto em `M03/review/`.
14. `MILESTONE_REPORT.md` gerado com evidência por Acceptance Criterion.

## Required proof

- saída do crypto round-trip e do caso de chave errada;
- saída do teste de rotação mostrando que nenhuma `SecretVersion` foi reescrita;
- saída do teste de dump do banco sem Recovery Key;
- prova, contra Swarm real, de que um Service não autorizado **não** recebe a secret;
- saída do scanner de plaintext com os valores plantados;
- evidência de que reveal exige step-up e gera AuditLog;
- um commit por Story.

## Constraints

- **Nunca** persistir plaintext de secret. Se a criptografia estiver indisponível, **bloquear** — jamais gravar em claro.
- **Nunca** logar, auditar, emitir em evento ou colocar em payload de Operation o valor de um secret ou a Recovery Key.
- `SecretVersion` é imutável: nenhuma operação a edita.
- Criar versão nova **não** pode alterar binding existente automaticamente em produção.
- Não implementar `CertificateVersion` (M04), credenciais de provider (M05), backup do Vault (M10) nem MFA (M11).
- Não implementar dynamic credentials nem PKI.
- Não acessar Docker fora do Swarm Executor.
- Não desabilitar teste, checker ou gate.
- Não usar criptografia caseira: usar primitivas AEAD estabelecidas da stack.

## Block policy

3 tentativas sem progresso → trocar de estratégia uma vez → `blocked` com diagnóstico. Dúvida sobre o modelo criptográfico → `BLOCKED_FOR_HUMAN_APPROVAL` e ADR; **não** improvisar esquema de chaves. Docker indisponível → `BLOCKED_EXTERNAL_DEPENDENCY` nas Stories de materialização.

## End state

Para o implementer: `READY_FOR_REVIEW`, `BLOCKED` ou `FAILED`. Nunca abandonar trabalho silenciosamente. Ao atingir `READY_FOR_REVIEW`, gerar `MILESTONE_REPORT.md`, atualizar `review-state.json` e devolver o controle ao orquestrador — **não iniciar M04 automaticamente**.

Security Gate humano (Anexo C §22, G1→G2).

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
