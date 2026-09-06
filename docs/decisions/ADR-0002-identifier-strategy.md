---
title: "ADR-0002 — Estratégia de identificadores"
status: "Proposed"
date: "2026-09-06"
decision-required-before: "M01-01"
---

# ADR-0002 — Estratégia de identificadores

**Status:** `Proposed` — exige aceitação humana **antes** da Story `M01-01-user-and-authentication`, que cria a primeira tabela.

## Context

`docs/architecture/09-data-model-apis-contracts.md` §19 exige uma decisão e não a toma:

> ID interno/exposto — “UUIDv7 ou ULID são adequados; **decisão final deve ser única para toda a plataforma**.”

O §1 do mesmo documento estabelece o princípio: “Todas as entidades usam IDs não sequenciais expostos externamente; nomes e slugs nunca são chaves primárias.”

Os exemplos espalhados pela especificação convergem para **ID prefixado por tipo**:

| Documento | Exemplos |
|---|---|
| doc 07 §7 | `team_01…`, `prj_01…`, `env_01…`, `svc_01…`, `rel_01…` |
| doc 03 §9.2 | `team_01`, `prj_albert`, `env_prod`, `svc_api`, `dep_918`, `rel_221` |
| doc 08 §5 | `cert_01HX…`, `rtr_dom_01HX…`, `vault_sv_01HX…` |
| Anexo F §9.1/§13 | `op_01…`, `apr_123`, `agc_…`, `usr_…` |

O prefixo `01HX…` é a assinatura de um ULID (timestamp Crockford Base32). Nada disso foi formalizado.

Esta decisão precisa ser tomada antes da primeira migration porque afeta a chave primária de **todas** as entidades, o formato da API pública (`/v1/teams/{teamId}/…`), as URIs de Resources do MCP (`paas://services/{service_id}`), o valor gravado nas labels do Swarm (ADR-0001) e a enumerabilidade dos recursos (Anexo C §7.3).

## Decision (proposta)

**ULID como identificador único de toda a plataforma, persistido como `char(26)` e exposto com prefixo de tipo.**

1. **Persistência.** Toda tabela de domínio usa `id char(26) PRIMARY KEY` contendo um ULID canônico (Crockford Base32, 26 caracteres, monotônico dentro do mesmo milissegundo). ULID é lexicograficamente ordenável por tempo, o que preserva localidade de índice em B-tree sem expor sequência previsível.
2. **Representação externa.** A API pública, a UI, o MCP, os eventos e as labels do Swarm usam `<prefixo>_<ulid>`, por exemplo `svc_01HX8Z9K3M4P5Q6R7S8T9V0W1X`. O prefixo é metadado de legibilidade e diagnóstico; a identidade é o ULID.
3. **Registro de prefixos.** Existe um mapa único `tipo → prefixo` no código (`usr`, `team`, `prj`, `env`, `svc`, `rel`, `art`, `bld`, `dep`, `op`, `sec`, `sv`, `dom`, `cert`, `cv`, `cl`, `node`, `enr`, `bkp`, `snap`, `rst`, `apr`, `agc`, `tok`, `inc`, `alr`). Adicionar um tipo novo obriga registrar o prefixo; prefixo duplicado é erro de boot.
4. **Validação de entrada.** Um ID recebido com prefixo de tipo diferente do esperado é `VALIDATION_ERROR`, não `NOT_FOUND`. Isso impede confusão de tipo, mas **não substitui autorização** — a checagem de tenancy do Anexo C §7.3 continua obrigatória e independente.
5. **Slugs.** Continuam humanos, mutáveis e **nunca** referenciados por foreign key (doc 09 §19). Rotas amigáveis resolvem slug → ID dentro do boundary de tenancy.
6. **Revisions.** Ortogonal a este ADR: `revision` continua `bigint` monotônico por recurso (doc 09 §19), e `SecretVersion.versionNumber` continua inteiro monotônico por Secret.

## Consequences

**Positivas**
- Um único formato para banco, API, eventos, labels e MCP — nenhuma tradução entre representações.
- Coerente com todos os exemplos já escritos na especificação; nenhum documento precisa ser corrigido.
- Ordenação temporal natural: paginação por cursor keyset (doc 09 §20) e índices `(teamId, createdAt DESC)` ficam eficientes.
- Prefixo torna log, audit e suporte legíveis sem consultar o schema.
- IDs gerados na aplicação: uma transação pode montar o grafo completo (Service + Operation + OutboxEvent) sem round-trip ao banco, o que importa para o boundary transacional do doc 09 §24.

**Negativas / custo**
- `char(26)` ocupa 26 bytes contra 16 de `uuid` nativo. Em `audit_events` e `operations` — as tabelas de maior volume, com piso de teste de 1.000.000 e 250.000 linhas (Anexo B §9.1) — isso é mensurável, embora pequeno em termos absolutos.
- ULID não é tipo nativo do PostgreSQL: ordenação, validação e geração ficam na aplicação.
- ULID codifica o timestamp de criação. Isso vaza *quando* um recurso foi criado para quem já está autorizado a vê-lo. Não é considerado risco relevante porque `createdAt` já é exposto na API; mas é registrado explicitamente.

## Alternatives considered

| Alternativa | Avaliação |
|---|---|
| **UUIDv7 em coluna `uuid` nativa** | Tecnicamente muito próximo: também é time-ordered e ocupa 16 bytes com suporte nativo. **Rejeitado por coerência**: exigiria uma segunda representação para os IDs prefixados que a especificação inteira já usa, ou abandonar os prefixos e reescrever exemplos em 5 documentos. Se o custo de armazenamento se provar relevante nos testes de piso GA (`M13-09`), um ADR posterior pode migrar — a decisão fica localizada no gerador de IDs. |
| **UUIDv4** | Rejeitado. Aleatório puro fragmenta índices B-tree em tabelas de alto volume e não oferece a ordenação temporal que a paginação por cursor aproveita. |
| **BIGSERIAL com hashid na borda** | Rejeitado. Viola o doc 09 §1 (“IDs não sequenciais expostos externamente”) e cria duas identidades para o mesmo recurso, exatamente o que este ADR quer evitar. |
| **Prefixo persistido junto com o ULID (`char(30)`)** | Rejeitado. Duplica no dado uma informação que a coluna/tabela já determina, e torna o custo de armazenamento pior sem ganho. |

## Affected docs

- `docs/architecture/09-data-model-apis-contracts.md` §19 (fecha a decisão em aberto)
- `docs/implementation/SPEC_CONFLICTS.md` SC-08

## Affected modules

Todas as migrations, todos os serializers, o roteamento da API pública, as URIs de Resources do MCP, as labels de ownership (ADR-0001), a paginação por cursor e os helpers de teste/factories.
