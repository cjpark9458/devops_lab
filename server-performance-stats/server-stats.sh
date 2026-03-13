#!/bin/bash

# ============================
# = Server Performance Stats =
# ============================

# get system info
get_system_infos(){
    echo "-----------------"
    echo "#1. System infos:"
    echo "-----------------"
    hostnamectl
}

# get system uptime
get_system_uptime(){
    echo "------------------"
    echo "#2. System uptime:"
    echo "------------------"
    uptime
}

# get logged in users
get_logged_in_users(){
    echo "--------------------"
    echo "#3. Logged in users:"
    echo "--------------------"
    who
}

# Header stats
get_header_stats() {
    get_system_infos
    echo ""
    get_system_uptime
    echo ""
    get_logged_in_users
}

# get total CPU usage
get_cpu_usage() {
    echo "----------------"
    echo "#4-1. CPU Usage:"
    echo "----------------"

    local cpu_idle=$(vmstat 1 2 | tail -1 | awk '{print $15}')
    echo "CPU Usage: $((100 - cpu_idle))%"
}

# get top 5 processes by CPU usage
get_top_cpu_processes() {
    echo "-----------------------------------"
    echo "#4-2. Top 5 Processes by CPU Usage:"
    echo "-----------------------------------"
    ps aux --sort -%cpu | head -n 6 | \
    awk 'NR==1 {
            printf "%-10s %-7s %-7s %-7s %s\n", "USER", "PID", "%CPU", "%MEM", "COMMAND"
        }
        NR>1 {
            printf "%-10s %-7s %-7s %-7s %s\n", $1, $2, $3, $4, $11
        }'
}

# get total memory usage
get_memory_usage() {
    echo "-------------------"
    echo "#5-1. Memory Usage:"
    echo "-------------------"
    free | awk '/Mem:/ {
        total=$2/1024^2; used=$3/1024^2; avail=$7/1024^2;
        printf "Total: %.1fGi \nUsed: %.1fGi (%.2f%%) \nAvail: %.1fGi (%.2f%%)\n", \
        total, used, (used/total)*100, avail, (avail/total)*100
    }'
}

# get top 5 processes by memory usage
get_top_memory_processes() {
    echo "--------------------------------------"
    echo "#5-2. Top 5 Processes by Memory Usage:"
    echo "--------------------------------------"
    ps aux --sort -%mem | head -n 6 | \
    awk 'NR==1 {
            printf "%-10s %-7s %-7s %-7s %s\n", "USER", "PID", "%CPU", "%MEM", "COMMAND"
        }
        NR>1 {
            printf "%-10s %-7s %-7s %-7s %-50.50s\n", $1, $2, $3, $4, $11
        }'
}

# get total disk usage
get_disk_usage() {
    echo "---------------"
    echo "#6. Disk Usage:"
    echo "---------------"

    local DISK_TARGETS=("/orcl" "/opsr" "/")

    printf "%-12s %-8s %-8s %-8s %-5s\n" "Mount" "Total" "Used" "Free" "Use%"
    for path in "${DISK_TARGETS[@]}"; do
        if [ -d "$path" ]; then
            local TARGET_EX=$(df -h "$path" | awk 'NR==2')

            if [ -z "$TARGET_EX" ]; then
                printf "%-12s %-30s\n" "$path" "[ERROR] Partition not found"

            else
                echo "$TARGET_EX" | awk -v p="$path" '{
                    usage=$5; gsub(/%/,"",usage);
                    status = (usage >= 90) ? "[ALERT]" : "OK";
                    printf "%-12s %-8s %-8s %-8s %-5s %-10s\n", $6, $2, $3, $4, $5, status
                }'
            fi
        else
            printf "%-12s %-30s\n" "$path" "[SKIP] Directory not found"
        fi
    done
}

main() {
    echo "======================================="
    echo "Server Performance Stats"
    echo "======================================="

    get_header_stats
    echo ""

    get_cpu_usage
    echo ""

    get_top_cpu_processes
    echo ""

    get_memory_usage
    echo ""

    get_top_memory_processes
    echo ""

    get_disk_usage
    echo ""
}

main
