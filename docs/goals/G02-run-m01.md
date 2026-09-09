# G02 — Execute M01 até o Pull Request

Rodar o Milestone **M01 — First Vertical Slice** de ponta a ponta, sem
supervisão, e parar com um Pull Request pronto para o humano ler.

O M01 entrega a espinha dorsal do produto: login → Team → Project → Cluster →
Environment → Service a partir de imagem OCI → Desired State → Operation → Swarm
Executor → Docker Service → healthy → logs → scale 1→3.

## Ponto de partida

- M00 em `human_acceptance`.
- `ADR-0001` e `ADR-0002` **aceitos**. Nenhum conflito de especificação aberto.
- 25 Stories. `M01-90` `done`; `M01-91` `pending` com metade do escopo já
  entregue e registrada no próprio arquivo da Story.
- `bin/gate local` em 239 s. A suíte **não é segura em paralelo** — cinco specs
  quebram com `--parallel`, e isso é o que resta da `M01-91`.

## Como executar

```sh
/backlog docs/implementation/M01
```

Uma Story por turno, na ordem que `tasks.sh next` devolver. O Stop hook conduz;
não improvise ordem.

**As duas primeiras Stories editam os próprios gates** (`M01-91`) e já editaram o
loop (`M01-90`). Ao mexer em `bin/gate*`, `lib/gates/**` ou
`tools/opanel-loop/**`, commite essa mudança sozinha, antes de qualquer Story de
domínio, e rode `tools/opanel-loop/scripts/smoke-test.sh` no mesmo turno.

## Condição de conclusão

O Goal está `READY` quando, com comando e exit code demonstrados:

1. Todas as Stories `required: true` estão `done`, cada uma com commit,
   `reports/<ID>.md` e `review/<ID>.md` com `Critical = 0` e `High = 0`.
2. `bin/stop-gate M01` devolve `ok: true`.
3. `MILESTONE_REPORT.md` existe com `Status: READY_FOR_REVIEW` e **as oito seções
   que o `lib/gates/stop_gate.rb` exige por nome**: `Stories`, `Quality`,
   `Findings`, `Resultado funcional`, `Blocked`, `Dependências novas`,
   `Conflitos de especificação`, `Human acceptance requested`. Escrever um
   relatório melhor com outros títulos reprova o gate — foi o F01 do
   `MILESTONE_REVIEW_06` do M00.
4. `/review-milestone docs/implementation/M01` foi executado e o veredito está
   gravado em `MILESTONE_REVIEW_<NN>.md`.
5. Um **Pull Request está aberto** contra `main`, com o CI verde no commit final.
6. O PR descreve honestamente o que ficou aberto — Medium, Low e qualquer
   critério não atingido.

## O Pull Request

Autorizado pelo dono do repositório neste Goal. Abrir com `gh pr create` contra
`main`, do branch de trabalho, quando 1 a 4 estiverem satisfeitos.

O corpo descreve: o que o Milestone entrega em termos observáveis, o veredito do
review com os counts, o que está aberto, e o run de CI verde amarrado ao commit
do PR. **Não** declarar aceitação: `human_acceptance` é ato humano.

Se o CI ficar vermelho por causa de infraestrutura — e isso aconteceu no M00 com
um erro de rede no `setup-ruby` — diga qual job, por quê, e se o código está
coberto por outra execução verde. Não chame de verde o que está vermelho.

## Restrições

- **Nunca** enfraquecer teste, gate, threshold, assertion, boundary ou
  acceptance criterion para obter verde. Corrigir a implementação é o caminho;
  mudar um gate exige Story ou ADR próprio.
- **Não** editar `docs/architecture/**`, os anexos, `docs/AGENT_RULES.md`,
  `bin/gate*`, `bin/stop-gate` ou `lib/gates/**` fora da Story que os declara.
- **Não** mergear o PR, não declarar `human_acceptance`, não iniciar o M02.
- Toda Story precisa de entrada em `boundaries.yml` **antes** da primeira edição.
- Sem evidência não há sucesso: comando, exit code, e o critério que ele satisfaz.
- `--no-verify` nunca é automático.

## Política de bloqueio

Três tentativas sem progresso → mudar de estratégia uma vez → `blocked` com
diagnóstico reproduzível em `BLOCKERS.md`, e seguir com Stories independentes.

Conflito com a especificação → `blocked` imediatamente, registrado em
`SPEC_CONFLICTS.md`. Nunca redesenhar em silêncio.

Duas rodadas de review sem queda em `Critical + High` → o loop **para** e chama o
humano. Não amplie orçamento para continuar: quem amplia é o humano, por
`review-state.sh budget`.

## Estado final

`READY`, `BLOCKED` ou `FAILED`. Em `READY`, o Pull Request está aberto e o run
para. A decisão de aceitar o M01 e liberar o M02 é humana.
