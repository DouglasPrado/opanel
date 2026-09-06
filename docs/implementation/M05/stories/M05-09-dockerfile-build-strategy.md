# M05-09 — Dockerfile build strategy over BuildKit

## Objective
Oferecer controle total da imagem para projetos que precisam, usando o Dockerfile do repositório através de BuildKit/Buildx — com o mesmo isolamento da estratégia automática.

## Outcome
Selecionar `dockerfile` ignora a detecção automática e usa o arquivo indicado; o resultado é indistinguível para o resto do sistema: uma imagem OCI por digest.

## References
- `docs/architecture/02-build-deploy.md` §6.1 (Dockerfile como estratégia avançada), §6.2
- `docs/annexes/C-threat-model-security-hardening.md` §10 (Dockerfile é código arbitrário), T03
- `docs/annexes/D-test-strategy.md` §8

## Preconditions
`M05-07` done.

## Scope
- Estratégia `dockerfile` usando `dockerfilePath` e `rootDir` validados em `M05-02`.
- Execução via BuildKit/Buildx dentro do builder isolado.
- Multi-stage suportado; o resultado é uma imagem OCI publicável.
- Saída idêntica à do Railpack para o resto do sistema.
- Fixtures no corpus: Dockerfile simples, multi-stage, build pesado e Dockerfile que falha.

## Out of Scope
- Build args e secrets (`M05-10`).
- Publicação e digest (`M05-12`).
- Multi-arch (backlog).

## Application Layer
- **Providers:** adapter de BuildKit, isolando a API e normalizando erros.

## Security Requirements
- **Um Dockerfile é código arbitrário.** Instruções `RUN` podem baixar binários, consumir CPU, tentar acessar a rede e explorar o ambiente do builder (doc 02 §7). Todo o isolamento de `M05-07` é o que torna esta Story aceitável.
- Selecionar `dockerfile` **não** relaxa nenhum limite: os mesmos CPU/memória/pids/disco/tempo e a mesma policy de egress se aplicam.
- O Dockerfile **não** pode montar o socket do host nem diretórios sensíveis; o builder não os oferece.
- `dockerfilePath` já foi validado contra path traversal em `M05-02`; a validação é reafirmada no momento do uso.
- Nenhum secret de runtime é disponibilizado ao build.
- Erros do BuildKit são normalizados; a saída bruta é tratada como conteúdo não confiável.

## Observability Requirements
Etapas do Dockerfile visíveis na timeline com duração e status de cache. A camada que falhou é identificada.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Dockerfile inexistente no caminho | Erro claro nomeando o caminho procurado. |
| `RUN` tentando acessar rede interna | Bloqueado pela policy de egress e registrado. |
| `RUN` consumindo recursos excessivos | Morto pelos limites. |
| Build multi-stage com estágio final vazio | Erro claro; não publicar imagem inválida. |
| Instrução tentando montar socket/host path | Impossível: o builder não oferece. |
| Falha em uma camada | Identificada na timeline; logs completos e sanitizados. |

## Acceptance Criteria
1. Selecionar `dockerfile` ignora a detecção automática e usa o arquivo indicado.
2. Multi-stage funciona e produz imagem OCI publicável.
3. O resultado é indistinguível do Railpack para o resto do sistema.
4. Os mesmos limites de recurso e a mesma policy de egress do builder se aplicam, provado por fixture.
5. `RUN` tentando alcançar rede interna ou metadata é bloqueado e registrado.
6. Nenhuma instrução consegue montar o socket do host ou diretório sensível.
7. `dockerfilePath` é revalidado no uso; path traversal é rejeitado.
8. Dockerfile inexistente produz erro nomeando o caminho.
9. Estágio final vazio produz erro; nenhuma imagem inválida é publicada.
10. Nenhum secret de runtime participa do build.
11. A camada que falhou é identificada na timeline.
12. O corpus inclui Dockerfile simples, multi-stage, pesado e que falha.

## Required Tests
- **Build Lab**: cada fixture do corpus; camada que falha identificada.
- **security**: `RUN` tentando rede interna/metadata; tentativa de montar socket; path traversal no `dockerfilePath`; limites aplicados.
- **unit**: normalização de erro do BuildKit.

## Quality Gates
Local Quality Gate + Build Lab + `bin/security`.

## Definition of Done
Os 12 Acceptance Criteria satisfeitos, isolamento reafirmado por fixtures, corpus verde, Critical/High = 0.
