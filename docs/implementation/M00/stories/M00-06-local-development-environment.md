# M00-06 — Reproducible local development environment

## Objective
Fazer um clone limpo virar um ambiente funcional com **um único comando documentado**, para humanos e para o loop autônomo.

## Outcome
`bin/setup` (ou equivalente documentado) instala dependências, prepara o banco, compila assets e deixa `bin/dev` pronto para subir web + worker + Vite juntos.

## References
- `docs/annexes/A-implementation-roadmap.md` §5 M0 (critérios de aceite)
- `docs/annexes/D-test-strategy.md` §3 (ambiente Local), §3.1 (reprodutibilidade)
- `docs/annexes/H-autonomous-development-loop.md` §12 (sandbox e isolamento)

## Preconditions
`M00-02`, `M00-03` e `M00-04` done.

## Scope
- `bin/setup`: idempotente, detecta pré-requisitos ausentes e falha com instrução acionável.
- `bin/dev`: sobe servidor web, worker do Solid Queue e Vite em um único processo supervisionado.
- Serviços locais de desenvolvimento (PostgreSQL) provisionáveis por código.
- Seeds de desenvolvimento **sintéticos** — nenhum dado real, nenhuma PII.
- `README` do repositório atualizado com o comando único, pré-requisitos e como destruir/recriar o ambiente.
- Documentação de como recriar o ambiente do zero, exigida pelo Anexo H §12.1.

## Out of Scope
- Swarm Lab (`M00-17`).
- CI (`M00-11`).
- Ambientes de staging/produção.
- Qualquer seed de domínio (não existe domínio ainda).

## Security Requirements
- Nenhuma credencial de produção pode existir no workspace (Anexo H §3.2). O setup falha se detectar variável de ambiente com padrão de credencial de produção.
- Seeds não contêm dado real, conforme Anexo D §22.
- O ambiente local não recebe acesso ao Docker socket de produção.

## Observability Requirements
`bin/dev` mostra, em um lugar só, o status dos três processos e a porta de cada um; a falha de qualquer um deles é visível imediatamente, não silenciosa.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Pré-requisito ausente (versão de Ruby, Node, PostgreSQL) | `bin/setup` falha cedo, dizendo qual pré-requisito e qual versão. |
| Porta ocupada | Erro identificando a porta e o processo, não crash genérico. |
| `bin/setup` executado duas vezes | Idempotente: segunda execução não corrompe nem duplica estado. |
| Banco já existente com schema antigo | `db:prepare` migra; se incompatível, falha com instrução de recriar. |

## Acceptance Criteria
1. Em um clone limpo, o comando único documentado leva a aplicação a servir uma página Inertia.
2. `bin/setup` é idempotente: duas execuções seguidas terminam com exit code 0 e mesmo estado.
3. `bin/dev` sobe web, worker e Vite; derrubar um deles é visível no output.
4. Seeds de desenvolvimento aplicam sem erro e não contêm dado real.
5. O `README` documenta pré-requisitos, comando único, como resetar o ambiente e como destruí-lo.
6. `bin/setup` falha com mensagem acionável quando um pré-requisito está ausente.
7. Nenhuma credencial de produção é necessária para rodar localmente; o setup falha se encontrar uma.

## Required Tests
- **integration**: execução de `bin/setup` em ambiente limpo dentro do CI; segunda execução idempotente.
- **integration**: seeds aplicam e são reexecutáveis.
- **security**: secret scan sobre seeds e configuração local.

## Quality Gates
Local Quality Gate classe Infrastructure (config validation + fixtures/lab definidos).

## Definition of Done
Os 7 Acceptance Criteria satisfeitos, `bin/setup` verde no CI em ambiente limpo, `README` completo, Critical/High = 0.
