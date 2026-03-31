#!/bin/bash
set -u
set -o pipefail

# ==========================================
# [0] 설정 및 경로 정의
# ==========================================
CONFIG_FILE="$HOME/.log-archive.conf"
LOG_FILE="$HOME/.log-archive-tool.log"
LOCK_FILE="$HOME/.log-archive-tool.lock"
CRON_MARKER="# log-archive-tool"
MIN_DISK_FREE_MB=500

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 내부 상태 변수
PENDING_CRON_ACTION="none"

log_dir=""
days_to_keep_logs="7"
days_to_keep_backups="30"
cron_hour="2"
cron_minute="0"
cron_mode="daily"
cron_days_of_week="1-5"

SCRIPT_PATH="$(readlink -f "$0")"

# ==========================================
# [1] 유틸리티 및 조회 함수
# ==========================================
log_msg() { echo "[$(date '+%F %T')] $*"; }
is_uint() { [[ "${1:-}" =~ ^[0-9]+$ ]]; }

prompt_for_input() {
    local input
    read -r -p "$1 [$2]: " input
    echo "${input:-$2}"
}

prompt_int_range() {
    local value
    while true; do
        read -r -p "$1 [$2]: " value
        value="${value:-$2}"
        if is_uint "$value" && (( 10#$value >= $3 && 10#$value <= $4 )); then
            echo "$value"; return 0
        fi
        echo -e "${RED}범위: $3~$4${NC}"
    done
}

schedule_desc() {
    case "$cron_mode" in
        daily)   printf "매일 %02d:%02d" "$cron_hour" "$cron_minute" ;;
        weekday) printf "주중(월~금) %02d:%02d" "$cron_hour" "$cron_minute" ;;
        custom)  printf "지정 요일(%s) %02d:%02d" "$cron_days_of_week" "$cron_hour" "$cron_minute" ;;
    esac
}

cron_line() {
    local df; case "$cron_mode" in weekday) df="1-5" ;; custom) df="${cron_days_of_week:-1-5}" ;; *) df="*" ;; esac
    echo "$cron_minute $cron_hour * * $df $(printf '%q' "$SCRIPT_PATH") --auto >> $(printf '%q' "$LOG_FILE") 2>&1 $CRON_MARKER"
}

cron_list() { crontab -l 2>/dev/null || true; }

final_check_crontab() {
    echo -e "\n${YELLOW}=========================================="
    echo "       [최종 시스템 크론탭 확인]"
    echo -e "==========================================${NC}"
    local list=$(cron_list)
    if [ -n "$list" ]; then
        echo "$list" | grep --color=always -E "$CRON_MARKER|$SCRIPT_PATH|$"
    else
        echo "현재 등록된 크론탭 작업이 없습니다."
    fi
    echo -e "${YELLOW}==========================================${NC}\n"
}

# ==========================================
# [2] 시스템 반영 및 아카이브 로직
# ==========================================
load_config() {
    [ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"
    log_dir="${log_dir:-}"; days_to_keep_logs="${days_to_keep_logs:-7}"
    days_to_keep_backups="${days_to_keep_backups:-30}"
    cron_hour="${cron_hour:-2}"; cron_minute="${cron_minute:-0}"
    cron_mode="${cron_mode:-daily}"; cron_days_of_week="${cron_days_of_week:-1-5}"
}

apply_changes_to_system() {
    echo -e "\n${YELLOW}설정을 저장하고 크론탭에 반영합니다...${NC}"
    cat <<EOF > "$CONFIG_FILE"
log_dir="$log_dir"
days_to_keep_logs="$days_to_keep_logs"
days_to_keep_backups="$days_to_keep_backups"
cron_hour="$cron_hour"
cron_minute="$cron_minute"
cron_mode="$cron_mode"
cron_days_of_week="$cron_days_of_week"
EOF
    local cc="$(cron_list)"
    case "$PENDING_CRON_ACTION" in
        register)
            local nl="$(cron_line)"
            { echo "$cc" | grep -Fv "$SCRIPT_PATH" | grep -Fv "$CRON_MARKER"; echo "$nl"; } | crontab - ;;
        remove)
            local fc="$(echo "$cc" | grep -Fv "$SCRIPT_PATH" | grep -Fv "$CRON_MARKER")"
            if [ -n "$fc" ]; then printf '%s\n' "$fc" | crontab -; else crontab -r; fi ;;
    esac
}

# 실제 자동 실행 시 호출되는 핵심 로직
run_archive() {
    if [ -z "$log_dir" ] || [ ! -d "$log_dir" ]; then return 1; fi

    # 중복 실행 방지 (운영 환경 필수)
    exec 200>"$LOCK_FILE"
    if ! flock -n 200; then log_msg "이미 실행 중인 프로세스가 있어 중단합니다."; return 1; fi

    archive_dir="$log_dir/archive"; mkdir -p "$archive_dir"
    archive_file="$archive_dir/logs_$(date +"%Y%m%d_%H%M%S").tar.gz"

    mapfile -d '' files < <(find "$log_dir" -maxdepth 1 -type f -mtime +"$days_to_keep_logs" -print0)
    if [ ${#files[@]} -eq 0 ]; then log_msg "아카이브할 대상 파일이 없습니다."; return 0; fi

    if printf '%s\0' "${files[@]}" | tar -czf "$archive_file" --null -T -; then
        printf '%s\0' "${files[@]}" | xargs -0 rm -f
        find "$archive_dir" -name "*.tar.gz" -type f -mtime +"$days_to_keep_backups" -delete
        log_msg "아카이브 완료: $(basename "$archive_file")"
    fi
}

# ==========================================
# [3] 메인 메뉴
# ==========================================
load_config
[[ "${1:-}" == "--auto" ]] && { run_archive; exit $?; }

while true; do
    echo -e "\n=========================================="
    echo "    로그 관리 도구 (운영 환경 최적화)"
    echo "=========================================="
    echo "1. 로그 디렉토리 설정 (대상: ${log_dir:-미설정})"
    echo "2. 보관/보존 기간 설정 (원본 $days_to_keep_logs 일 / 백업 $days_to_keep_backups 일)"
    echo "3. 자동 실행 스케줄 설정 ($(schedule_desc))"
    echo -e "4. Cron 등록/수정 예약 (상태: ${YELLOW}$PENDING_CRON_ACTION${NC})"
    echo "5. Cron 삭제 예약"
    echo "6. 현재 시스템 크론탭 실시간 조회"
    echo -e "${GREEN}7. 설정 반영 및 종료 (crontab -l 확인)${NC}"
    echo -e "${RED}8. 무시하고 그냥 종료 (crontab -l 확인)${NC}"
    echo "=========================================="
    read -r -p "선택 [1-8]: " choice

    case "$choice" in
        1) temp=$(prompt_for_input "경로" "/var/log")
           [ -d "$temp" ] && log_dir="$temp" || echo -e "${RED}유효한 경로가 아닙니다.${NC}" ;;
        2) days_to_keep_logs=$(prompt_for_input "원본보관" "$days_to_keep_logs")
           days_to_keep_backups=$(prompt_for_input "백업보존" "$days_to_keep_backups") ;;
        3) read -r -p "1:매일, 2:주중, 3:요일: " mc
           [ "$mc" == "1" ] && cron_mode="daily"
           [ "$mc" == "2" ] && cron_mode="weekday"
           [ "$mc" == "3" ] && { cron_days_of_week=$(prompt_for_input "요일" "1,3,5"); cron_mode="custom"; }
           cron_hour=$(prompt_int_range "시" "$cron_hour" 0 23)
           cron_minute=$(prompt_int_range "분" "$cron_minute" 0 59) ;;
        4) PENDING_CRON_ACTION="register" ;;
        5) PENDING_CRON_ACTION="remove" ;;
        6) echo -e "\n--- 시스템 크론탭 상태 ---"
           cron_list | grep -F "$CRON_MARKER" || echo "등록된 아카이브 작업이 없습니다." ;;
        7) apply_changes_to_system
           final_check_crontab
           exit 0 ;;
        8) echo "변경 사항을 무시하고 종료합니다."
           final_check_crontab
           exit 0 ;;
        *) echo -e "${RED}잘못된 입력입니다.${NC}" ;;
    esac
done
