# M03-02 — Recovery Key generation and verification challenge

## Objective
Entregar ao usuário a única cópia da chave que permite recuperar o Vault — exibida uma vez, verificada por challenge, e nunca persistida de forma recuperável.

## Outcome
No onboarding, o OWNER gera a Recovery Key, copia/baixa/imprime, e **prova** que salvou respondendo a um challenge parcial. Depois disso, a UI mostra apenas fingerprint e metadados.

## References
- `docs/architecture/01-foundation.md` §11.2 (UX de Recovery Key)
- `docs/architecture/04-identity-teams-security.md` §12 (Recovery Key e governança)
- `docs/architecture/10-ui-use-cases.md` UC-002, §21.2
- `docs/annexes/C-threat-model-security-hardening.md` §12.1, T06

## Preconditions
`M03-01` done.

## Scope
- Geração de material de recuperação com entropia adequada e formato legível/transcrevível em blocos.
- **Exibição única**: copiar, baixar arquivo e imprimir; nenhuma exibição posterior.
- **Challenge de verificação**: pedir blocos/trechos específicos; só depois marcar `recoveryVerifiedAt`.
- Fingerprint estável para a UI referenciar a chave sem revelá-la.
- Estado do onboarding: não concluir enquanto a verificação não passar.
- Regenerar antes da verificação **invalida** a chave anterior.

## Out of Scope
- Rotação depois de verificada (`M03-03`).
- Verificação periódica de recovery e drill (`M10-16`).
- Custódia por terceiros / escrow — não há requisito.
- MFA no fluxo (`M11-05`).

## Application Layer
- **Commands:** `GenerateRecoveryKey`, `VerifyRecoveryKey`.
- **Policies:** OWNER ou `INSTANCE_ADMIN` conforme o escopo do Vault.

## UI Impact
Fluxo do doc 01 §11.2: gerar → **exibir uma única vez** → copiar/baixar/imprimir → confirmar que salvou → challenge → verificado. Depois, apenas `••••••••` com fingerprint e data.

## Security Requirements
- A Recovery Key **nunca** é registrada em log, analytics, error reporting, audit ou backup da plataforma (doc 01 §11, regra explícita).
- Não é persistida de forma recuperável: apenas o material derivado necessário para validar o challenge e o fingerprint.
- O challenge não pode ser um oráculo: um número limitado de tentativas, sem revelar quais blocos estão certos.
- Fechar o modal antes da verificação deixa o onboarding **incompleto**, e uma nova geração invalida a anterior (doc 10 UC-002).
- O download é gerado no cliente ou entregue sem persistir no servidor.
- Geração e verificação geram AuditLog **sem** a chave.

## Observability Requirements
AuditLog: `recovery_key.generated`, `recovery_key.verified` (e `denied` quando o challenge falha), com actor, método e resultado — nunca com material.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Usuário fecha o modal antes de verificar | Onboarding permanece incompleto; a chave pode ser regenerada, invalidando a anterior. |
| Challenge falha | **Não** marcar como verificada; limitar tentativas. |
| Usuário perde a chave antes de verificar | Regenerar é o caminho; a anterior é invalidada. |
| Usuário perde a chave depois de verificar | Risco crítico exposto na UI; a recuperação só existe enquanto a chave existir (doc 05 §21). |
| Tentativa de exibir novamente | Impossível: o valor não está armazenado de forma recuperável. |

## Acceptance Criteria
1. A Recovery Key é gerada por CSPRNG com **no mínimo 128 bits de entropia**, em formato transcrevível por blocos com dígito verificador.
2. É exibida **uma única vez**, com copiar, baixar e imprimir.
3. Não existe caminho para exibi-la novamente, provado por teste.
4. O challenge pede blocos específicos e só marca `recoveryVerifiedAt` quando passa.
5. O challenge limita tentativas e não revela quais blocos estavam corretos.
6. Fechar antes de verificar deixa o onboarding incompleto.
7. Regenerar antes da verificação invalida a chave anterior.
8. A chave **não** aparece em log, audit, analytics, error reporting ou backup, provado por teste com valor plantado.
9. A UI mostra apenas fingerprint e metadados após a verificação.
10. Geração e verificação geram AuditLog sem material criptográfico.
11. A operação exige OWNER ou `INSTANCE_ADMIN`; negativo cross-team passa.

## Required Tests
- **unit**: entropia e formato; validação do challenge; limite de tentativas.
- **integration**: fluxo completo de geração e verificação; regeneração invalidando a anterior; ausência de caminho de reexibição.
- **security**: chave ausente de log/audit/backup com valor plantado; challenge sem oráculo.
- **policy**: negado a quem não é OWNER/`INSTANCE_ADMIN`.
- **E2E**: onboarding completo com verificação.

## Quality Gates
Local Quality Gate + `bin/security`. **Story crítica: exige plan mode.**

## Definition of Done
Os 11 Acceptance Criteria satisfeitos, ausência de reexibição e de vazamento provadas, challenge sem oráculo, Critical/High = 0.
