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

all: build-l

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

# Система обновления
.PHONY: prepare-release install-scripts test-update-system

# Подготовка релиза
prepare-release:
	@echo "Подготовка релиза..."
	@if [ "$(OS)" != "Windows_NT" ]; then chmod +x scripts/prepare-release.sh; fi
	@./scripts/prepare-release.sh -p linux-amd64 -o ./release

# Установка скриптов (делает их исполняемыми)
install-scripts:
	@echo "Установка скриптов системы обновления..."
	@if [ "$(OS)" != "Windows_NT" ]; then chmod +x scripts/*.sh; fi
	@echo "Скрипты сделаны исполняемыми"

# Тестирование системы обновления (базовая проверка)
test-update-system:
	@echo "Тестирование системы обновления..."
	@echo "1. Проверка синтаксиса скриптов..."
	@for script in scripts/*.sh; do \
		if bash -n "$$script"; then \
			echo "  $$script: OK"; \
		else \
			echo "  $$script: ERROR"; \
			exit 1; \
		fi \
	done
	@echo "2. Проверка наличия необходимых файлов..."
	@for file in scripts/common-functions.sh scripts/github-api.sh scripts/prepare-release.sh; do \
		if [ -f "$$file" ]; then \
			echo "  $$file: найден"; \
		else \
			echo "  $$file: не найден"; \
			exit 1; \
		fi \
	done
	@echo "3. Проверка systemd служб..."
	@for service in scripts/systemd/*.service; do \
		if [ -f "$$service" ]; then \
			echo "  $$service: найден"; \
		else \
			echo "  $$service: не найден"; \
		fi \
	done
	@echo "Тестирование завершено успешно!"

# Создание тестового тега для проверки
test-tag:
	@echo "Создание тестового тега v1.0.0-test..."
	@git tag -f v1.0.0-test 2>/dev/null || true
	@echo "Тег создан: v1.0.0-test"

# Очистка тестового тега
clean-test-tag:
	@echo "Удаление тестового тега..."
	@git tag -d v1.0.0-test 2>/dev/null || true
	@echo "Тег удален"

# Создание полного релиза с архивом
release: prepare-release
	@echo "Релиз создан успешно!"
	@if [ -d "./release" ]; then \
		echo "Содержимое директории release:"; \
		ls -la ./release/; \
		echo ""; \
		echo "Архивы:"; \
		find ./release -name "*.tar.gz" -type f | while read file; do \
			echo "  $$file"; \
		done; \
	fi

# Создание только архива (если релиз уже подготовлен)
release-archive:
	@if [ ! -d "./release" ]; then \
		echo "Ошибка: директория release не существует. Сначала выполните make prepare-release"; \
		exit 1; \
	fi
	@echo "Создание архива из последнего релиза..."
	@latest_tag=$$(git describe --tags --abbrev=0 2>/dev/null || echo ""); \
	if [ -z "$$latest_tag" ]; then \
		echo "Ошибка: не найден git тег"; \
		exit 1; \
	fi; \
	if [ -d "./release/$$latest_tag" ]; then \
		echo "Создание архива для тега $$latest_tag..."; \
		tar -czf "./release/swapip-$$latest_tag.tar.gz" -C "./release" "$$latest_tag"; \
		echo "Архив создан: ./release/swapip-$$latest_tag.tar.gz"; \
	else \
		echo "Ошибка: директория ./release/$$latest_tag не существует"; \
		exit 1; \
	fi

# Полный тестовый цикл системы обновления
test-full-cycle: test-tag prepare-release clean-test-tag
	@echo "Полный тестовый цикл завершен!"
	@echo "Созданные файлы находятся в директории ./release"
