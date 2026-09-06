# M04-04 — Domain and DomainBinding desired state

## Objective
Modelar o hostname e sua ligação a um Service e porta como desired state, com estados derivados de verificação real.

## Outcome
Um `Domain` existe com hostname normalizado e único; um `DomainBinding` liga hostname → Service → porta, com `desiredRevision`/`appliedRevision` e estado derivado.

## References
- `docs/architecture/08-networking-domains-edge.md` §9 (modelo de roteamento), §10 (estados de domínio), §24 (estados derivados), §26 (modelo de dados)
- `docs/architecture/09-data-model-apis-contracts.md` §11.2 (Domain), §18 (`UNIQUE(normalizedHostname)`)

## Preconditions
`M04-03` done.

## Scope
- `Domain`: id, teamId, hostname normalizado (punycode), verificationState, ownershipType, timestamps.
- `DomainBinding`: id, environmentId, serviceId, servicePortId, domainId, tlsMode, desiredRevision, appliedRevision.
- Constraint `UNIQUE(normalizedHostname) WHERE status != REVOKED` — unicidade **global da instalação**.
- Normalização: lowercase, punycode, remoção de ponto final, validação de formato.
- Estados derivados do doc 08 §24: `ACTIVE`, `PENDING`, `DEGRADED`, `BLOCKED`, `FAILED`, `DISABLED`.
- Um hostname por binding como modelo default; múltiplas portas do mesmo Service podem ter hostnames distintos.

## Out of Scope
- Verificação de DNS de domínio de terceiro (`M07-02`).
- Emissão de certificado (`M04-09`).
- Path routing (doc 08 §9.1 permite, mas o default é hostname; sem requisito imediato).
- Políticas por domínio (`M07-07`).

## Domain Impact
**Entidades:** `Domain`, `DomainBinding`.
**Invariante crítica:** dois Teams **não** podem se apropriar do mesmo hostname (doc 08, teste obrigatório do Anexo D §9).

## Application Layer
- **Commands:** `CreateDomain`, `CreateDomainBinding`, `UpdateDomainBinding`, `RemoveDomainBinding`.
- **Queries:** `DomainsForEnvironment`, `DomainDetail`.
- **Policies:** `domain.create` para ADMIN/DEVELOPER conforme escopo.

## Security Requirements
- **Unicidade global de hostname**: impedir que um Team sequestre o domínio de outro é um controle de segurança, não de conveniência. A constraint fica no banco.
- Hostname é normalizado antes da checagem de unicidade — variações Unicode/punycode não podem burlar a constraint.
- Criar binding para Service de outro Team é negado sem revelar existência.
- Toda criação e remoção gera AuditLog.

## Observability Requirements
Estado derivado com o motivo; `observedAt` do último check. Nenhum estado é uma coluna escrita pela API sem verificação (doc 08 §24).

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Hostname já usado por outro Team | Rejeitado sem revelar quem o usa. |
| Variação de normalização tentando burlar a unicidade | Rejeitada; a normalização precede a checagem. |
| Binding para porta inexistente | Rejeitado por validação. |
| Binding para Service de outro Team | Negado sem revelar existência. |
| Remoção de domínio ativo | Permitida com aviso de impacto; o efeito em certificado é avaliado em `M07-05`. |
| Hostname malformado | Rejeitado com a regra explicada. |

## Acceptance Criteria
1. `Domain` e `DomainBinding` existem com os campos do doc 08 §26.
2. O hostname é normalizado (lowercase, punycode) antes de qualquer checagem.
3. `UNIQUE(normalizedHostname)` entre domínios não revogados existe no banco e é provado por caso negativo.
4. Dois Teams não conseguem se apropriar do mesmo hostname, provado por teste.
5. Variações de normalização não burlam a unicidade, provado por teste com formas equivalentes.
6. Binding para porta inexistente ou Service de outro Team é rejeitado.
7. Os estados do Domain são **derivados** de checks, não colunas escritas pela API.
8. `desiredRevision`/`appliedRevision` existem no binding.
9. Criação e remoção geram AuditLog; negativo cross-team passa.
10. Hostname malformado é rejeitado com regra explicada.

## Required Tests
- **unit**: normalização; validação de hostname; derivação de estado.
- **integration**: unicidade global; formas equivalentes de hostname; binding inválido.
- **policy**: negativo cross-team; apropriação entre Teams.

## Quality Gates
Local Quality Gate + `bin/security`.

## Definition of Done
Os 10 Acceptance Criteria satisfeitos, unicidade global e resistência a variações de normalização provadas, Critical/High = 0.
