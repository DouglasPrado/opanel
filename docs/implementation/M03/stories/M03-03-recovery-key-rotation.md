# M03-03 — Recovery Key rotation with MEK rewrap

## Objective
Permitir trocar a Recovery Key sem recriptografar todo o Vault, fazendo apenas o rewrap da Master Encryption Key.

## Outcome
O OWNER rotaciona a Recovery Key com step-up authentication; uma nova chave é exibida uma vez e verificada; **nenhuma** `SecretVersion` é reescrita; a chave antiga deixa de desbloquear.

## References
- `docs/architecture/01-foundation.md` §11.1 (rotacionar não exige recriptografar tudo)
- `docs/architecture/04-identity-teams-security.md` §12 (rotação exige OWNER + step-up)
- `docs/annexes/C-threat-model-security-hardening.md` §12.1
- `docs/annexes/E-operational-runbooks.md` RB-19 (Recovery Key perdida ou exposta)

## Preconditions
`M03-02` done. `M03-04` (step-up) precisa existir antes da liberação da operação na UI.

## Scope
- Rotação: gerar nova Recovery Key → derivar nova KEK → **rewrap da MEK** → nova versão de `EncryptionKeyEnvelope` → verificar a nova chave por challenge → retirar a versão anterior.
- Atomicidade: ou a rotação completa, ou o estado anterior permanece íntegro e utilizável.
- Exigência de OWNER + step-up authentication.
- Janela de segurança antes de retirar o envelope anterior.
- Suporte ao cenário do RB-19: chave exposta mas MEK íntegra → rotacionar e revogar cópias antigas.

## Out of Scope
- Rotação da própria MEK com re-encrypt de todas as versões — não é requisito e teria custo e risco muito maiores; se vier a ser necessário, exige ADR.
- Rotação de credenciais de provider afetadas (`M11`, RB-20).
- Drill de recuperação (`M10-16`).

## Application Layer
- **Commands:** `RotateRecoveryKey`.
- **Policies:** OWNER por padrão; `INSTANCE_ADMIN` para o escopo de instalação. ADMIN **não** rotaciona (doc 04 §6.2).

## Security Requirements
- Exige **step-up authentication** (doc 04 §8.3).
- A rotação **não** recriptografa `SecretVersion`; qualquer implementação que o faça é finding Critical (custo e risco desnecessários, e contradiz o doc 01 §11.1).
- A chave antiga deixa de desbloquear após a retirada da versão anterior do envelope, e isso é testado.
- Nenhuma das duas chaves aparece em log, audit ou backup.
- A rotação gera AuditLog com actor, timestamp e fingerprints (antigo e novo) — **nunca** as chaves.
- Falha no meio da rotação **não** pode deixar o Vault inacessível: o estado anterior permanece válido até a nova chave ser verificada.

## Observability Requirements
- `recovery_key.rotated` no AuditLog com fingerprints.
- `RecoveryReadinessView` reflete `ROTATION_REQUIRED` quando a política exigir e volta a `READY` após a rotação verificada.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Falha no meio do rewrap | Estado anterior íntegro; o Vault continua acessível com a chave antiga. |
| Nova chave não verificada | A versão anterior do envelope **não** é retirada; a antiga continua válida. |
| Step-up expirado | Exigir novamente antes de executar. |
| Rotação concorrente | Serializada; duas rotações simultâneas não podem produzir envelope inconsistente. |
| Chave antiga usada após a retirada | Rejeitada. |
| Suspeita de exposição da chave | RB-19: rotacionar, revogar cópias antigas e, se houver evidência de acesso a secrets, rotacionar as credenciais afetadas. |

## Acceptance Criteria
1. A rotação gera nova Recovery Key, faz rewrap da MEK e cria nova versão do envelope.
2. **Nenhuma `SecretVersion` é reescrita** durante a rotação, provado por teste que compara os registros antes e depois.
3. A nova chave é exibida uma vez e verificada por challenge antes de a versão anterior ser retirada.
4. A chave antiga deixa de desbloquear após a retirada, provado por teste.
5. Falha no meio da rotação mantém o estado anterior íntegro e o Vault acessível.
6. A operação exige OWNER (ou `INSTANCE_ADMIN` no escopo de instalação) **e** step-up authentication.
7. ADMIN não consegue rotacionar por padrão.
8. Rotações concorrentes são serializadas.
9. Nenhuma das chaves aparece em log, audit ou backup, provado com valores plantados.
10. AuditLog registra fingerprints antigo e novo, nunca as chaves.
11. O estado de recovery readiness é atualizado corretamente.

## Required Tests
- **unit**: cálculo do rewrap; transição de versões do envelope.
- **integration**: rotação completa; **contagem de `SecretVersion` inalterada**; falha no meio preservando o estado; rotação concorrente; chave antiga rejeitada após retirada.
- **policy**: negado a ADMIN; exige step-up.
- **security**: chaves ausentes de log/audit/backup.

## Quality Gates
Local Quality Gate + `bin/security`. **Story crítica: exige plan mode.**

## Definition of Done
Os 11 Acceptance Criteria satisfeitos, ausência de re-encrypt provada por contagem, falha no meio preservando acesso, Critical/High = 0.
