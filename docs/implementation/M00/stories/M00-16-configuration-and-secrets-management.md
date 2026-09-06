# M00-16 — Environment configuration and development secrets management

## Objective
Definir como a aplicação recebe configuração e credenciais por ambiente, garantindo que configuração ausente ou inválida **falhe fechado** em vez de cair em default permissivo.

## Outcome
A aplicação declara sua configuração obrigatória; boot com configuração inválida aborta com mensagem acionável; nenhum segredo de desenvolvimento está versionado; nenhuma credencial de produção existe no workspace.

## References
- `docs/annexes/I-engineering-playbook-quality-gates.md` §2 (“Secure by default”)
- `docs/annexes/C-threat-model-security-hardening.md` §16 (estado interno), §17.1 (redaction)
- `docs/annexes/H-autonomous-development-loop.md` §3.2 (guardrails independentes do modo)
- `docs/annexes/A-implementation-roadmap.md` §5 M0 (“configuração inválida falhando no startup”)

## Preconditions
`M00-01` done.

## Scope
- Declaração explícita e tipada da configuração por ambiente: obrigatória vs opcional, com valor default apenas onde o default é **seguro**.
- Validação no boot: ausência ou formato inválido aborta com exit code diferente de zero e mensagem que diz **qual** chave e **o que** se esperava.
- Separação entre configuração não sensível e credencial; credencial nunca em arquivo versionado.
- Arquivo de exemplo versionado (`.env.example` ou equivalente) com todas as chaves e **nenhum valor real**.
- Guardrail de workspace: um check que falha se detectar padrão de credencial de produção no ambiente, integrado a `bin/setup` e ao Stop Gate.
- Erro de configuração passa por redaction: a mensagem diz que a chave está ausente/inválida, nunca imprime o valor recebido.

## Out of Scope
- Vault da plataforma e SecretVersion (M03) — isto é configuração **da instalação**, não secret de aplicação do usuário.
- Provider credentials (M04, M05, M10).
- Rotação de credencial (M11, RB-20).

## Security Requirements
- Ausência de configuração **nunca** abre acesso, expõe segredo ou concede privilégio (Anexo I §2).
- Nenhuma credencial de produção pode existir no workspace autônomo (Anexo H §3.2), e isso é verificado por comando, não por confiança.
- O arquivo de exemplo não contém valor real, verificado pelo secret scan.
- Mensagem de erro de configuração não imprime o valor recebido.

## Observability Requirements
A falha de boot por configuração precisa ser distinguível de qualquer outra falha de boot no log e no exit code, para que o RB-01 saiba diferenciar “regressão de versão” de “config quebrada”.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Chave obrigatória ausente | Boot aborta, exit code ≠ 0, mensagem nomeia a chave. |
| Chave presente com formato inválido | Boot aborta com o formato esperado descrito. |
| Chave opcional ausente | Usa o default **seguro** e registra em log de nível informativo. |
| Credencial de produção no workspace | `bin/setup` e `bin/stop-gate` falham. |
| Valor sensível em mensagem de erro | Redaction mascara; teste comprova. |

## Acceptance Criteria
1. A configuração obrigatória é declarada de forma tipada e centralizada.
2. Boot com chave obrigatória ausente aborta com exit code ≠ 0 e mensagem nomeando a chave.
3. Boot com valor de formato inválido aborta descrevendo o formato esperado.
4. Chave opcional ausente usa default seguro; nenhum default abre acesso ou concede privilégio.
5. Existe arquivo de exemplo versionado com todas as chaves e nenhum valor real.
6. Nenhum segredo de desenvolvimento está versionado, comprovado pelo secret scan sobre o histórico do branch.
7. O guardrail de workspace falha quando detecta padrão de credencial de produção, provado por caso negativo.
8. Mensagem de erro de configuração não imprime o valor recebido, provado por teste.
9. A falha de boot por configuração é distinguível no log de outras falhas de boot.

## Required Tests
- **unit**: validação de configuração obrigatória, opcional e de formato.
- **integration**: boot abortando em três cenários (ausente, inválida, opcional ausente com default).
- **security**: secret scan sobre o exemplo e sobre o histórico; guardrail de credencial de produção; redaction da mensagem de erro.

## Quality Gates
Local Quality Gate classe Infrastructure + secret scan de `M00-10`.

## Definition of Done
Os 9 Acceptance Criteria satisfeitos, três cenários de boot testados, guardrail provado por caso negativo, Critical/High = 0.
