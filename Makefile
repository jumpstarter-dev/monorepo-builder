.PHONY: help build push build-push clean

help:
	@echo "Monorepo Builder - Available targets:"
	@echo ""
	@echo "  make build       - Build the monorepo from source repositories"
	@echo "  make push        - Force push main and release branches to origin"
	@echo "  make build-push  - Build and push in one command"
	@echo "  make clean       - Remove generated monorepo and temp directories"
	@echo "  make help        - Show this help message"
	@echo ""

build:
	@echo "Building monorepo..."
	./build-monorepo.sh

push:
	@echo "Pushing monorepo branches to origin..."
	@if [ ! -d "monorepo/.git" ]; then \
		echo "Error: monorepo directory does not exist. Run 'make build' first."; \
		exit 1; \
	fi
	@echo "Pushing main branch..."
	cd monorepo && git push -f --set-upstream origin main
	@echo "Pushing release branches..."
	cd monorepo && git push -f origin release-0.5 release-0.6 release-0.7

build-push: build push
	@echo "Build and push complete!"

clean:
	@echo "Cleaning up..."
	rm -rf monorepo temp
	@echo "Clean complete!"
