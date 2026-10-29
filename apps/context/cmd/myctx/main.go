package main

import (
	"context"
	"os"
	"os/signal"
	"syscall"

	"github.com/Stygian-Tech/my-context-protocol/apps/context/internal/cli"
)

var version = "dev"

func main() {
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()
	os.Exit(cli.Main(ctx, os.Args[1:], os.Stdin, os.Stdout, os.Stderr, version))
}
