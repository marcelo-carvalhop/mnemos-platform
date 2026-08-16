# Mnemos Backend

Implementação de referência do backend Mnemos, baseada em Python/FastAPI. Este código oferece contas, sincronização, registro de terminais, ingestão idempotente de reviews, geração e serviços auxiliares.

O backend oficial não define sozinho a compatibilidade Mnemos. Implementadores externos devem usar os contratos normativos de `../spec/` e a documentação de `../docs/developers/backend-implementation.md`.

Para desenvolvimento local, o fluxo recomendado parte da raiz do monorepositório:

```bash
cp backend/.env.example .env
docker compose up -d postgres minio minio-init
docker compose run --rm migrate
docker compose up -d server worker
```

Para testes Python diretos:

```bash
cd backend
python -m venv .venv
source .venv/bin/activate
pip install -e '.[dev]'
pytest
```
