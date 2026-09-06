# M10-05 — Platform database backup adapter

## Objective
Proteger a fonte de verdade do produto com uma cópia lógica independente do provider, reduzindo a dependência de um fornecedor específico.

## Outcome
Backups lógicos periódicos do Platform Database, com `schemaVersion` no manifesto e capacidade de restaurar em uma instância isolada para validação.

## References
- `docs/architecture/05-backup-restore-dr.md` §4 (banco da própria plataforma), §4.1 (estratégia recomendada), §4.2 (RPO/RTO)
- `docs/annexes/B-nfr-slos.md` §11 (PostgreSQL do Control Plane: RPO ≤ 5 min, RTO ≤ 30 min)
- `docs/annexes/E-operational-runbooks.md` RB-23

## Preconditions
`M10-04` done.

## Scope
- Backup **lógico** periódico, independente do provider.
- Consciência de PITR/WAL quando o provider oferecer, para reduzir o RPO — e registro explícito de quando **não** está disponível.
- Backup full diário como recovery point simples e portátil.
- `schemaVersion` registrado no manifesto, garantindo compatibilidade com a versão da aplicação.
- Restore para database **temporário** durante drills (`M10-16`).
- Backup sem bloquear a operação normal da plataforma.

## Out of Scope
- Restore em produção (`M10-11`).
- Backup dos bancos das aplicações dos clientes — fora do escopo (doc 05 §1.2).
- Réplica/HA do banco — decisão de implementação, não deste Milestone (doc 05 §23, item aberto).

## Application Layer
- **Providers:** adapter de backup do PostgreSQL.
- **Commands:** `RunDatabaseBackup`.

## Security Requirements
- O dump contém **ciphertext** de SecretVersions, nunca plaintext — a proteção vem de M03. Este backup **não** revela secrets sozinho (doc 01 §11.1).
- O payload é cifrado por `M10-04` antes de sair.
- A credencial de acesso ao banco para backup tem privilégio mínimo de leitura.
- O `schemaVersion` é obrigatório: restaurar em versão incompatível é falha silenciosa perigosa.
- O dump nunca é gravado em disco não protegido nem em local público durante o processo.
- AuditLog para cada execução.

## Observability Requirements
- `recoveryPointAt` alimentando o RPO real.
- Duração e tamanho por execução; comparação com a baseline.
- Alerta quando o backup excede o RPO alvo (doc 05 §17.2).

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Banco sob carga | Backup não pode degradar a operação além do aceitável; janela e método considerados. |
| PITR indisponível no provider | Registrado explicitamente; o RPO alcançável reflete isso. |
| Dump interrompido | `FAILED`; run anterior preservado. |
| Espaço insuficiente no destino | `FAILED` com causa; alerta. |
| `schemaVersion` ausente | Run `FAILED`. |
| Dump em disco temporário | Área protegida, removida ao final. |

## Acceptance Criteria
1. O backup lógico do Platform Database é executado conforme a política e independe do provider.
2. `schemaVersion` é registrado no manifesto; sua ausência faz o run falhar.
3. PITR é usado quando disponível; sua indisponibilidade é **registrada** e reflete no RPO alcançável.
4. O backup full diário existe como recovery point portátil.
5. O payload é cifrado antes de sair da plataforma.
6. O dump contém apenas ciphertext de SecretVersions; ele **não** revela secrets sozinho, provado por teste.
7. A credencial de backup tem privilégio mínimo de leitura.
8. Nenhum dump é gravado em local não protegido; a área temporária é removida ao final.
9. O backup não degrada a operação além do aceitável.
10. Dump interrompido resulta em `FAILED` e preserva o run anterior.
11. `recoveryPointAt` alimenta o RPO real; exceder o alvo gera alerta.
12. Cada execução gera AuditLog.

## Required Tests
- **integration**: backup e restore em instância isolada; dump sem plaintext de secret; `schemaVersion` ausente.
- **security**: credencial de privilégio mínimo; área temporária removida; dump sem secrets legíveis.
- **unit**: cálculo de RPO alcançável com e sem PITR.

## Quality Gates
Local Quality Gate + `bin/security`.

## Definition of Done
Os 12 Acceptance Criteria satisfeitos, dump comprovadamente sem plaintext, RPO real medido, Critical/High = 0.
