# M04-08 — Certificate and CertificateVersion with encrypted private keys

## Objective
Modelar certificado como intenção e versão como material emitido, garantindo que a chave privada seja armazenada **cifrada** pelo envelope da plataforma.

## Outcome
`Certificate` representa o conjunto de nomes desejado; cada `CertificateVersion` é imutável e guarda a chave privada cifrada; um dump do banco não revela nenhuma chave.

## References
- `docs/architecture/08-networking-domains-edge.md` §13.2 (armazenamento com envelope encryption)
- `docs/architecture/09-data-model-apis-contracts.md` §11.3 (Certificate, CertificateVersion, CertificateDistribution)
- `docs/architecture/05-backup-restore-dr.md` §6 (certificados no backup)
- `docs/annexes/C-threat-model-security-hardening.md` T12

## Preconditions
M03 aceito (`M03-01` fornece o envelope). Independente das demais Stories de M04.

## Scope
- `Certificate`: id, teamId, primaryName, SANs, `domainSetHash`, challengeType, status, activeVersionId, renewAfter.
- `CertificateVersion`: id, certificateId, certificatePem, **encryptedPrivateKey**, chainPem, issuedAt, notBefore, notAfter, providerOrderRef, fingerprint. **Imutável**.
- `CertificateDistribution`: certificateVersionId, ingressNodeId, status, distributedAt, verifiedAt.
- Estados do doc 09 §17: `PENDING → ISSUING → DISTRIBUTING → ACTIVE → RENEWING → ACTIVE | FAILED | REVOKED`.
- Chave privada cifrada com o mesmo envelope de `M03-01`, com AAD ligando ao `certificateVersionId`.
- Deduplicação por `domainSetHash`, para não emitir certificados redundantes (doc 08 §15).

## Out of Scope
- Emissão via ACME (`M04-09`).
- Distribuição (`M04-10`) e renovação (`M04-11`).
- Backup de certificados (`M10-07`).
- Certificado fornecido pelo usuário (`tlsMode: PROVIDED`) — o campo existe, o fluxo de upload é Story própria em `M07` se houver requisito.

## Domain Impact
**Invariante:** `CertificateVersion` é imutável — a renovação **cria** versão nova, nunca sobrescreve a distribuída (doc 09 §11.3).

## Application Layer
- **Commands:** `CreateCertificateIntent`, `StoreCertificateVersion`.
- **Queries:** `CertificateStatus`, `CertificateExpiry`.

## Security Requirements
- A chave privada **nunca** é persistida em claro (doc 08 §13.2, Anexo C §12).
- AAD liga o ciphertext ao `certificateVersionId`: mover o material entre registros faz a decifra falhar.
- A chave privada nunca aparece em API, log, evento, audit, métrica ou UI.
- A decifra só acontece no Certificate Distributor, em memória, durante a distribuição.
- Sem o envelope disponível, a operação **bloqueia**; nunca há fallback.
- Uma versão retirada não é apagada enquanto puder ser necessária ao recovery (doc 05 §6).

## Observability Requirements
- Fingerprint, validade e status por versão; dias restantes até expirar.
- Alerta antecipado configurável (consumido por `M04-11` e por `M09-08`).

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Envelope indisponível | Bloquear; nunca gravar chave em claro. |
| Material movido entre registros | Decifra falha por AAD. |
| Certificado duplicado para o mesmo conjunto de nomes | Deduplicado por `domainSetHash`. |
| Versão expirada ainda ativa | Status reflete o risco; o alerta dispara antes da janela crítica. |
| Tentativa de editar uma versão | Impossível; teste comprova. |

## Acceptance Criteria
1. `Certificate`, `CertificateVersion` e `CertificateDistribution` existem com os campos do doc 09 §11.3.
2. A chave privada é armazenada **somente cifrada**, provado por dump do banco.
3. O AAD liga o ciphertext ao `certificateVersionId`; mover o material faz a decifra falhar.
4. A chave privada não aparece em API, log, evento, audit, métrica ou UI, provado com valor plantado.
5. `CertificateVersion` é imutável; nenhum caminho a edita.
6. `domainSetHash` deduplica pedidos para o mesmo conjunto de nomes.
7. Sem envelope disponível, a operação bloqueia sem fallback.
8. Os estados da state machine são respeitados; transição inválida é rejeitada.
9. Uma versão retirada não é apagada enquanto puder ser necessária ao recovery.
10. Fingerprint, validade e dias restantes são consultáveis.

## Required Tests
- **unit**: state machine; `domainSetHash`; imutabilidade.
- **integration**: chave cifrada no banco; AAD; envelope indisponível bloqueando.
- **security**: valor plantado ausente de todos os sinks; dump do banco sem chave legível.

## Quality Gates
Local Quality Gate + `bin/security` + `bin/fitness` (AF-06).

## Definition of Done
Os 10 Acceptance Criteria satisfeitos, chave comprovadamente cifrada, imutabilidade garantida, Critical/High = 0.
