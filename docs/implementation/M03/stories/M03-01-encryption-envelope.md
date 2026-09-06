# M03-01 — Encryption envelope and key management

## Objective
Implementar o envelope de criptografia da plataforma: uma Master Encryption Key que cifra os dados sensíveis e que é ela própria protegida por uma KEK derivada da Recovery Key.

## Outcome
Existe um `EncryptionKeyEnvelope` versionado no banco contendo apenas material **embrulhado**; a MEK nunca é persistida em claro nem exibida; nenhum dado sensível é gravado sem passar por AEAD.

## References
- `docs/architecture/01-foundation.md` §11 (criptografia do Vault e Recovery Key), §11.1 (objetivos)
- `docs/architecture/09-data-model-apis-contracts.md` §6.3 (EncryptionKeyEnvelope)
- `docs/annexes/C-threat-model-security-hardening.md` §12 (Vault e ciclo de vida do secret), §2 (ativos críticos)
- `docs/annexes/B-nfr-slos.md` §13 (secrets at rest: AEAD com chave versionada)

## Preconditions
M02 aceito.

## Scope
- `EncryptionKeyEnvelope`: id (versão do envelope), wrappedKey, kdf e parâmetros, createdAt, retiredAt.
- AEAD com chave versionada para cifrar valores sensíveis; cada ciphertext carrega a versão do envelope usada.
- Derivação da KEK a partir da Recovery Key com KDF resistente e parâmetros versionados.
- Interface interna única de cifra/decifra; nenhum outro código chama primitiva criptográfica diretamente.
- Inicialização do envelope no bootstrap do Vault, ligada ao fluxo de Recovery Key (`M03-02`).
- Fail-closed: criptografia indisponível **bloqueia** a operação.

## Out of Scope
- Recovery Key em si (`M03-02`) e rotação (`M03-03`).
- `SecretVersion` (`M03-05`) — esta Story entrega o mecanismo, não o uso.
- Backup do estado de criptografia (`M10-06`).
- HSM/KMS externo — não há requisito; seria ADR próprio.

## Domain Impact
**Entidade:** `EncryptionKeyEnvelope`, versionado. Uma versão retirada é mantida apenas enquanto necessária ao recovery planejado (doc 09 §6.3).

## Application Layer
- **Commands:** `InitializeEncryption`.
- Módulo de criptografia com API mínima: `encrypt(plaintext, context)`, `decrypt(ciphertext)`, `envelope_version`.

## Security Requirements
Esta Story é o núcleo criptográfico da plataforma:
- O banco armazena **apenas** material embrulhado (doc 09 §6.3).
- A MEK **nunca** aparece na UI, em log, em erro, em métrica ou em backup do storage primário.
- A Recovery Key não é persistida de forma recuperável.
- **Não implementar criptografia caseira**: usar primitivas AEAD estabelecidas da stack, com nonce único por operação.
- Contexto de autenticação (AAD) inclui identificadores do recurso, para impedir que um ciphertext seja movido de um registro para outro.
- Erro de decifra **não** revela material parcial nem distingue “chave errada” de “dado corrompido” de forma explorável.
- Fail-closed: sem chave disponível, a operação falha; jamais grava em claro.

## Observability Requirements
- Falha de criptografia é erro classificado e alertável, sem conteúdo sensível.
- A versão do envelope em uso é observável para diagnóstico e para o recovery readiness (`M03-13`).
- Nenhuma métrica ou log expõe material criptográfico.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| MEK indisponível | Operações que exigem cifra/decifra falham fechado, com erro classificado. |
| Ciphertext movido para outro registro | Falha na verificação de AAD; não decifra. |
| Chave errada | Falha genérica e segura; sem material parcial, sem oráculo. |
| Envelope de versão antiga | Decifra continua funcionando enquanto a versão não for retirada. |
| Nonce reutilizado | Impossível por construção; teste de propriedade cobre. |

## Acceptance Criteria
1. `EncryptionKeyEnvelope` existe e armazena **somente** material embrulhado.
2. A MEK não é persistida em claro e não aparece em UI, log, erro, métrica ou backup do storage primário.
3. Todo valor sensível é cifrado com AEAD e carrega a versão do envelope.
4. O AAD inclui identificadores do recurso; mover um ciphertext para outro registro faz a decifra falhar, provado por teste.
5. Chave errada falha de forma segura, sem revelar material parcial.
6. Nonce é único por operação, garantido por teste de propriedade.
7. Criptografia indisponível **bloqueia** a operação; nenhum caminho grava em claro, provado por teste.
8. Existe uma única interface interna de cifra/decifra; nenhum outro código chama primitiva criptográfica diretamente, verificado por teste estático.
9. Uma versão antiga do envelope continua decifrando enquanto não for retirada.
10. Nenhum log ou métrica expõe material criptográfico.

## Required Tests
- **unit**: propriedades e invariantes do envelope; unicidade de nonce; AAD.
- **integration**: crypto round-trip real; chave errada; ciphertext movido; envelope antigo; fail-closed sem chave.
- **security**: ausência de material criptográfico em log/métrica; interface única de cifra verificada estaticamente.

## Quality Gates
Local Quality Gate + `bin/security`. **Story crítica: exige plan mode.** Dúvida sobre o esquema de chaves → `BLOCKED_FOR_HUMAN_APPROVAL` e ADR, nunca improviso.

## Definition of Done
Os 10 Acceptance Criteria satisfeitos, crypto round-trip e fail-closed provados, nenhuma primitiva criptográfica fora do módulo único, Critical/High = 0.
