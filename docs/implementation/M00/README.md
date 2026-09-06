---
milestone: "M00"
name: "Foundation"
type: "milestone"
status: "pending"
---

# M00 — Foundation

## Identity

| Campo | Valor |
|---|---|
| **ID** | M00 |
| **Nome** | Foundation |
| **Objetivo** | Transformar o repositório em uma base de engenharia executável, testável e governável por agentes, sem implementar nenhuma funcionalidade do domínio do Opanel. |
| **Resultado observável** | Um clone limpo sobe com um único comando documentado; `bin/gate local`, `bin/gate pre-commit` e `bin/gate post-commit` executam e falham corretamente; o CI barra merge com lint/typecheck/test/security vermelhos; as fitness functions AF-01..AF-10 rodam; `tasks.json` é validado por schema; o Swarm Lab sobe e é destruído por comando. |

## Why

Sem esta base, cada Story seguinte pagaria o custo de decidir onde o código mora, como se testa e o que significa “pronto”. Pior: o Autonomous Development Loop (Anexo H) não teria Stop Gates determinísticos e o agente poderia declarar `DONE` por inspeção visual — o failure mode nº 1 do §16 daquele anexo.

M00 desbloqueia **todos** os Milestones. Ele também é o ponto onde a stack é congelada de fato: a estrutura de diretórios criada aqui resolve o conflito SC-01 (Next.js vs Inertia) em código, não apenas em documento.

## Scope

- Aplicação Rails 8.1.x única, PostgreSQL, Solid Queue.
- Inertia + React + TypeScript + Vite + Tailwind servidos pela própria aplicação Rails.
- Importação, organização e **inventário** da biblioteca de componentes React existente.
- Ambiente local reproduzível e seeds de desenvolvimento.
- Harness de testes: RSpec + FactoryBot com PostgreSQL real; Vitest + Testing Library; Playwright; Swarm Lab descartável.
- Lint, format, typecheck, security scan e secret scan.
- CI com os gates de PR e merge do Anexo D §20 e do Anexo I §15.
- Scripts de Local Quality Gate, Pre-commit Gate e Post-commit Gate.
- Fitness functions AF-01..AF-10 executáveis (mesmo que algumas comecem vacuamente verdes).
- Infraestrutura do Autonomous Loop: schema e validador de `tasks.json`, Stop Gate, diretórios de evidence/review/report.
- Logging estruturado, `request_id`/`correlation_id`, health e readiness da própria plataforma.
- Configuração por ambiente que **falha fechado** quando inválida.
- Templates: ADR, Story Report, Milestone Report.

## Out of Scope

| Deixado para | O quê |
|---|---|
| M01 | Qualquer entidade de domínio (User, Team, Project, Environment, Service, Operation), autenticação real e acesso ao Docker. |
| M04 | Traefik, domínios e TLS. |
| M05 | GitHub App, Railpack, BuildKit e Registry. |
| M09 | Backend de métricas, logs históricos, alertas. |
| M11 | MFA, tokens de API, quotas. |
| M13 | Performance Lab, chaos e suites de segurança pesadas. |

Explicitamente **não** faz parte de M00: criar um design system novo, criar abstrações especulativas de domínio, ou instalar dependência “para usar depois”.

## Dependencies

- **Hard:** nenhuma. M00 é a raiz do grafo.
- **Soft:** biblioteca de componentes React existente (repositório `gba.dev`) para `M00-05` — ver SC-07. Se indisponível, `M00-05` fica `BLOCKED_EXTERNAL_DEPENDENCY` sem bloquear as demais Stories.

## User-visible Outcome

Nenhum usuário final. O “usuário” de M00 é o desenvolvedor e o agente:

- clona o repositório e sobe tudo com um comando documentado;
- roda a suíte inteira localmente com o mesmo comando que o CI usa;
- recebe uma falha de gate explicando **o que** falhou e **onde**, não um stack trace;
- abre `/up` e vê o health da aplicação e a readiness do banco e da fila.

## Technical Outcome

- Estrutura de diretórios congelada: `app/commands/`, `app/queries/`, `app/policies/`, `app/operations/`, `app/reconcilers/`, `app/executors/`, `app/providers/`, `app/frontend/{ui,shared,features,layouts,pages,hooks,lib,types}`.
- Migrations aplicáveis e reversíveis; `db:prepare` funciona em banco limpo.
- Solid Queue rodando com um job de exemplo observável.
- Pipeline CI com jobs separados por classe de gate, cada um com nome estável.
- `bin/` com scripts idempotentes de gate, lab e validação de pack.
- Correlation ID atravessando request → log → job.

## Architecture Impact

| Categoria | Impacto |
|---|---|
| Entities | Nenhuma entidade de domínio. Apenas tabelas de infraestrutura do Solid Queue. |
| Modules | Boundaries criados vazios com regra de dependência: `controllers → commands/queries → models`; `reconcilers → executors`; `providers` isolam APIs externas. |
| Infrastructure | Dockerfile de desenvolvimento, compose local, Swarm Lab descartável, CI. |
| UI | App shell mínimo servido por Inertia, com o inventário de componentes importado. |
| Observability | Logger estruturado JSON, `request_id`, health/readiness. |

## Security

Controles que **nascem** aqui e valem para todo o projeto:

- Secret scan em pre-commit e CI; nenhum segredo de desenvolvimento versionado.
- `bundler-audit` e auditoria de dependências npm no CI.
- Brakeman no CI (informativo em M00, bloqueante a partir de M01 para Critical/High novos).
- Configuração inválida ou incompleta **aborta o boot** — nunca cai em default permissivo (Anexo I §2, “Secure by default”).
- Fitness function AF-02 já existe e falha se qualquer arquivo fora de `app/executors/` referenciar `docker.sock` ou um cliente Docker privilegiado — mesmo antes de existir um executor.
- Nenhuma credencial de produção pode existir no workspace (Anexo H §3.2).

## Observability

Sinais mínimos exigidos ao final de M00:

- log estruturado com `timestamp`, `level`, `message`, `request_id`, `correlation_id`, `source`;
- `GET /up` com status da aplicação, do PostgreSQL e da fila, sem vazar versão/configuração sensível;
- job de exemplo que propaga `correlation_id` do request que o enfileirou;
- tempo de execução de cada gate registrado no output do CI.

## Testing

| Classe | Obrigatória em M00 |
|---|---|
| Static | Sim — lint, format, typecheck, migration validation, secret scan, dependency scan. |
| Unit | Sim — helpers de configuração, gerador de correlation ID, validador de `tasks.json`. |
| Integration | Sim — migration em banco limpo, boot com config inválida, enfileiramento e execução de job. |
| Contract | Não aplicável ainda (nenhum contrato externo). |
| Docker/Swarm | Sim — o Swarm Lab sobe, expõe uma Engine API utilizável e é destruído idempotentemente. |
| E2E | Smoke apenas — a aplicação responde e renderiza uma página Inertia. |
| Security | Sim — secret scan e dependency scan executando e falhando quando devem. |
| Performance / Chaos | Não. |

## Acceptance Criteria

1. Um clone limpo sobe com **um** comando documentado e serve uma página Inertia renderizada por React.
2. `db:prepare` funciona em banco vazio; toda migration criada é reversível ou tem forward-fix documentado.
3. Um job Solid Queue é enfileirado e executado, e o `correlation_id` do request aparece no log do job.
4. Iniciar a aplicação com configuração obrigatória ausente **falha** com mensagem acionável e código de saída diferente de zero.
5. `bin/gate local` executa format, lint, typecheck e testes relacionados, e retorna exit code 0 apenas quando todos passam.
6. `bin/gate pre-commit` executa a checklist do Anexo I §12.1 e impede o commit quando qualquer item falha.
7. `bin/gate post-commit` executa a checklist do Anexo I §14.2 e reporta objetivamente o que falhou.
8. As fitness functions AF-01..AF-10 existem, executam e são reportadas individualmente; cada uma tem um teste que prova que ela **falha** quando a regra é violada.
9. O CI reprova um PR com typecheck, lint, teste ou secret scan falhando; os jobs têm nomes estáveis referenciados pelo Merge Gate.
10. `bin/pack validate` valida todos os `tasks.json` do Implementation Pack contra o schema e falha em estado inválido.
11. O Stop Gate do Anexo H §4.2 existe, executa e devolve `ok:false` com razão objetiva quando qualquer check falha.
12. `bin/swarm-lab up` e `bin/swarm-lab down` sobem e destroem um Swarm descartável de forma idempotente; nenhum teste aponta para Docker de produção.
13. `app/frontend/components/INVENTORY.md` existe e lista os componentes importados por nome, responsabilidade, props e categoria.
14. Nenhum segredo de desenvolvimento está versionado, comprovado pelo secret scan em toda a história do branch.
15. Templates de ADR, Story Report e Milestone Report existem e são referenciados por este pack.

## Exit Gate

Claude pode mover M00 para `READY_FOR_REVIEW` quando:

- [ ] todas as Stories `required: true` estão `done` com commit registrado em `tasks.json`;
- [ ] os 15 Acceptance Criteria acima estão satisfeitos com evidência (comando + exit code) no `MILESTONE_REPORT.md`;
- [ ] `bin/gate local`, `bin/gate pre-commit`, `bin/gate post-commit` e o Stop Gate executam com exit code 0 no estado final;
- [ ] o pipeline de CI está verde em uma execução completa do branch;
- [ ] fitness functions AF-01..AF-10 verdes, cada uma com o teste negativo correspondente passando;
- [ ] `bin/pack validate` verde para os 15 Milestones;
- [ ] Critical = 0 e High = 0 no review de todas as Stories;
- [ ] nenhuma dependência foi adicionada sem justificativa registrada no Story Report (Anexo I §23.3);
- [ ] `MILESTONE_REPORT.md` gerado com evidências objetivas.

Depois disso, o orquestrador executa o review independente. Apenas
`VERDICT: ACCEPTED`, com Critical = 0 e High = 0, move `review-state.json` para
`human_acceptance`.

**Gate humano:** aceitação do ambiente de engenharia. O humano valida que o ciclo `escrever → testar → gate → commit` funciona de ponta a ponta antes de qualquer domínio ser implementado. M01 nunca começa automaticamente.
