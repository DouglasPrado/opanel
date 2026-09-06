# M03-06 — ServiceSecretBinding with pinned versions

## Objective
Ligar um Service a uma **versão específica** de um Secret, com nome de destino e modo de injeção próprios — implementando o princípio “pinned por padrão”.

## Outcome
Um Service declara `DATABASE_URL → SecretVersion v7`; criar `v8` **não** altera esse binding; a UI mostra “nova versão disponível”.

## References
- `docs/architecture/01-foundation.md` §9.3 (bindings por Service), §9.4 (pinned por padrão)
- `docs/architecture/09-data-model-apis-contracts.md` §6.2 (ServiceSecretBinding), §27 (validação de Bind Secret)
- `docs/architecture/10-ui-use-cases.md` UC-030, §15.3, §15.4

## Preconditions
`M03-05` done.

## Scope
- `ServiceSecretBinding`: serviceId, targetName, secretVersionId, injectionMode (`SECRET_FILE` recomendado, `ENVIRONMENT` por compatibilidade).
- **Pinned por padrão**: o binding aponta para uma versão específica, nunca para “latest”.
- Um mesmo `SecretVersion` pode ser usado por múltiplos Services; cada binding tem seu `targetName`.
- Diferenciação entre o nome canônico do Secret e o nome recebido pela aplicação.
- Alterar binding muda o desired state do Service e gera Operation.
- Sinal “nova versão disponível” calculado por comparação, não por alteração automática.
- Validações do doc 09 §27: o Secret pertence ao Team permitido; a versão existe e está ativa/retida; `targetName` válido.

## Out of Scope
- Materialização no Swarm (`M03-07`).
- Promoção entre Environments (`M03-08`).
- `autoPromoteSecrets` para não-produção — o campo existe desde `M01-11`; a política automática, se vier a existir, precisa de decisão de produto e Story própria.
- Bindings no nível de Environment com herança — a especificação permite materializar no Control Plane (doc 09 §6.1), mas M03 entrega o binding por Service, que é o que o least privilege exige.

## Domain Impact
**Entidade:** `ServiceSecretBinding`.
**Invariante:** produção referencia versão específica. Criar uma versão nova **nunca** muda um binding existente automaticamente (doc 01 §9.4).

## Application Layer
- **Commands:** `BindSecretVersion`, `UnbindSecret`.
- **Queries:** `BindingsForService`, `SecretUsage` (quem usa qual versão).
- **Policies:** `vault.bind`; alterar binding em `PRODUCTION` pode exigir role mais alta conforme policy (doc 10 UC-030).

## UI Impact
Tabela “Variables & Secrets” do doc 10 §15.3: key, origem (variável simples ou Vault), versão, modo de injeção. Banner “nova versão disponível” com ação explícita de atualizar.

## Security Requirements
- **Least privilege**: cada Service recebe apenas as secrets que declara (doc 01 §9.3).
- O binding referencia a versão por ID; **nenhum** plaintext é copiado para o Service.
- Bindar um Secret de outro Team é negado e não revela a existência do Secret.
- `injectionMode: ENVIRONMENT` é permitido apenas com aviso explícito de maior exposição operacional (doc 01 §10.2).
- Alterar binding gera AuditLog com secretId e versão anterior/nova — nunca o valor.
- Versão revogada ou indisponível bloqueia o binding (doc 10 UC-030).

## Observability Requirements
- `secret.binding.changed.v1` sem valores.
- Métrica: bindings desatualizados em relação à última versão.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Nova versão criada | Binding permanece; UI mostra “nova versão disponível”. |
| Secret de outro Team | Negado sem revelar existência. |
| Versão revogada/indisponível | Bloquear o binding. |
| `targetName` duplicado no mesmo Service | Rejeitado por validação. |
| `targetName` inválido como chave de ambiente | Rejeitado. |
| Binding em `PRODUCTION` por role insuficiente | Negado conforme policy. |

## Acceptance Criteria
1. Um Service liga um `targetName` a uma `SecretVersion` específica, com modo de injeção escolhido.
2. Criar uma versão nova **não** altera o binding existente, provado por teste.
3. A UI/API sinaliza “nova versão disponível” por comparação, sem alterar nada.
4. O mesmo `SecretVersion` pode ser usado por vários Services com `targetName` diferentes.
5. Bindar Secret de outro Team é negado sem revelar a existência.
6. Versão revogada ou indisponível bloqueia o binding.
7. `targetName` duplicado no mesmo Service ou inválido como chave é rejeitado.
8. `injectionMode: ENVIRONMENT` gera aviso explícito de maior exposição.
9. Alterar binding muda o desired state e gera Operation.
10. AuditLog registra secretId e versões anterior/nova, nunca o valor.
11. A matriz de permissões de bind é testada, incluindo restrição em `PRODUCTION`.

## Required Tests
- **unit**: validação de `targetName`; cálculo de “versão desatualizada”.
- **integration**: pinning preservado ao criar nova versão; bloqueio por versão indisponível; duplicidade de `targetName`.
- **policy**: negativo cross-team; restrição em `PRODUCTION`.
- **security**: ausência de plaintext em binding, evento e audit.

## Quality Gates
Local Quality Gate + `bin/security`.

## Definition of Done
Os 11 Acceptance Criteria satisfeitos, pinning provado, ausência de plaintext verificada, Critical/High = 0.
