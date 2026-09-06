# M10-12 — Environment restore from snapshot

## Objective
Recriar um Environment a partir de um snapshot lógico, preferindo criar um clone paralelo a sobrescrever produção.

## Outcome
O operador escolhe um snapshot e um cluster alvo; a plataforma resolve `SecretVersion` e digests, recria networks, services e domains, e valida health.

## References
- `docs/architecture/05-backup-restore-dr.md` §14.2 (restaurar configuração de Environment), §13.2 (restore seguro por padrão)
- `docs/architecture/10-ui-use-cases.md` UC-038, §19.3
- `docs/architecture/09-data-model-apis-contracts.md` §14

## Preconditions
`M10-09` e `M10-11` done.

## Scope
- Fluxo do doc 05 §14.2: snapshot → escolher cluster alvo → resolver `SecretVersion` → resolver digests → criar networks/services/domains → validar health.
- **Preferência por Environment clone**, em vez de sobrescrever o existente (doc 05 §13.2).
- Sobrescrita como caminho explícito, com confirmação reforçada.
- Validação prévia: `SecretVersion` disponíveis, digests presentes no Registry, capacidade no cluster alvo.
- Diferenciação explícita na UI entre “restaurar configuração” e “restaurar dados gerenciados externos” — o segundo **não** existe.

## Out of Scope
- Clean Rebuild da instalação inteira (`M10-13`).
- Restauração de dados de aplicação — fora do escopo.
- Migração de Environment entre clusters como feature de produto (UC-011) — `M10-18`.

## Application Layer
- **Commands:** `RestoreEnvironmentSnapshot`.
- **Queries:** `RestoreEligibility`.

## Security Requirements
- **Preferir clone a sobrescrita** (doc 05 §13.2): sobrescrever produção a partir de um snapshot é a operação mais perigosa deste Milestone.
- Sobrescrita exige step-up e confirmação com digitação do nome.
- `SecretVersion` são **resolvidas**, não copiadas: a auditoria e o versionamento são preservados (doc 05 §9.3).
- Digest ausente no Registry **bloqueia antes** de criar qualquer recurso.
- Restaurar não pode conceder acesso a secrets de outro Team: o snapshot e o alvo pertencem ao mesmo Team.
- Cada restore gera AuditLog com snapshot, alvo e modo (clone × sobrescrita).

## Observability Requirements
Progresso por recurso recriado; validação de health ao final; o que não pôde ser restaurado e por quê.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| `SecretVersion` indisponível | Bloquear antes de criar recursos. |
| Digest ausente no Registry | Bloquear antes; informar qual artefato falta. |
| Capacidade insuficiente no cluster alvo | Avisar antes; permitir escolher outro cluster. |
| Domínio já em uso | Conflito de unicidade global: bloquear com explicação; no modo clone, oferecer domínio alternativo. |
| Sobrescrita de produção | Step-up + confirmação por digitação. |
| Falha parcial | Estado registrado; recursos criados ficam identificáveis. |

## Acceptance Criteria
1. O restore de snapshot recria networks, services, domains e configuração no cluster alvo.
2. O padrão é criar um **Environment clone**; sobrescrever é caminho explícito.
3. Sobrescrita exige step-up e confirmação por digitação do nome.
4. `SecretVersion` são resolvidas por ID, **não** copiadas.
5. `SecretVersion` indisponível bloqueia **antes** de criar recursos.
6. Digest ausente no Registry bloqueia antes e informa qual artefato falta.
7. Capacidade insuficiente é avisada antes, com opção de outro cluster.
8. Conflito de domínio é bloqueado com explicação; no modo clone, um alternativo é oferecido.
9. A UI diferencia “restaurar configuração” de dados gerenciados externos, que **não** são restaurados.
10. Falha parcial registra o estado e mantém os recursos criados identificáveis.
11. O health é validado ao final; o que não pôde ser restaurado é listado.
12. O restore gera AuditLog com snapshot, alvo e modo; negativo cross-team passa.

## Required Tests
- **Docker/Swarm**: restore criando networks e services reais; health validado.
- **integration**: `SecretVersion` indisponível; digest ausente; conflito de domínio; falha parcial.
- **policy**: step-up para sobrescrita; negativo cross-team.
- **E2E**: restaurar um Environment como clone e verificar que ele responde.

## Quality Gates
Local Quality Gate + suíte Docker/Swarm + E2E + `bin/security`.

## Definition of Done
Os 12 Acceptance Criteria satisfeitos, clone como padrão provado, bloqueios prévios verificados, Critical/High = 0.
