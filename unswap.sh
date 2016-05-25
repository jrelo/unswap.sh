#!/bin/bash
set -e
scriptname=$(basename $0)
pidfile="/var/run/${scriptname}"
exec 200>$pidfile
flock -n 200 || (echo "Filelock (/var/run/${scriptname}) detected, exiting..."; exit 35);
pid=$$
echo $pid 1>&200

function ctrlc {
    echo -en "\n### Cleaning up...\n";
    rm -v /var/run/${scriptname};
    echo -en "### Exiting...\n";
    exit $?;
}

trap ctrlc SIGINT
trap ctrlc SIGTERM

cat /proc/swaps

function unswap {
awk -F'[ \t-]+' '/^[a-f0-9]*-[a-f0-9]* /{recent="0x"$1" 0x"$2}/Swap:/&&$2>0{print recent}' /proc/$1/smaps | while read memstart memend; 
do 
    if [[ $(grep MemFree: /proc/meminfo|awk '{print $2}') -lt $(grep Swap /proc/$1/smaps|awk '{ sum+=$2} END {print sum}') ]];
    then
	echo "Not enough free memory.";
	grep MemFree: /proc/meminfo;
        exit 12;	
    fi
    
    echo -e "Pulling $memstart-$memend out of swap..."; 
    gdb --batch --pid $1 -ex "dump memory /dev/null $memstart $memend" &>/dev/null; 
done
}

if [[ $# -eq 0 ]]; 
then
    echo 'Usage: $0 <pid> [...]';
    exit 2;
fi

for pid in "$@";
do 
    grep -H VmSwap /proc/$pid/status
    echo "Pulling swapped pages back into memory for process id: $pid...";
    unswap $pid;
    grep -H VmSwap /proc/$pid/status;
done

cat /proc/swaps;
if [[ -f /var/run/{pidfile} ]]; 
then
    rm -v /var/run/{scriptname};
fi
