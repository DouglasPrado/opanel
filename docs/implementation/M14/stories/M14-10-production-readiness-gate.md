# M14-10 — Production Readiness gate as an objective checklist

## Objective

Executar o gate final: cada item respondido com evidência, o resultado consolidado e o controle devolvido ao humano que decide se a plataforma vai para produção.

## Outcome

Um relatório em que ninguém precisa perguntar “mas está pronto?”, porque a resposta está item a item.

## References

- `docs/annexes/A-implementation-roadmap.md` §11 — gates por classe
- `docs/annexes/B-nfr-slos.md` §19 — gate de Production Readiness
- `docs/annexes/I-engineering-playbook-quality-gates.md`
- `docs/annexes/C-threat-model-security-hardening.md` §23, §25

## Preconditions

- `M14-01` a `M14-09` concluídas.

## Scope

Checklist consolidado, cada item com estado (`PASS`, `FAIL`, `WAIVED`, `PENDING_HUMAN`) e referência à evidência:

- **Funcional**: E2E de aceitação verde; jornadas críticas cobertas; Use Cases obrigatórios com owner.
- **Instalação e operação**: instalação limpa por operador independente; runbooks exercitados; índice por sintoma publicado.
- **Continuidade**: upgrade e rollback exercitados; DR drill com RPO/RTO dentro do alvo.
- **Segurança**: checklist de go-live completo; AF-01..AF-10 verdes; sem credencial de produção no repositório; pentest externo declarado como pendente humano.
- **Capacidade**: baseline estabelecida; pisos GA exercitados; envelope e limites publicados.
- **Resiliência**: suíte de chaos verde com invariantes preservadas; degradação documentada.
- **Observabilidade**: SLOs instrumentados e validados; error budget com política vigente.
- **Governança**: limitações e waivers declarados, nenhum vencido.
- **Release**: RC produzido com pacote de evidência imutável.

Regras do gate:

- Item sem evidência é `FAIL`. Não existe `PASS` por inspeção visual.
- `WAIVED` exige waiver válido, aprovado por humano, dentro do prazo.
- `PENDING_HUMAN` é um estado legítimo e **declarado**, nunca convertido em `PASS` pelo agente.
- Um único `FAIL` bloqueia o gate.

## Out of Scope

- **A decisão de ir para produção.** O agente produz o relatório e para. Declarar GA é ação humana.

## Security Requirements

- Nenhum item de segurança é marcado `PASS` sem evidência executada.
- O agente **não** aprova o próprio waiver.
- O relatório final não contém secret.

## Observability Requirements

- Relatório publicado com todos os itens, estados, evidências e disposições.
- Resumo executivo com: `PASS`, `FAIL`, `WAIVED`, `PENDING_HUMAN` e o que falta para GA.

## Failure Scenarios

| Cenário | Comportamento esperado |
|---|---|
| Item sem evidência marcado `PASS` | Violação de integridade do gate; **Critical**. |
| Agente declara GA | Violação do gate humano; parar. |
| Waiver vencido usado como `WAIVED` | Gate falha. |
| `PENDING_HUMAN` convertido em `PASS` | Violação; **Critical**. |
| Um `FAIL` presente | Gate bloqueado; nenhum RC promovido. |

## Acceptance Criteria

1. Todos os itens do checklist têm estado e referência à evidência.
2. Nenhum item está `PASS` sem evidência executada.
3. `WAIVED` só aparece com waiver válido, aprovado e dentro do prazo.
4. `PENDING_HUMAN` é declarado e não convertido pelo agente.
5. Um único `FAIL` bloqueia o gate, sem exceção automatizada.
6. O relatório traz o resumo executivo e o que falta para GA.
7. O relatório não contém secret.
8. O agente **não** declara GA nem promove o RC.
9. O controle é devolvido ao humano com `MILESTONE_REPORT.md` em `Status: READY_FOR_REVIEW`.

## Required Tests

- Execução do gate consolidado.
- Teste de que o gate falha quando um item fica sem evidência.

## Quality Gates

Local Quality Gate; Post-commit Gate; todos os gates de release.

## Definition of Done

- [ ] 9 Acceptance Criteria com evidência.
- [ ] Relatório de Production Readiness publicado.
- [ ] Controle devolvido ao gate humano.
- [ ] Self-review; `tasks.json` atualizado com commit.
