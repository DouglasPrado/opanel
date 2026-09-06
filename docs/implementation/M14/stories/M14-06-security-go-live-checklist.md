# M14-06 — Security go-live checklist

## Objective

Executar item a item o checklist de go-live do Anexo C §23, com evidência por item — não com uma declaração de que “a segurança foi considerada”.

## Outcome

Um checklist preenchido em que cada linha aponta para um teste, um scan, um relatório ou um waiver aprovado.

## References

- `docs/annexes/C-threat-model-security-hardening.md` §23, §25
- `docs/implementation/M13/` — suítes de validação
- `docs/annexes/I-engineering-playbook-quality-gates.md` §16.2

## Preconditions

- M13 concluída: as suítes que produzem a evidência existem.

## Scope

- Execução de cada item do checklist, com o campo de evidência preenchido por referência verificável.
- Verificação dos controles de superfície: portas expostas, endpoints administrativos, headers de segurança, TLS mínimo, CORS e cookies.
- Verificação de que a Docker API não está exposta em nenhuma interface de rede.
- Verificação de que apenas o Swarm Executor referencia o socket (AF-02).
- Verificação das fitness functions AF-01..AF-10, todas verdes.
- Verificação de que não há credencial de produção no workspace nem no histórico do repositório.
- Varredura de dependências: vulnerabilidades conhecidas classificadas e tratadas ou waived.
- Revisão dos defaults: configuração ausente não abre acesso, não expõe secret, não concede privilégio.
- Confirmação de que os itens que exigem atividade humana — pentest externo, revisão independente — estão **declarados como pendentes**, não marcados como feitos.

## Out of Scope

- Executar o pentest: atividade humana externa.

## Security Requirements

- Item sem evidência é item **reprovado**; não existe aprovação por inspeção visual.
- Waiver de segurança exige risco, mitigação compensatória, dono, expiração e aprovação humana registrada.
- Nenhuma evidência do checklist contém secret.

## Observability Requirements

- Checklist publicado com estado, evidência e disposição por item.
- Lista separada dos itens pendentes de atividade humana.

## Failure Scenarios

| Cenário | Comportamento esperado |
|---|---|
| Item sem evidência | Reprovado; gate falha. |
| Docker API exposta | Finding **Critical**. |
| Credencial no histórico do repositório | Finding **Critical**; rotação imediata. |
| Fitness function vermelha | Gate falha. |
| Pentest marcado como feito sem ter ocorrido | Finding **Critical** de integridade do processo. |

## Acceptance Criteria

1. Todos os itens do Anexo C §23 são executados com evidência verificável.
2. Nenhuma porta ou endpoint administrativo está exposto indevidamente.
3. A Docker API não está acessível por rede; apenas o Swarm Executor referencia o socket.
4. AF-01..AF-10 estão verdes.
5. Não há credencial de produção no workspace nem no histórico do repositório.
6. Vulnerabilidades de dependência estão tratadas ou waived com justificativa.
7. Os defaults são seguros na ausência de configuração.
8. Waivers têm risco, mitigação, dono, expiração e aprovação humana.
9. Itens que dependem de atividade humana estão declarados como pendentes.
10. Nenhuma evidência contém secret.

## Required Tests

- Execução das suítes de M13 referenciadas pelo checklist.
- Scan de exposição de rede, de dependências e de segredos no histórico.

## Quality Gates

Local Quality Gate; AF-01..AF-10.

## Definition of Done

- [ ] 10 Acceptance Criteria com evidência.
- [ ] Checklist publicado, sem item sem evidência.
- [ ] Self-review; `tasks.json` atualizado com commit.
