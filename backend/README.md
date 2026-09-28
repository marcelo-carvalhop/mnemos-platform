# Backend Mnemos

Implementação de referência em FastAPI, SQLAlchemy e PostgreSQL. A API contém módulos de autenticação, sincronização, cotas, geração assistida, conta e terminal. O worker consome a fila de `generation_jobs` no banco; o Compose inclui MinIO como armazenamento de objetos para desenvolvimento. O código da API não define sozinho a interoperabilidade: consulte [os contratos públicos](../spec/README.md), [o modelo de dados](../docs/architecture/data-model.md) e [a integração T5 Touch](../docs/integration/t5-touch.md).

## Desenvolvimento local

Na raiz do repositório:

```bash
cp backend/.env.example .env
docker compose up -d postgres minio minio-init
docker compose run --rm migrate
docker compose up -d server worker
```

`/healthz` verifica liveness; `/readyz` verifica acesso ao banco. Em desenvolvimento, a documentação OpenAPI pode estar em `/docs`, conforme `ENABLE_DOCS`. O comando de migração é uma etapa separada, não uma consequência implícita do boot da API.

Para executar a suíte Python fora do contêiner, com o PostgreSQL de desenvolvimento disponível:

```bash
cd backend
python -m venv .venv
source .venv/bin/activate
pip install -e '.[dev]'
pytest
```

A suíte deriva um banco de testes próprio de `DATABASE_URL`, migra e limpa suas tabelas. Verifique as variáveis antes de executar em outra infraestrutura. A API de terminal separa bearer da conta de bearer físico; `POST /v1/terminal/reviews` atualmente rejeita o lote que `firmware/t5-touch/src/storage.cpp` produz, pois espera `reviewedAtMs` e `source` do contrato interno. O comportamento e o plano de conformidade estão em [docs/integration/t5-touch.md](../docs/integration/t5-touch.md).
