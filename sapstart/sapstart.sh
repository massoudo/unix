#!/bin/bash
###############################################################
##
## Start and stop SAP instances following a dependency order.
## Useful for using with unix/linux 'init'.
##
## Usage:    sapstart.sh start|stop|status
## Author:   massoudo
##           https://github.com/massoudo
## Version:  20190715
##
###############################################################

PATH=/bin; export PATH
CUT=/usr/bin/cut
CURL=/usr/bin/curl


words(){
    echo $#
}

instancestate() {
    local host=$1
    local instancenr=$2
    local dbname=$3

    /usr/sap/hostctrl/exe/sapcontrol -host $host -nr $instancenr -function GetProcessList
    A=$?
    if [ $A -eq 3 ]; then
        echo " SAP instance SYSNR=$instancenr running on host $host at $(date)"
        state=running
    elif [ $A -eq 4 ]; then
        echo " SAP instance SYSNR=$instancenr not started on host $host yet $(date) "
        state=stopped
    elif [ $A -eq 1 ]; then
        echo " SAP instance SYSNR=$instancenr : invalid parameter error returned on host $host at $(date) "
        state=transition
    else
        echo " SAP instance SYSNR=$instancenr partially started on host $host at $(date) [return $A]"
        state=transition
    fi
}

checkdependence(){
    local DEPENDENCY="$1"
    if [ ! -z "$DEPENDENCY" ]; then
        local host=$(   echo $DEPENDENCY | $CUT -d, -f1)
        local sysnr=$(  echo $DEPENDENCY | $CUT -d, -f2)
        local dbname=$( echo $DEPENDENCY | $CUT -d, -f3)
        instancestate "$host" "$sysnr" "$dbname"
        if [ $state != running ]; then
            echo " Waiting for instance $sysnr in $host"
            let waiting++
            continue 1
        fi
    fi
}

depenceon(){
    local DEPENDENCY="$1"
    if [ ! -z "$DEPENDENCY" ]; then
        local Dhost=$(   echo $DEPENDENCY | $CUT -d, -f1)
        local Dsysnr=$(  echo $DEPENDENCY | $CUT -d, -f2)
        local Ddbname=$( echo $DEPENDENCY | $CUT -d, -f3)
        if [ $Dhost == $host -a "$Dsysnr"0 -eq "$sysnr"0  ]; then
            local Ahost=$(   echo ${INSTANCE[$INDEX]} | $CUT -d, -f1)
            local Asysnr=$(  echo ${INSTANCE[$INDEX]} | $CUT -d, -f2)
            local Adbname=$( echo ${INSTANCE[$INDEX]} | $CUT -d, -f3)
            instancestate "$Ahost" "$Asysnr" "$Adbname"
            if [ $state != stopped ]; then
                echo " Instance $host $sysnr $bname is waiting for $Ahost $Asysnr $Adbname"
                let waiting++
                continue 2
            fi
        fi
    fi
}

MAXWAITTIME=1200

###################################################
##             LIST OF INSTANCES
## <host>, <System number>, <db name>, <os user>
###################################################
INSTANCE_INDEXES="0 1 2"
INSTANCE[2]="s4hana01,01,,bwdadm"
INSTANCE[1]="s4hana01,02,,bwdadm"
INSTANCE[0]="s4hana01,00,HAD,hadadm"

###################################################
##             LIST OF DEPENDENCES
##     <host>, <System number>, <db name>
###################################################
INSTANCE_DEPENDENCY_1[2]="s4hana01,02"
INSTANCE_DEPENDENCY_2[2]="s4hana01,00,HAD"

echo "service $0 $@ at `date`"

case "$1" in
    start)
        echo -n "Starting SAP"
        exec 2>&1
        echo "Starting SAP"
        startsec=$(date +%s)

        while true; do
            started=0
            for index in $INSTANCE_INDEXES; do
                host=$(   echo ${INSTANCE[$index]} | $CUT -d, -f1)
                sysnr=$(  echo ${INSTANCE[$index]} | $CUT -d, -f2)
                dbname=$( echo ${INSTANCE[$index]} | $CUT -d, -f3)
                STARTED[$index]="unknown"
                instancestate "$host" "$sysnr" "$dbname"
                if [ $state == running ] ; then
                    let started++
                    continue
                fi
                if [ "${STARTED[$index]}" != true ]; then
                    checkdependence "${INSTANCE_DEPENDENCY_1[$index]}"
                    checkdependence "${INSTANCE_DEPENDENCY_2[$index]}"
                    checkdependence "${INSTANCE_DEPENDENCY_3[$index]}"
                    echo " starting instance $sysnr in $host"
                    /usr/sap/hostctrl/exe/sapcontrol -host $host -nr $sysnr -function Start
                    STARTED[$index]=true
                fi
            done
            echo " started instances $started, instances waiting to be started $((${#STARTED[*]}-$started))"
            if [ $started -eq $(words $INSTANCE_INDEXES) ]; then
                echo " all instances running"
                break;
            fi
            duration=$(($(date +%s)-$startsec))
            if [ $duration -gt $MAXWAITTIME ]; then
                echo " Maximum wait time $MAXWAITTIME sec for SAP system start is over, giving up."
                exit -1
            fi
            sleep 5
        done
        echo "Started SAP in $(($(date +%s)-$startsec)) sec"
        ;;
    stop)
        echo -n "Stopping SAP"
        exec 2>&1
        echo "Stopping SAP"
        startsec=$(date +%s)
        while true; do
            stopped=0
            for index in $INSTANCE_INDEXES; do
                host=$(   echo ${INSTANCE[$index]} | $CUT -d, -f1)
                sysnr=$(  echo ${INSTANCE[$index]} | $CUT -d, -f2)
                dbname=$( echo ${INSTANCE[$index]} | $CUT -d, -f3)
                osuser=$( echo ${INSTANCE[$index]} | $CUT -d, -f4)
                instancestate "$host" "$sysnr" "$dbname"
                if [ $state == stopped ] ; then
                    let stopped++
                    continue
                fi

                if [ "${STOPPED[$index]}" != true ]; then
                    for INDEX in $INSTANCE_INDEXES; do
                        if [ $INDEX -ne $index ]; then
                            depenceon "${INSTANCE_DEPENDENCY_1[$INDEX]}"
                            depenceon "${INSTANCE_DEPENDENCY_2[$INDEX]}"
                            depenceon "${INSTANCE_DEPENDENCY_3[$INDEX]}"
                        fi
                    done
                    echo " stopping $host $sysnr"
                    su - -c "$(readlink -f /usr/sap/*/*$sysnr/exe/sapcontrol) -nr $sysnr -function Stop" $osuser
                    STOPPED[$index]=true
                fi
            done
            echo " stopped instances $stopped, instances waiting to be stopped $((${#STOPPED[*]}-$stopped))"
            if [ $stopped -eq $(words $INSTANCE_INDEXES) ]; then
                echo " all instances stopped"
                break;
            fi
            duration=$(($(date +%s)-$startsec))
            if [ $duration -gt $MAXWAITTIME ]; then
                echo " Maximum wait time $MAXWAITTIME sec for SAP system stop is over, giving up."
                exit -1
            fi
            sleep 1
        done
        echo "Stopped SAP in $(($(date +%s)-$startsec)) sec"
        ;;
    status)
        echo -n "Status of SAP"
        running=0
        stopped=0
        intransition=0
        error=0
        for index in $INSTANCE_INDEXES; do
            host=$(   echo ${INSTANCE[$index]} | $CUT -d, -f1)
            sysnr=$(  echo ${INSTANCE[$index]} | $CUT -d, -f2)
            dbname=$( echo ${INSTANCE[$index]} | $CUT -d, -f3)
            state=
            instancestate "$host" "$sysnr" "$dbname"
            if [   "$state" == running ]; then
                let running++
            elif [ "$state" == stopped ]; then
                let stopped++
            elif [ "$state" == transition ]; then
                let intransition++
            else
                let error++
            fi
        done
        echo " instances in state stopped $stopped, running $running, intransition $intransition and error $error"
        ;;
     *)
        echo "Usage: $0 {start|stop|status}"
        exit 1
        ;;
esac
