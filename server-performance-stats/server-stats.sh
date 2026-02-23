#!/bin/bash

TIMESTAMP_DATE="$(date "+%y%m%d")"
LOG_FILE="server-stats_${TIMESTAMP_DATE}.txt"

{
        echo "######################"
        echo "# System Uptime Info #"
        echo "######################"

        uptime

        echo

        echo "####################"
        echo "# Total CPU Usage  #"
        echo "####################"
        top -bn1 | awk '/%Cpu\(s\)/ {print "Usage: " 100-$8 "%"}'

        echo

        echo "######################"
        echo "# Total Memory Usage #"
        echo "######################"
        free | awk '/^Mem:/ {total=$2/1024^2;used=$3/1024^2;avail=$7/1024^2; printf "Total: %.1fGi \nUsed: %.1fGi (%.2f%) \nAvail: %.1fGi (%.2f%)\n", total, used, (used/total)*100, avail, (avail/total)*100}'

        echo


        echo "#####################"
        echo "# Total Disk Usage  #"
        echo "#####################"

        # 점검할 경로 리스트(엔진 경로, 로그 경로)
        DISK_TARGETS=("/orcl" "/opsr")
        for path in "${DISK_TARGETS[@]}"
        do
                if [ -d "$path" ]; then
                        df -h "$path" | awk 'NR==2 {printf "[%-10s] Total: %5s | Used: %5s (%s) | Free: %5s\n", $6, $2, $3, $5, $4}'
                fi
        done

        echo

        echo "################################"
        echo "# Top 5 processes by CPU usage #"
        echo "################################"

        ps aux --sort -%cpu | head -n 6 | awk 'NR==1 {printf "%-10s %-7s %-7s %-7s %s\n", "USER", "PID", "%CPU", "%MEM", "COMMAND"} NR>1 {printf "%-10s %-7s %-7s %-7s %s\n", $1, $2, $3, $4, $11}'

        echo

        echo "################################"
        echo "# Top 1 Process Detailed Info  #"
        echo "################################"

        TOP_PID=$(ps aux --sort -%cpu | awk 'NR==2 {print $2}')
        if [ -n "$TOP_PID" ]; then
                echo "Detailed info for Top Memory Process (PID: $TOP_PID):"
                ps -fp $TOP_PID -ww | awk 'NR==2 {print $0}'
        else
                echo "No process found."
        fi

        echo

        echo "###################################"
        echo "# Top 5 processes by Memory usage #"
        echo "###################################"

        ps aux --sort -%mem | head -n 6 | awk 'NR==1 {printf "%-10s %-7s %-7s %-7s %s\n", "USER", "PID", "%CPU", "%MEM", "COMMAND"} NR>1 {printf "%-10s %-7s %-7s %-7s %-50.50s\n", $1, $2, $3, $4, $11}'

        echo

        echo "################################"
        echo "# Top 1 Process Detailed Info  #"
        echo "################################"

        TOP_PID=$(ps aux --sort -%mem | awk 'NR==2 {print $2}')
        if [ -n "$TOP_PID" ]; then
                echo "Detailed info for Top Memory Process (PID: $TOP_PID):"
                ps -fp $TOP_PID -ww | awk 'NR==2 {print $0}'
        else
                echo "No process found."
        fi

} > "$LOG_FILE"
