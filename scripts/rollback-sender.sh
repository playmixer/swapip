#!/bin/bash
# rollback-sender.sh - откат sender компонента к предыдущей версии

set -e

# Загрузка общих функций
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common-functions.sh"

# Конфигурация
COMPONENT="sender"
INSTALL_PATH="./"
BACKUP_DIR="./backups"

# Функции
usage() {
    echo "Использование: $0 [OPTIONS]"
    echo ""
    echo "Опции:"
    echo "  --list            Показать список доступных резервных копий"
    echo "  --latest          Откатиться к последней резервной копии"
    echo "  --backup FILE     Откатиться к указанной резервной копии"
    echo "  --dry-run         Показать что будет сделано без фактического выполнения"
    echo "  --help            Показать эту справку"
    echo ""
    echo "Описание:"
    echo "  Выполняет откат sender компонента к предыдущей версии из резервной копии."
    echo ""
    echo "Пример:"
    echo "  $0 --list"
    echo "  $0 --latest"
    echo "  $0 --backup /opt/swapip/backups/sender_1.0.0_20250101_120000.tar.gz"
}

# Разбор параметров
parse_arguments() {
    ACTION="list"
    SPECIFIC_BACKUP=""
    DRY_RUN=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --list)
                ACTION="list"
                shift
                ;;
            --latest)
                ACTION="latest"
                shift
                ;;
            --backup)
                SPECIFIC_BACKUP="$2"
                ACTION="specific"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
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

# Проверка установки
check_installation() {
    if [ ! -d "$INSTALL_PATH" ]; then
        log_error "Sender не установлен в $INSTALL_PATH"
        exit 1
    fi
    
    # Проверка текущей версии
    CURRENT_VERSION=$(get_current_version "$COMPONENT")
    log_info "Текущая версия sender: $CURRENT_VERSION"
}

# Показать список резервных копий
list_backups() {
    log_info "Поиск резервных копий для $COMPONENT..."
    
    local backup_files=()
    
    # Поиск файлов резервных копий
    if [ -d "$BACKUP_DIR" ]; then
        backup_files=($(ls -t "$BACKUP_DIR/${COMPONENT}_"*.tar.gz 2>/dev/null || true))
    fi
    
    if [ ${#backup_files[@]} -eq 0 ]; then
        log_warning "Резервные копии не найдены"
        echo "Директория: $BACKUP_DIR"
        return 1
    fi
    
    echo "Доступные резервные копии:"
    echo "=========================================="
    
    for i in "${!backup_files[@]}"; do
        local file="${backup_files[$i]}"
        local filename=$(basename "$file")
        
        # Извлечение информации из имени файла
        local version=$(echo "$filename" | grep -oP "${COMPONENT}_\K[0-9]+\.[0-9]+\.[0-9]+")
        local date_part=$(echo "$filename" | grep -oP '[0-9]{8}_[0-9]{6}')
        local date_formatted=$(echo "$date_part" | sed 's/\([0-9]\{4\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)_\([0-9]\{2\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)/\1-\2-\3 \4:\5:\6/')
        
        local size=$(du -h "$file" | cut -f1)
        
        printf "%-3s %-20s %-19s %-8s %s\n" \
            "$((i+1)))" "$version" "$date_formatted" "$size" "$filename"
    done
    
    echo "=========================================="
    echo "Всего резервных копий: ${#backup_files[@]}"
    echo ""
    echo "Для отката используйте:"
    echo "  $0 --latest                    # Откат к последней резервной копии"
    echo "  $0 --backup ФАЙЛ               # Откат к указанной копии"
    echo ""
    
    return 0
}

# Получение последней резервной копии
get_latest_backup_file() {
    local latest_backup=$(ls -t "$BACKUP_DIR/${COMPONENT}_"*.tar.gz 2>/dev/null | head -1)
    
    if [ -z "$latest_backup" ]; then
        log_error "Резервные копии не найдены"
        return 1
    fi
    
    echo "$latest_backup"
}

# Проверка резервной копии
validate_backup() {
    local backup_file=$1
    
    if [ ! -f "$backup_file" ]; then
        log_error "Файл резервной копии не найден: $backup_file"
        return 1
    fi
    
    # Проверка что это tar.gz архив
    if ! file "$backup_file" | grep -q "gzip compressed data"; then
        log_error "Файл не является gzip архивом: $backup_file"
        return 1
    fi
    
    # Проверка содержимого
    if ! tar -tzf "$backup_file" | grep -q "."; then
        log_error "Архив пуст или поврежден: $backup_file"
        return 1
    fi
    
    local filename=$(basename "$backup_file")
    local size=$(du -h "$backup_file" | cut -f1)
    
    log_info "Резервная копия проверена:"
    log_info "  Файл: $filename"
    log_info "  Размер: $size"
    
    return 0
}

# Создание резервной копии текущего состояния
backup_current_state() {
    local current_version
    current_version=$(get_current_version "$COMPONENT")
    
    log_info "Создание резервной копии текущего состояния ($current_version)..."
    
    local backup_file
    backup_file=$(create_backup "$COMPONENT" "${current_version}_pre_rollback")
    
    if [ $? -eq 0 ]; then
        log_success "Резервная копия текущего состояния создана: $backup_file"
        echo "$backup_file"
    else
        log_error "Не удалось создать резервную копию текущего состояния"
        return 1
    fi
}

# Выполнение отката
perform_rollback() {
    local backup_file=$1
    
    log_info "Начало отката из резервной копии: $(basename "$backup_file")"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "Режим dry-run: откат не будет выполнен"
        log_info "Будет восстановлено из: $backup_file"
        log_info "В директорию: $INSTALL_PATH"
        return 0
    fi
    
    # Создание резервной копии текущего состояния
    local pre_rollback_backup=""
    if [ "$DRY_RUN" = false ]; then
        pre_rollback_backup=$(backup_current_state)
    fi
    
    # Удаление текущей версии
    log_info "Удаление текущей версии из $INSTALL_PATH..."
    rm -rf "$INSTALL_PATH"/*
    
    # Восстановление из резервной копии
    log_info "Восстановление из резервной копии..."
    
    if tar -xzf "$backup_file" -C "$INSTALL_PATH"; then
        log_success "Файлы восстановлены"
        
        # Установка прав
        chmod +x "$INSTALL_PATH/$COMPONENT" 2>/dev/null || true
        
        # Проверка восстановленной версии
        local restored_version
        restored_version=$(get_current_version "$COMPONENT")
        
        log_success "Версия после отката: $restored_version"
    else
        log_error "Ошибка при восстановлении из резервной копии"
        
        # Попытка восстановления из pre_rollback backup
        if [ -n "$pre_rollback_backup" ] && [ -f "$pre_rollback_backup" ]; then
            log_error "Попытка восстановления из резервной копии до отката..."
            tar -xzf "$pre_rollback_backup" -C "$INSTALL_PATH"
        fi
        
        return 1
    fi
    
    return 0
}

# Откат к последней резервной копии
rollback_to_latest() {
    log_info "Поиск последней резервной копии..."
    
    local latest_backup
    latest_backup=$(get_latest_backup_file)
    
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    log_info "Найдена резервная копия: $(basename "$latest_backup")"
    
    # Проверка резервной копии
    if ! validate_backup "$latest_backup"; then
        return 1
    fi
    
    # Выполнение отката
    if perform_rollback "$latest_backup"; then
        log_success "Откат к последней резервной копии выполнен успешно"
        return 0
    else
        log_error "Ошибка при откате к последней резервной копии"
        return 1
    fi
}

# Откат к указанной резервной копии
rollback_to_specific() {
    local backup_file=$SPECIFIC_BACKUP
    
    log_info "Откат к указанной резервной копии: $backup_file"
    
    # Проверка резервной копии
    if ! validate_backup "$backup_file"; then
        return 1
    fi
    
    # Подтверждение
    if [ "$DRY_RUN" = false ]; then
        echo ""
        echo "Вы собираетесь выполнить откат sender:"
        echo "  Из: $backup_file"
        echo "  В: $INSTALL_PATH"
        echo ""
        echo "Текущая версия будет сохранена в резервной копии."
        echo ""
        
        read -p "Продолжить? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Откат отменен"
            exit 0
        fi
    fi
    
    # Выполнение отката
    if perform_rollback "$backup_file"; then
        log_success "Откат к указанной резервной копии выполнен успешно"
        return 0
    else
        log_error "Ошибка при откате к указанной резервной копии"
        return 1
    fi
}

# Основная функция
main() {
    log_info "Начало работы скрипта отката sender..."
    
    # Проверка прав
    check_root
    
    # Разбор параметров
    parse_arguments "$@"
    
    # Проверка зависимостей
    check_dependencies
    
    # Проверка установки
    check_installation
    
    case $ACTION in
        "list")
            # Показать список резервных копий
            list_backups
            ;;
        "latest")
            # Откат к последней резервной копии
            rollback_to_latest
            ;;
        "specific")
            # Откат к указанной резервной копии
            if [ -z "$SPECIFIC_BACKUP" ]; then
                log_error "Не указан файл резервной копии"
                usage
                exit 1
            fi
            rollback_to_specific
            ;;
        *)
            log_error "Неизвестное действие: $ACTION"
            exit 1
            ;;
    esac
    
    # Итоговая информация
    if [ $? -eq 0 ] && [ "$ACTION" != "list" ]; then
        log_success "=========================================="
        log_success "Откат sender выполнен успешно!"
        log_success ""
        log_success "Текущая версия: $(get_current_version "$COMPONENT")"
        log_success ""
        log_success "Команды управления:"
        log_success "  Запуск: ./$COMPONENT"
        log_success "  Проверка версии: ./$COMPONENT --version"
        log_success ""
        log_success "Для повторного отката используйте:"
        log_success "  $0 --list"
        log_success "=========================================="
    fi
}

# Запуск основной функции
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi