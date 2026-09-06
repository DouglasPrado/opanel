# M10-16 — Restore verification and periodic drills

## Objective
Provar que os backups são **recuperáveis**, e não apenas que foram criados — detectando corrupção, chave perdida, schema incompatível e credencial expirada antes de um incidente real.

## Outcome
Drills automáticos e periódicos executam integridade, restore de banco, recuperação do Vault e rebuild de Environment, e registram `PASS`/`FAIL` com evidência.

## References
- `docs/architecture/05-backup-restore-dr.md` §16 (restore verification e drills), §16.1 (backup bem-sucedido ≠ recuperável), §16.2 (tipos de drill)
- `docs/annexes/D-test-strategy.md` §15 (backup/restore/DR testing), §15.1 (restore drill sem conhecimento privilegiado)
- `docs/annexes/B-nfr-slos.md` §11.1 (RPO/RTO só valem após medição em restore real)

## Preconditions
`M10-11` e `M10-13` done.

## Scope
- `RecoveryVerification`: tipo, status, `executedAt`, evidência.
- Tipos de drill do doc 05 §16.2: **Integrity Check** (todo backup), **DB Restore Test** (semanal), **Vault Recovery Test** (mensal), **Environment Rebuild** (mensal/trimestral), **Full DR Drill** (trimestral/semestral).
- Restore em ambiente **temporário e isolado** para os drills.
- Verificações do doc 05 §16.1: o banco abre, o schema é válido, o Vault decifra o canário, os certificados são parseáveis, os checksums do manifesto conferem.
- Medição de RPO e RTO reais em cada drill.
- **Drill sem conhecimento privilegiado** (Anexo D §15.1): o operador segue o runbook usando apenas o que estaria disponível em um incidente real, e os passos manuais que precisariam virar automação são registrados.

## Out of Scope
- Drill final de release (`M14-05`).
- Chaos combinado com DR (`M13-10`).

## Application Layer
- **Commands:** `RunVerification`.
- **Queries:** `VerificationHistory`.

## Security Requirements
- O drill roda em ambiente **isolado**; ele nunca toca a instalação de produção.
- O canário do Vault é um secret dedicado a esse fim — não se usa um secret real do cliente para testar recuperação.
- Um drill que falha marca o recovery point como **não confiável**, e isso é visível.
- Credenciais usadas no drill são de teste e rotacionáveis.
- **Backup sem restore verificado não conta como proteção** (doc 05 §23): o Protection Readiness reflete isso.

## Observability Requirements
Histórico de drills com tipo, resultado, RPO/RTO medidos e evidência. Idade do último drill bem-sucedido alimenta o Protection Readiness.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Backup corrompido | Drill `FAIL`; recovery point marcado como não confiável; alerta. |
| Recovery Key incorreta no teste | `FAIL` esperado quando o teste é negativo; `FAIL` real quando deveria funcionar. |
| Schema incompatível | Detectado no drill, não em um incidente. |
| Ambiente de drill indisponível | Drill não executado, **registrado como não executado** — nunca presumido `PASS`. |
| Drill demorando além do RTO alvo | Registrado; o RTO alcançável é atualizado. |
| Passo manual no runbook | Registrado como candidato a automação. |

## Acceptance Criteria
1. `RecoveryVerification` existe com tipo, status, timestamp e evidência.
2. Os cinco tipos de drill do doc 05 §16.2 existem com cadências configuráveis.
3. O Integrity Check roda em **todo** backup.
4. O drill de restore usa ambiente **temporário e isolado**; nunca toca produção.
5. As verificações do doc 05 §16.1 são executadas: banco abre, schema válido, Vault decifra o canário, certificados parseáveis, checksums conferem.
6. O canário do Vault é um secret dedicado, não um secret real do cliente.
7. Um drill que falha marca o recovery point como **não confiável** e alerta.
8. Ambiente indisponível registra “não executado”, **nunca** `PASS` presumido.
9. **RPO e RTO são medidos** em cada drill e atualizam os valores alcançáveis.
10. O drill executado sem conhecimento privilegiado registra os passos manuais que precisam virar automação.
11. Backup sem restore verificado **não** conta como proteção no Protection Readiness.
12. O histórico de drills é consultável com evidência.

## Required Tests
- **DR Lab**: cada tipo de drill; backup corrompido detectado; ambiente indisponível.
- **integration**: recovery point marcado não confiável; atualização de RPO/RTO alcançáveis.
- **security**: isolamento do ambiente de drill; canário dedicado.

## Quality Gates
Local Quality Gate + DR Lab + `bin/security`.

## Definition of Done
Os 12 Acceptance Criteria satisfeitos, drills com RPO/RTO medidos, ausência de `PASS` presumido, Critical/High = 0.
