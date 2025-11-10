package main

import (
	"context"
	"log"
	"os"
	"os/signal"
	"swapip/internal/adapters/logger"
	"swapip/internal/core/config"
	"swapip/internal/core/swapip"
	"syscall"
)

func main() {
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, os.Kill, syscall.SIGTERM)
	defer cancel()
	cfg, err := config.Init()
	if err != nil {
		log.Fatal(err)
	}

	lgr, err := logger.New(
		ctx,
		logger.SetLevel(cfg.LogLevel),
		logger.SetLogPath(cfg.LogPath),
	)
	if err != nil {
		log.Fatal(err)
	}
	lgr.Info("Starting ...")

	swap := swapip.New(ctx, cfg.SwapConfig, lgr)
	if err := swap.Send(); err != nil {
		log.Fatal(err)
	}
	lgr.Info("Stopped")
	lgr.Sync()
}
