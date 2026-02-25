.PHONY: install uninstall test unit integration lint clean

PSQL       ?= psql
PGDATABASE ?= pggit_dev
TEST_DB    ?= pggit_test

SQL_FILES := $(sort $(wildcard sql/install/*.sql))

install: $(SQL_FILES)
	$(PSQL) -d $(PGDATABASE) -v ON_ERROR_STOP=1 $(foreach f,$^,-f $(f))

uninstall:
	$(PSQL) -d $(PGDATABASE) -v ON_ERROR_STOP=1 -f sql/uninstall/0000-drop-all.sql

test: unit integration

unit:
	tools/run-pgtap.sh $(TEST_DB) test/unit

integration:
	tools/run-pgtap.sh $(TEST_DB) test/integration

lint:
	tools/lint-sql.sh sql/

clean: uninstall
