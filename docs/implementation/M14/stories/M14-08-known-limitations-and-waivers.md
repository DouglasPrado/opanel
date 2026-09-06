# M14-08 — Known limitations and active waivers register

## Objective

Declarar por escrito o que a plataforma não faz, o que não foi testado e o que foi aceito como risco — antes de alguém descobrir em produção.

## Outcome

Um documento em que cada limitação tem escopo, impacto, contorno e, quando aplicável, dono e prazo.

## References

- `docs/annexes/I-engineering-playbook-quality-gates.md` §16.3 — política de waiver
- `docs/annexes/D-test-strategy.md` §24.1 — waivers de teste
- `docs/annexes/C-threat-model-security-hardening.md` §24 — riscos residuais declarados
- `docs/implementation/SPEC_CONFLICTS.md`
- `docs/annexes/B-nfr-slos.md` §9, §10 — limites declarados

## Preconditions

- M13 concluída: os limites testados são conhecidos.

## Scope

- **Limitações funcionais**: capacidades ausentes do MVP, com o contorno operacional disponível.
- **Limites de escala**: os valores testados em `M13-09`, o comportamento ao ultrapassá-los e o que não foi testado — declarado como não testado, nunca como suportado.
- **Riscos residuais**: itens do modelo de ameaça aceitos, com a mitigação compensatória.
- **Waivers vigentes**: cada um com identificação, motivo, risco, mitigação, dono, data de expiração e aprovação humana.
- **Conflitos de especificação abertos**: os que permanecem em `SPEC_CONFLICTS.md`, com o impacto sobre o release.
- **Dependências externas** e o que acontece quando cada uma está indisponível.
- Regra de expiração: waiver vencido é finding no próximo gate; ele não se renova por inércia.

## Out of Scope

- Resolver as limitações: cada uma vira Story futura no backlog, não trabalho de M14.

## Security Requirements

- Waiver de segurança exige aprovação humana registrada e mitigação compensatória descrita.
- O documento não expõe detalhe explorável de uma vulnerabilidade aceita; descreve a classe e a mitigação.
- Nenhum waiver dispensa permanentemente um controle: todo waiver tem prazo.

## Observability Requirements

- Lista de waivers com data de expiração, verificável automaticamente.
- Alerta ou gate que falha quando um waiver expira sem renovação aprovada.

## Failure Scenarios

| Cenário | Comportamento esperado |
|---|---|
| Waiver sem dono ou sem prazo | Inválido; gate falha. |
| Waiver de segurança sem aprovação humana | Finding **Critical**. |
| Limite não testado descrito como suportado | Finding **High**. |
| Waiver vencido em uso | Gate falha no próximo release. |
| Detalhe explorável publicado | Finding **High**. |

## Acceptance Criteria

1. As limitações funcionais estão declaradas com escopo, impacto e contorno.
2. Os limites de escala testados são publicados; o não testado é declarado como não testado.
3. Riscos residuais aceitos estão listados com mitigação compensatória.
4. Todo waiver tem identificação, motivo, risco, mitigação, dono, expiração e aprovação humana.
5. Waiver de segurança tem aprovação humana registrada.
6. Nenhum waiver é permanente.
7. Conflitos de especificação abertos estão listados com impacto sobre o release.
8. Dependências externas e o efeito da sua indisponibilidade estão documentados.
9. Existe verificação automatizada que falha quando um waiver expira.
10. O documento não contém detalhe explorável.

## Required Tests

- Verificação automatizada de expiração e completude dos waivers.

## Quality Gates

Local Quality Gate.

## Definition of Done

- [ ] 10 Acceptance Criteria com evidência.
- [ ] Registro publicado e verificado.
- [ ] Self-review; `tasks.json` atualizado com commit.
