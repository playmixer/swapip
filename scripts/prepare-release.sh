#!/bin/bash
# prepare-release.sh - подготовка файлов для релиза на основе Git tag

set -e

# Загрузка общих функций
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common-functions.sh"

# Конфигурация по умолчанию
DEFAULT_PLATFORMS="linux-amd64 windows-386"
DEFAULT_OUTPUT_DIR="release"
FORCE_BUILD=false
CREATE_ARCHIVE=true

# Функции
usage() {
    echo "Использование: $0 [-p PLATFORMS] [-o OUTPUT_DIR] [-f] [--no-archive] [-h]"
    echo ""
    echo "Параметры:"
    echo "  -p PLATFORMS  Платформы через запятую (по умолчанию: $DEFAULT_PLATFORMS)"
    echo "  -o OUTPUT_DIR Выходная директория (по умолчанию: $DEFAULT_OUTPUT_DIR)"
    echo "  -f            Принудительная сборка, даже если тег уже существует"
    echo "  --no-archive  Не создавать архив tar.gz (по умолчанию: создавать)"
    echo "  -h            Показать эту справку"
    echo ""
    echo "Описание:"
    echo "  Скрипт определяет версию из текущего Git тега (формат vX.Y.Z)"
    echo "  и подготавливает файлы для релиза, включая создание архива."
    echo ""
    echo "Пример:"
    echo "  $0 -p linux-amd64 -o ./release"
    echo "  $0 -p linux-amd64,windows-386 -f"
    echo "  $0 --no-archive"
}

# Получение текущего Git тега
get_current_tag() {
    # Получаем текущий тег (если мы на теге)
    local tag=$(git describe --tags --exact-match 2>/dev/null || echo "")
    
    if [ -z "$tag" ]; then
        # Если не на теге, получаем последний тег из истории
        tag=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
    fi
    
    echo "$tag"
}

# Проверка формата тега
validate_tag_format() {
    local tag=$1
    
    # Проверка формата vX.Y.Z
    if [[ ! "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9\.]+)?$ ]]; then
        log_error "Неверный формат тега: $tag"
        log_error "Тег должен соответствовать формату vX.Y.Z или vX.Y.Z-PRERELEASE"
        exit 1
    fi
    
    # Извлечение версии без префикса 'v'
    local version=${tag#v}
    echo "$version"
}

# Проверка существования релиза
check_release_exists() {
    local tag=$1
    local output_dir=$2
    
    if [ -d "$output_dir/$tag" ]; then
        log_warning "Релиз для тега $tag уже существует в $output_dir/$tag"
        return 0
    fi
    
    return 1
}

# Проверка окружения
check_environment() {
    log_info "Проверка окружения..."
    
    # Проверка Git
    if ! command -v git &> /dev/null; then
        log_error "Git не установлен"
        exit 1
    fi
    
    # Проверка Go
    if ! command -v go &> /dev/null; then
        log_error "Go не установлен"
        exit 1
    fi
    
    # Проверка make
    if ! command -v make &> /dev/null; then
        log_error "Make не установлен"
        exit 1
    fi
    
    # Проверка что мы в git репозитории
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        log_error "Текущая директория не является git репозиторием"
        exit 1
    fi
    
    log_success "Окружение проверено успешно"
}

# Разбор параметров командной строки
parse_arguments() {
    # Обработка long options вручную
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p)
                PLATFORMS="$2"
                shift 2
                ;;
            -o)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            -f)
                FORCE_BUILD=true
                shift
                ;;
            --no-archive)
                CREATE_ARCHIVE=false
                shift
                ;;
            -h)
                usage
                exit 0
                ;;
            *)
                log_error "Неизвестный параметр: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Установка значений по умолчанию если не заданы
    PLATFORMS=${PLATFORMS:-$DEFAULT_PLATFORMS}
    OUTPUT_DIR=${OUTPUT_DIR:-$DEFAULT_OUTPUT_DIR}
}

# Сборка для платформы
build_for_platform() {
    local platform=$1
    local version=$2
    local output_dir=$3
    
    log_info "Сборка для платформы: $platform"
    
    # Разбор платформы
    local goos goarch
    case $platform in
        linux-amd64)
            goos="linux"
            goarch="amd64"
            binary_ext=""
            ;;
        windows-386)
            goos="windows"
            goarch="386"
            binary_ext=".exe"
            ;;
        darwin-amd64)
            goos="darwin"
            goarch="amd64"
            binary_ext=""
            ;;
        *)
            log_error "Неподдерживаемая платформа: $platform"
            return 1
            ;;
    esac
    
    # Создание директории для платформы
    local platform_dir="$output_dir/$platform"
    mkdir -p "$platform_dir"
    
    # Экспорт переменных для Makefile
    export GOOS="$goos"
    export GOARCH="$goarch"
    export VERSION="v$version"
    
    log_info "Сборка sender..."
    if ! make build-l 2>&1 | tee -a "$LOG_DIR/build.log"; then
        log_error "Ошибка сборки sender для $platform"
        return 1
    fi
    
    # Копирование бинарников
    local sender_src="./build/sender/sender$binary_ext"
    local recepient_src="./build/recepient/recepient$binary_ext"
    
    if [ ! -f "$sender_src" ]; then
        log_error "Бинарник sender не найден: $sender_src"
        return 1
    fi
    
    if [ ! -f "$recepient_src" ]; then
        log_error "Бинарник recepient не найден: $recepient_src"
        return 1
    fi
    
    cp "$sender_src" "$platform_dir/sender$binary_ext"
    cp "$recepient_src" "$platform_dir/recepient$binary_ext"
    
    log_success "Сборка для $platform завершена"
}

# Создание checksums
create_checksums() {
    local dir=$1
    local checksum_file="$dir/checksums.txt"
    
    log_info "Создание checksums..."
    
    > "$checksum_file"  # Очистка файла
    
    # Прямое перечисление файлов вместо использования find
    # для совместимости с Windows (где find.exe - это команда поиска текста)
    local found_files=0
    
    # Ищем бинарники в поддиректориях платформ
    for platform_dir in "$dir"/*/; do
        # Проверяем, является ли platform_dir директорией
        if [ ! -d "$platform_dir" ]; then
            continue
        fi
        
        # Проверяем файлы sender и recepient в этой директории
        for binary_name in sender recepient; do
            # Проверяем наличие файла без расширения и с расширением .exe
            for ext in "" ".exe"; do
                local binary_file="${platform_dir}${binary_name}${ext}"
                if [ -f "$binary_file" ]; then
                    found_files=1
                    log_info "Найден файл: $binary_file"
                    local checksum=$(sha256sum "$binary_file" | awk '{print $1}')
                    local filename=$(basename "$binary_file")
                    echo "$checksum  $filename" >> "$checksum_file"
                    log_info "  $filename: $checksum"
                fi
            done
        done
    done
    
    # Также проверяем файлы непосредственно в корневой директории (на всякий случай)
    for binary_name in sender recepient; do
        for ext in "" ".exe"; do
            local binary_file="${dir}/${binary_name}${ext}"
            if [ -f "$binary_file" ]; then
                found_files=1
                log_info "Найден файл: $binary_file"
                local checksum=$(sha256sum "$binary_file" | awk '{print $1}')
                local filename=$(basename "$binary_file")
                echo "$checksum  $filename" >> "$checksum_file"
                log_info "  $filename: $checksum"
            fi
        done
    done
    
    if [ "$found_files" -eq 0 ]; then
        log_warning "Не найдены бинарники sender или recepient в $dir"
    else
        log_success "Checksums созданы: $checksum_file"
    fi
}

# Создание version.json
create_version_json() {
    local dir=$1
    local version=$2
    local tag=$3
    
    local version_file="$dir/version.json"
    
    log_info "Создание version.json..."
    
    cat > "$version_file" << EOF
{
  "version": "$version",
  "tag": "$tag",
  "build_date": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "git_commit": "$(git rev-parse HEAD)",
  "git_commit_short": "$(git rev-parse --short HEAD)",
  "components": {
    "sender": {
      "name": "swapip-sender",
      "description": "Sender component for swapip"
    },
    "recepient": {
      "name": "swapip-recepient",
      "description": "Recepient component for swapip"
    }
  },
  "platforms": ["$(echo "$PLATFORMS" | sed 's/,/", "/g')"]
}
EOF
    
    log_success "Version.json создан: $version_file"
}

# Копирование скриптов
copy_scripts() {
    local dir=$1
    
    log_info "Копирование скриптов..."
    
    # Копируем все скрипты из директории scripts
    if [ -d "$SCRIPT_DIR" ]; then
        cp -r "$SCRIPT_DIR" "$dir/" 2>/dev/null || true
        log_info "Директория scripts скопирована"
    else
        log_error "Директория scripts не найдена: $SCRIPT_DIR"
        return 1
    fi
    
    # Удаляем ненужные файлы (если есть)
    if [ -d "$dir/scripts" ]; then
        rm -f "$dir/scripts/"*.log 2>/dev/null || true
        # Делаем скрипты исполняемыми
        find "$dir/scripts" -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
        log_info "Скрипты сделаны исполняемыми"
    else
        log_warning "Директория $dir/scripts не существует после копирования"
    fi
    
    log_success "Скрипты скопированы"
}

# Создание README
create_readme() {
    local dir=$1
    local version=$2
    
    local readme_file="$dir/README.md"
    
    log_info "Создание README.md..."
    
    cat > "$readme_file" << EOF
# SwapIP Release v$version

## Описание
Этот релиз содержит бинарники и скрипты для компонентов swapip.

## Компоненты
1. **sender** - компонент отправителя
2. **recepient** - компонент получателя

## Платформы
$(echo "$PLATFORMS" | tr ',' '\n' | sed 's/^/- /')

## Установка
Для установки выполните соответствующий скрипт:

### Установка sender
\`\`\`bash
sudo ./scripts/install-sender.sh
\`\`\`

### Установка recepient
\`\`\`bash
sudo ./scripts/install-recepient.sh
\`\`\`

## Обновление
Для проверки и установки обновлений используйте скрипты:

### Проверка обновлений
\`\`\`bash
sudo /opt/swapip/scripts/check-sender-version.sh --check
sudo /opt/swapip/scripts/check-recepient-version.sh --check
\`\`\`

### Установка обновлений
\`\`\`bash
sudo /opt/swapip/scripts/update-sender.sh --update
sudo /opt/swapip/scripts/update-recepient.sh --update
\`\`\`

## Проверка целостности
Все бинарники имеют checksums в файле \`checksums.txt\`. Для проверки:
\`\`\`bash
sha256sum -c checksums.txt
\`\`\`

## Версия
- Версия: $version
- Git commit: $(git rev-parse --short HEAD)
- Дата сборки: $(date -u +"%Y-%m-%d %H:%M:%S")

## Лицензия
Проприетарная
EOF
    
    log_success "README.md создан"
}

# Создание архива tar.gz
create_archive() {
    local release_dir=$1
    local version=$2
    local tag=$3
    local output_dir=$4
    
    log_info "Создание архива..."
    
    local archive_name="swapip-v${version}.tar.gz"
    local archive_path="${output_dir}/${archive_name}"
    
    # Переходим в родительскую директорию релиза
    local parent_dir=$(dirname "$release_dir")
    local dir_name=$(basename "$release_dir")
    
    log_info "Архивирование $dir_name в $archive_name"
    
    if command -v tar &> /dev/null; then
        if tar -czf "$archive_path" -C "$parent_dir" "$dir_name" 2>/dev/null; then
            log_success "Архив создан: $archive_path"
            
            # Проверка размера архива
            local archive_size
            if command -v stat &> /dev/null; then
                archive_size=$(stat -c%s "$archive_path" 2>/dev/null || echo "0")
            elif command -v wc &> /dev/null; then
                archive_size=$(wc -c < "$archive_path" 2>/dev/null || echo "0")
            else
                archive_size="unknown"
            fi
            
            if [[ "$archive_size" =~ ^[0-9]+$ ]] && [ "$archive_size" -gt 0 ]; then
                # Преобразование в человекочитаемый формат
                if [ "$archive_size" -lt 1024 ]; then
                    size_human="${archive_size}B"
                elif [ "$archive_size" -lt 1048576 ]; then
                    size_human="$((archive_size / 1024))KB"
                elif [ "$archive_size" -lt 1073741824 ]; then
                    size_human="$((archive_size / 1048576))MB"
                else
                    size_human="$((archive_size / 1073741824))GB"
                fi
                log_info "Размер архива: $size_human"
            fi
            
            # Проверка целостности архива
            if tar -tzf "$archive_path" &> /dev/null; then
                log_success "Архив проверен на целостность"
            else
                log_warning "Не удалось проверить целостность архива"
            fi
            
            return 0
        else
            log_error "Ошибка при создании архива"
            return 1
        fi
    else
        log_error "Команда tar не найдена. Не удалось создать архив."
        return 1
    fi
}

# Основная функция
main() {
    log_info "Начало подготовки релиза..."
    
    # Разбор параметров
    parse_arguments "$@"
    
    # Проверка окружения
    check_environment
    
    # Получение текущего тега
    local tag
    tag=$(get_current_tag)
    
    if [ -z "$tag" ]; then
        log_error "Не найден Git тег. Создайте тег командой: git tag -a vX.Y.Z -m 'Release vX.Y.Z'"
        exit 1
    fi
    
    log_info "Текущий тег: $tag"
    
    # Валидация формата тега
    local version
    version=$(validate_tag_format "$tag")
    log_info "Версия: $version"
    
    # Создание выходной директории
    local release_dir="$OUTPUT_DIR/$tag"
    
    # Проверка существования релиза
    if check_release_exists "$tag" "$OUTPUT_DIR" && [ "$FORCE_BUILD" = false ]; then
        log_error "Релиз уже существует. Используйте -f для принудительной пересборки."
        exit 1
    fi
    
    # Очистка старой директории если принудительная сборка
    if [ "$FORCE_BUILD" = true ] && [ -d "$release_dir" ]; then
        log_warning "Удаление существующего релиза: $release_dir"
        rm -rf "$release_dir"
    fi
    
    # Создание структуры директорий
    mkdir -p "$release_dir"
    
    # Разделение платформ
    IFS=',' read -ra platforms_array <<< "$PLATFORMS"
    
    # Сборка для каждой платформы
    for platform in "${platforms_array[@]}"; do
        platform=$(echo "$platform" | xargs)  # Удаление пробелов
        build_for_platform "$platform" "$version" "$release_dir"
    done
    
    # Создание дополнительных файлов
    create_checksums "$release_dir"
    create_version_json "$release_dir" "$version" "$tag"
    copy_scripts "$release_dir"
    create_readme "$release_dir" "$version"
    
    # Создание архива если не отключено
    local archive_path=""
    if [ "$CREATE_ARCHIVE" = true ]; then
        if create_archive "$release_dir" "$version" "$tag" "$OUTPUT_DIR"; then
            archive_path="$OUTPUT_DIR/swapip-v${version}.tar.gz"
        else
            log_warning "Не удалось создать архив, но релиз подготовлен"
        fi
    else
        log_info "Создание архива отключено (--no-archive)"
    fi
    
    # Итоговая информация
    log_success "=========================================="
    log_success "Релиз успешно подготовлен!"
    log_success "Версия: $version"
    log_success "Директория: $release_dir"
    if [ -n "$archive_path" ] && [ -f "$archive_path" ]; then
        log_success "Архив: $archive_path"
    fi
    log_success ""
    log_success "Содержимое:"
    list_files_recursive "$release_dir" | sort | while read -r file; do
        local relative_path=${file#$release_dir/}
        
        # Кроссплатформенное получение размера файла
        local size_bytes
        size_bytes=$(get_file_size "$file" 2>/dev/null || echo "0")
        
        # Преобразование в человекочитаемый формат
        local size_human
        # Проверяем, что size_bytes является числом
        if [[ ! "$size_bytes" =~ ^[0-9]+$ ]]; then
            size_human="unknown"
        elif [ "$size_bytes" -eq 0 ] 2>/dev/null; then
            size_human="0B"
        elif [ "$size_bytes" -lt 1024 ]; then
            size_human="${size_bytes}B"
        elif [ "$size_bytes" -lt 1048576 ]; then
            size_human="$((size_bytes / 1024))KB"
        elif [ "$size_bytes" -lt 1073741824 ]; then
            size_human="$((size_bytes / 1048576))MB"
        else
            size_human="$((size_bytes / 1073741824))GB"
        fi
        
        log_success "  $relative_path ($size_human)"
    done
    
    # Добавляем архив в список если он создан
    if [ -n "$archive_path" ] && [ -f "$archive_path" ]; then
        local archive_size
        if command -v stat &> /dev/null; then
            archive_size=$(stat -c%s "$archive_path" 2>/dev/null || echo "0")
        elif command -v wc &> /dev/null; then
            archive_size=$(wc -c < "$archive_path" 2>/dev/null || echo "0")
        else
            archive_size="unknown"
        fi
        
        if [[ "$archive_size" =~ ^[0-9]+$ ]] && [ "$archive_size" -gt 0 ]; then
            if [ "$archive_size" -lt 1024 ]; then
                size_human="${archive_size}B"
            elif [ "$archive_size" -lt 1048576 ]; then
                size_human="$((archive_size / 1024))KB"
            elif [ "$archive_size" -lt 1073741824 ]; then
                size_human="$((archive_size / 1048576))MB"
            else
                size_human="$((archive_size / 1073741824))GB"
            fi
            log_success "  $(basename "$archive_path") ($size_human)"
        else
            log_success "  $(basename "$archive_path")"
        fi
    fi
    
    log_success ""
    if [ "$CREATE_ARCHIVE" = false ] || [ -z "$archive_path" ] || [ ! -f "$archive_path" ]; then
        log_success "Следующие шаги:"
        log_success "1. Создайте архив: tar -czf swapip-v$version.tar.gz -C $OUTPUT_DIR $tag/"
        log_success "2. Создайте релиз на GitHub с тегом $tag"
        log_success "3. Загрузите архив в релиз"
    else
        log_success "Следующие шаги:"
        log_success "1. Создайте релиз на GitHub с тегом $tag"
        log_success "2. Загрузите архив $archive_path в релиз"
    fi
    log_success "=========================================="
}

# Запуск основной функции
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
