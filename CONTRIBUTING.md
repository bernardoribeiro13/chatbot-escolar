# Como contribuir

## Fluxo de branches

```text
feat/*  fix/*  chore/*  ──PR──▶  dev  ──PR──▶  main (+ tag de versão)
```

- Todo trabalho começa numa branch criada a partir de `dev`, com prefixo `feat/`, `fix/` ou `chore/`.
- A branch entra em `dev` por pull request, com o CI verde.
- Quando `dev` está pronta para uma versão, abre-se um pull request de `dev` para `main`. Depois do merge, a `main` recebe a tag da versão (`v0.1`, `v0.2`…, SemVer).
- Não há deploy automático: o projeto tem só CI, sem CD.
- Commits seguem [Conventional Commits](https://www.conventionalcommits.org/) em inglês, com escopos `api`, `bot`, `infra`, `kb` e `docs`.

## CI

O workflow [.github/workflows/ci.yml](.github/workflows/ci.yml) roda em todo pull request e todo push para `dev` e `main`. Um push novo num pull request cancela a execução anterior do mesmo PR. Cada job vira um check com o nome abaixo:

| Check            | O que verifica                                                                                                                                                                                 |
| ---------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `secrets`        | Roda o [gitleaks](https://github.com/gitleaks/gitleaks) no **histórico inteiro** do Git, procurando senhas, tokens e chaves.                                                                     |
| `shellcheck`     | Roda o [ShellCheck](https://www.shellcheck.net/) em todos os scripts `*.sh` versionados.                                                                                                          |
| `compose-config` | Copia `infra/.env.example` para `infra/.env` e valida o `infra/docker-compose.yml` com `docker compose config`.                                                                                 |
| `db-smoke`       | Depende de `compose-config`. Sobe Postgres e Redis, roda [infra/tests/check-db.sh](infra/tests/check-db.sh) e sempre derruba tudo no fim (`docker compose down -v`). Se falhar, mostra os logs. |

O que o `db-smoke` testa:

- os schemas `escolar` e `rag`, a extensão `vector` e os usuários `chatbot_admin`, `api_user` e `rag_user` existem;
- `api_user` não cria tabela em `rag`, `escolar` nem `public`, e não lê `rag`; `rag_user` não lê `escolar`;
- `api_user` e `rag_user` leem e gravam nas tabelas do próprio schema sem prefixo (via `search_path`), incluindo uma coluna `vector(3)` no `rag`;
- a senha certa do `api_user` entra e uma senha errada é recusada;
- o Redis responde `PONG`.

## pre-commit

Os mesmos tipos de verificação rodam na sua máquina antes de cada commit, via [pre-commit](https://pre-commit.com/). Os hooks estão em [.pre-commit-config.yaml](.pre-commit-config.yaml):

- gitleaks, para segredos;
- shellcheck;
- validação de YAML;
- final de arquivo e espaços sobrando;
- arquivos grandes demais;
- um bloqueio para arquivos `.env` (só o `.env.example` pode ser versionado).

Instalação (uma vez por máquina, com [uv](https://docs.astral.sh/uv/)):

```bash
uv tool install pre-commit
pre-commit install            # ativa os hooks neste repositório
```

Para rodar em todos os arquivos, sem precisar commitar:

```bash
pre-commit run --all-files
```

Na primeira execução, o pre-commit baixa as ferramentas dos hooks; o gitleaks pode levar alguns minutos.

## Testar o banco localmente

Com o Docker rodando, dentro de `infra/`:

```bash
cp .env.example .env               # só na primeira vez; troque as senhas se quiser
docker compose up -d --wait
bash tests/check-db.sh
```

O script lê usuários e senhas do `infra/.env`, mostra `OK` ou `FAIL` por verificação e termina com código diferente de zero se qualquer uma falhar. As tabelas de teste (`ci_probe`) são apagadas no fim. Para recomeçar do zero: `docker compose down -v`.
