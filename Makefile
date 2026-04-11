# Версия приложения (можно переопределить через окружение)
# Определение ОС
ifeq ($(OS),Windows_NT)
    # Windows
    VERSION ?= $(shell git describe --tags --abbrev=0 2>/dev/null || echo "0.0.0")
    COMMIT ?= $(shell git rev-parse --short HEAD 2>/dev/null || echo "unknown")
    BUILD_TIME ?= $(shell powershell -Command "Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ'")
else
    # Unix-like
    VERSION ?= $(shell git describe --tags --abbrev=0 2>/dev/null || echo "0.0.0")
    COMMIT ?= $(shell git rev-parse --short HEAD 2>/dev/null || echo "unknown")
    BUILD_TIME ?= $(shell date -u +"%Y-%m-%dT%H:%M:%SZ")
endif

# Флаги для передачи версии в бинарник
LD_FLAGS = -X 'swapip/internal/version.Version=$(VERSION)' \
           -X 'swapip/internal/version.Commit=$(COMMIT)' \
           -X 'swapip/internal/version.Date=$(BUILD_TIME)' \
           -X 'swapip/internal/version.BuildTime=$(BUILD_TIME)'

# Цели по умолчанию
.PHONY: all build-w build-l build-version version clean

all:
	build-l
	build-w

# Сборка для Windows (386)
build-w:
	GOOS=windows GOARCH=386 go build -ldflags="$(LD_FLAGS)" -o ./build/recepient/recepient.exe ./cmd/recepient/recepient.go
	GOOS=windows GOARCH=386 go build -ldflags="$(LD_FLAGS)" -o ./build/sender/sender.exe ./cmd/sender/sender.go

# Сборка для Linux (amd64)
build-l:
	GOOS=linux GOARCH=amd64 go build -ldflags="$(LD_FLAGS)" -o ./build/recepient/recepient ./cmd/recepient/recepient.go
	GOOS=linux GOARCH=amd64 go build -ldflags="$(LD_FLAGS)" -o ./build/sender/sender ./cmd/sender/sender.go

# Сборка с версионированием (текущая ОС)
build-version:
	go build -ldflags="$(LD_FLAGS)" -o ./build/recepient/recepient ./cmd/recepient/recepient.go
	go build -ldflags="$(LD_FLAGS)" -o ./build/sender/sender ./cmd/sender/sender.go

# Показать информацию о версии
version:
	@echo "Version:    $(VERSION)"
	@echo "Commit:     $(COMMIT)"
	@echo "Build time: $(BUILD_TIME)"
	@echo "LD flags:   $(LD_FLAGS)"

# Очистка билдов
clean:
	rm -rf ./build/*