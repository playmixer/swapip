package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"os/signal"
	"swapip/internal/adapters/logger"
	"swapip/internal/core/config"
	"swapip/internal/core/swapip"
	"swapip/internal/version"
	"syscall"

	"go.uber.org/zap"
)

func main() {
	// Проверка флага --version
	if len(os.Args) > 1 && (os.Args[1] == "--version" || os.Args[1] == "-v") {
		fmt.Fprintf(os.Stderr, "Version flag detected\n")
		fmt.Println(version.String())
		return
	}

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

	// Логирование версии при запуске
	lgr.Info("Starting swapip sender", zap.String("version", version.String()))

	swap := swapip.New(ctx, cfg.SwapConfig, lgr)
	if err := swap.Send(); err != nil {
		log.Fatal(err)
	}
	lgr.Info("Stopped")
	lgr.Sync()
}
