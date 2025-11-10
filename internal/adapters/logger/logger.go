package logger

import (
	"context"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"time"

	"go.uber.org/zap"
	"go.uber.org/zap/zapcore"

	"github.com/playmixer/secret-keeper/pkg/tools"
)

type Logger struct {
	l *zap.Logger
}

type loggerConfigurator struct {
	level        string
	logPath      string
	isTerminal   bool
	isFile       bool
	isRotateFile bool
	prefix       string
}

type option func(*loggerConfigurator)

func SetLevel(level string) option {
	return func(l *loggerConfigurator) {
		l.level = level
	}
}

func SetLogPath(path string) option {
	return func(l *loggerConfigurator) {
		if path != "" {
			l.logPath = path + "/log.log"
			l.isFile = true
		}
	}
}

func SetEnableFileOutput(t bool) option {
	return func(lc *loggerConfigurator) {
		lc.isFile = t
	}
}

func SetEnableTerminalOutput(t bool) option {
	return func(lc *loggerConfigurator) {
		lc.isTerminal = t
	}
}

func New(ctx context.Context, options ...option) (*Logger, error) {
	ctx = context.WithoutCancel(ctx)
	l := &Logger{}
	cfg := loggerConfigurator{
		level:        "info",
		logPath:      "./logs/log.log",
		isTerminal:   true,
		isFile:       false,
		isRotateFile: true,
		prefix:       "2006-01-02",
	}

	for _, opt := range options {
		opt(&cfg)
	}

	if cfg.logPath != "" {
		err := os.MkdirAll(filepath.Dir(cfg.logPath), tools.Mode0750)
		if err != nil {
			log.Println("failed create directory for logs")
		}
	}

	l.l = prepareCore(cfg)

	if cfg.isRotateFile {
		go func(ctx context.Context, l *Logger) {
			ticker := time.NewTicker(time.Minute)
			for {
				select {
				case <-ctx.Done():
					return
				case <-ticker.C:
					current := time.Now()
					if current.Minute() == 0 && current.Hour() == 0 {
						l.l.Sync()
						l.l = prepareCore(cfg)
					}
				}
			}
		}(ctx, l)
	}

	return l, nil
}

func prepareCore(cfg loggerConfigurator) *zap.Logger {
	stdout := zapcore.AddSync(os.Stdout)
	if cfg.isRotateFile {
		cfg.logPath = "./logs/log_" + time.Now().Format(cfg.prefix) + ".log"
	}
	f, err := os.OpenFile(cfg.logPath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, tools.Mode0600)
	if err != nil {
		panic(fmt.Errorf("failed create log file: %w", err))
	}
	file := zapcore.AddSync(f)

	level, err := zap.ParseAtomicLevel(cfg.level)
	if err != nil {
		panic(fmt.Errorf("failed parse level: %w", err))
	}

	productionCfg := zap.NewProductionEncoderConfig()
	productionCfg.TimeKey = "timestamp"
	productionCfg.EncodeTime = zapcore.ISO8601TimeEncoder

	developmentCfg := zap.NewDevelopmentEncoderConfig()
	developmentCfg.EncodeLevel = zapcore.CapitalColorLevelEncoder

	consoleEncoder := zapcore.NewConsoleEncoder(developmentCfg)
	fileEncoder := zapcore.NewJSONEncoder(productionCfg)

	ouputs := []zapcore.Core{}
	if cfg.isFile {
		ouputs = append(ouputs, zapcore.NewCore(fileEncoder, file, level))
	}
	if cfg.isTerminal {
		ouputs = append(ouputs, zapcore.NewCore(consoleEncoder, stdout, level))
	}

	core := zapcore.NewTee(ouputs...)
	return zap.New(core, zap.AddCaller(), zap.AddStacktrace(zapcore.ErrorLevel))
}

func (l *Logger) Sync() {
	l.l.Sync()
}

func (l *Logger) Info(msg string, fields ...zap.Field) {
	l.l.Info(msg, fields...)
}

func (l *Logger) Error(msg string, fields ...zap.Field) {
	l.l.Error(msg, fields...)
}

func (l *Logger) Debug(msg string, fields ...zap.Field) {
	l.l.Debug(msg, fields...)
}
