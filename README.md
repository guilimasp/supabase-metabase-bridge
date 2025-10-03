# Local Metabase + Supabase

Simple setup for running Metabase locally connected to your Supabase Postgres database.

**Built for myself** - feel free to use if you need the same thing.

## Quick Start

1. Copy `.env.example` to `.env` and fill in your values
2. `docker compose up -d`
3. `bash scripts/metabase-setup.sh`
4. Open http://localhost:3000

## Prerequisites

- Docker & Docker Compose
- `curl` and `jq` (install with `brew install curl jq`)

## Environment Variables

See `.env.example` for all required variables:

- **MB_ENCRYPTION_SECRET_KEY**: Strong key (min 16 chars) - **never commit this**
- **SUPABASE_DB_***: Your Supabase Postgres credentials
- **MB_ADMIN_***: Admin user for Metabase

## Supabase Setup

1. Create a **readonly user** (avoid `postgres`/`service_role`)
2. Grant access only to needed schemas/tables
3. Use direct connection (port 5432) or session pooling

## Important Notes

- **Local/self-hosted** - no pre-built dashboards
- Credentials stored in `.env` (not committed)
- H2 database for Metabase metadata (fine for local dev)
- Automatic daily sync (Metabase default)

## Troubleshooting

- Check logs: `docker compose logs metabase`
- Restart: `docker compose restart`
- Reset: `docker compose down -v && docker compose up -d`