# Contributing

## Run the tests

```sh
createdb pggit_test
psql -d pggit_test -c 'CREATE EXTENSION IF NOT EXISTS pgcrypto; CREATE EXTENSION IF NOT EXISTS pgtap'
make install PGDATABASE=pggit_test
make test TEST_DB=pggit_test
```

CI runs the same against PostgreSQL 16 in a container.

## Propose a change

1. Open an issue describing the problem before a large change.
2. Work test-first: add or change a pgTAP test, watch it fail, make it pass.
3. Keep the plan count in each test file equal to the number of assertions.
4. Sign off commits (`git commit -s`); we use the Developer Certificate of
   Origin.

## What we will not merge

Features outside `docs/product.md`, and anything the README would claim
without a test behind it.
