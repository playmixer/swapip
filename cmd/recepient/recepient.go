package main

import (
	"context"
	"errors"
	"log"
	"net/http"
	"os"
	"os/signal"
	"swapip/internal/adapters/logger"
	"swapip/internal/core/config"
	"swapip/internal/core/swapip"
	"syscall"
	"time"

	"go.uber.org/zap"
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
	go func() {
		if err := swap.RunServer(ctx); err != nil && !errors.Is(err, http.ErrServerClosed) {
			lgr.Error("server run failed", zap.Error(err))
		}
	}()
	<-ctx.Done()
	lgr.Info("Stopping ...")
	err = swap.ShutdownServer(ctx)
	if err != nil && !errors.Is(err, http.ErrServerClosed) {
		lgr.Error("server shutdown failed", zap.Error(err))
	}
	time.Sleep(time.Second * 2)
	lgr.Info("Stopped")
	lgr.Sync()
}
