# M07-06 — Domain ownership verification before activation

## Objective
Provar que quem reivindica um domínio realmente o controla, **antes** de ativar rota ou emitir certificado — porque apontar o DNS para o IP da plataforma não é prova de posse.

## Outcome
Um domínio só sai de pendente após um challenge de posse bem-sucedido; sem ele, nem a rota nem o certificado existem.

## References
- `docs/architecture/08-networking-domains-edge.md` §10 (verificação e ownership), §26 (`Domain.verificationState`, `ownershipType`)
- `docs/annexes/D-test-strategy.md` §9 (dois Teams não podem se apropriar do mesmo hostname)
- `docs/annexes/C-threat-model-security-hardening.md` §7.3 (anti-IDOR e boundary), §14.1

## Preconditions
`M07-02` done.

## Scope
- `DomainVerificationChallenge`: token único por domínio e por Team, com validade.
- Método de verificação por registro TXT dedicado na zona do domínio.
- `verificationState` e `ownershipType` no `Domain`.
- Verificação **obrigatória** antes de: ativar a rota, emitir certificado, criar registro gerenciado.
- Reverificação periódica configurável, para detectar perda de controle do domínio.
- Comportamento em caso de perda: o domínio é marcado e a política decide entre manter servindo com aviso ou degradar.

## Out of Scope
- Verificação por arquivo HTTP — o challenge HTTP-01 de `M07-08` prova controle para a CA, mas a posse na plataforma usa TXT dedicado para não depender de a rota já estar ativa.
- Transferência de domínio entre Teams — sem requisito; o caminho é remover e reivindicar com nova verificação.

## Domain Impact
`Domain.verificationState`, `Domain.ownershipType`, `DomainVerificationChallenge`.

## Application Layer
- **Commands:** `CreateVerificationChallenge`, `VerifyDomainOwnership`.
- **Reconciler:** `DomainReconciler` executando a verificação.

## Security Requirements
Esta é a Story que impede o cenário mais grave do Milestone:
- **Sem verificação de posse, um Team poderia apontar um domínio alheio para a plataforma e obter certificado válido para ele.** A verificação por TXT dedicado prova controle sobre a zona, não apenas sobre o apontamento.
- O token é **único por domínio e por Team**: um token não pode ser reutilizado por outro Team nem para outro domínio.
- O token tem validade; expirado, exige novo challenge.
- A verificação é pré-condição **dura** de rota, certificado e registro gerenciado — não um aviso.
- Reverificação periódica detecta perda de controle; um domínio que deixou de ser do cliente não deve continuar sendo servido indefinidamente.
- Falha de verificação é registrada; tentativas repetidas de reivindicar domínio alheio são sinal de abuso.

## Observability Requirements
Estado de verificação com o token esperado, o observado e o timestamp da última tentativa. Métrica de verificações por resultado.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Token não encontrado | Domínio permanece não verificado; nada é ativado. |
| Token de outro Team presente | **Não** verifica; o token é escopado. |
| Propagação lenta | Retry com backoff; não declarar falha cedo. |
| Token expirado | Novo challenge necessário. |
| Perda de controle detectada na reverificação | Domínio marcado; política decide manter com aviso ou degradar. |
| Tentativas repetidas de reivindicar domínio alheio | Registradas como sinal de abuso; rate limit. |

## Acceptance Criteria
1. Um `DomainVerificationChallenge` é criado com token único por domínio **e** por Team.
2. A verificação por TXT dedicado prova controle sobre a zona.
3. **Sem verificação, a rota não é ativada, o certificado não é emitido e o registro gerenciado não é criado** — provado por três testes distintos.
4. Um token de outro Team **não** verifica o domínio, provado por teste.
5. O token tem validade; expirado, exige novo challenge.
6. A reverificação periódica detecta perda de controle.
7. Perda de controle marca o domínio; a política decide o comportamento.
8. Tentativas repetidas de reivindicar domínio alheio são registradas e limitadas por rate limit.
9. A propagação lenta usa backoff sem declarar falha cedo.
10. O estado mostra token esperado × observado e o timestamp da última tentativa.
11. Falhas de verificação são registradas.

## Required Tests
- **security**: emissão bloqueada sem posse; rota não ativada sem posse; registro não criado sem posse; token de outro Team; reivindicação de domínio alheio.
- **integration**: expiração do token; reverificação detectando perda; backoff.
- **unit**: geração e escopo do token.

## Quality Gates
Local Quality Gate + `bin/security`. **Story crítica: exige plan mode.**

## Definition of Done
Os 11 Acceptance Criteria satisfeitos, os três bloqueios sem posse provados, token escopado verificado, Critical/High = 0.
