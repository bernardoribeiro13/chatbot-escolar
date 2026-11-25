# infra: ambiente local de banco de dados

Ambiente de desenvolvimento local com dois contêineres, orquestrados por Docker Compose:

| Serviço    | Imagem                   | Contêiner          | Para quê                                                    |
| ---------- | ------------------------ | ------------------ | ----------------------------------------------------------- |
| `postgres` | `pgvector/pgvector:pg16` | `chatbot-postgres` | PostgreSQL 16 com pgvector; schemas `escolar` (API) e `rag` |
| `redis`    | `redis:7-alpine`         | `chatbot-redis`    | Estado da conversa do bot (sem persistência em disco)       |

> ⚠️ **As senhas deste ambiente servem só para desenvolvimento local.** Não reutilize em nenhum outro ambiente. As portas são publicadas apenas em `127.0.0.1`, então nada fica exposto na rede.

## Pré-requisitos

- [Docker](https://docs.docker.com/get-docker/) (no Windows e no macOS, o Docker Desktop precisa estar aberto)
- Docker Compose v2 (o comando `docker compose`, já incluso no Docker Desktop)

Todos os comandos abaixo são executados **dentro da pasta `infra/`**.

## Configuração

Copie o arquivo de exemplo e troque as três senhas:

```bash
cp .env.example .env
```

| Variável            | Uso                                                        |
| ------------------- | ---------------------------------------------------------- |
| `POSTGRES_DB`       | Nome do banco (padrão `chatbot`)                           |
| `POSTGRES_USER`     | Usuário administrador e de migração (padrão `chatbot_admin`) |
| `POSTGRES_PASSWORD` | Senha do administrador                                     |
| `API_DB_PASSWORD`   | Senha do `api_user`                                        |
| `RAG_DB_PASSWORD`   | Senha do `rag_user`                                        |
| `DB_PORT`           | Porta do Postgres no host (padrão `5432`)                  |
| `REDIS_PORT`        | Porta do Redis no host (padrão `6379`)                     |

O `infra/.env` é ignorado pelo Git e **nunca deve ser commitado**.

> As senhas são lidas **só na primeira inicialização**, quando o volume está vazio. Se trocar uma senha no `.env` depois disso, recrie o ambiente com `docker compose down -v` (ver abaixo).

## Uso

```bash
docker compose up -d        # sobe os dois serviços em segundo plano
docker compose ps           # status; espere os dois ficarem "healthy"
docker compose logs -f postgres   # logs (Ctrl+C para sair); troque por "redis" se quiser
docker compose down         # para e remove os contêineres, MANTENDO os dados
```

### Recriar do zero

```bash
docker compose down -v
docker compose up -d
```

O `-v` apaga o volume `pgdata`, ou seja, **todos os dados do banco**. Com o volume vazio, o Postgres roda de novo o script [postgres/init/01-init.sh](postgres/init/01-init.sh), que cria a extensão, os schemas e os usuários. Esse script **só roda com o volume vazio**: um `docker compose up -d` comum, com dados existentes, não executa nada.

O Redis não grava nada em disco, então o estado da conversa some sempre que o contêiner é recriado.

## Usuários do banco

| Usuário         | Para quem               | O que pode fazer                                                                                          |
| --------------- | ----------------------- | --------------------------------------------------------------------------------------------------------- |
| `chatbot_admin` | Migrações e administração | Superusuário. Cria e altera tabelas em `escolar` e `rag`.                                               |
| `api_user`      | API (Django)            | `SELECT`, `INSERT`, `UPDATE`, `DELETE` nas tabelas de `escolar`. `search_path = escolar`. Não cria tabelas e não acessa `rag`. |
| `rag_user`      | Bot / RAG               | `SELECT`, `INSERT`, `UPDATE`, `DELETE` nas tabelas de `rag`. `search_path = rag, public` (o tipo `vector` fica em `public`). Não cria tabelas e não acessa `escolar`. |

As permissões dos usuários de aplicação valem para as tabelas e sequências **criadas pelo `chatbot_admin`** (privilégios padrão, `ALTER DEFAULT PRIVILEGES`). Por isso as migrações devem rodar sempre como `chatbot_admin`.

## Como conectar

| Campo   | Valor                                       |
| ------- | ------------------------------------------- |
| Host    | `localhost`                                 |
| Porta   | `DB_PORT` (padrão `5432`)                   |
| Banco   | `POSTGRES_DB` (padrão `chatbot`)            |
| Usuário | `chatbot_admin`, `api_user` ou `rag_user`   |
| Senha   | a do `.env` correspondente                  |

Exemplos de URL (com os valores padrão):

```text
postgresql://api_user:<senha>@localhost:5432/chatbot
postgresql://rag_user:<senha>@localhost:5432/chatbot
redis://localhost:6379/0
```

Não é preciso ter `psql` ou `redis-cli` instalados: dá para usar os que vêm dentro dos contêineres.

```bash
# Shell psql como administrador
docker compose exec postgres psql -U chatbot_admin -d chatbot

# Dentro do psql:
#   \dn   lista os schemas (deve mostrar escolar e rag)
#   \dx   lista as extensões (deve mostrar vector)
#   \du   lista os usuários (chatbot_admin, api_user, rag_user)

# Conectar como usuário de aplicação (sem pedir senha, ver aviso abaixo)
docker compose exec postgres psql -U api_user -d chatbot

# Testar a senha de verdade: conecta a partir de outro contêiner na mesma rede
docker run --rm -it --network chatbot-escolar_default pgvector/pgvector:pg16 \
  psql -h postgres -U api_user -d chatbot

# Redis
docker compose exec redis redis-cli ping   # responde PONG
```

> **Aviso:** a imagem do Postgres confia em qualquer conexão feita de dentro do próprio contêiner (socket local e `127.0.0.1`), então `docker compose exec ... psql` **não pede senha**, nem com `-h localhost`. Conexões vindas de fora do contêiner (outros contêineres, ou o seu computador pela porta publicada) exigem senha (`scram-sha-256`).
