# chatbot-escolar

[![CI](https://github.com/bernardoribeiro13/chatbot-escolar/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/bernardoribeiro13/chatbot-escolar/actions/workflows/ci.yml)

> ⚠️ **Aviso:** este é um projeto **fictício**, criado para fins de estudo. Ele **não usa dados reais** de nenhuma escola, aluno, responsável ou funcionário.

TODO

## O que o sistema faz

TODO

## Arquitetura

TODO

## Stack

TODO

## Como rodar

TODO

## Estrutura de pastas

```text
chatbot-escolar/
├── api/              # futuro Django + DRF
├── bot/              # futuro FastAPI
├── infra/            # futuro docker-compose: Postgres e Redis
├── knowledge-base/   # documentos fictícios do colégio para o RAG
├── docs/             # requisitos, ADRs, glossário, diagramas
└── .github/
    └── pull_request_template.md
```

## Convenções

- **Fluxo de trabalho:** GitHub Flow. A branch `main` é protegida; todo trabalho acontece em branches com prefixo `feat/`, `fix/`, `docs/`, `chore/` ou `test/` e entra via pull request.
- **Commits:** Conventional Commits, com escopos `api`, `bot`, `infra`, `kb` e `docs`.
- **Versionamento:** SemVer, com tags `v0.1`, `v0.2` etc. por incremento.
- **Python:** [uv](https://docs.astral.sh/uv/) para dependências e ambientes, [Ruff](https://docs.astral.sh/ruff/) para lint e formatação, e pytest para testes.
- **Idioma:** commits e código técnico em inglês; nomes de domínio em português; documentação em PT-BR.

## Roadmap por incrementos

TODO

## Licença

TODO
