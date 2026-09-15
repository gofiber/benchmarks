## help: 💡 Display available commands
.PHONY: help
help:
	@echo '⚡️ GoFiber/Benchmarks Development:'
	@sed -n 's/^##//p' ${MAKEFILE_LIST} | column -t -s ':' |  sed -e 's/^/ /'

## compare: 📈 Compare Fiber v2 and v3 (COUNT, BENCHTIME)
.PHONY: compare
compare:
	./compare.sh

## format: 🎨 Fix code format issues
.PHONY: format
format:
	go run mvdan.cc/gofumpt@latest -w -l .

## lint: 🚨 Run lint checks
.PHONY: lint
lint:
	cd v2 && go run github.com/golangci/golangci-lint/v2/cmd/golangci-lint@v2.13.2 run ./...
	cd v3 && go run github.com/golangci/golangci-lint/v2/cmd/golangci-lint@v2.13.2 run ./...

## tidy: 📌 Clean and tidy dependencies
.PHONY: tidy
tidy:
	cd v2 && go mod tidy -v
	cd v3 && go mod tidy -v
