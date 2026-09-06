---
milestone: "M10"
type: "autonomous-goal"
---

# M10 — Autonomous Goal

## Completion condition

M10 está `READY` quando, com comando e exit code demonstrados:

1. Stories `required: true` `done` com `commit`; nenhuma `required` `blocked`; `bin/pack validate` verde.
2. Suítes unit, integration, request, policy e contract verdes.
3. Contract tests do `BackupStorageProvider` verdes (put/get/delete, checksum, multipart).
4. **Teste de isolamento criptográfico** verde: um dump do banco restaurado **sem** a Recovery Key **não** permite revelar nenhum secret.
5. **Teste de chave incorreta** verde: restore com Recovery Key errada falha sem produzir plaintext parcial.
6. **Teste de backup corrompido** verde: checksum/manifest detecta e o backup **não** é marcado como restaurável.
7. **Teste de retenção** verde: o último recovery point válido e os pontos protegidos **não** podem ser apagados.
8. **Teste de digest ausente** verde: um artifact necessário indisponível no Registry é detectado **antes** do rebuild.
9. Suíte Docker/Swarm verde: Clean Rebuild recriando networks, secrets, services e ingress; Fast Swarm Restore no caminho aplicável.
10. **Drill de Clean Rebuild em infraestrutura vazia** verde, com **RPO e RTO medidos e registrados**.
11. Teste de restore de `EnvironmentSnapshot` verde, sem duplicar plaintext.
12. Teste de restore destrutivo verde: exige reautenticação e confirmação explícita.
13. **Teste de migração de Environment entre Clusters** verde: plano, `dry-run`, corte de tráfego só após health no destino, abort antes do corte e limpeza da origem (UC-011).
14. `bin/fitness` e `bin/security` verdes; Critical/High = 0 em `M10/review/`.
15. `MILESTONE_REPORT.md` gerado com `Status: READY_FOR_REVIEW` e evidência por Acceptance Criterion.

## Required proof

- RPO e RTO **medidos** no drill, com timestamps;
- saída do teste de dump sem Recovery Key;
- saída do teste de chave incorreta;
- saída do teste de backup corrompido;
- inventário do que foi recriado no Clean Rebuild e a validação de health;
- um commit por Story.

## Constraints

- **Backup sempre em destino externo ao cluster protegido.**
- **Recovery Key nunca no backup principal** e nunca em plaintext.
- Payload cifrado **antes** de sair da plataforma; manifest só com material embrulhado.
- Snapshot referencia `SecretVersion` IDs; **nunca** duplica plaintext.
- Restore destrutivo **sempre** com reautenticação e confirmação explícita.
- Preferir restaurar em recurso novo antes de substituir o atual.
- Retenção **nunca** apaga o último recovery point válido nem ponto protegido.
- Backup sem restore verificado **não** conta como proteção.
- Não implementar backup dos bancos gerenciados dos clientes.
- Não desabilitar teste, checker ou gate.

## Block policy

3 tentativas sem progresso → mudar estratégia uma vez → `blocked`. Bucket S3-compatible indisponível → `BLOCKED_EXTERNAL_DEPENDENCY`. Infraestrutura vazia para o drill indisponível → `BLOCKED_EXTERNAL_DEPENDENCY` em `M10-13` e `M10-16`; **não** marcar o Milestone como pronto sem o drill. Se um restore produzir plaintext parcial com chave errada, **parar**: é falha de segurança crítica.

## End state

Para o implementer: `READY_FOR_REVIEW`, `BLOCKED` ou `FAILED`. Nunca abandonar trabalho silenciosamente. Ao atingir `READY_FOR_REVIEW`, gerar `MILESTONE_REPORT.md`, atualizar `review-state.json` e devolver o controle ao orquestrador — **não iniciar M11 automaticamente**.

DR Gate humano (Anexo A §11).

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
