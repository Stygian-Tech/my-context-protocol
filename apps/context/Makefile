.PHONY: build test check install
VERSION ?= dev
PREFIX ?= $(HOME)/.local
BINDIR ?= $(PREFIX)/bin
build:
	go build -trimpath -ldflags "-X main.version=$(VERSION)" -o bin/context ./cmd/context
test:
	go test -race -cover ./...
check:
	test -z "$$(gofmt -l cmd internal)"
	go vet ./...
	go test -race ./...
install:
	sh scripts/install.sh "$(BINDIR)" "$(VERSION)"
