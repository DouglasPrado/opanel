# M05-13 — Build cache with per-Service namespacing and metrics

## Objective
Tornar o segundo build significativamente mais rápido que o primeiro, sem que o cache vire um canal entre projetos nem uma dependência de corretude.

## Outcome
Builds reaproveitam layers não invalidadas; o cache é namespaced por Service e por plataforma; a UI mostra bytes reutilizados e etapas em cache.

## References
- `docs/architecture/02-build-deploy.md` §8 (cache de build)
- `docs/annexes/C-threat-model-security-hardening.md` §10 (cache poisoning)
- `docs/annexes/B-nfr-slos.md` §7 (cache degrada performance, não corretude; cache não é dado crítico de backup)

## Preconditions
`M05-12` done.

## Scope
- Cache de registry compartilhado entre builders, para que o build não dependa de cair no mesmo builder.
- **Namespacing por Service** e por plataforma/arquitetura, evitando colisão e poluição entre projetos.
- Métricas de cache: bytes reutilizados, etapas em cache, duração por etapa.
- Invalidação correta: mudança de input invalida o que deve invalidar.
- GC de cache com política de tamanho e idade.
- Regra: **cache é otimização**. Perder o cache degrada performance, nunca corretude; o cache não entra no backup.

## Out of Scope
- Cache compartilhado entre Teams — explicitamente **não**: o Anexo C §10 proíbe compartilhar cache entre tenants não confiáveis.
- Cache distribuído sofisticado (backlog).

## Application Layer
- **Queries:** `BuildCacheMetrics`.
- **Jobs:** GC de cache.

## Security Requirements
- **Cache poisoning** (Anexo C §10): o cache é namespaced e invalidável; nunca compartilhado entre tenants não confiáveis. Um build de um Team não pode envenenar o cache de outro.
- A credencial de acesso ao cache de registry é escopada como a de push.
- O cache **não** guarda build secrets: o secret mount é efêmero por construção e não vira layer.
- O GC nunca remove cache em uso por um build em andamento.

## Observability Requirements
- Por build: bytes reutilizados, etapas em cache × miss, e o efeito na duração.
- Métrica agregada de hit rate por Service, para detectar invalidação excessiva.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Cache indisponível | Build **funciona**, apenas mais lento; jamais falha por ausência de cache. |
| Cache corrompido | Detectado e descartado; build refeito sem cache. |
| Mudança de input não invalidando | Defeito de corretude: teste garante que alteração relevante invalida. |
| GC durante build ativo | Cache em uso não é removido. |
| Cache crescendo sem limite | Política de tamanho/idade aplicada; alerta de disco (RB-17). |
| Tentativa de acessar cache de outro Team | Bloqueada pelo namespacing. |

## Acceptance Criteria
1. Um segundo build do mesmo Service reaproveita layers não invalidadas, com ganho mensurável.
2. O cache é namespaced por Service e por plataforma/arquitetura.
3. Um build de um Team não acessa nem envenena o cache de outro, provado por teste.
4. Cache indisponível **não** falha o build; apenas o torna mais lento.
5. Cache corrompido é detectado e descartado, e o build é refeito sem cache.
6. Alteração de input relevante invalida o cache correspondente, provado por teste.
7. Build secrets não aparecem no cache.
8. O GC respeita cache em uso por build ativo.
9. A política de tamanho e idade é aplicada, com alerta de disco.
10. Métricas de bytes reutilizados, etapas em cache e hit rate por Service estão disponíveis.
11. O cache **não** entra no backup da plataforma.

## Required Tests
- **Build Lab**: hit/miss com resultado funcional idêntico; cache indisponível; cache corrompido; invalidação por mudança de input.
- **security**: isolamento de cache entre Teams; ausência de build secret no cache.
- **integration**: GC respeitando build ativo; política de tamanho.

## Quality Gates
Local Quality Gate + Build Lab + `bin/security`.

## Definition of Done
Os 11 Acceptance Criteria satisfeitos, isolamento entre Teams provado, cache como otimização (não dependência) verificado, Critical/High = 0.
