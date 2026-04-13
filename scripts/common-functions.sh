#!/bin/bash
# common-functions.sh - общие функции для системы обновления swapip

set -e

# Определение операционной системы
detect_os() {
    case "$(uname -s)" in
        Linux*)     OS=Linux;;
        Darwin*)    OS=macOS;;
        CYGWIN*)    OS=Cygwin;;
        MINGW*)     OS=MinGW;;
        MSYS*)      OS=MSYS;;
        Windows*)   OS=Windows;;
        *)          OS=Unknown;;
    esac
    echo "$OS"
}

OS=$(detect_os)

# Цвета для вывода (только для терминалов, поддерживающих цвета)
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
fi

# Константы путей в зависимости от ОС
if [ "$OS" = "Linux" ] || [ "$OS" = "macOS" ]; then
    # Unix-like системы
    LOG_DIR="./logs"
    CACHE_DIR="./cache"
    CONFIG_DIR="./config"
    INSTALL_DIR="./"
    BACKUP_DIR="./backups"
    PATH_SEPARATOR="/"
elif [[ "$OS" == *"MINGW"* ]] || [[ "$OS" == *"MSYS"* ]] || [[ "$OS" == *"CYGWIN"* ]] || [ "$OS" = "Windows" ]; then
    # Windows системы (Git Bash, Cygwin, MSYS2)
    LOG_DIR="./logs"
    CACHE_DIR="./cache"
    CONFIG_DIR="./config"
    INSTALL_DIR="./"
    BACKUP_DIR="./backups"
    PATH_SEPARATOR="/"
else
    # По умолчанию Unix-like пути
    LOG_DIR="./logs"
    CACHE_DIR="./cache"
    CONFIG_DIR="./config"
    INSTALL_DIR="./"
    BACKUP_DIR="./backups"
    PATH_SEPARATOR="/"
fi

# Для тестирования можно переопределить через переменные окружения
LOG_DIR="${SWAPIP_LOG_DIR:-$LOG_DIR}"
CACHE_DIR="${SWAPIP_CACHE_DIR:-$CACHE_DIR}"
CONFIG_DIR="${SWAPIP_CONFIG_DIR:-$CONFIG_DIR}"
INSTALL_DIR="${SWAPIP_INSTALL_DIR:-$INSTALL_DIR}"
BACKUP_DIR="${SWAPIP_BACKUP_DIR:-$BACKUP_DIR}"

# Функции логирования
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2
    # Пытаемся записать в лог, но игнорируем все ошибки
    {
        mkdir -p "$LOG_DIR" 2>/dev/null
        echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_DIR/swapip.log" 2>/dev/null
    } 2>/dev/null || true
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2
    {
        mkdir -p "$LOG_DIR" 2>/dev/null
        echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_DIR/swapip.log" 2>/dev/null
    } 2>/dev/null || true
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2
    {
        mkdir -p "$LOG_DIR" 2>/dev/null
        echo "[WARNING] $(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_DIR/swapip.log" 2>/dev/null
    } 2>/dev/null || true
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2
    {
        mkdir -p "$LOG_DIR" 2>/dev/null
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_DIR/swapip.log" 2>/dev/null
    } 2>/dev/null || true
}

# Проверка прав root (только для Unix-систем)
check_root() {
    if [ "$OS" = "Linux" ] || [ "$OS" = "macOS" ]; then
        if [ "$EUID" -ne 0 ]; then
            log_error "Этот скрипт должен запускаться с правами root (sudo)"
            exit 1
        fi
    elif [[ "$OS" == *"MINGW"* ]] || [[ "$OS" == *"MSYS"* ]] || [[ "$OS" == *"CYGWIN"* ]]; then
        # В Windows Git Bash/Cygwin проверяем, запущен ли от администратора
        if ! net session > /dev/null 2>&1; then
            log_warning "Скрипт рекомендуется запускать от имени администратора в Windows"
        fi
    else
        log_warning "Проверка прав root не поддерживается для ОС: $OS"
    fi
}

# Проверка зависимостей с учетом ОС
check_dependencies() {
    local deps=("curl" "wget" "tar" "jq")
    local missing=()
    
    # Добавляем команду для checksum в зависимости от ОС
    if [ "$OS" = "Linux" ] || [ "$OS" = "macOS" ]; then
        deps+=("sha256sum")
    elif [[ "$OS" == *"MINGW"* ]] || [[ "$OS" == *"MSYS"* ]] || [[ "$OS" == *"CYGWIN"* ]]; then
        deps+=("sha256sum")
    else
        deps+=("shasum")
    fi
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        log_error "Отсутствуют зависимости: ${missing[*]}"
        
        if [ "$OS" = "Linux" ]; then
            log_info "Установите их командой: sudo apt-get install ${missing[*]}"
        elif [ "$OS" = "macOS" ]; then
            log_info "Установите их командой: brew install ${missing[*]}"
        elif [[ "$OS" == *"MINGW"* ]] || [[ "$OS" == *"MSYS"* ]]; then
            log_info "Установите их через pacman: pacman -S ${missing[*]}"
        fi
        
        exit 1
    fi
}

# Создание необходимых директорий
create_directories() {
    mkdir -p "$LOG_DIR"
    mkdir -p "$CACHE_DIR"
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$BACKUP_DIR"
    
    # Установка прав (только для Unix-систем)
    if [ "$OS" = "Linux" ] || [ "$OS" = "macOS" ]; then
        chmod 755 "$LOG_DIR" "$CACHE_DIR" "$CONFIG_DIR" "$INSTALL_DIR" "$BACKUP_DIR"
        chown root:root "$LOG_DIR" "$CACHE_DIR" "$CONFIG_DIR" "$INSTALL_DIR" "$BACKUP_DIR" 2>/dev/null || true
    fi
}

# Получение текущей версии компонента
get_current_version() {
    local component=$1
    local binary_path="$INSTALL_DIR/$component"

    
    # Добавляем .exe для Windows если нужно
    if [[ "$OS" == *"MINGW"* ]] || [[ "$OS" == *"MSYS"* ]] || [[ "$OS" == *"CYGWIN"* ]] || [ "$OS" = "Windows" ]; then
        if [ ! -f "$binary_path" ] && [ -f "${binary_path}.exe" ]; then
            binary_path="${binary_path}.exe"
        fi
    fi
    
    if [ ! -f "$binary_path" ]; then
        echo "0.0.0"
        return 1
    fi
    
    # Пытаемся получить версию из бинарника
    local version=$("$binary_path" --version 2>/dev/null | grep -oP 'version \Kv[0-9]+\.[0-9]+\.[0-9]+' || echo "0.0.0")
    echo "$version"
}

# Проверка целостности файла через checksum
verify_checksum() {
    local file=$1
    local checksum_file=$2
    
    if [ ! -f "$checksum_file" ]; then
        log_warning "Файл checksum не найден: $checksum_file"
        return 1
    fi
    
    local expected_checksum=$(grep "$(basename "$file")" "$checksum_file" | awk '{print $1}')
    
    if [ -z "$expected_checksum" ]; then
        log_warning "Checksum для $(basename "$file") не найден в $checksum_file"
        return 1
    fi
    
    local actual_checksum
    if command -v sha256sum &> /dev/null; then
        actual_checksum=$(sha256sum "$file" | awk '{print $1}')
    elif command -v shasum &> /dev/null; then
        actual_checksum=$(shasum -a 256 "$file" | awk '{print $1}')
    else
        log_error "Не найдена команда для вычисления checksum (sha256sum или shasum)"
        return 1
    fi
    
    if [ "$expected_checksum" = "$actual_checksum" ]; then
        log_success "Checksum проверен успешно для $(basename "$file")"
        return 0
    else
        log_error "Checksum не совпадает для $(basename "$file")"
        log_error "Ожидалось: $expected_checksum"
        log_error "Получено:  $actual_checksum"
        return 1
    fi
}

# Создание резервной копии
create_backup() {
    local component=$1
    local version=$2
    local backup_name="${component}_${version}_$(date +%Y%m%d_%H%M%S).tar.gz"
    local backup_path="$BACKUP_DIR/$backup_name"
    
    log_info "Создание резервной копии $component версии $version..."
    
    # Создаем директорию для бэкапов если её нет
    mkdir -p "$BACKUP_DIR"
    
    # Архивируем
    if tar -czf "$backup_path" -C "$INSTALL_DIR" "$component" 2>/dev/null; then
        log_success "Резервная копия создана: $backup_path"
        echo "$backup_path"
    else
        log_error "Не удалось создать резервную копию"
        return 1
    fi
}

# Восстановление из резервной копии
restore_backup() {
    local component=$1
    local backup_file=$2
    
    if [ ! -f "$backup_file" ]; then
        log_error "Файл резервной копии не найден: $backup_file"
        return 1
    fi
    
    log_info "Восстановление $component из резервной копии..."
    
    # Удаление текущей версии
    rm -rf "$INSTALL_DIR/$component"
    mkdir -p "$INSTALL_DIR/$component"
    
    # Распаковка резервной копии
    if tar -xzf "$backup_file" -C "$INSTALL_DIR/$component"; then
        log_success "Восстановление завершено успешно"
        return 0
    else
        log_error "Ошибка при восстановлении из резервной копии"
        return 1
    fi
}

# Получение последней резервной копии
get_latest_backup() {
    local component=$1
    ls -t "$BACKUP_DIR/${component}_"*.tar.gz 2>/dev/null | head -1
}

# Валидация версии
validate_version() {
    local version=$1
    
    if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9\.]+)?$ ]]; then
        log_error "Неверный формат версии: $version"
        log_error "Используйте формат: X.Y.Z или X.Y.Z-PRERELEASE"
        return 1
    fi
    
    return 0
}

# Сравнение версий
compare_versions() {
    local ver1=$1
    local ver2=$2
    
    # Удаляем префикс v если есть
    ver1=${ver1#v}
    ver2=${ver2#v}
    
    # Сравниваем через sort -V
    if command -v sort &> /dev/null && sort --version 2>&1 | grep -q GNU; then
        local sorted=$(printf "%s\n%s" "$ver1" "$ver2" | sort -V)
        local first=$(echo "$sorted" | head -1)
        
        if [ "$ver1" = "$ver2" ]; then
            echo "equal"
        elif [ "$ver1" = "$first" ]; then
            echo "older"
        else
            echo "newer"
        fi
    else
        # Простое сравнение через awk если sort -V не доступен
        local v1=$(echo "$ver1" | awk -F. '{ printf("%03d%03d%03d\n", $1, $2, $3) }')
        local v2=$(echo "$ver2" | awk -F. '{ printf("%03d%03d%03d\n", $1, $2, $3) }')
        
        if [ "$v1" -eq "$v2" ]; then
            echo "equal"
        elif [ "$v1" -lt "$v2" ]; then
            echo "older"
        else
            echo "newer"
        fi
    fi
}

# Проверка доступности сети
check_network() {
    if curl -s --connect-timeout 5 https://api.github.com > /dev/null; then
        return 0
    else
        log_warning "Нет доступа к интернету или GitHub API недоступен"
        return 1
    fi
}

# Ожидание с прогресс-баром
wait_with_progress() {
    local seconds=$1
    local message=${2:-"Ожидание"}
    
    echo -n "$message "
    for ((i=0; i<seconds; i++)); do
        echo -n "."
        sleep 1
    done
    echo " Готово!"
}

# Отправка уведомления (заглушка для расширения)
send_notification() {
    local title=$1
    local message=$2
    local level=${3:-"info"}
    
    log_info "Уведомление [$level]: $title - $message"
    # Здесь можно добавить интеграцию с email, Slack, Telegram и т.д.
}

# Загрузка файла с проверкой
download_file() {
    local url=$1
    local output=$2
    local max_retries=${3:-3}
    local retry_delay=${4:-5}
    
    for ((i=1; i<=max_retries; i++)); do
        log_info "Загрузка $url (попытка $i/$max_retries)..."
        
        if wget -q --show-progress -O "$output" "$url"; then
            log_success "Файл загружен: $output"
            return 0
        fi
        
        if [ $i -lt $max_retries ]; then
            log_warning "Ошибка загрузки, повтор через $retry_delay секунд..."
            sleep "$retry_delay"
        fi
    done
    
    log_error "Не удалось загрузить файл после $max_retries попыток: $url"
    return 1
}

# Проверка свободного места
check_disk_space() {
    local required_mb=$1
    
    if [ "$OS" = "Linux" ] || [ "$OS" = "macOS" ]; then
        local available_mb=$(df -m "$INSTALL_DIR" | awk 'NR==2 {print $4}')
    elif [[ "$OS" == *"MINGW"* ]] || [[ "$OS" == *"MSYS"* ]]; then
        local available_mb=$(df -m "$INSTALL_DIR" | awk 'NR==2 {print $4}')
    else
        log_warning "Проверка свободного места не поддерживается для ОС: $OS"
        return 0
    fi
    
    if [ "$available_mb" -lt "$required_mb" ]; then
        log_error "Недостаточно свободного места. Требуется: ${required_mb}MB, доступно: ${available_mb}MB"
        return 1
    fi
    
    log_info "Достаточно свободного места: ${available_mb}MB"
    return 0
}

# Получение времени модификации файла (кроссплатформенное)
get_file_modification_time() {
    local file=$1
    
    if [ ! -f "$file" ]; then
        echo "0"
        return 1
    fi
    
    # Определяем команду в зависимости от ОС
    if command -v stat &> /dev/null; then
        # Проверяем, какая версия stat доступна
        if stat --version 2>&1 | grep -q GNU; then
            # GNU stat (Linux)
            stat -c %Y "$file" 2>/dev/null || echo "0"
        else
            # BSD stat (macOS)
            stat -f %m "$file" 2>/dev/null || echo "0"
        fi
    elif command -v perl &> /dev/null; then
        # Используем Perl как универсальное решение
        perl -e 'print ((stat($ARGV[0]))[9])' "$file" 2>/dev/null || echo "0"
    elif command -v python3 &> /dev/null; then
        # Используем Python 3
        python3 -c "import os; print(int(os.path.getmtime('$file')))" 2>/dev/null || echo "0"
    elif command -v python &> /dev/null; then
        # Используем Python 2
        python -c "import os; print(int(os.path.getmtime('$file')))" 2>/dev/null || echo "0"
    else
        # Последнее средство: использовать дату файла через ls (не точно, но лучше чем ничего)
        if [ "$OS" = "Linux" ] || [ "$OS" = "macOS" ]; then
            ls -l --time-style=+%s "$file" 2>/dev/null | awk '{print $6}' | head -1 || echo "0"
        else
            echo "0"
        fi
    fi
}

# Форматирование Unix timestamp в читаемую дату (кроссплатформенное)
format_unix_timestamp() {
    local timestamp=$1
    local format=${2:-"%Y-%m-%d %H:%M:%S"}
    
    if [ -z "$timestamp" ] || [ "$timestamp" = "0" ]; then
        echo "N/A"
        return 0
    fi
    
    # Пытаемся использовать date с поддержкой разных ОС
    if date --version 2>&1 | grep -q GNU; then
        # GNU date (Linux)
        date -d "@$timestamp" "+$format" 2>/dev/null || echo "N/A"
    elif command -v date &> /dev/null; then
        # BSD date (macOS) или другие
        if date -j -f "%s" "$timestamp" "+$format" 2>/dev/null; then
            return 0
        else
            # Попробуем альтернативный подход
            if command -v perl &> /dev/null; then
                perl -e "print scalar(localtime($timestamp))" 2>/dev/null || echo "N/A"
            else
                echo "N/A"
            fi
        fi
    else
        echo "N/A"
    fi
}

# Получение размера файла в байтах (кроссплатформенное)
get_file_size() {
    local file=$1
    
    if [ ! -f "$file" ]; then
        echo "unknown"
        return 1
    fi
    
    if command -v stat &> /dev/null; then
        if stat --version 2>&1 | grep -q GNU; then
            # GNU stat (Linux)
            stat -c %s "$file" 2>/dev/null || echo "unknown"
        else
            # BSD stat (macOS)
            stat -f %z "$file" 2>/dev/null || echo "unknown"
        fi
    elif command -v perl &> /dev/null; then
        perl -e 'print -s $ARGV[0]' "$file" 2>/dev/null || echo "unknown"
    elif command -v wc &> /dev/null; then
        # wc -c работает везде, но медленно для больших файлов
        wc -c < "$file" 2>/dev/null || echo "unknown"
    else
        echo "unknown"
    fi
}

# Получение даты модификации файла в формате YYYY-MM-DD (кроссплатформенное)
get_file_modification_date() {
    local file=$1
    
    if [ ! -f "$file" ]; then
        echo "unknown"
        return 1
    fi
    
    local timestamp
    timestamp=$(get_file_modification_time "$file")
    
    if [ "$timestamp" != "0" ]; then
        format_unix_timestamp "$timestamp" "%Y-%m-%d"
    else
        echo "unknown"
    fi
}

# Кроссплатформенное рекурсивное перечисление файлов
# Используется вместо 'find' для совместимости с Windows
list_files_recursive() {
    local dir=$1
    
    if [ ! -d "$dir" ]; then
        log_error "Директория не существует: $dir"
        return 1
    fi
    
    # Для Unix-систем используем find если доступен
    if command -v find >/dev/null 2>&1 && ! command -v find | grep -q "C:\\Windows"; then
        # Проверяем, что это не Windows find
        if find --version >/dev/null 2>&1; then
            # Это Unix find
            find "$dir" -type f
            return 0
        fi
    fi
    
    # Для Windows или когда find недоступен, используем рекурсивный обход
    local file
    for file in "$dir"/*; do
        if [ -f "$file" ]; then
            echo "$file"
        elif [ -d "$file" ]; then
            list_files_recursive "$file"
        fi
    done
}

# Экспорт функций для использования в других скриптах
export -f log_info log_success log_warning log_error
export -f check_root check_dependencies create_directories
export -f get_current_version verify_checksum create_backup restore_backup
export -f get_latest_backup validate_version compare_versions
export -f check_network wait_with_progress send_notification
export -f download_file check_disk_space
export -f get_file_modification_time format_unix_timestamp
export -f get_file_size get_file_modification_date
export -f list_files_recursive
