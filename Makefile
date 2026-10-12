.PHONY: lint test-ci check
# Check Python syntax in the orchestration code.
lint:
	python -m compileall -q orchestration
# Run automated tests when a tests directory exists.
test-ci:
	python -m pytest -q
# Run both checks.
check: lint test-ci
 
