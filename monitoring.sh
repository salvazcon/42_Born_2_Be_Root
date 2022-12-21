#!/bin/bash
ARCH=$(uname -a)
CORE=$(grep 'physical id' /proc/cpuinfo | wc -l)
VCORE=$(grep 'processor' /proc/cpuinfo | wc -l)
RAM=$(free -m | grep 'Mem:' | awk '{print $3 "/" $2}')
RAM_PERC=$(free -m | grep 'Mem:' | awk '{printf ("%.2f", $3/$2*100)}')
MEM_ACTU=$(df -BM --total | grep 'total' | tr -d "M" | awk '{print $3}')
MEM_TOTA=$(df -BG --total | grep 'total' | awk '{print $2}')
MEM_PERC=$(df -BM --total | grep 'total' | awk '{print $5}')
CORE_PERC=$(top -bn1 | grep '%Cpu' | awk '{printf("%.1f", $2+$4)}')
LAST_BOOT=$(who -b | cut -c23-)
LVM_USE=$(if [ $(lsblk | grep 'lvm' | wc -l) -gt 0 ]; then echo yes; else echo no; fi)
NUM_TCP=$(grep 'TCP' /proc/net/sockstat | awk '{print($3)}')
USER_COUNT=$(users | wc -w)
IPV4_COUNT=$(hostname -I)
MAC_ADRESS=$(ip a | grep 'ether' | awk '{print $2}')
SUDO_COUNT=$(grep 'COMMAND' /var/log/sudo/sudo.log | wc -l)

wall "#Architecture: $ARCH
        #CPU physical: $CORE
        #vCPU: $VCORE
        #Memory Usage: ${RAM}MB (${RAM_PERC}%)
        #Disk Usage: ${MEM_ACTU}/${MEM_TOTA}b (${MEM_PERC})
        #CPU load: ${CORE_PERC}%
        #Last boot: $LAST_BOOT
        #LVM use: $LVM_USE
        #Connexions TCP: $NUM_TCP ESTABLISHED
        #User log: $USER_COUNT
        #Network: IP $IPV4_COUNT ($MAC_ADRESS)
        #Sudo: $SUDO_COUNT cmd"