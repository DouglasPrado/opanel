# M14-09 — Release process and evidence packaging

## Objective

Definir e executar o processo que transforma um commit em Release Candidate, com toda a evidência empacotada e recuperável meses depois.

## Outcome

Um Release Candidate que se explica sozinho: o que é, do que veio, o que foi testado e com que resultado.

## References

- `docs/annexes/I-engineering-playbook-quality-gates.md` §12, §14, §15.2
- `docs/annexes/D-test-strategy.md` §20, §24
- `docs/implementation/M06/` — imutabilidade por digest

## Preconditions

- `M14-01` verde; suítes de M13 disponíveis.

## Scope

- Pipeline de Release Candidate consolidando: gates locais, suítes de segurança, performance com comparação de baseline, chaos, upgrade, E2E de aceitação e fitness functions.
- Identificação do RC: commit, versão, digests dos artefatos produzidos e data.
- **Pacote de evidência**: relatórios de cada suíte com a metadata obrigatória, checklist de segurança, registro de limitações e waivers, resultado dos exercícios operacionais.
- Índice do pacote: cada item do gate aponta para a evidência correspondente.
- Imutabilidade: o pacote é versionado e associado ao commit; ele não é editado depois — uma correção gera um novo RC.
- Reprodutibilidade: o processo é executável novamente e produz os mesmos artefatos a partir do mesmo commit.
- Notas de release geradas a partir do que efetivamente entrou, não de uma lista mantida à mão.
- Critério de promoção do RC: quais gates precisam estar verdes e quem decide.

## Out of Scope

- Publicar a release ao público: decisão humana, fora do escopo autônomo.

## Security Requirements

- O pacote de evidência não contém secret, credencial nem dado real de cliente.
- Artefatos são referenciados por digest imutável, nunca por tag mutável.
- A geração do pacote não usa credencial de produção.

## Observability Requirements

- Painel do RC: cada gate com estado, duração e link para a evidência.
- Histórico comparável entre RCs sucessivos.

## Failure Scenarios

| Cenário | Comportamento esperado |
|---|---|
| Gate sem evidência no pacote | RC inválido. |
| Pacote editado após a criação | Violação de imutabilidade; novo RC obrigatório. |
| Artefato referenciado por tag | Finding **High**. |
| Secret no pacote de evidência | Finding **Critical**. |
| Processo não reproduzível | Finding **High**. |

## Acceptance Criteria

1. O pipeline de RC consolida todos os gates listados.
2. O RC é identificado por commit, versão, digests e data.
3. O pacote de evidência contém os relatórios com metadata completa.
4. Cada item do gate aponta para a sua evidência no índice.
5. O pacote é imutável; correção gera novo RC.
6. O processo é reproduzível a partir do mesmo commit.
7. As notas de release são geradas a partir do que entrou.
8. Artefatos são referenciados por digest, nunca por tag.
9. O pacote não contém secret nem dado real.
10. O critério de promoção e o decisor estão declarados.

## Required Tests

- Execução completa do pipeline de RC.
- Verificação de imutabilidade e de ausência de secret no pacote.

## Quality Gates

Local Quality Gate; Post-commit Gate; fitness functions.

## Definition of Done

- [ ] 10 Acceptance Criteria com evidência.
- [ ] Um RC produzido e arquivado.
- [ ] Self-review; `tasks.json` atualizado com commit.
