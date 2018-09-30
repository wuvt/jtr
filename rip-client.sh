#!/bin/bash
ENDPOINT="http://localhost:5000/api"
ME=${ME:-1}
POLLTIME=${POLLTIME:-10}
WORKDIR="/tmp/rip-client"
STOREPATH="/home/eric/test/"
UUID=""
IDLE=0 #whether we should be idle

setStatus() {
# status, uuid, percent progress
	REPORTUUID=$2 # we don't actually use this, but oh well, I'm not fixing the code elsewhere.
	STATUS=$1
	if [[ -n $3 ]]; then
		PROGRESS=$3
	else PROGRESS=0
	fi
	case $STATUS in
		"done")
			curl -XPUT ${ENDPOINT}/status/$ME -d "state=DONE"
		;;
		"progress")
			curl -XPUT ${ENDPOINT}/status/$ME -d "state=IN_PROGRESS&progress=$PROGRESS"
		;;
		"error")
			curl -XPUT ${ENDPOINT}/status/$ME -d "state=ERROR"
		;;
	esac
}

getStatus() {
	NEXTUUID=$(curl ${ENDPOINT}/status/$ME)
	if [[ $1 != $NEXTUUID ]] && [[ $NEXTUUID != "None" ]]
	then
		echo $NEXTUUID
		return 0
	else
		echo $1
		return 1
	fi
}

whipperStatus() {
	CHECKUUID=$1
	infofile=${CHECKUUID}-ripinfo
	last_rip=$(awk '/^Ripping track ([0-9]+) of ([0-9]+):/{ print $3,$5}' <$infofile | tr -d : | tail -n1)
	current_track=$(cut -d' ' -f1 <<<$last_rip)
	total_tracks=$(cut -d' ' -f2 <<<$last_rip)
	stage_progress=$(awk '/^(Verifying|Reading) track '"$current_track"' of ([0-9]+) .* \.\.\. +([0-9]+) \%/' < $infofile\
		| tail -n2 | head -n1)
	
	# sometimes we'll get an empty line. I guess we can ignore that
	# behaviour and just return data that doesn't pass muster at all
	if [[ -z $stage_progress ]]
	then
		return 101
	fi
	# we assume Reading is <=50% for the track, and Verifying is >=50%, and
	# that that is roughly linear.
	# We don't want to return 99 or 100
	case $(awk '{ print $1 }' <<<$stage_progress) in
		"Verifying")
			percent=$(( $( rev <<<$stage_progress | awk '{ print $2 }' | rev )/2+50 ))
			if [[ $current_track -ge 0 ]] && [[ $total_tracks -ge 0 ]] && [[ $percent -ge 0 ]]
			then
				RES=$(dc <<<"5k $current_track 1- $total_tracks / 1 $total_tracks / $percent 100/ *+ 100* 0k 1/ p")
				if [[ $RES -ge 98 ]]
				then
					return 98
				else
					return $RES
				fi
			else return 101
			fi
			;;
		"Reading")
			percent=$(( $( rev <<<$stage_progress | awk '{ print $2 }' | rev )/2 ))
			if [[ $current_track -ge 0 ]] && [[ $total_tracks -ge 0 ]] && [[ $percent -ge 0 ]]
			then
				RES=$(dc <<<"5k $current_track 1- $total_tracks / 1 $total_tracks / $percent 100/ *+ 100* 0k 1/ p")
				if [[ $RES -ge 98 ]]
				then
					return 98
				else
					return $RES
				fi
			else return 101
			fi
			;;
		*)
			return -1
	esac

}

checkDeps() {
	if ! which curl || ! which whipper || ! which eject || ! which dc
	then
		echo "[ERROR] Missing Dependencies" >&2
		exit 1
	fi
}

# start of main program

if [[ -d $WORKDIR ]]
then
	cd $WORKDIR
else
	mkdir $WORKDIR
	cd $WORKDIR
fi

checkDeps

while true
do
	UUID=""
	while [[ -z $UUID ]]
	do
		UUID=$(getStatus)
		sleep $POLLTIME
	done
	eject -t # TODO make sure CD drive is actually in
	setStatus "progress" $UUID 0
	IDLE=1
	# note: it's really important to send ripper's stdout through
	# tr to be able to parse
	whipper cd rip -U --cdr -O $STOREPATH/$UUID \
		2>${UUID}-riperror | tr '\r' '\n' > ${UUID}-ripinfo &
	sleep 50 #do nothing for a bit so that it doesn't have harmless errors
	while [[ -n $(jobs) ]]
	do
		whipperStatus $UUID
		COMPLETION=$?
		if [[ $COMPLETION -lt 0 ]]
		then
			echo "$(date -Is) Serious Error?" >&2
			#setStatus "error" $UUID
			# We probably have an error, but we'll keep
			# "running" until whipper dies.
		elif [[ $COMPLETION -gt 100 ]]
		then # this is probably a harmless error
			echo "$(date -Is) minor error?" >&2
		elif [[ $COMPLETION -lt 100 ]]
		then
			setStatus "progress" $UUID $COMPLETION
		fi
		sleep $POLLTIME
	done
	# whipper is no longer running
	# TODO figure out actual errors.
	setStatus "done" $UUID
	eject # just in case whipper doesn't
done

