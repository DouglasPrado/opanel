# Fontes de ícones

Ordem de preferência da biblioteca:

1. [Hugeicons](https://hugeicons.com/) por meio de `@hugeicons/react` e `@hugeicons/core-free-icons`
2. SVGL apenas para logos e marcas
3. Material Line Icons (Line MD) somente para animações escolhidas manualmente
4. SVG local documentado quando não houver equivalente semântico

O registro semântico padrão fica em `icons.tsx` e usa Hugeicons estáticos. Os
SVGs animados opcionais ficam incorporados em `line-md-icons.tsx`, sem
requisições de rede durante a execução.

Exceções locais:

- `logo`: SVG local da marca do projeto.
