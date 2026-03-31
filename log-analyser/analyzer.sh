#!/bin/bash
set -u
set -o pipefail

# ==========================================
# [0] 색상 정의 및 설정
# ==========================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# 분석 결과를 담을 임시 디렉토리 생성
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# ==========================================
# [1] 유틸리티 함수
# ==========================================
prompt_for_input() {
    local message="$1"
    local default_value="$2"
    local input
    read -r -p "$message [$default_value]: " input
    echo "${input:-$default_value}"
}

is_positive_int() {
    [[ "${1:-}" =~ ^[0-9]+$ ]] && [ "$1" -gt 0 ]
}

prompt_positive_int() {
    local message="$1"
    local default_value="$2"
    local value
    while true; do
        value=$(prompt_for_input "$message" "$default_value")
        if is_positive_int "$value"; then
            echo "$value"
            return 0
        fi
        echo -e "${RED}1 이상의 숫자를 입력하세요.${NC}"
    done
}

validate_log_file() {
    local file_path="$1"
    if [ ! -f "$file_path" ]; then
        echo -e "${RED}오류: 파일이 존재하지 않습니다 -> $file_path${NC}"
        return 1
    fi
    if [ ! -r "$file_path" ]; then
        echo -e "${RED}오류: 파일 읽기 권한이 없습니다 -> $file_path${NC}"
        return 1
    fi
    return 0
}

# ==========================================
# [2] 핵심 분석 로직 (Single Pass Optimization)
# ==========================================
analyze_log() {
    local log_file="$1"
    local top_n="$2"

    echo -e "\n${CYAN}로그 분석 중...${NC}"

    # 로그를 한 번만 읽어서 각 항목별 임시 파일로 분리 저장
    awk -v tmp="$TMP_DIR" '
    {
        # 1. IP ($1)
        print $1 > (tmp "/ip.raw")

        # 2. Path (정규식 추출)
        if (match($0, /"([A-Z]+) ([^ ]+) [^"]+"/, m)) {
            print m[2] > (tmp "/path.raw")
        }

        # 3. Status ($9)
        if (NF >= 9) {
            print $9 > (tmp "/status.raw")
        }

        # 4. User Agent (정규식 추출)
        if (match($0, /"([^"]*)" "([^"]*)"$/, m)) {
            ua = m[2]
            if (ua == "" || ua == "-") ua = "Unknown"
            print ua > (tmp "/ua.raw")
        }
    }
    ' "$log_file"

    # 전체 요청 수 계산
    local total_req=$(wc -l < "$log_file")
    echo -e "${YELLOW}=========================================="
    echo -e "  분석 요약: $log_file"
    echo -e "  전체 요청 수: $total_req 건"
    echo -e "==========================================${NC}"

    # 결과 출력 함수
    print_top() {
        local title="$1"
        local file="$2"
        echo -e "\n${GREEN}# $title (Top $top_n)${NC}"
        if [ ! -s "$file" ]; then
            echo "데이터가 없습니다."
            return
        fi
        sort "$file" | uniq -c | sort -nr | head -n "$top_n" | awk '{
            count=$1
            $1=""
            sub(/^ /,"")
            printf "%-10s - %s requests\n", count, $0
        }'
    }

    print_top "가장 많은 요청을 보낸 IP" "$TMP_DIR/ip.raw"
    print_top "가장 많이 호출된 경로 (URL)" "$TMP_DIR/path.raw"
    print_top "HTTP 상태 코드 분포" "$TMP_DIR/status.raw"
    print_top "주요 User Agents" "$TMP_DIR/ua.raw"
}

# ==========================================
# [3] 메인 실행부
# ==========================================
main() {
    clear
    echo -e "${CYAN}==========================================${NC}"
    echo -e "${CYAN}       Nginx Access Log Analyzer v2.0     ${NC}"
    echo -e "${CYAN}==========================================${NC}"

    local log_file
    local top_n

    log_file=$(prompt_for_input "분석할 로그 파일 경로" "./access.log")
    validate_log_file "$log_file" || exit 1

    top_n=$(prompt_positive_int "상위 몇 개 항목을 표시할까요?" "5")

    # 분석 시작 시간 기록
    start_time=$(date +%s)

    analyze_log "$log_file" "$top_n"

    # 소요 시간 계산
    end_time=$(date +%s)
    elapsed=$((end_time - start_time))
    echo -e "\n${CYAN}------------------------------------------"
    echo -e "분석 완료 (소요 시간: ${elapsed}초)"
    echo -e "------------------------------------------${NC}"
}

main
