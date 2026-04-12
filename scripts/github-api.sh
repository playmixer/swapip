#!/bin/bash
# github-api.sh - функции для работы с GitHub API

set -e

# Загрузка общих функций
if [ -f "$(dirname "$0")/common-functions.sh" ]; then
    source "$(dirname "$0")/common-functions.sh"
else
    echo "ОШИБКА: Не найден файл common-functions.sh"
    exit 1
fi

# Конфигурация GitHub
GITHUB_API_BASE="https://api.github.com"
GITHUB_REPO_OWNER="playmixer"  # Заменить на актуального владельца репозитория
GITHUB_REPO_NAME="swapip"   # Заменить на имя репозитория
CACHE_FILE="$CACHE_DIR/last_check.json"
CACHE_TTL=3600  # 1 час в секундах

# Получение последнего релиза из GitHub
get_latest_release() {
    local use_cache=${1:-true}
    
    # Проверка кэша если запрошено
    if [ "$use_cache" = "true" ] && [ -f "$CACHE_FILE" ]; then
        local cache_age=$(($(date +%s) - $(get_file_modification_time "$CACHE_FILE")))
        
        if [ "$cache_age" -lt "$CACHE_TTL" ]; then
            log_info "Используются кэшированные данные (возраст: ${cache_age}с)"
            # Проверяем валидность JSON в кэше
            if jq . "$CACHE_FILE" > /dev/null 2>&1; then
                cat "$CACHE_FILE"
                return 0
            else
                log_warning "Кэш-файл содержит невалидный JSON, игнорируем"
                rm -f "$CACHE_FILE"
            fi
        fi
    fi
    
    # Проверка сети
    if ! check_network; then
        log_warning "Нет доступа к сети, использование кэшированных данных если доступны"
        if [ -f "$CACHE_FILE" ]; then
            # Проверяем валидность JSON в кэше
            if jq . "$CACHE_FILE" > /dev/null 2>&1; then
                cat "$CACHE_FILE"
                return 0
            else
                log_warning "Кэш-файл содержит невалидный JSON, игнорируем"
                rm -f "$CACHE_FILE"
                log_error "Нет кэшированных данных и нет доступа к сети"
                echo "{}"
                return 1
            fi
        else
            log_error "Нет кэшированных данных и нет доступа к сети"
            echo "{}"
            return 1
        fi
    fi
    
    log_info "Запрос к GitHub API для получения последнего релиза..."
    
    local api_url="$GITHUB_API_BASE/repos/$GITHUB_REPO_OWNER/$GITHUB_REPO_NAME/releases/latest"
    local response
    local http_code

    log_info "$api_url"
    
    # Выполняем запрос с обработкой ошибок
    response=$(curl -s -w "%{http_code}" "$api_url" -H "Accept: application/vnd.github.v3+json")
    http_code=${response: -3}
    response=${response%???}
    
    if [ "$http_code" -eq 200 ]; then
        # Сохраняем в кэш
        echo "$response" > "$CACHE_FILE"
        chmod 644 "$CACHE_FILE"
        
        log_success "Данные успешно получены и сохранены в кэш"
        echo "$response"
        return 0
    elif [ "$http_code" -eq 404 ]; then
        log_warning "Релизы не найдены в репозитории"
        echo "{}"
        return 1
    elif [ "$http_code" -eq 403 ]; then
        log_warning "Rate limit превышен (HTTP 403)"
        
        # Пытаемся получить информацию о rate limit
        local rate_info=$(curl -s "$GITHUB_API_BASE/rate_limit" -H "Accept: application/vnd.github.v3+json")
        local reset_time=$(echo "$rate_info" | jq -r '.resources.core.reset // 0')
        
        if [ "$reset_time" -gt 0 ]; then
            local reset_date=$(format_unix_timestamp "$reset_time" "%H:%M:%S")
            log_info "Rate limit сбросится в $reset_date"
        fi
        
        # Используем кэш если есть
        if [ -f "$CACHE_FILE" ]; then
            # Проверяем валидность JSON в кэше
            if jq . "$CACHE_FILE" > /dev/null 2>&1; then
                log_info "Используем кэшированные данные из-за rate limit"
                cat "$CACHE_FILE"
                return 0
            else
                log_warning "Кэш-файл содержит невалидный JSON, игнорируем"
                rm -f "$CACHE_FILE"
                log_error "Нет кэшированных данных для использования"
                echo "{}"
                return 1
            fi
        else
            log_error "Нет кэшированных данных для использования"
            echo "{}"
            return 1
        fi
    else
        log_error "Ошибка GitHub API: HTTP $http_code"
        echo "{}"
        return 1
    fi
}

# Получение информации о конкретном релизе по тегу
get_release_by_tag() {
    local tag=$1
    local use_cache=${2:-false}
    
    # Проверка кэша для конкретного тега
    local tag_cache_file="$CACHE_DIR/release_${tag}.json"
    if [ "$use_cache" = "true" ] && [ -f "$tag_cache_file" ]; then
        local cache_age=$(($(date +%s) - $(get_file_modification_time "$tag_cache_file")))
        
        if [ "$cache_age" -lt "$CACHE_TTL" ]; then
            log_info "Используются кэшированные данные для тега $tag"
            cat "$tag_cache_file"
            return 0
        fi
    fi
    
    log_info "Запрос к GitHub API для получения релиза $tag..."
    
    local api_url="$GITHUB_API_BASE/repos/$GITHUB_REPO_OWNER/$GITHUB_REPO_NAME/releases/tags/$tag"
    local response
    local http_code
    
    response=$(curl -s -w "%{http_code}" "$api_url" -H "Accept: application/vnd.github.v3+json")
    http_code=${response: -3}
    response=${response%???}
    
    if [ "$http_code" -eq 200 ]; then
        # Сохраняем в кэш
        echo "$response" > "$tag_cache_file"
        chmod 644 "$tag_cache_file"
        
        echo "$response"
        return 0
    else
        log_error "Ошибка при получении релиза $tag: HTTP $http_code"
        echo "{}"
        return 1
    fi
}

# Получение списка всех релизов
get_all_releases() {
    local page=${1:-1}
    local per_page=${2:-10}
    
    log_info "Запрос списка релизов (страница $page)..."
    
    local api_url="$GITHUB_API_BASE/repos/$GITHUB_REPO_OWNER/$GITHUB_REPO_NAME/releases?page=$page&per_page=$per_page"
    
    curl -s "$api_url" -H "Accept: application/vnd.github.v3+json"
}

# Получение URL для скачивания бинарника
get_download_url() {
    local release_data=$1
    local component=$2  # "sender" или "recepient"
    local platform=${3:-"linux-amd64"}
    
    # Определяем имя файла в зависимости от компонента и платформы
    local filename="swapip-${component}-${platform}"
    
    # Ищем asset с нужным именем
    local download_url=$(echo "$release_data" | jq -r ".assets[] | select(.name | contains(\"$filename\")) | .browser_download_url // empty")
    
    if [ -n "$download_url" ]; then
        echo "$download_url"
        return 0
    fi
    
    # Если не нашли точное совпадение, ищем архив с компонентом
    download_url=$(echo "$release_data" | jq -r ".assets[] | select(.name | contains(\"$component\")) | .browser_download_url // empty")
    
    if [ -n "$download_url" ]; then
        echo "$download_url"
        return 0
    fi
    
    # Если не нашли, возвращаем URL основного архива
    download_url=$(echo "$release_data" | jq -r '.assets[0].browser_download_url // empty')
    
    if [ -n "$download_url" ]; then
        echo "$download_url"
        return 0
    fi
    
    log_error "Не найден URL для скачивания компонента $component"
    return 1
}

# Получение версии из данных релиза
get_version_from_release() {
    local release_data=$1

    # Проверяем валидность JSON
    if ! echo "$release_data" | jq . > /dev/null 2>&1; then
        log_error "Получены невалидные JSON данные"
        log_info "Данные (первые 100 символов): ${release_data:0:100}"
        return 1
    fi

    # Рекурсивно ищем tag_name в JSON, также проверяем другие возможные поля
    local version=$(echo "$release_data" | jq -r '.. | .tag_name? // .version? // .tag? // empty' | head -1)
    
    if [ -n "$version" ] && [ "$version" != "null" ]; then
        # Удаляем префикс 'v' если есть
        version=${version#v}
        echo "$version"
        return 0
    fi
    
    log_error "Не удалось извлечь версию из данных релиза"
    log_info "Данные (первые 200 символов): ${release_data:0:200}"
    return 1
}

# Получение даты релиза
get_release_date() {
    local release_data=$1
    
    local date=$(echo "$release_data" | jq -r '.published_at // .created_at // empty')
    
    if [ -n "$date" ]; then
        echo "$date"
        return 0
    fi
    
    return 1
}

# Проверка наличия новой версии
check_for_updates() {
    local current_version=$1
    local component=$2
    
    log_info "Проверка обновлений для $component (текущая версия: $current_version)..."
    
    local release_data
    release_data=$(get_latest_release)
    
    if [ -z "$release_data" ] || [ "$release_data" = "{}" ]; then
        log_warning "Не удалось получить информацию о релизах"
        return 1
    fi
    
    local latest_version
    latest_version=$(get_version_from_release "$release_data")
    
    if [ $? -ne 0 ] || [ -z "$latest_version" ]; then
        log_error "Не удалось получить версию из релиза"
        return 1
    fi
    
    log_info "Последняя доступная версия: $latest_version"
    
    # Сравнение версий
    local comparison
    comparison=$(compare_versions "$current_version" "$latest_version")
    
    case "$comparison" in
        "older")
            log_success "Доступно обновление: $current_version -> $latest_version"
            echo "$latest_version"
            return 0
            ;;
        "equal")
            log_info "Установлена последняя версия: $current_version"
            echo "$current_version"
            return 1
            ;;
        "newer")
            log_warning "Установлена более новая версия чем доступная: $current_version > $latest_version"
            echo "$latest_version"
            return 1
            ;;
        *)
            log_error "Ошибка при сравнении версий"
            return 1
            ;;
    esac
}

# Очистка кэша
clear_cache() {
    log_info "Очистка кэша GitHub API..."
    
    rm -f "$CACHE_DIR"/last_check.json
    rm -f "$CACHE_DIR"/release_*.json
    
    log_success "Кэш очищен"
}

# Получение информации о rate limit
get_rate_limit() {
    log_info "Проверка rate limit GitHub API..."
    
    local response
    response=$(curl -s "$GITHUB_API_BASE/rate_limit" -H "Accept: application/vnd.github.v3+json")
    
    local limit=$(echo "$response" | jq -r '.resources.core.limit // 0')
    local remaining=$(echo "$response" | jq -r '.resources.core.remaining // 0')
    local reset=$(echo "$response" | jq -r '.resources.core.reset // 0')
    
    if [ "$reset" -gt 0 ]; then
        local reset_date=$(format_unix_timestamp "$reset" "%Y-%m-%d %H:%M:%S")
        log_info "Rate limit: $remaining/$limit (сброс в $reset_date)"
    else
        log_info "Rate limit: $remaining/$limit"
    fi
    
    echo "$remaining"
}

# Настройка репозитория
set_repository() {
    local owner=$1
    local repo=$2
    
    if [ -n "$owner" ] && [ -n "$repo" ]; then
        GITHUB_REPO_OWNER="$owner"
        GITHUB_REPO_NAME="$repo"
        log_success "Репозиторий установлен: $owner/$repo"
    else
        log_error "Необходимо указать владельца и имя репозитория"
        return 1
    fi
}

# Экспорт функций
export -f get_latest_release get_release_by_tag get_all_releases
export -f get_download_url get_version_from_release get_release_date
export -f check_for_updates clear_cache get_rate_limit set_repository