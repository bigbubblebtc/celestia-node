SHELL=/usr/bin/env bash
PROJECTNAME=$(shell basename "$(PWD)")
DIR_FULLPATH=$(shell pwd)
versioningPath := "github.com/celestiaorg/celestia-node/nodebuilder/node"
LDFLAGS=-ldflags="-X '$(versioningPath).buildTime=$(shell date)' -X '$(versioningPath).lastCommit=$(shell git rev-parse HEAD)' -X '$(versioningPath).semanticVersion=$(shell git describe --tags --dirty=-dev 2>/dev/null || git rev-parse --abbrev-ref HEAD)'"
ifeq (${PREFIX},)
	PREFIX := /usr/local
endif
ifeq ($(ENABLE_VERBOSE),true)
	LOG_AND_FILTER = | tee debug.log
	VERBOSE = -v
else
	VERBOSE =
	LOG_AND_FILTER =
endif
## help: Get more info on make commands.
help: Makefile
	@echo " Choose a command run in "$(PROJECTNAME)":"
	@sed -n 's/^##//p' $< | column -t -s ':' |  sed -e 's/^/ /'
.PHONY: help

## install-hooks: Install git-hooks from .githooks directory.
install-hooks:
	@echo "--> Installing git hooks"
	@git config core.hooksPath .githooks
.PHONY: install-hooks

## build: Build celestia-node binary.
build:
	@echo "--> Building Celestia"
	@go build -o build/ ${LDFLAGS} ./cmd/celestia
.PHONY: build

## clean: Clean up celestia-node binary.
clean:
	@echo "--> Cleaning up ./build"
	@rm -rf build/*
.PHONY: clean

## cover: generate to code coverage report.
cover:
	@echo "--> Generating Code Coverage"
	@go install github.com/ory/go-acc@latest
	@go-acc -o coverage.txt `go list ./... | grep -v nodebuilder/tests` -- -v
.PHONY: cover

## deps: install dependencies.
deps:
	@echo "--> Installing Dependencies"
	@go mod download
.PHONY: deps

## install: Install all build binaries into the $PREFIX (/usr/local/ by default) directory.
install:
	@echo "--> Installing Celestia"
	@install -v ./build/* -t ${PREFIX}/bin/
.PHONY: install

## go-install: Build and install the celestia-node binary into the GOBIN directory.
go-install:
	@echo "--> Installing Celestia"
	@go install ${LDFLAGS} ./cmd/celestia
.PHONY: go-install

## cel-shed: Build cel-shed binary.
cel-shed:
	@echo "--> Building cel-shed"
	@go build ./cmd/cel-shed
.PHONY: cel-shed

## install-shed: Build and install the cel-shed binary into the GOBIN directory.
install-shed:
	@echo "--> Installing cel-shed"
	@go install ./cmd/cel-shed
.PHONY: install-shed

## cel-key: Build cel-key binary.
cel-key:
	@echo "--> Building cel-key"
	@go build ./cmd/cel-key
.PHONY: cel-key

## install-key: Build and install the cel-key binary into the GOBIN directory.
install-key:
	@echo "--> Installing cel-key"
	@go install ./cmd/cel-key
.PHONY: install-key

## fmt: Formats only *.go (excluding *.pb.go *pb_test.go). Runs `gofmt & goimports` internally.
fmt: sort-imports
	@find . -name '*.go' -type f -not -path "*.git*" -not -name '*.pb.go' -not -name '*pb_test.go' | xargs gofmt -w -s
	@find . -name '*.go' -type f -not -path "*.git*"  -not -name '*.pb.go' -not -name '*pb_test.go' | xargs goimports -w -local github.com/celestiaorg
	@go mod tidy -compat=1.20
	@cfmt -w -m=100 ./...
	@markdownlint --fix --quiet --config .markdownlint.yaml .
.PHONY: fmt

## lint: Linting *.go files using golangci-lint. Look for .golangci.yml for the list of linters. Also lint *.md files using markdownlint.
lint: lint-imports
	@echo "--> Running linter"
	@golangci-lint run
	@markdownlint --config .markdownlint.yaml '**/*.md'
	@cfmt -m=100 ./...
.PHONY: lint

## test-unit: Running unit tests
test-unit:
	@echo "--> Running unit tests"
	@go test $(VERBOSE) -covermode=atomic -coverprofile=coverage.txt `go list ./... | grep -v nodebuilder/tests` $(LOG_AND_FILTER)
.PHONY: test-unit

## test-unit-race: Running unit tests with data race detector
test-unit-race:
	@echo "--> Running unit tests with data race detector"
	@go test -race `go list ./... | grep -v nodebuilder/tests`
.PHONY: test-unit-race

## test-swamp: Running swamp tests located in nodebuilder/tests
test-swamp:
	@echo "--> Running swamp tests"
	@go test ./nodebuilder/tests
.PHONY: test-swamp

## test-swamp-race: Running swamp tests with data race detector located in node/tests
test-swamp-race:
	@echo "--> Running swamp tests with data race detector"
	@go test -race ./nodebuilder/tests
.PHONY: test-swamp-race

## test: Running both unit and swamp tests
test:
	@echo "--> Running all tests without data race detector"
	@go test ./...
	@echo "--> Running all tests with data race detector"
	@go test -race ./...
.PHONY: test

## benchmark: Running all benchmarks
benchmark:
	@echo "--> Running benchmarks"
	@go test -run="none" -bench=. -benchtime=100x -benchmem ./...
.PHONY: benchmark

PB_PKGS=$(shell find . -name 'pb' -type d)
PB_CORE=$(shell go list -f {{.Dir}} -m github.com/tendermint/tendermint)
PB_GOGO=$(shell go list -f {{.Dir}} -m github.com/gogo/protobuf)
PB_CELESTIA_APP=$(shell go list -f {{.Dir}} -m github.com/celestiaorg/celestia-app)
PB_NMT=$(shell go list -f {{.Dir}} -m github.com/celestiaorg/nmt)

## pb-gen: Generate protobuf code for all /pb/*.proto files in the project.
pb-gen:
	@echo '--> Generating protobuf'
	@for dir in $(PB_PKGS); \
		do for file in `find $$dir -type f -name "*.proto"`; \
			do protoc -I=. -I=${PB_CORE}/proto/ -I=${PB_GOGO} -I=${PB_CELESTIA_APP}/proto -I=${PB_NMT} --gogofaster_out=paths=source_relative:. $$file; \
			echo '-->' $$file; \
		done; \
	done;
.PHONY: pb-gen


## openrpc-gen: Generate OpenRPC spec for Celestia-Node's RPC api
openrpc-gen:
	@echo "--> Generating OpenRPC spec"
	@go run ./cmd/docgen fraud header state share das p2p node blob
.PHONY: openrpc-gen

## lint-imports: Lint only Go imports.
## flag -set-exit-status doesn't exit with code 1 as it should, so we use find until it is fixed by goimports-reviser
lint-imports:
	@echo "--> Running imports linter"
	@for file in `find . -type f -name '*.go'`; \
		do goimports-reviser -list-diff -set-exit-status -company-prefixes "github.com/celestiaorg" -project-name "github.com/celestiaorg/celestia-node" -output stdout $$file \
		 || exit 1;  \
    done;
.PHONY: lint-imports

## sort-imports: Sort Go imports.
sort-imports:
	@goimports-reviser -company-prefixes "github.com/celestiaorg" -project-name "github.com/celestiaorg/celestia-node" -output stdout ./...
.PHONY: sort-imports

## adr-gen: Generate ADR from template. Must set NUM and TITLE parameters.
adr-gen:
	@echo "--> Generating ADR"
	@curl -sSL https://raw.githubusercontent.com/celestiaorg/.github/main/adr-template.md > docs/architecture/adr-$(NUM)-$(TITLE).md
.PHONY: adr-gen

## telemetry-infra-up: launches local telemetry infrastructure. This includes grafana, jaeger, loki, pyroscope, and an otel-collector.
## you can access the grafana instance at localhost:3000 and login with admin:admin.
telemetry-infra-up:
	PWD="${DIR_FULLPATH}/docker/telemetry" docker-compose -f ./docker/telemetry/docker-compose.yml up
.PHONY: telemetry-infra-up

## telemetry-infra-down: tears the telemetry infrastructure down. The stores for grafana, prometheus, and loki will persist.
telemetry-infra-down:
	PWD="${DIR_FULLPATH}/docker/telemetry" docker-compose -f ./docker/telemetry/docker-compose.yml down
.PHONY: telemetry-infra-down

## goreleaser: List Goreleaser commands and checks if GoReleaser is installed.
goreleaser: Makefile
	@echo " Choose a goreleaser command to run:"
	@sed -n 's/^## goreleaser/goreleaser/p' $< | column -t -s ':' |  sed -e 's/^/ /'
	@goreleaser --version
.PHONY: goreleaser

## goreleaser-build: Builds the celestia binary using GoReleaser for your local OS.
goreleaser-build:
	goreleaser build --snapshot --clean --single-target
.PHONY: goreleaser-build

## goreleaser-release: Builds the release celestia binaries as defined in .goreleaser.yaml. This requires there be a git tag for the release in the local git history.
goreleaser-release:
	goreleaser release --clean --fail-fast --skip-publish
.PHONY: goreleaser-release
