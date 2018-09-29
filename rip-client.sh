#!/bin/bash
ENDPOINT="http://localhost:5000/api"
ME=1
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
	# I've never really understood why this is the necessary idiom to read
	# stuff into an array, but whatever...
	read -a Status < <(tail -n 2 ${CHECKUUID}-ripinfo |sed 1q \
		| sed -E -r -e 's/^(Verifying|Reading) track ([0-9]+) of ([0-9]+) .* \.\.\. +([0-9]+) \%/\1 \2 \3 \4/'\
		-e '/((D|d)oing|(E|e)ncoding)/d'\
		-e '/^(CRC|Peak|Rip)/d'\
		-e 's/^(Getting) .* track \(([0-9]+) of ([0-9]+)\)/\1 \2 \3/'\
		-e 's/^track +[0-9]\: rip accurate/Cleaning/'\
		-e '/^(Using|Checking|CDDB|MusicBrainz|Disc|Matching|Artist|Title|Duration|URL|Release|Type|Barcode|Cat|output|Ripping)/d'\
		-e '/^Reading TOC/d'\
		-e '/^(Verifying|Reading|Ripping) track ([0-9]+) of ([0-9]+)\:/d')
	# sometimes we'll get an empty line. I guess we can ignore that
	# behaviour and just return data that doesn't pass muster
	if [[ -z ${Status[0]} ]]
	then
		return 101
	fi
	# we assume Reading is <=50% for the track, and Verifying is >=50%, and
	# that that is roughly linear.
	# We don't want to return 99
	case ${Status[0]} in
		"Verifying")
			TRA=${Status[1]}
			TOT=${Status[2]}
			PCT=$(( ${Status[3]}/2+50 ))
			if [[ $TRA -ge 0 ]] && [[ $TOT -ge 0 ]] && [[ $PCT -ge 0 ]]
			then
				RES=$(dc <<<"5k $TRA 1- $TOT / 1 $TOT / $PCT 100/ *+ 100* 0k 1/ p")
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
			TRA=${Status[1]}
			TOT=${Status[2]}
			PCT=$(( ${Status[3]}/2 ))
			if [[ $TRA -ge 0 ]] && [[ $TOT -ge 0 ]] && [[ $PCT -ge 0 ]]
			then
				RES=$(dc <<<"5k $TRA 1- $TOT / 1 $TOT / $PCT 100/ *+ 100* 0k 1/ p")
				if [[ $RES -ge 98 ]]
				then
					return 98
				else
					return $RES
				fi
			else return 101
			fi
			;;
		"Getting")
			return 99
			;;
		"Cleaning")
			return 100
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
	if UUID=$(getStatus $UUID)
	then
		eject -t
		setStatus "progress" $UUID 0
		IDLE=1
		# note: it's really important to send ripper's stdout through
		# tr to be able to parse
		whipper cd rip -U --cdr -O $STOREPATH/$UUID \
			2>${UUID}-riperror | tr '\r' '\n' > ${UUID}-ripinfo &
		sleep 50 #do nothing for a bit so that it doesn't have harmless errors
	else
		if [[ -n $(jobs) ]]
		then
			whipperStatus $UUID
			COMPLETION=$?
			if [[ $COMPLETION -lt 0 ]]
			then
				setStatus "error" $UUID
				# We probably have an error, but we'll keep
				# "running" until whipper dies.
			elif [[ $COMPLETION -gt 100 ]]
			then # this is probably a harmless error
				echo "minor error?"
			elif [[ $COMPLETION -lt 100 ]]
			then
				setStatus "progress" $UUID $COMPLETION
			elif [[ $COMPLETION -eq 100 ]]
			then
				setStatus "done" $UUID
				IDLE=0
			fi
		else
			# here, we handle the case where whipper dies or
			# finishes without us setting done.
			if ! $IDLE
			then
				whipperStatus $UUID
				COMPLETION=$?
				if [[ $COMPLETION -eq 100 ]]
				then
					setStatus "done" $UUID
					IDLE=0
				else
					# There's a good chance whipper errored
					# out. We'll hard-fail here
					setStatus "error" $UUID
					IDLE=0
					eject
				fi
			fi
		fi
	fi
	sleep 5
done

