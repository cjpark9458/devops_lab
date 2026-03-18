#!/bin/bash

# [0] 설정 및 색상 정의
CONFIG_FILE="$HOME/.log-archive.conf"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 기본값 설정
log_dir=""
days_to_keep_logs="7"
days_to_keep_backups="30"

# [1] 설정 불러오기/저장 함수
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    fi
}

save_config() {
    cat <<EOF > "$CONFIG_FILE"
log_dir="$log_dir"
days_to_keep_logs="$days_to_keep_logs"
days_to_keep_backups="$days_to_keep_backups"
EOF
}

# [2] 유틸리티 함수
prompt_for_input() {
    read -r -p "$1 [$2]: " input
    echo "${input:-$2}"
}

# [3] 핵심 아카이브 로직 (수동/자동 공통 사용)
run_archive() {
    if [ -z "$log_dir" ] || [ ! -d "$log_dir" ]; then
        echo -e "${RED}오류: 로그 디렉토리가 설정되지 않았거나 존재하지 않습니다.${NC}"
        return 1
    fi

    archive_dir="$log_dir/archive"
    mkdir -p "$archive_dir"
    timestamp=$(date +"%Y%m%d_%H%M%S")
    archive_file="$archive_dir/logs_backup_$timestamp.tar.gz"

    echo -e "${YELLOW}대상 파일을 검색 중입니다... (기준: $days_to_keep_logs 일)${NC}"
    files=$(find "$log_dir" -maxdepth 1 -type f -mtime +$days_to_keep_logs)

    if [ -z "$files" ]; then
        echo -e "${GREEN}아카이브할 대상이 없습니다.${NC}"
    else
        # [중요] 압축 성공 시에만 원본 삭제 (&& 사용)
        if echo "$files" | tr '\n' '\0' | tar -czvf "$archive_file" --null -T - 2>/dev/null; then
            echo "[$timestamp] $archive_file 생성 완료" >> "$archive_dir/archive_history.log"
            echo "$files" | xargs rm -f
            echo -e "${GREEN}성공: 아카이브 및 원본 삭제 완료!${NC}"

            # 오래된 백업 정리
            find "$archive_dir" -name "*.tar.gz" -type f -mtime +$days_to_keep_backups -delete
            echo "오래된 백업 정리 완료 (기준: $days_to_keep_backups 일)."
        else
            echo -e "${RED}오류: 압축 파일 생성 중 문제가 발생했습니다. 원본을 유지합니다.${NC}"
            return 1
        fi
    fi
}

# [4] Cron 설정 함수
setup_cron() {
    echo ""
    echo "--- 자동 실행(Cron) 설정 ---"
    echo "설정된 값으로 매일 새벽 2시에 자동 실행합니다."
    read -r -p "계속하시겠습니까? (y/n): " cron_choice

    if [[ "$cron_choice" == "y" || "$cron_choice" == "Y" ]]; then
        SCRIPT_PATH=$(readlink -f "$0")
        # --auto 인자를 붙여서 등록 (입력 프롬프트 건너뛰기용)
        CRON_LINE="0 2 * * * $SCRIPT_PATH --auto"

        if crontab -l 2>/dev/null | grep -q "$SCRIPT_PATH"; then
            echo -e "${YELLOW}[알림] 이미 크론탭에 등록되어 있습니다.${NC}"
        else
            (crontab -l 2>/dev/null; echo "$CRON_LINE") | crontab -
            echo -e "${GREEN}[성공] 크론탭 등록 완료: 매일 02:00 실행${NC}"
        fi
        save_config # 현재 설정을 저장하여 Cron이 읽을 수 있게 함
    else
        echo "취소되었습니다."
    fi
}

# ==========================================
# 메인 실행부
# ==========================================

load_config # 저장된 설정이 있으면 불러옴

# [A] 자동 실행 모드 (--auto 인자가 있을 때)
if [[ "$1" == "--auto" ]]; then
    run_archive
    exit 0
fi

# [B] 인터랙티브 모드 (메뉴 화면)
USER_NAME=$(prompt_for_input "사용자 이름을 입력하세요" "$USER")
echo -e "${GREEN}반갑습니다, ${USER_NAME}님! 로그 관리 도구를 시작합니다.${NC}"

while true; do
    echo ""
    echo "=========================================="
    echo "    로그 아카이브 도구 메뉴"
    echo "=========================================="
    echo "1. 로그 디렉토리 설정 (현재: ${log_dir:-미설정})"
    echo "2. 로그 보관 일수 설정 (현재: $days_to_keep_logs 일)"
    echo "3. 백업 보관 일수 설정 (현재: $days_to_keep_backups 일)"
    echo "4. 아카이브 프로세스 실행 (수동)"
    echo "5. 자동 실행(Cron) 예약 설정"
    echo "6. 설정 저장 후 종료"
    echo "=========================================="

    read -r -p "선택하세요 [1-6]: " choice

    case $choice in
        1)
            temp_dir=$(prompt_for_input "로그 디렉토리 경로" "/var/log")
            if [ ! -d "$temp_dir" ]; then
                echo -e "${RED}오류: 존재하지 않는 디렉토리입니다.${NC}"
            else
                log_dir="$temp_dir"
                echo -e "${GREEN}설정 완료: $log_dir${NC}"
            fi
            ;;
        2)
            days_to_keep_logs=$(prompt_for_input "아카이브 주기(일)" "$days_to_keep_logs")
            [[ "$days_to_keep_logs" =~ ^[0-9]+$ ]] || days_to_keep_logs="7"
            ;;
        3)
            days_to_keep_backups=$(prompt_for_input "백업 보관 주기(일)" "$days_to_keep_backups")
            [[ "$days_to_keep_backups" =~ ^[0-9]+$ ]] || days_to_keep_backups="30"
            ;;
        4)
            run_archive
            ;;
        5)
            setup_cron
            ;;
        6)
            save_config
            echo -e "${GREEN}설정을 저장하고 프로그램을 종료합니다.${NC}"
            break
            ;;
        *)
            echo -e "${RED}잘못된 선택입니다. 1~6을 입력하세요.${NC}"
            ;;
    esac
done
