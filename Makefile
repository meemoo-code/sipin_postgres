.RECIPEPREFIX = >
MAKEFLAGS += --no-builtin-rules

PSQL := psql
PSQL_FLAGS  := -v ON_ERROR_STOP=1
PG_INIT := postgres://postgres:postgres@localhost
PG_DB := borndigital
PG_CONNINFO := $(PG_INIT)/$(PG_DB)

.PHONY: all database setup
.PHONY: create_table-%

all: test

setup: create_table-sipin_sip_deliveries

database:
> @$(PSQL) --command "DROP DATABASE IF EXISTS $(PG_DB)" $(PG_INIT)
> @$(PSQL) --command "CREATE DATABASE $(PG_DB)" $(PG_INIT)

create_table-%: tables/%.ddl
> @echo creating $* using $<
> @$(PSQL) --file=$< $(PG_CONNINFO)

repl:
> @$(PSQL) $(PG_CONNINFO)
