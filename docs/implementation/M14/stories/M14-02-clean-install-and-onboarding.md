# M14-02 — Clean install and onboarding by an independent operator

## Objective

Provar que a plataforma pode ser instalada e colocada em uso a partir da documentação, por alguém que não a construiu.

## Outcome

Um registro honesto do que travou, quanto tempo levou e o que a documentação não dizia — seguido da correção.

## References

- `docs/architecture/01-foundation.md` — bootstrap e instalação
- `docs/annexes/E-operational-runbooks.md` — instalação e onboarding
- `docs/annexes/D-test-strategy.md` §19, §21

## Preconditions

- Infraestrutura limpa disponível.
- **Um operador que não participou da implementação** — condição essencial, não conveniência.

## Scope

- Instalação do zero em host novo, seguindo apenas a documentação publicada.
- Bootstrap: primeiro administrador, geração e custódia da Recovery Key, verificação da chave.
- Onboarding: primeiro Team, Project, Environment e primeiro Service no ar.
- Cronometragem de cada etapa e registro de **todo** ponto de fricção, dúvida ou passo ausente.
- Verificação de que os defaults são seguros: nada aberto por omissão, nenhuma senha padrão, nenhum serviço exposto sem intenção.
- Verificação de pré-requisitos: a documentação declara versões, portas, recursos e permissões necessárias.
- Correção da documentação e do instalador com base no exercício; **reexecução** para confirmar.
- Registro do resultado como evidência do gate.

## Out of Scope

- Upgrade: `M14-03`.

## Security Requirements

- A Recovery Key é entregue uma vez, custodiada pelo operador e verificada; ela não é persistida de forma recuperável.
- Nenhuma credencial de produção é usada; o exercício usa infraestrutura de teste.
- Após a instalação, o scan confirma que nenhuma porta administrativa está exposta indevidamente.

## Observability Requirements

- Relatório: etapas, tempos, obstáculos, correções aplicadas e resultado da reexecução.
- Estado final verificado por health checks, não por inspeção manual.

## Failure Scenarios

| Cenário | Comportamento esperado |
|---|---|
| Passo ausente na documentação | Registrado, corrigido e reexecutado. |
| Operador precisa perguntar a quem implementou | Finding: a documentação está incompleta. |
| Default inseguro | Finding **Critical**. |
| Porta administrativa exposta | Finding **Critical**. |
| Recovery Key recuperável do sistema | Finding **Critical**. |

## Acceptance Criteria

1. A instalação é executada por um operador que não participou da implementação.
2. Apenas a documentação publicada é usada; consultas ao time viram findings.
3. O bootstrap gera e verifica a Recovery Key, sem persistência recuperável.
4. O onboarding chega a um Service no ar.
5. Todos os pontos de fricção são registrados com tempo.
6. Nenhum default inseguro é encontrado; nenhuma porta administrativa exposta.
7. A documentação e o instalador são corrigidos com base no exercício.
8. A reexecução após as correções ocorre sem obstáculos bloqueantes.
9. O relatório é arquivado como evidência do gate.

## Required Tests

- Instalação automatizada em infraestrutura limpa (teste de fumaça).
- Verificação de exposição de portas e defaults.

## Quality Gates

Local Quality Gate.

## Definition of Done

- [ ] 9 Acceptance Criteria com evidência.
- [ ] Reexecução limpa demonstrada.
- [ ] Self-review; `tasks.json` atualizado com commit.
