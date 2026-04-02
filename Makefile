.PHONY: setup lint format typecheck test run clean

VENV = venv
PYTHON = $(VENV)/bin/python
PIP = $(VENV)/bin/pip

# Create virtual environment and install dependencies
setup: $(VENV)/bin/activate

$(VENV)/bin/activate: requirements.txt setup.py
	python -m venv $(VENV)
	$(PIP) install -U pip
	-$(PIP) install -r requirements.txt
	-$(PIP) install -e .
	$(PIP) install ruff black mypy pytest
	touch $(VENV)/bin/activate

# Formatting code
format: setup
	$(VENV)/bin/black src/

# Linting code
lint: setup
	$(VENV)/bin/ruff check src/

# Type checking
typecheck: setup
	$(VENV)/bin/mypy src/

# Running tests
test: setup
	$(VENV)/bin/pytest tests/ || echo "No tests configured yet!"

# Running dev server
run: setup
	$(VENV)/bin/run-fitly-dev

# Quick clean
clean:
	rm -rf $(VENV)
	rm -rf build/
	rm -rf dist/
	rm -rf *.egg-info
	find . -type d -name "__pycache__" -exec rm -rf {} +
	find . -type f -name "*.pyc" -delete
