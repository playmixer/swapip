// Package version содержит информацию о версии приложения,
// которая заполняется во время сборки через ldflags.
package version

import (
	"fmt"
	"runtime"
)

// Переменные, заполняемые при сборке через -ldflags.
var (
	// Version - семантическая версия приложения (например, "1.0.0").
	Version = "dev"

	// Commit - хэш коммита Git.
	Commit = "unknown"

	// Date - дата сборки в формате RFC3339.
	Date = "unknown"

	// BuildTime - время сборки в формате RFC3339.
	BuildTime = "unknown"
)

// String возвращает строковое представление версии.
func String() string {
	return fmt.Sprintf("version %s (commit: %s, built: %s, go: %s)",
		Version, Commit, Date, runtime.Version())
}

// Info возвращает детальную информацию о версии в виде map.
func Info() map[string]string {
	return map[string]string{
		"version":   Version,
		"commit":    Commit,
		"date":      Date,
		"buildTime": BuildTime,
		"goVersion": runtime.Version(),
		"platform":  fmt.Sprintf("%s/%s", runtime.GOOS, runtime.GOARCH),
	}
}
