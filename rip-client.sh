#!/bin/bash
ENDPOINT="http://localhost:5000/api"
ME=${ME:-1}
DRIVE=${DRIVE:-/dev/sr0}
POLLTIME=${POLLTIME:-10}
WORKDIR=$HOME
STOREPATH="$HOME/rips/"
UUID=""
IDLE=0 #whether we should be idle
LOCAL=${LOCAL:-0}

setStatus() {
# status, uuid, percent progress
	REPORTUUID=$2 # FIXME we don't actually use this, but oh well, I'm not fixing the code elsewhere.
	STATUS=$1
	if [[ -n $3 ]]; then
		PROGRESS=$3
	else PROGRESS=0
	fi
	#TODO add more error conditions
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
	infofile=$STOREPATH/${CHECKUUID}/${CHECKUUID}-ripinfo
	errorfile=$STOREPATH/${CHECKUUID}/${CHECKUUID}-riperror
	last_rip=$(awk '/ripping track ([0-9]+) of ([0-9]+):/{ print $3,$5}' <$errorfile | tr -d : | tail -n1)
	current_track=$(cut -d' ' -f1 <<<$last_rip)
	total_tracks=$(cut -d' ' -f2 <<<$last_rip)
	stage_progress=$(awk '/^(Verifying|Reading) track '"$current_track"' of ([0-9]+) .* \.\.\. +([0-9]+) %/' < $infofile\
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

checkError() {
	CHECKUUID=$1
	infofile=$STOREPATH/${CHECKUUID}/${CHECKUUID}-ripinfo
	errorfile=$STOREPATH/${CHECKUUID}/${CHECKUUID}-riperror
	if [[ -n $( tail -n30 $infofile |grep 'rip NOT accurate' ) ]]
	then
		return 1
	elif [[ -n $( grep "equal to 'MAX_TRIES'" $infofile ) ]]
	then
		return 1
	elif [[ -n $( grep "CRITICAL" $errorfile ) ]]
	then
		return 1
	else
		return 0
	fi
}

promptInfo() {
	read -p 'WL ID: ' PROMPT_UUID
	read -p 'Stack: ' PROMPT_STACK
	read -p 'Artist Name: ' PROMPT_ARTIST
	read -p 'Album Name: ' PROMPT_ALBUM
}

storeInfo() {
	STOUUID=$1
	INFOFILE=$STOREPATH/${STOUUID}/${STOUUID}-humanmeta.yml
	cat >$INFOFILE <<EOF
---
$1:
  id: $1
  stack: $2
  artist: $3
  album: $4
EOF

}

appendInfo() {
	APUUID=$1
	shift
	INFOFILE=$STOREPATH/${APUUID}/${APUUID}-humanmeta.yml
	if [[ -e $INFOFILE ]]
	then
		echo "$@" >> $INFOFILE
	fi
}

checkDeps() {
	if ! which curl || ! which whipper || ! which eject || ! which dc
	then
		echo "[ERROR] Missing Dependencies" >&2
		echo "we require whipper, curl, ejcect, and dc (bc)" >&2
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
		if [[ $LOCAL -ne 0 ]]
		then
			UUID=$(getStatus)
			sleep $POLLTIME
		else
			promptInfo
			UUID=$PROMPT_UUID
		fi
	done
	eject -t $DRIVE # TODO make sure CD drive is actually in
	mkdir $STOREPATH/$UUID
	if [[ $LOCAL -ne 0 ]]
	then
		setStatus "progress" $UUID 0
	else
		storeInfo $UUID ${PROMPT_STACK} "${PROMPT_ARTIST}" "${PROMPT_ALBUM}"
	fi
	IDLE=1
	# note: it's really important to send ripper's stdout through
	# tr to be able to parse
	whipper cd -d $DRIVE rip -U --cdr -O $STOREPATH/$UUID \
		2>$STOREPATH/${UUID}/${UUID}-riperror |\
		tr '\r' '\n' > $STOREPATH/${UUID}/${UUID}-ripinfo &
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
			if [[ $LOCAL -ne 0 ]]
			then
				setStatus "progress" $UUID $COMPLETION
			else
				echo "progress" $UUID $COMPLETION
			fi
		fi
		jobs
		sleep $POLLTIME
	done
	# whipper is no longer running
	# TODO figure out actual errors.
	if [[ $LOCAL -ne 0 ]]
	then
		if ( checkError $UUID )
		then
			setStatus "done" $UUID
		else
			setStatus "error" $UUID
		fi
	else
		if ( checkError $UUID )
		then
			echo "done" $UUID
		else
			appendInfo $UUID "  error: true"
			echo "error" $UUID
		fi
	fi
	eject $DRIVE # just in case whipper doesn't
done

