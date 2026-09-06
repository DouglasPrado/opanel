# M02-07 — Adopt runtime state as an explicit administrative operation

## Objective
Oferecer o caminho inverso do Platform Wins: transformar o estado atual do runtime em novo Desired State — **somente** como operação humana, explícita e auditada.

## Outcome
Um `INSTANCE_ADMIN` revisa a divergência e escolhe adotar o estado observado; o Desired State passa a refletir o runtime; tudo fica auditado. Nada disso acontece automaticamente.

## References
- `docs/architecture/07-internal-control-plane.md` §8.1 (adopt como operação explícita), §24 (`POST /services/:id/adopt-runtime`)
- `docs/architecture/04-identity-teams-security.md` §7 (INSTANCE_ADMIN)
- `docs/annexes/C-threat-model-security-hardening.md` §7.2 (ações privilegiadas)

## Preconditions
`M02-06` done.

## Scope
- Operação `ADOPT_RUNTIME_STATE` sobre um recurso `DRIFTED`.
- Tela de revisão mostrando, campo a campo, o desired atual e o observado, com o que mudaria.
- Exige `INSTANCE_ADMIN` e confirmação explícita.
- Grava o novo desired state, incrementa `desiredRevision`, resolve o `DriftRecord` como `ADOPTED`.
- AuditLog detalhado com before/after sanitizado.

## Out of Scope
- Adoção de recurso **sem** ownership da plataforma — permanece proibida (doc 07 §7).
- Adoção automática por qualquer heurística.
- Adoção em massa; a operação é por recurso.
- Step-up authentication (`M03-04`) — quando existir, esta operação passa a exigi-lo; a Story registra isso como evolução prevista.

## Application Layer
- **Commands:** `AdoptRuntimeState`.
- **Policies:** exclusivamente `INSTANCE_ADMIN`.

## Async / Control Plane
Adotar altera **intenção do usuário**. Por isso é a única operação deste Milestone que escreve colunas de desired state a partir de observação — e ela **não** é um reconciler. AF-03 continua válida: nenhum reconciler faz isso; apenas este Command, disparado por humano.

## API Impact
`POST /services/:id/adopt-runtime` conceitual, retornando o recurso atualizado e o `operationId` de reconciliação subsequente.

## UI Impact
Tela de comparação lado a lado, com confirmação proporcional ao risco: em `PRODUCTION`, exige digitar o nome do recurso (doc 10 §26).

## Security Requirements
- **Somente `INSTANCE_ADMIN`.** Nem OWNER do Team pode adotar — a operação altera a fonte de verdade a partir de um estado que pode ter sido produzido por um ator não autorizado.
- Auditoria obrigatória com before/after sanitizado e o `DriftRecord` correlacionado.
- Recurso sem ownership da plataforma **não** pode ser adotado.
- A operação é registrada como ação privilegiada e aparece na visão de segurança.

## Observability Requirements
AuditLog com `action: service.runtime.adopted`, actor, `driftRecordId`, before/after sanitizado e `requestId`.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Usuário sem `INSTANCE_ADMIN` | Negado e auditado como `DENIED`. |
| Recurso sem ownership | Bloqueado com explicação; adoção não é caminho para importar workload de terceiro. |
| Estado observado mudou entre a revisão e a confirmação | Rejeitar com `CONFLICT` e reapresentar a comparação atualizada. |
| Campo observado inválido para o desired state | Bloquear a adoção daquele campo com validação; não gravar valor impossível. |
| Adoção durante operação em andamento | Serializada pelo lease; nunca concorrente. |

## Acceptance Criteria
1. `AdoptRuntimeState` existe e opera sobre um recurso `DRIFTED`.
2. A operação exige `INSTANCE_ADMIN`; OWNER e ADMIN do Team são negados, provado por teste.
3. A tela mostra a comparação campo a campo antes da confirmação.
4. Adotar grava o novo desired state, incrementa `desiredRevision` e resolve o `DriftRecord` como `ADOPTED`.
5. Recurso sem ownership da plataforma **não** pode ser adotado.
6. Estado observado alterado entre revisão e confirmação resulta em `CONFLICT` com nova comparação.
7. Valor observado inválido para o desired state é rejeitado por validação.
8. A adoção é serializada pelo lease do recurso.
9. AuditLog registra actor, `driftRecordId` e before/after sanitizado.
10. **Nenhum** caminho automático de adoção existe, verificado por teste que exercita o reconciler com drift e confirma que ele reverte em vez de adotar.
11. Em `PRODUCTION`, a confirmação exige digitar o nome do recurso.

## Required Tests
- **unit**: validação de campos adotáveis; resolução do `DriftRecord`.
- **integration**: `CONFLICT` por mudança entre revisão e confirmação; serialização por lease.
- **policy**: negado a OWNER, ADMIN, DEVELOPER e VIEWER; permitido a `INSTANCE_ADMIN`; negativo cross-team.
- **Docker/Swarm**: adoção sobre drift real; recurso sem ownership bloqueado.
- **security**: ausência de caminho automático; AuditLog completo.

## Quality Gates
Local Quality Gate + suíte Docker/Swarm + `bin/fitness` (AF-03 continua verde: nenhum reconciler escreve intenção).

## Definition of Done
Os 11 Acceptance Criteria satisfeitos, ausência de adoção automática provada, restrição a `INSTANCE_ADMIN` verificada, Critical/High = 0.
