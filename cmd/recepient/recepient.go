package main

import (
	"context"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"swapip/internal/adapters/logger"
	"swapip/internal/core/config"
	"swapip/internal/core/swapip"
	"swapip/internal/version"
	"syscall"
	"time"

	"go.uber.org/zap"
)

func main() {
	// Проверка флага --version
	if len(os.Args) > 1 && (os.Args[1] == "--version" || os.Args[1] == "-v") {
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
	lgr.Info("Starting swapip recipient", zap.String("version", version.String()))

	swap := swapip.New(ctx, cfg.SwapConfig, lgr)
	go func() {
		if err := swap.RunServer(ctx); err != nil && !errors.Is(err, http.ErrServerClosed) {
			lgr.Error("server run failed", zap.Error(err))
		}
	}()
	<-ctx.Done()
	lgr.Info("Stopping ...")
	shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer shutdownCancel()
	err = swap.ShutdownServer(shutdownCtx)
	if err != nil && !errors.Is(err, http.ErrServerClosed) {
		lgr.Error("server shutdown failed", zap.Error(err))
	}
	time.Sleep(time.Second * 2)
	lgr.Info("Stopped")
	lgr.Sync()
}
