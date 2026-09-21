# pgGit — top-level Makefile. Delegates to extension/ and cargo.

.PHONY: install uninstall test lint clean

install:
	$(MAKE) -C extension install

uninstall:
	$(MAKE) -C extension uninstall

test:
	$(MAKE) -C extension test

lint:
	$(MAKE) -C extension lint

clean:
	$(MAKE) -C extension clean
