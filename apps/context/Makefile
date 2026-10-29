.PHONY: build test check install
VERSION ?= dev
build:
	go build -trimpath -ldflags "-X main.version=$(VERSION)" -o bin/context ./cmd/context
test:
	go test -race -cover ./...
check:
	test -z "$$(gofmt -l cmd internal)"
	go vet ./...
	go test -race ./...
install:
	go install -trimpath -ldflags "-X main.version=$(VERSION)" ./cmd/context
