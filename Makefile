BATS := ./tests/bats-core/bin/bats
BATS_FLAGS := --print-output-on-failure

.PHONY: test test-unit test-integration test-acceptance

test: test-unit test-integration test-acceptance

test-unit:
	$(BATS) $(BATS_FLAGS) tests/unit/

test-integration:
	$(BATS) $(BATS_FLAGS) tests/integration/

test-acceptance:
	$(BATS) $(BATS_FLAGS) tests/acceptance/
