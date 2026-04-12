#!/bin/bash
# update-recepient.sh - обновление recepient компонента swapip
# Упрощенная версия: проверка версии, загрузка, бэкап, установка, очистка

set -e

# Загрузка общих функций
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common-functions.sh"
source "$SCRIPT_DIR/github-api.sh"

# Конфигурация
COMPONENT="recepient"
BINARY_NAME="recepient"
INSTALL_PATH="./"
BACKUP_DIR="./backups"
TEMP_DIR="./tmp/swapip-update"
ARCHIVE_FILE=""

# Для совместимости с общими функциями
INSTALL_DIR="./"

# Функции
usage() {
    echo "Использование: $0 [OPTIONS]"
    echo ""
    echo "Опции:"
    echo "  --force    Принудительное обновление даже если версия совпадает"
    echo "  --help     Показать эту справку"
    echo ""
    echo "Описание:"
    echo "  Автоматически проверяет и устанавливает обновления для recepient компонента."
    echo "  Если компонент не установлен - устанавливает последнюю версию."
    echo ""
    echo "Процесс обновления:"
    echo "  1. Проверка наличия новой версии"
    echo "  2. Если текущая версия младше или отсутствует - скачивание"
    echo "  3. Распаковка архива"
    echo "  4. Создание бэкапа текущей версии (если существует)"
    echo "  5. Установка новой версии"
    echo "  6. Удаление архива и временных файлов"
    echo ""
    echo "Пример:"
    echo "  $0"
    echo "  $0 --force"
}

# Разбор параметров
parse_arguments() {
    FORCE=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                FORCE=true
                shift
                ;;
            --help|-h)
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
}

# Получение текущей версии (если установлена)
get_current_version_safe() {
    # Создаем временную переменную для совместимости
    local temp_install_dir="$INSTALL_DIR"
    INSTALL_DIR="$INSTALL_PATH"
    
    if [ -f "$INSTALL_PATH/$BINARY_NAME" ]; then
        get_current_version "$COMPONENT"
    else
        echo "0.0.0"  # Версия по умолчанию если компонент не установлен
    fi
    
    # Восстанавливаем значение (хотя это не обязательно, так как скрипт завершится)
    INSTALL_DIR="$temp_install_dir"
}

# Проверка необходимости обновления
check_update_needed() {
    log_info "Проверка текущей версии recepient..."
    
    CURRENT_VERSION=$(get_current_version_safe)
    
    # Получение информации о последнем релизе
    local release_data
    release_data=$(get_latest_release)
    
    if [ -z "$release_data" ] || [ "$release_data" = "{}" ]; then
        log_error "Не удалось получить информацию о релизах"
        return 1
    fi
    
    # Извлекаем оригинальный тег (с префиксом v)
    RELEASE_TAG=$(echo "$release_data" | jq -r '.tag_name // empty')
    if [ -z "$RELEASE_TAG" ] || [ "$RELEASE_TAG" = "null" ]; then
        log_error "Не удалось извлечь тег релиза"
        return 1
    fi
    
    LATEST_VERSION=$(get_version_from_release "$release_data")
    
    if [ $? -ne 0 ] || [ -z "$LATEST_VERSION" ]; then
        log_error "Не удалось получить версию из релиза"
        return 1
    fi
    
    log_info "Последняя доступная версия: $LATEST_VERSION (тег: $RELEASE_TAG)"
    
    if [ "$CURRENT_VERSION" = "0.0.0" ]; then
        log_info "Recepient не установлен. Будет установлена последняя версия."
        NEED_UPDATE=true
        return 0
    fi
    
    log_info "Текущая версия recepient: $CURRENT_VERSION"
    
    if [ "$FORCE" = true ]; then
        log_info "Принудительное обновление включено"
        NEED_UPDATE=true
        return 0
    fi
    
    # Сравнение версий
    local comparison
    comparison=$(compare_versions "$CURRENT_VERSION" "$LATEST_VERSION")
    
    case "$comparison" in
        "older")
            log_success "Доступно обновление: $CURRENT_VERSION -> $LATEST_VERSION"
            NEED_UPDATE=true
            ;;
        "equal")
            log_info "Установлена последняя версия: $CURRENT_VERSION"
            NEED_UPDATE=false
            ;;
        "newer")
            log_warning "Установлена более новая версия чем доступная: $CURRENT_VERSION > $LATEST_VERSION"
            NEED_UPDATE=false
            ;;
        *)
            log_error "Ошибка при сравнении версий"
            return 1
            ;;
    esac
    
    return 0
}

# Загрузка новой версии
download_new_version() {
    local version=$LATEST_VERSION
    local tag="$RELEASE_TAG"
    
    log_info "Загрузка версии $version (тег: $tag)..."
    
    # Получение информации о релизе
    local release_data
    release_data=$(get_release_by_tag "$tag")
    
    if [ -z "$release_data" ] || [ "$release_data" = "{}" ]; then
        log_error "Не удалось получить информацию о релизе $tag"
        return 1
    fi
    
    # Получение URL для скачивания
    local download_url
    download_url=$(get_download_url "$release_data" "$COMPONENT")
    
    if [ $? -ne 0 ] || [ -z "$download_url" ]; then
        log_error "Не удалось получить URL для скачивания"
        return 1
    fi
    
    log_info "URL для скачивания: $download_url"
    
    # Определение имени файла
    local filename=$(basename "$download_url")
    ARCHIVE_FILE="$TEMP_DIR/$filename"
    
    # Создание временной директории
    mkdir -p "$TEMP_DIR"
    
    # Загрузка файла
    if ! download_file "$download_url" "$ARCHIVE_FILE"; then
        log_error "Ошибка загрузки файла"
        return 1
    fi
    
    log_success "Архив загружен: $ARCHIVE_FILE"
    return 0
}

# Распаковка архива
extract_archive() {
    log_info "Распаковка архива..."
    
    if [ ! -f "$ARCHIVE_FILE" ]; then
        log_error "Архив не найден: $ARCHIVE_FILE"
        return 1
    fi
    
    # Распаковка архива
    if [[ "$ARCHIVE_FILE" == *.tar.gz ]] || [[ "$ARCHIVE_FILE" == *.tgz ]]; then
        tar -xzf "$ARCHIVE_FILE" -C "$TEMP_DIR"
    elif [[ "$ARCHIVE_FILE" == *.zip ]]; then
        unzip -q "$ARCHIVE_FILE" -d "$TEMP_DIR"
    else
        log_error "Неподдерживаемый формат архива: $ARCHIVE_FILE"
        return 1
    fi
    
    # Поиск бинарника в распакованных файлах
    DOWNLOADED_BINARY=$(find "$TEMP_DIR" -name "$BINARY_NAME" -type f | head -1)
    
    if [ -z "$DOWNLOADED_BINARY" ]; then
        log_error "Бинарник $BINARY_NAME не найден в архиве"
        return 1
    fi
    
    log_success "Архив распакован. Бинарник найден: $DOWNLOADED_BINARY"
    
    # Проверка checksum если доступен
    local checksum_file=$(find "$TEMP_DIR" -name "checksums.txt" -type f | head -1)
    if [ -n "$checksum_file" ]; then
        log_info "Проверка checksum..."
        if verify_checksum "$DOWNLOADED_BINARY" "$checksum_file"; then
            log_success "Checksum проверен успешно"
        else
            log_error "Checksum не совпадает"
            return 1
        fi
    fi
    
    return 0
}

# Создание бэкапа текущей версии
create_backup_if_exists() {
    if [ -f "$INSTALL_PATH/$BINARY_NAME" ]; then
        log_info "Создание резервной копии текущей версии..."
        BACKUP_FILE=$(create_backup "$COMPONENT" "$CURRENT_VERSION")
        
        if [ $? -ne 0 ]; then
            log_error "Не удалось создать резервную копию"
            return 1
        fi
        
        log_success "Резервная копия создана: $BACKUP_FILE"
    else
        log_info "Текущая версия не установлена, бэкап не требуется"
    fi
    
    return 0
}

# Установка новой версии
install_new_version() {
    log_info "Установка новой версии..."
    
    # Проверка бинарника
    if [ ! -f "$DOWNLOADED_BINARY" ]; then
        log_error "Загруженный бинарник не найден: $DOWNLOADED_BINARY"
        return 1
    fi
    
    # Проверка версии бинарника
    log_info "Проверка версии нового бинарника..."
    local new_version
    new_version=$("$DOWNLOADED_BINARY" --version 2>/dev/null | grep -oP 'version \K[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
    
    if [ "$new_version" = "unknown" ]; then
        log_warning "Не удалось определить версию нового бинарника"
    else
        log_info "Версия нового бинарника: $new_version"
    fi
    
    # Создание директории установки если не существует
    mkdir -p "$(dirname "$INSTALL_PATH/$BINARY_NAME")"
    
    # Копирование бинарника
    log_info "Копирование бинарника в $INSTALL_PATH..."
    cp -f "$DOWNLOADED_BINARY" "$INSTALL_PATH/$BINARY_NAME"
    chmod +x "$INSTALL_PATH/$BINARY_NAME"
    
    # Проверка что бинарник работает
    log_info "Проверка работоспособности бинарника..."
    if ! "$INSTALL_PATH/$BINARY_NAME" --version &>/dev/null; then
        log_error "Новый бинарник не работает"
        return 1
    fi
    
    log_success "Новая версия установлена"
    return 0
}

# Очистка временных файлов
cleanup_temp_files() {
    log_info "Очистка временных файлов..."
    
    # Удаление архива если он существует
    if [ -f "$ARCHIVE_FILE" ]; then
        rm -f "$ARCHIVE_FILE"
        log_info "Архив удален: $ARCHIVE_FILE"
    fi
    
    # Удаление временной директории
    if [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
        log_info "Временная директория удалена: $TEMP_DIR"
    fi
    
    log_success "Очистка завершена"
}

# Основная функция
main() {
    log_info "Начало работы скрипта обновления recepient..."
    
    # Проверка прав
    check_root
    
    # Разбор параметров
    parse_arguments "$@"
    
    # Проверка зависимостей
    check_dependencies
    
    # Проверка необходимости обновления
    if ! check_update_needed; then
        log_error "Ошибка при проверке обновлений"
        exit 1
    fi
    
    if [ "$NEED_UPDATE" = false ]; then
        log_info "Обновление не требуется"
        exit 0
    fi
    
    log_info "Начало процесса обновления..."
    
    # Шаг 1: Загрузка новой версии
    if ! download_new_version; then
        log_error "Ошибка при загрузке новой версии"
        exit 1
    fi
    
    # Шаг 2: Распаковка архива
    if ! extract_archive; then
        log_error "Ошибка при распаковке архива"
        cleanup_temp_files
        exit 1
    fi
    
    # Шаг 3: Создание бэкапа текущей версии
    if ! create_backup_if_exists; then
        log_error "Ошибка при создании бэкапа"
        cleanup_temp_files
        exit 1
    fi
    
    # Шаг 4: Установка новой версии
    if ! install_new_version; then
        log_error "Ошибка при установке новой версии"
        
        # Попытка отката из бэкапа
        if [ -n "$BACKUP_FILE" ] && [ -f "$BACKUP_FILE" ]; then
            log_info "Попытка восстановления из бэкапа..."
            if restore_backup "$COMPONENT" "$BACKUP_FILE"; then
                log_success "Откат выполнен успешно"
            else
                log_error "Ошибка при откате"
            fi
        fi
        
        cleanup_temp_files
        exit 1
    fi
    
    # Шаг 5: Очистка временных файлов
    cleanup_temp_files
    
    # Проверка версии после обновления
    local updated_version
    updated_version=$(get_current_version "$COMPONENT")
    
    log_success "Обновление завершено успешно!"
    log_success "Текущая версия: $updated_version"
    
    # Отправка уведомления
    send_notification "Recepient обновлен" "Версия $CURRENT_VERSION -> $updated_version" "success" 2>/dev/null || true
    
    exit 0
}

# Запуск основной функции
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi