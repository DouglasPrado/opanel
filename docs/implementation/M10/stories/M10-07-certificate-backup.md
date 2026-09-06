# M10-07 — Certificate export, backup and redistribution after restore

## Objective
Proteger certificados e suas chaves privadas cifradas, para que a recuperação não dependa de reemissão sob rate limit e provider indisponível.

## Outcome
`CertificateVersion` entra no backup com a chave privada cifrada; após o restore, o Certificate Manager redistribui a versão ativa para os ingress.

## References
- `docs/architecture/05-backup-restore-dr.md` §6 (certificados TLS), §6.1 (por que fazer backup mesmo sendo renováveis)
- `docs/architecture/08-networking-domains-edge.md` §13.2 (armazenamento cifrado)
- `docs/annexes/B-nfr-slos.md` §11 (certificados: RPO ≤ 15 min, RTO ≤ 30 min)

## Preconditions
`M10-04` done. M04 aceito.

## Scope
- Inclusão de `Certificate` e `CertificateVersion` no escopo protegido, com a chave privada **cifrada**.
- Manifesto registrando domains, issuer, serial, `issuedAt`, `expiresAt` e fingerprint (doc 05 §6.1).
- Após o restore, o Certificate Manager **redistribui** a versão ativa para todos os ingress, reutilizando `M04-10`.
- Após a recuperação, a renovação normal via ACME/DNS-01 volta a funcionar.
- Alerta quando o backup de certificados está desatualizado após uma rotação (doc 05 §17.2).

## Out of Scope
- Reemissão como estratégia primária de recuperação — ela é o fallback, não o caminho (doc 05 §6.1).
- Revogação de certificado.
- Certificados fornecidos pelo usuário.

## Security Requirements
- A chave privada permanece **cifrada no backup** (doc 05 §6.1, regra explícita) — o backup herda a proteção de `M04-08`.
- O manifesto registra metadados, **nunca** material da chave.
- Após o restore, a distribuição segue a política de confirmação de `M04-10`: nada é ativado sem ACK.
- Uma `CertificateVersion` restaurada é imutável, como a original.
- Depender apenas de reemissão durante um desastre aumenta o RTO e pode esbarrar em rate limit, DNS indisponível ou credencial expirada — por isso o backup existe.

## Observability Requirements
Estado de proteção dos certificados no Protection Readiness. Alerta de backup de certificado desatualizado após rotação.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Restore com certificados válidos | Redistribuir e ativar após ACK. |
| Certificado restaurado já expirado | Detectado; reemissão iniciada; a rota não é declarada segura com certificado vencido. |
| Envelope indisponível | Chaves não decifráveis; sinalizado como parte do recovery do Vault. |
| ACME indisponível após restore | Certificados restaurados continuam servindo; a renovação entra em retry. |
| Backup desatualizado após rotação | Alerta. |
| Fingerprint divergente | Falha de integridade; não distribuir. |

## Acceptance Criteria
1. `Certificate` e `CertificateVersion` fazem parte do escopo protegido, com a chave privada **cifrada**.
2. O manifesto registra domains, issuer, serial, validade e fingerprint — **nunca** material da chave.
3. Após o restore, a versão ativa é redistribuída para todos os ingress.
4. A ativação após o restore respeita a política de confirmação de `M04-10`.
5. Fingerprint divergente é falha de integridade e impede a distribuição.
6. Certificado restaurado já expirado é detectado e a reemissão é iniciada; a rota não é declarada segura.
7. ACME indisponível após o restore não impede os certificados restaurados de servirem.
8. Envelope indisponível torna as chaves não decifráveis, e isso é sinalizado como parte do recovery do Vault.
9. Backup de certificados desatualizado após rotação gera alerta.
10. A `CertificateVersion` restaurada permanece imutável.
11. O estado de proteção aparece no Protection Readiness.

## Required Tests
- **integration**: restore e redistribuição; fingerprint divergente; certificado expirado.
- **Docker/Swarm**: ingress servindo o certificado restaurado após ACK.
- **security**: chave cifrada no backup; manifesto sem material.

## Quality Gates
Local Quality Gate + suíte Docker/Swarm + `bin/security`.

## Definition of Done
Os 11 Acceptance Criteria satisfeitos, redistribuição após restore provada, chave protegida, Critical/High = 0.
