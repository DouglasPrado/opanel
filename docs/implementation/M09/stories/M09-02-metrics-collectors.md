# M09-02 — Metric collectors on every node

## Objective
Coletar métricas de host, de container e do ingress próximas aos workloads, de forma independente do backend de armazenamento.

## Outcome
Cada node executa os coletores necessários; as séries chegam enriquecidas com a identidade da plataforma; trocar o backend não exige trocar os coletores.

## References
- `docs/architecture/03-runtime-observability.md` §9 (arquitetura de observabilidade), §9.1 (fontes de métricas)
- `docs/annexes/C-threat-model-security-hardening.md` §14 (exporters não públicos), doc 03 §18 (coletores privilegiados hardenizados)

## Preconditions
`M09-01` done.

## Scope
- Coletores como Services gerenciados da plataforma, em modo global: métricas de host, métricas de container e métricas do Traefik.
- Métricas do Docker/Swarm via Engine API pelo Executor: estado de nodes, Services, Tasks, réplicas desejadas × rodando, falhas.
- Enriquecimento com a identidade de `M09-01`.
- Endpoints dos exporters **não públicos**.
- Coletores tratados como componentes privilegiados: imagem mínima, permissões mínimas.
- Independência do backend: os coletores expõem/enviam dados sem conhecer o destino final.

## Out of Scope
- Backend e consultas (`M09-03`).
- Logs (`M09-05`).
- Métricas customizadas da aplicação do usuário — o contrato permite; o suporte explícito é evolução.

## Application Layer
- **Commands:** `EnsureCollectors`.
- **Reconciler:** os coletores são Services gerenciados, reconciliados como qualquer outro.

## Security Requirements
- **Exporters nunca públicos** (Anexo C §14): eles expõem informação detalhada da infraestrutura.
- Coletores que precisam de acesso ao Docker são **componentes privilegiados** e devem ser hardenizados (doc 03 §18): imagem mínima, sem shell quando possível, permissões estritas.
- O acesso ao Docker pelos coletores é **somente leitura**, e a decisão é registrada explicitamente como no caso do Traefik (`M04-01`).
- Nenhuma métrica carrega valor sensível.
- Os coletores rodam com limites de recurso, para não competir com os workloads que observam.

## Observability Requirements
Saúde dos coletores por node; lacunas de coleta visíveis. Um node sem coleta é **sinalizado**, não silenciosamente ausente.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Coletor cai em um node | Lacuna sinalizada; o node aparece sem dados recentes, não como saudável. |
| Exporter acessível externamente | Detectado como problema de configuração e reportado. |
| Coletor consumindo recursos demais | Limites aplicados; alerta. |
| Node novo | Coletor agendado automaticamente pelo modo global. |
| Engine API indisponível | Métricas de Swarm ficam indisponíveis com causa; as de host/container continuam. |

## Acceptance Criteria
1. Coletores de host, de container e de ingress rodam em modo global e são Services gerenciados.
2. As métricas do Docker/Swarm são obtidas via Executor, não por acesso direto de outro componente.
3. As séries são enriquecidas com a identidade de `M09-01`.
4. Os endpoints dos exporters **não** são acessíveis publicamente, provado por teste.
5. O acesso dos coletores ao Docker é somente leitura e está documentado.
6. Os coletores têm limites de recurso aplicados.
7. Coletor caído produz lacuna **sinalizada**; o node não aparece como saudável por ausência de dado.
8. Node novo recebe os coletores automaticamente.
9. Engine API indisponível degrada apenas as métricas de Swarm, com causa.
10. Nenhuma métrica carrega valor sensível.
11. Trocar o backend **não** exige alterar os coletores.

## Required Tests
- **Docker/Swarm**: coletores agendados em modo global; node novo recebendo; coletor caído.
- **security**: exporters não públicos; acesso somente leitura; ausência de valor sensível.
- **integration**: lacuna sinalizada; Engine API indisponível.

## Quality Gates
Local Quality Gate + suíte Docker/Swarm + `bin/security`.

## Definition of Done
Os 11 Acceptance Criteria satisfeitos, exporters privados provados, lacuna sinalizada em vez de silêncio, Critical/High = 0.
