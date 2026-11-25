"""Convites, pela linha de comando do servidor.

    python -m app.invites criar "Turma de quinta" [--limite 30]
    python -m app.invites listar
    python -m app.invites pessoas <convite>
    python -m app.invites renomear <convite> "Novo nome"
    python -m app.invites revogar <convite>
    python -m app.invites atribuir <convite> <email> [<email> ...]
    python -m app.invites importar

<convite> é o id, o nome ou as primeiras letras do código. O código só aparece
uma vez, ao criar: o banco guarda o hash, como faz com senhas. No servidor:

    sudo docker compose exec server python -m app.invites listar
"""

from __future__ import annotations

import argparse
import secrets
import sys
from datetime import UTC, datetime

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.auth.service import invite_codes, invite_hash, invite_hint
from app.db import SessionLocal
from app.models import Invite, User

# Sem 0/O e 1/I/L: o código é ditado e digitado no celular.
ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"


def new_code() -> str:
    return "-".join("".join(secrets.choice(ALPHABET) for _ in range(4)) for _ in range(3))


def when(moment: datetime | None) -> str:
    return moment.astimezone().strftime("%d/%m/%Y %H:%M") if moment else "—"


def find(session: Session, ref: str) -> Invite:
    ref = ref.strip()
    rows = (
        session.execute(
            select(Invite).where(
                (Invite.id == ref)
                | (func.lower(Invite.label) == ref.lower())
                | (Invite.code_hint == ref.lower()[:4])
            )
        )
        .scalars()
        .all()
    )
    if len(rows) != 1:
        sys.exit(f"'{ref}' corresponde a {len(rows)} convites. Use o id (veja `listar --ids`).")
    return rows[0]


def create(session: Session, label: str, limit: int | None, code: str | None) -> None:
    code = code or new_code()
    if session.execute(select(Invite).where(Invite.code_hash == invite_hash(code))).first():
        sys.exit("Esse código já existe.")
    session.add(
        Invite(
            id=secrets.token_hex(18),
            code_hash=invite_hash(code),
            code_hint=invite_hint(code),
            label=label,
            max_uses=limit,
            created_at=datetime.now(UTC),
        )
    )
    session.commit()
    print(f"Convite criado: {label}")
    print(f"Código: {code}")
    print("Guarde o código agora: ele não aparece de novo.")


def table(session: Session, show_ids: bool) -> None:
    rows = session.execute(
        select(
            Invite,
            func.count(User.id),
            func.count(User.email_verified_at),
            func.max(User.created_at),
        )
        .outerjoin(User, User.invite_id == Invite.id)
        .group_by(Invite.id)
        .order_by(Invite.created_at)
    ).all()
    head = (
        f"{'NOME':<28} {'CÓDIGO':<8} {'CONTAS':>6} {'CONFIRM.':>8} {'LIMITE':>6}  "
        f"{'ÚLTIMA CONTA':<16}  ESTADO"
    )
    print(head + ("  ID" if show_ids else ""))
    for invite, total, confirmed, last in rows:
        state = "revogado" if invite.revoked_at else "ativo"
        limit = invite.max_uses if invite.max_uses is not None else "—"
        hint = invite.code_hint.upper() + "…"
        line = (
            f"{invite.label[:28]:<28} {hint:<8} {total:>6} {confirmed:>8} "
            f"{limit:>6}  {when(last):<16}  {state:<8}"
        )
        print(line + (f"  {invite.id}" if show_ids else ""))
    loose = session.execute(
        select(func.count())
        .select_from(User)
        .where(User.email.is_not(None), User.invite_id.is_(None))
    ).scalar_one()
    print(f"\nContas com e-mail sem convite registrado: {loose}")


def people(session: Session, ref: str) -> None:
    invite = find(session, ref)
    users = (
        session.execute(select(User).where(User.invite_id == invite.id).order_by(User.created_at))
        .scalars()
        .all()
    )
    print(f"{invite.label}: {len(users)} conta(s)")
    for user in users:
        mark = "confirmada" if user.email_verified_at else "sem confirmar"
        print(f"  {when(user.created_at)}  {user.email}  ({mark})")


def assign(session: Session, ref: str, emails: list[str]) -> None:
    invite = find(session, ref)
    for email in emails:
        user = session.execute(
            select(User).where(User.email == email.strip().lower())
        ).scalar_one_or_none()
        if user is None:
            print(f"  {email}: nenhuma conta com esse e-mail")
            continue
        user.invite_id = invite.id
        print(f"  {email} -> {invite.label}")
    session.commit()


def import_listed(session: Session) -> None:
    """Puts the INVITE_CODE codes in the table now, instead of on first use,
    so they show up in `listar` and can be renamed before anyone uses them."""
    for position, raw in enumerate(invite_codes(), start=1):
        if session.execute(select(Invite).where(Invite.code_hash == invite_hash(raw))).first():
            print(f"  nº {position} ({invite_hint(raw).upper()}…): já estava")
            continue
        session.add(
            Invite(
                id=secrets.token_hex(18),
                code_hash=invite_hash(raw),
                code_hint=invite_hint(raw),
                label=f"INVITE_CODE nº {position}",
                created_at=datetime.now(UTC),
            )
        )
        print(f"  nº {position} ({invite_hint(raw).upper()}…): importado")
    session.commit()


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(prog="python -m app.invites")
    sub = parser.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("criar", help="cria um convite e mostra o código uma vez")
    c.add_argument("nome")
    c.add_argument("--limite", type=int, default=None, help="máximo de contas")
    c.add_argument("--codigo", default=None, help="usar este código em vez de sortear")
    ls = sub.add_parser("listar", help="quantas contas vieram de cada convite")
    ls.add_argument("--ids", action="store_true")
    p = sub.add_parser("pessoas", help="as contas de um convite")
    p.add_argument("convite")
    r = sub.add_parser("renomear")
    r.add_argument("convite")
    r.add_argument("nome")
    v = sub.add_parser("revogar", help="o código para de abrir cadastro; as contas continuam")
    v.add_argument("convite")
    a = sub.add_parser("atribuir", help="liga contas existentes a um convite")
    a.add_argument("convite")
    a.add_argument("emails", nargs="+")
    sub.add_parser("importar", help="põe os códigos do INVITE_CODE na tabela")
    args = parser.parse_args(argv)

    with SessionLocal() as session:
        if args.cmd == "criar":
            create(session, args.nome, args.limite, args.codigo)
        elif args.cmd == "listar":
            table(session, args.ids)
        elif args.cmd == "pessoas":
            people(session, args.convite)
        elif args.cmd == "renomear":
            invite = find(session, args.convite)
            invite.label = args.nome
            session.commit()
            print(f"Renomeado: {args.nome}")
        elif args.cmd == "revogar":
            invite = find(session, args.convite)
            invite.revoked_at = datetime.now(UTC)
            session.commit()
            print(f"Revogado: {invite.label}. As contas que ele trouxe continuam.")
        elif args.cmd == "atribuir":
            assign(session, args.convite, args.emails)
        elif args.cmd == "importar":
            import_listed(session)


if __name__ == "__main__":
    main()
