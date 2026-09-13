"""O banco onde os testes podem quebrar coisas.

A suíte usava o mesmo Postgres do `docker compose up`. Isso não é um detalhe de
higiene: `_drain_queue` marca todo job em andamento como `failed` e
`test_generation.py` faz `DELETE FROM pending_cards`, então rodar `pytest`
enquanto se testa o app no emulador apaga o trabalho real — inclusive uma fila
de aprovação que, no plano grátis, guarda a única geração da conta (§7.7.1).

O banco de teste é derivado do configurado com o sufixo `_test`, criado e
migrado pela própria suíte. Ninguém precisa lembrar de exportar nada, que é
justamente o modo de proteção que já falhou aqui: `DATABASE_URL` correto no CI
e esquecido na máquina de quem desenvolve.

A trava importa tanto quanto a separação. Se a derivação quebrar, a suíte se
recusa a rodar em vez de apagar dados de novo — um teste que destrói dados de
desenvolvimento falha silenciosamente no sentido que interessa: tudo passa.
"""

from __future__ import annotations

import os

from sqlalchemy import create_engine, text
from sqlalchemy.engine import make_url

# Este bloco roda antes de qualquer `import app.*`. `get_settings` é
# lru_cache-ado: se algo ler as configurações antes daqui, o engine nasce
# apontando para o banco errado e nada mais adianta.
_DEFAULT = "postgresql+psycopg://flashcards:change-me-locally@localhost:5435/flashcards"

_configured = make_url(os.environ.get("DATABASE_URL", _DEFAULT))
_name = _configured.database or ""
# Idempotente: quem já apontou para um banco de teste continua nele, em vez de
# ganhar um `flashcards_test_test`.
_TEST_DB = _name if _name.endswith("_test") else f"{_name}_test"
_test_url = _configured.set(database=_TEST_DB)

os.environ["DATABASE_URL"] = _test_url.render_as_string(hide_password=False)
# §8.1 — sem attestation para falar, e nunca produção: `validate_for_production`
# derruba o processo com os padrões de desenvolvimento, que é o certo, e um
# teste não deve depender de quem exportou o quê.
os.environ.setdefault("ENVIRONMENT", "test")


def _create_database_if_missing() -> None:
    """`CREATE DATABASE` não roda dentro de transação, daí o AUTOCOMMIT.

    A conexão é feita no banco de manutenção `postgres`, não no configurado:
    criar o banco de teste não pode depender de o banco de desenvolvimento
    existir — numa máquina limpa ele não existe.
    """
    admin = create_engine(
        _configured.set(database="postgres").render_as_string(hide_password=False),
        isolation_level="AUTOCOMMIT",
        future=True,
    )
    try:
        with admin.connect() as conn:
            exists = conn.execute(
                text("SELECT 1 FROM pg_database WHERE datname = :name"),
                {"name": _TEST_DB},
            ).scalar()
            if not exists:
                # Identificador não é parâmetro; por isso o nome vem de
                # `_configured`, do ambiente, e não de nada que um teste escreva.
                conn.execute(text(f'CREATE DATABASE "{_TEST_DB}"'))
    finally:
        admin.dispose()


def _migrate() -> None:
    """Sobe o schema com as mesmas migrações da produção.

    `Base.metadata.create_all` seria mais rápido e testaria um schema que
    ninguém roda: uma migração quebrada passaria despercebida até o deploy.
    """
    from alembic import command
    from alembic.config import Config

    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    config = Config(os.path.join(root, "alembic.ini"))
    config.set_main_option("script_location", os.path.join(root, "migrations"))
    command.upgrade(config, "head")


_create_database_if_missing()
_migrate()


def pytest_configure(config) -> None:
    """A trava. Depois desta linha, apagar tabelas é seguro."""
    from app.db import engine

    name = engine.url.database or ""
    if not name.endswith("_test"):
        raise SystemExit(
            f"recusando rodar a suíte contra o banco {name!r}: os testes apagam "
            "linhas e este não é um banco de teste"
        )


def pytest_sessionstart(session) -> None:
    """Cada execução começa do zero.

    As contas e os jobs de execuções anteriores não são inofensivos: a cota é
    uma geração por conta (§7.7), então um teste que conta gerações restantes
    lê o passado de outra execução e falha por um motivo que não é o dele.
    """
    from app.db import Base, engine

    tables = ", ".join(f'"{t.name}"' for t in Base.metadata.sorted_tables)
    if not tables:
        return
    with engine.begin() as conn:
        conn.execute(text(f"TRUNCATE {tables} RESTART IDENTITY CASCADE"))
