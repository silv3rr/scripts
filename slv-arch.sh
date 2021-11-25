#!/bin/sh

################################################################################
# slv-archiver                                            slv-arch-20211125-all
################################################################################
#
# Moves rels from incoming to archive
# Includes extra support for TV Series, 0DAY, MP3 and MV sections
#
# Moves dirs to appropriate target dir in archive:
#   /apps/* -> /archive/apps
#
# Creates dirs in archive for tv series:
#   /tv/Series.Name.S01E02-GRP -> /archive/tv/Series/S01
#
# Handles daydirs:
#        /0day/0310 -> /archive/0day/2013-03
#        /mp3/2013-03-10 -> /archive/mp3
#
# Needs: awk basename date find grep touch
# Use a separate config file "slv-arch.conf", or copy settings below
#
################################################################################

# Config moved to slv-arch.conf

################################################################################
# END OF CONFIG
################################################################################

# ph33r what comes below ;)

if [ "$( id -u )" -ne 0 ] || [ "$LOGNAME" != "root" ]; then
	echo "You have to be root to run this script!"
	exit 0
fi

# DEBUG=1 or "./slv-arch.sh debug" does not actually mkdir and mv but
# just shows what actions the script would have executed instead
DEBUG=0

# Check if .conf file exists, source if it does
SCRIPT_CONF="$(dirname "$0")/$(basename -s '.sh' "$0").conf"
if [ -s "$SCRIPT_CONF" ]; then
	if [ "$DEBUG" -ge 1 ]; then
		echo "[DEBUG] Using SCRIPT_CONF=$SCRIPT_CONF"
	fi
	 # shellcheck source=slv-arch.conf
	. "$SCRIPT_CONF" || { echo "[ERROR] could not load $SCRIPT_CONF"; exit 1; }
fi

# Config checks
if [ -z "$GLDIR" ]; then
	echo "[ERROR] GLDIR is not set correctly, exiting..."
	exit 1
fi
if echo "$MINS_OLD" | grep -qv "[0-9]\+"; then
	echo "[ERROR] MINS_OLD is not set correctly, exiting..."
	exit 1
fi
if echo "$CHECK_MOUNTS" | grep -qv "[0-1]" || [ -z "$MOUNTS" ]; then
	CHECK_MOUNTS=0
fi

# Function to clean and create symlinks in tvarchive when using sub disks
# shellcheck disable=SC2046,SC2086
func_lnk() {
	if [ -n "$TVARCSUBS" ]; then
		if [ "$1" = "DEL" ]; then
			find "$TVARCHIVE" $(dm 1) $(dx 1) -xtype l -delete
		fi
		find "$TVARCHIVE" $(dm 2) $(dx 2) $(ty d) $PF_P | \
		while read -r i; do
			link="$(basename "$i")"
			if [ ! -L "$TVARCHIVE/$link" ]; then
				ln -s "$i" "$TVARCHIVE/$link"
			fi
		done
	fi
}

# Function to convert KiB MiB GiB TiB
func_bc() {
	if echo "$1" | grep -q "[0-9]"; then
		U="$2"
		if [ "$U" = "" ]; then
			if [ "$1" -lt "1024" ]; then U="KiB"
				elif [ "$1" -ge "1024" ] && [ "$1" -lt "1024000" ]; then U="MiB"
				elif [ "$1" -ge "1024000" ] && [ "$1" -lt "1024000000" ]; then U="GiB"
				elif [ "$1" -ge "1024000000" ]; then U="TiB"
			fi
		fi
		case "$U" in
			KB) RET="${1}KiB" ;;
			MB) RET="$(( $1 / 1024 ))MB" ;;
			GB) RET="$(( $1 / 1024 / 1024 ))GB" ;;
			TB) RET="$( echo "$1 1024" | awk '{ printf "%0.1f%s", $1 / $2 / $2 / $2, "TB"; }' )" ;;
		esac
	fi
	echo "$RET"
}

# Few shortcuts for find command
F_RE="-regextype posix-egrep ! -regex"
PF_P="-printf "'%P\n'""
dm() { echo "-mindepth $1"; }
dx() { echo "-maxdepth $1"; }
ty() { echo "-type $1"; }
func_find() { if [ -n "$1" ]; then find "$@" 2>/dev/null ; fi; }

# Handle arguments
if echo "$1" | grep -iq "debug"; then
	DEBUG=1
	if echo "$2" | grep -q "[0-9]"; then
		DEBUG="$2"
	fi
fi
if echo "$1" | grep -iq "links"; then
	if echo "$2" | grep -q "DEL"; then
		func_lnk DEL
	else
		func_lnk
	fi
	exit
fi

# Get all mounts, for use in func_df below, run once
MAX=0
i=0
ALLMNT=""
MAX="$( echo "$MOUNTS" | wc -w )"
for m in $MOUNTS; do
	if [ $i -lt $(( MAX-1 )) ]; then
		ALLMNT="$ALLMNT\|$m"
	else
		ALLMNT="$m${ALLMNT}"
	fi
	i=$(( i+1 ))
done

# Convert min free variable set by user in settings above, run once
MIN_FREE_GB="$( func_bc "$MIN_FREE" GB )"

# Function to get free disk space, overwrites MIN_FREE_GB
func_df() {
	for d in "$@"; do
		ARC="ARCHIVE"
		if [ -n "$TVARCHIVE" ] && echo "$d" | grep -q "$TVARCHIVE"; then
			ARC="TVARCHIVE"
		fi
		if [ -n "$ZDARCHIVE" ] && echo "$d" | grep -q "$ZDARCHIVE"; then
			ARC="0DAYARCHIVE"
		fi
		if [ "$CHECK_MOUNTS" -eq 1 ]; then
			if ! findmnt --target "$d" | grep -q "\(^\| \)\($ALLMNT\)\(/\.[0-9]\| \)"; then
				if [ "$DEBUG" -ge 1 ]; then
					if [ "$d" != "$MOUNT_TMP" ]; then
						echo "[DEBUG] ${ARC}:DF OK $d - device not mounted"
					fi
					MOUNT_TMP="$d"
				fi
				return 1
			fi
		fi
		FS=$( df "$d" | awk '{ print $1 }' | tail -1 )
		DF=$( df "$d" | awk '{ print $4 }' | tail -1 )
		if echo "$DF" | grep -q "[0-9]"; then
			if [ "$DF" -lt "$MIN_FREE" ]; then
				if [ "$DEBUG" -ge 1 ] && ! echo "$*" | grep "NO_OUT"; then
					if [ "$d" != "$DF_TMP" ]; then
						echo "[DEBUG] ${ARC}:DF NOK $d - not enough disk space on \"$FS\" ($(func_bc "$DF" GB) free, $MIN_FREE_GB needed)"
					fi
				fi
				DF_TMP="$d"
				return 1
			else
				if [ "$DEBUG" -ge 1 ] && ! echo "$*" | grep "NO_OUT"; then
					if [ "$d" != "$DF_TMP" ]; then
						echo "[DEBUG] ${ARC}:DF OK $d - enough disk space on \"$FS\" ($(func_bc "$DF" GB) free, $MIN_FREE_GB needed)"
					fi
				fi
				DF_TMP="$d"
				return 0
			fi
		else
			echo "[ERROR] could not get free disk space on $d"
			return 1
		fi
	done
}

################################################################################
# MOVE
################################################################################
# Move src dirs to target for all sections
# shellcheck disable=SC2046,SC2086
for RULE in $MOVE; do
	SRC_DIR="$( echo "$RULE" | awk -F ":" '{ print $1 }' )"
	REG_EXP="$( echo "$RULE" | awk -F ":" '{ print $2 }' )"
	DST_DIR="$( echo "$RULE" | awk -F ":" '{ print $3 }' )"
	# Convert SKIP_PATH format to "(/NUKED-|/Archive|/_Old)"
	SKIP_PATH_SED="$( echo "$SKIP_PATH" | sed -e 's|\^|/|g' -e 's|[.*$]||g' )"
	for REL in $( func_find "$SRC_DIR" $(dm 1) $(dx 1) $(ty d) $F_RE "${SRC_DIR}(${SKIP_PATH_SED})" -printf '%f\n' | sort ); do
		if ! func_df "$DST_DIR"; then 
			if [ "$DEBUG" -ge 1 ]; then 
				if [ "$DEBUG" -ge 1 ]; then
					if [ "$DST_DIR" != "$SKIPTMP" ]; then
						echo "[DEBUG] MOVE: skip $DST_DIR"
					fi
				fi
				SKIPTMP="$DST_DIR"
			fi
		 	continue
		fi
		SKIP="NO"
		if func_find "$SRC_DIR/$REL" $(dm 1) $(dx 1) $(ty d) $PF_P | grep -q -e "^[cC][dD][1-9]$" -e "^[dD][iI][sS][cCkK][1-9]$" -e "^[dD][vV][dD][1-9]$"; then
			for each_cd in $( func_find "$SRC_DIR/$REL" $(dm 1) $(dx 1) $(ty d) $PF_P | grep -e "^[cC][dD][1-9]$" -e "^[dD][iI][sS][cCkK][1-9]$" -e "^[dD][vV][dD][1-9]$" ); do
				if ! func_find "$SRC_DIR/$REL/$each_cd" $(dm 1) $(dx 1) $PF_P | grep -Eq "$CHECK_FOR"; then
					if func_find "$SRC_DIR/$REL/$each_cd" $(dm 1) $(dx 1) $(ty f) $PF_P | grep -q "\.[sS][fF][vV]$"; then
						SKIP="YES"
					else
						SKIP="NO"
					fi
				fi
			done
		else
			if ! func_find "$SRC_DIR/$REL" $(dm 1) $(dx 1) $PF_P | grep -Eq "$CHECK_FOR"; then
				if func_find "$SRC_DIR/$REL" $(dm 1) $(dx 1) $(ty f) $PF_P | grep -Eq "\.[sS][fF][vV]$"; then
					SKIP="YES"
				else
					SKIP="NO"
				fi
			fi
		fi
		MATCH="NO"
		DIRAGE_OK="NO"
		CURDATE_SEC="$( $DATEBIN +%s )"
		DIRAGE_MIN=0
		DIRDATE_SEC="$( func_find "$SRC_DIR/$REL" $(dm 0) $(dx 0) $(ty d) -printf '%Ts\n' )"
		if echo "$DIRDATE_SEC" | grep -q "[0-9]"; then
			DIRAGE_MIN=$(( (CURDATE_SEC - DIRDATE_SEC) / 60 ))
		fi
		if [ "$DIRAGE_MIN" -ge "$MINS_OLD" ] && [ "$SKIP" = "NO" ]; then
			DIRAGE_OK="YES"
			if echo "$REL" | grep -Eq " $REG_EXP"; then
				MATCH="YES"
				if [ ! -d "$DST_DIR" ]; then
					if [ "$DEBUG" -ge 1 ]; then
						echo "[DEBUG] MOVE: mkdir $DST_DIR"
					else
						mkdir "$DST_DIR"
					fi
				fi
				if [ "$DEBUG" -ge 1 ]; then
					echo "[DEBUG] MOVE: mv $SRC_DIR/$REL $DST_DIR"
				else
					mv "$SRC_DIR/$REL" "$DST_DIR"
				fi
				LN="$( func_find "$SRC_DIR" $(dm 1) $(dx 1) $(ty l) -regex ".*(no-\(nfo\|sfv\|sample\))-$REL" )"
				if [ -n "$LN" ]; then
					if [ "$DEBUG" -ge 1 ]; then
						echo "[DEBUG] MOVE: mv $LN $DST_DIR"
					else
						mv "$LN" "$DST_DIR"
					fi
				fi
			fi
		fi
		if [ "$DEBUG" -ge 1 ]; then
			if [ "$DEBUG" -eq 2 ]; then
				DBG_AGE=" (DIRAGE_MIN=$DIRAGE_MIN MINS_OLD=$MINS_OLD)"
			fi
			RE_TMP="$(echo " $REG_EXP" | sed -r -e 's/^(.{30})$/\1/' -e t -e 's/^(.{30}).*/\1..<-cut->/' -e t)"
			echo "[DEBUG] MOVE:POSTCHK SRC=$SRC_DIR $REL DST=$DST_DIR RE=$RE_TMP MATCH=$MATCH AGE_OK=$DIRAGE_OK${DBG_AGE}"
		fi
	done
done

################################################################################
# TV 
################################################################################
# First set skip patterns for TVDIRS, then move releases
SKIP_SECTION=""
for TVDIR in $TVDIRS; do
	SKIP_SECTION="^$TVDIR\$|$SKIP_SECTION"
done
for RULE in $MOVE; do
	SRC_DIR="$( echo "$RULE" | awk -F ":" '{ print $1 }' )"
	REG_EXP="$( echo "$RULE" | awk -F ":" '{ print $2 }' )"
	DST_DIR="$( echo "$RULE" | awk -F ":" '{ print $3 }' )"
	if echo "$TVDIRS" | grep -q "$SRC_DIR"; then
		if echo "$DST_DIR" | grep -q "$TVARCHIVE"; then
			SKIP_PATH=" $REG_EXP|$SKIP_PATH"
		fi
	fi
done
# Check disk space for tvarchive, standard mount and when using subdisks
if [ -z "$TVARCSUBS" ]; then
	if [ -n "$TVARCHIVE" ]; then
		if ! func_df "$TVARCHIVE"; then
			if [ "$DEBUG" -ge 1 ]; then
				echo "[DEBUG] TV:SKIP $DST_DIR"
			fi
			exit 1
		fi
	fi
# Find initial sub disk with the most free disk space
else
	TVARCHSUB="$( \
		for i in $TVARCSUBS; do
			if func_df "$TVARCHIVE/$i" NO_OUT; then
				echo "$i $DF"
			fi
		done | sort -k2 -n | tail -1 | awk '{ print $1 }' \
	)"
	if [ "$TVARCHSUB" ]; then
		if [ "$DEBUG" -ge 1 ]; then
			echo "[DEBUG] TVARCHIVE:DF OK $TVARCHIVE - subdisk \"$TVARCHSUB\" has the most disk space free (of \"$TVARCSUBS\")"
			func_df "$TVARCHIVE/$TVARCHSUB"
		fi
	else
		if [ "$DEBUG" -ge 1 ]; then
			echo "[DEBUG] TVARCHIVE:DF NOK $TVARCHIVE - none of the subdisks \"$TVARCSUBS\" are mounted and/or have enough disk space free"
		fi
		exit 1
	fi
fi
NUM_TV=0
if echo "$NUM_DIRS_TV" | grep -q "[0-9]"; then
	NUM_TV=1
	DBG_NUM_TV=" NUM_DIRS_TV=$NUM_DIRS_TV"
fi
# shellcheck disable=SC2046,SC2086
for TVDIR in $TVDIRS; do
	SKIP="NO"
	SKIP_RE="$( echo "$SKIP_PATH" | sed "s|\^|\^$TVDIR/|g" )"
	# Move tv releases
	for REL in $( func_find "$TVDIR" $(dm 1) $(dx 1) $F_RE "${SKIP_SECTION}${SKIP_RE}" -printf '%Ts %p\n' | sort -n | head -$NUM_DIRS_TV | awk '{ print $NF }' ); do
		# Find sub disk which has currently the most free disk space
		if [ -n "$TVARCSUBS" ]; then
			TVARCHSUB="$( \
				for i in $TVARCSUBS; do
					if func_df "$TVARCHIVE/$i" NO_OUT; then
						echo "$i $DF"
					fi
				done | sort -k2 -n | tail -1 | awk '{ print $1 }' \
			)"
		fi
		# Check: CD/DISK/DVD subdirs
		if func_find "$REL" $(dm 1) $(dx 1) $(ty d) $PF_P | grep -q -e "^[cC][dD][1-9]$" -e "^[dD][iI][sS][cCkK][1-9]$" -e "^[dD][vV][dD][1-9]$"; then
			for each_cd in $( func_find "$REL" $(dm 1) $(dx 1) $(ty d) $PF_P | grep -e "^[cC][dD][1-9]$" -e "^[dD][iI][sS][cCkK][1-9]$" -e "^[dD][vV][dD][1-9]$" ); do
				if ! func_find "$DIR/$each_cd" $(dm 1) $(dx 1) $PF_P | grep -Eq "$CHECK_FOR"; then
					if func_find "$DIR/$each_cd" $(dm 1) $(dx 1) $(ty f) $PF_P | grep -q "\.[sS][fF][vV]$"; then
						SKIP="YES"
					else
						SKIP="NO"
					fi
				fi
			done
		# Check: *.sfv files
		else
			if ! func_find "$REL" $(dm 1) $(dx 1) $PF_P | grep -Eq "$CHECK_FOR"; then
				if func_find "$REL" $(dm 1) $(dx 1) $(ty f) $PF_P | grep -q "\.[sS][fF][vV]$"; then
					SKIP="YES"
				else
					SKIP="NO"
				fi
			fi
		fi
		if [ "$SKIP" = "NO" ]; then
			DIRAGE_MIN=0
			DIRAGE_OK="NO"
			CURDATE_SEC="$( $DATEBIN +%s )"
			DIRDATE_SEC="$( func_find "$REL" $(dm 0) $(dx 0) $(ty d) -printf '%Ts\n' )"
			DSTSERIES=""
			SEASON=""
			if echo "$DIRDATE_SEC" | grep -q "[0-9]"; then
				DIRAGE_MIN=$(( (CURDATE_SEC - DIRDATE_SEC) / 60 ))
			fi
			if [ "$NUM_TV" -eq 1 ] || [ "$DIRAGE_MIN" -ge "$MINS_OLD" ]; then
				DIRAGE_OK="YES"
				BASEDIR="$( basename "$REL" )"
				# RegEx to remove diff spelling and replace/remove tags from rel to get series titles
				SRCSERIES="$( echo "$BASEDIR" | sed \
					-e 's/^(no-\(nfo\|sfv\|sample\))-//g' \
					-e 's/\([._]\)A\([._]\)/\1a\2/g' \
					-e 's/\([._]\)And\([._]\)/\1and\2/g' \
					-e 's/\([._]\)In\([._]\)/\1in\2/g' \
					-e 's/\([._]\)Is\([._]\)/\1is\2/g' \
					-e 's/\([._]\)The\([._]\)/\1the\2/g' \
					-e 's/\([._]\)Of\([._]\)/\1of\2/g' \
					-e 's/\([._]\)On\([._]\)/\1on\2/g' \
					-e 's/\([._]\)Or\([._]\)/\1or\2/g' \
					-e 's/\([._]\)With\([._]\)/\1with\2/g' \
					-e 's/\.\(S[0-9]\+E[0-9]\+[a-z]\?\)\..*//gi' \
					-e 's/\.\(S[0-9]\+E[0-9]\+\-E[0-9]\+\)\..*//gi' \
					-e 's/\.\(S[0-9]\+E[0-9]\+[E-][0-9]\+\)\..*//gi' \
					-e 's/\.\(S[0-9]\+\)\..*//gi' \
					-e 's/\.\(E[0-9]\+\)\..*//gi' \
					-e 's/[._]\(\([0-9]\|[0-9]\)x[0-9]\+\)[._].*//gi' \
					-e 's/[._]\([0-9]\+[._][0-9]\+[._][0-9]\+\)[._].*//gi' \
					-e 's/[._-]\(hdtv\|pdtv\|dsr\|dsrip\|webrip\|web\|h264\|x264\|\|xvid\|720p\|1080p\|2160p\|ws\|dvdrip\|bluray\|uhd\)\($\|[._-]\).*//gi' \
					-e 's/[._-]\(dirfix\|proper\|repack\|nfofix\|preair\|pilot\|ppv\|extended\\|complete\|dual\|part.[0-9]\+\)\($\|[._-]\).*//gi' \
					-e 's/[._-]\(dutch\|german\|flemish\|french\|hungarian\|italian\|norwegian\|polish\|portuguese\|spanish\|russian\|swedish\)\($\|[._-]\).*//gi' )"
				SEASON="$( echo "$REL" | sed -e 's/.*[._-]S\([0-9]\+\)E[0-9].*/\1/i' \
					-e 's/.*S\([0-9]\|[0-9][0-9]\+\)\..*/\1/i' \
					-e 's/.*[._-]\([0-9]\+\)x[0-9].*/\1/i' \
					-e 's/.*\([0-9][0-9][0-9][0-9]\).[0-9][0-9].[0-9][0-9].*/\1/i' )"
				SEASON="S$SEASON"
				# In case of single digit season, pad with leading zero 
				if echo "$SEASON" | grep -q "^[0-9]$"; then
					SEASON="S0$SEASON"
				fi
				# Missing or non-standard season tag
				if echo "$SEASON" | grep -qv "^S\([0-9]$\|[0-9][0-9]\|[0-9][0-9][0-9]\)$"; then
					SEASON=""
				fi
				MV="NO"
				DSTSERIES="$( echo "$SRCSERIES" | sed 's/\(\w\)_/\1\./g' )"
				# Generate case insensitive glob ([aA][bB][cC]) and use for find/mv etc to prevent duplicate series dirs
				CHKSERIES="$( echo "$DSTSERIES" | sed 's/\([a-z]\|[A-Z]\)/[\L\1\U\1\]/g' )"
				DIRDATE="$( $DATEBIN --date "01/01/1970 +$DIRDATE_SEC seconds" +"%Y-%m-%d %H:%M:%S" )"
				if [ "$SEASON" = "" ]; then
					# Dir /archive/tv/Series does not exist (no season tag)
					if [ ! "$( func_find $TVARCHIVE/$CHKSERIES $(dm 0) $(dx 0) $(ty d) )" ]; then
						# standard tvarchive: mkdir
						if [ -z "$TVARCHSUB" ]; then
							if [ "$DEBUG" -ge 1 ]; then
								echo "[DEBUG] TV: mkdir $TVARCHIVE/$DSTSERIES"
							else
								mkdir "$TVARCHIVE/$DSTSERIES"
							fi
						# tv subdisks: mkdir (and link)
						else
							if [ "$DEBUG" -ge 1 ]; then
								if [ ! -d "$TVARCHIVE/$TVARCHSUB/$DSTSERIES" ]; then
									echo "[DEBUG] TV: mkdir $TVARCHIVE/$TVARCHSUB/$DSTSERIES"
								fi
								if [ ! -L $TVARCHIVE/$CHKSERIES ]; then
									echo "[DEBUG] TV: ln -s TVARCHSUB/$DSTSERIES" "$TVARCHIVE/$DSTSERIES"
								fi
								else
								if [ ! -d "$TVARCHIVE/$TVARCHSUB/$DSTSERIES" ]; then
									mkdir "$TVARCHIVE/$TVARCHSUB/$DSTSERIES"
								fi
								if [ ! -L $TVARCHIVE/$CHKSERIES ]; then
									ln -s "$TVARCHSUB/$DSTSERIES" "$TVARCHIVE/$DSTSERIES"
								fi
							fi
						fi
					fi
					# Dir /archive/tv/Series already exists
					if [ "$( func_find $TVARCHIVE/$CHKSERIES $(dm 0) $(dx 0) $(ty d) )" ]; then
						if [ "$( func_find $TVARCHIVE/$CHKSERIES $(dm 0) $(dx 0) $(ty d) | wc -l )" -eq 1 ]; then
							# standard tvarchive: mv rel
							if [ -z "$TVARCHSUB" ]; then
								if [ "$DEBUG" -ge 1 ]; then
									MV="DEBUG"
									echo "[DEBUG] TV: mv $REL" $TVARCHIVE/$CHKSERIES/
								else
									mv "$REL" $TVARCHIVE/$CHKSERIES/ && MV="YES"
								fi
							# tv subdisks: mv rel
							else
								if [ -L $TVARCHIVE/$CHKSERIES ]; then
									TVLINKSUB="$( dirname "$( readlink $TVARCHIVE/$CHKSERIES )" )"
									if [ "$TVLINKSUB" = "$TVARCHSUB" ]; then
										if [ "$DEBUG" -ge 1 ]; then
											MV="DEBUG"
											echo "[DEBUG] TV: mv $REL" $TVARCHIVE/$CHKSERIES/
										else
											mv "$REL" "$TVARCHIVE/$CHKSERIES/" && MV="YES"
										fi
									else
										if func_df "$TVARCHIVE/$TVLINKSUB"; then
											if [ "$DEBUG" -ge 1 ]; then
												MV="DEBUG"
												echo "[DEBUG] TV: mv $TVREL" $TVARCHIVE/$CHKSERIES/ "(to subdisk \"$TVLINKSUB\")"
											else
												mv "$REL" $TVARCHIVE/$CHKSERIES/ && MV="YES"
											fi
										else
											echo "[INFO] TV:SKIP mv $TVREL - \"$DSTSERIES\" is not on \"$TVARCHSUB\" and \"$TVLINKSUB\" is full/unmounted"
										fi
									fi
								fi
							fi
						else
							MV="NO"
							SKIP="YES"
							DUPEDIRS="$( func_find $TVARCHIVE/$CHKSERIES $(dm 0) $(dx 0) $(ty d) -printf '%f ' )"
							echo "[ERROR] TV:SKIP \"$DSTSERIES\" - more than 1 dir found... $DUPEDIRS )"
						fi
					fi
					# Restore original date of rel dir
					if [ "$MV" = "YES" ] && [ "$( func_find $TVARCHIVE/$CHKSERIES/$BASEDIR $(dm 0) $(dx 0) $(ty d) )" ]; then
						if [ "$DEBUG" -ge 1 ]; then
							echo "[DEBUG] TV: touch -d $DIRDATE" $TVARCHIVE/$CHKSERIES/$BASEDIR
						else
							touch -c -d "$DIRDATE" $TVARCHIVE/$CHKSERIES/$BASEDIR
						fi
					else
						if [ "$MV" != "DEBUG" ]; then
							echo "[ERROR] TV: wont touch \"$TVARCHIVE/$DSTSERIES/$BASEDIR\" - move failed or no dir (MV=$MV)"
						fi
					fi
				# Dir /archive/tv/Series does not exist
				else
					if [ ! "$( func_find $TVARCHIVE/$CHKSERIES $(dm 0) $(dx 0) $(ty d) )" ]; then
						# standard tvarchive: mkdir
						if [ -z "$TVARCHSUB" ]; then
							if [ "$DEBUG" -ge 1 ]; then
								echo "[DEBUG] TV: mkdir $TVARCHIVE/$DSTSERIES"
							else
								mkdir "$TVARCHIVE/$DSTSERIES"
							fi
						# tv subdisks: mkdir
						else
							if [ "$DEBUG" -ge 1 ]; then
								if [ ! -d "$TVARCHIVE/$TVARCHSUB/$DSTSERIES" ]; then
									echo "[DEBUG] TV: mkdir $TVARCHIVE/$TVARCHSUB/$DSTSERIES"
								fi
								if [ ! -L $TVARCHIVE/$CHKSERIES ]; then
									echo "[DEBUG] TV: ln -s $TVARCHSUB/$DSTSERIES $TVARCHIVE/$DSTSERIES"
								fi
							else
								if [ ! -d "$TVARCHIVE/$TVARCHSUB/$DSTSERIES" ]; then
									mkdir "$TVARCHIVE/$TVARCHSUB/$DSTSERIES"
								fi
								if [ ! -L $TVARCHIVE/$CHKSERIES ]; then
									ln -s "$TVARCHSUB/$DSTSERIES" "$TVARCHIVE/$DSTSERIES"
								fi
							fi
						fi
					fi
					# Dir /archive/tv/Series/S01 does not exist
					if [ ! "$( func_find $TVARCHIVE/$CHKSERIES/$SEASON $(dm 0) $(dx 0) $(ty d) )" ]; then
						# standard tvarchive: mkdir
						if [ -z "$TVARCHSUB" ]; then
							if [ "$DEBUG" -ge 1 ]; then
								MV="DEBUG"
								echo "[DEBUG] TV: mkdir $( func_find $TVARCHIVE/$CHKSERIES $(dm 0) $(dx 0) $(ty d) 2>/dev/null || echo \[NOT_FOUND\]:$TVARCHIVE/$CHKSERIES )/$SEASON"
							else
								mkdir "$( func_find $TVARCHIVE/$CHKSERIES $(dm 0) $(dx 0) $(ty d) 2>/dev/null )/$SEASON"
							fi
						# tv subdisks: mkdir
						else
							if [ -L $TVARCHIVE/$CHKSERIES ]; then
								TVLINKSUB="$( dirname "$( readlink $TVARCHIVE/$CHKSERIES )" )"
								if [ "$TVLINKSUB" = "$TVARCHSUB" ]; then
									if [ "$DEBUG" -ge 1 ]; then
										echo "[DEBUG] TV: mkdir $( func_find $TVARCHIVE/$CHKSERIES $(dm 0) $(dx 0) $(ty d) 2>/dev/null || echo \[NOT_FOUND\]:$TVARCHIVE/$CHKSERIES )/$SEASON"
									else
										mkdir "$( func_find $TVARCHIVE/$CHKSERIES $(dm 0) $(dx 0) $(ty d) 2>/dev/null )/$SEASON"
									fi
								else
									if func_df "$TVARCHIVE/$TVLINKSUB"; then 
										if [ "$DEBUG" -ge 1 ]; then
											echo "[DEBUG] TV: mkdir $( func_find $TVARCHIVE/$CHKSERIES $(dm 0) $(dx 0) $(ty d) 2>/dev/null || echo \[NOT_FOUND\]:$TVARCHIVE/$CHKSERIES )/$SEASON (on subdisk \"$TVLINKSUB\")"
										else	
											mkdir "$( func_find $TVARCHIVE/$CHKSERIES $(dm 0) $(dx 0) $(ty d) 2>/dev/null )/$SEASON"
										fi
									else
										echo "[INFO] TV:SKIP mkdir $TVARCHIVE/$DSTSERIES/$SEASON - \"$DSTSERIES\" links to \"$TVLINKSUB\" which is full/unmounted (not on \"$TVARCHSUB\")"
									fi
								fi
							fi
						fi
					fi
					# Dir /archive/tv/Series/S01 already exists
					if [ "$( func_find $TVARCHIVE/$CHKSERIES/$SEASON $(dm 0) $(dx 0) $(ty d) )" ]; then
						# standard tvarchive: mv
						if [ -z "$TVARCHSUB" ]; then
							if [ "$DEBUG" -ge 1 ]; then
								MV="DEBUG"
								echo "[DEBUG] TV: mv $REL" $TVARCHIVE/$CHKSERIES/$SEASON
							else
								mv "$REL" $TVARCHIVE/$CHKSERIES/$SEASON && MV="YES"
							fi
						# tv subdisks: mv
						else
							if [ "$( func_find $TVARCHIVE/$CHKSERIES $(dm 0) $(dx 0) $(ty d) | wc -l )" -eq 1 ]; then
								if [ -L $TVARCHIVE/$CHKSERIES ]; then
									TVLINKSUB="$( dirname "$( readlink $TVARCHIVE/$CHKSERIES )" )"
									if [ "$TVLINKSUB" = "$TVARCHSUB" ]; then
										if [ "$DEBUG" -ge 1 ]; then
											MV="DEBUG"
											echo "[DEBUG] TV: mv $REL" $TVARCHIVE/$CHKSERIES/$SEASON
										else
											mv "$REL" $TVARCHIVE/$CHKSERIES/$SEASON && MV="YES"
										fi
									else
										if func_df "$TVARCHIVE/$TVLINKSUB"; then 
											if [ "$DEBUG" -ge 1 ]; then
												MV="DEBUG"
												echo "[DEBUG] TV: mv $REL" $TVARCHIVE/$CHKSERIES/$SEASON "(on subdisk \"$TVLINKSUB\")"
											else
												mv "$REL" $TVARCHIVE/$CHKSERIES/$SEASON && MV="YES"
											fi
										else
											MV="NO"
											echo "[INFO] TV:SKIP mv $REL - dir \"$DSTSERIES\" is not on \"$TVARCHSUB\" and \"$TVLINKSUB\" is full or not mounted"
										fi
									fi
								fi
							else
								MV="NO"
								DUPEDIRS="$( func_find $TVARCHIVE/$CHKSERIES $(dm 0) $(dx 0) $(ty d) | sed "s|${GLDIR}/site||g" | tr '\n' ' ')"
								echo "[ERROR] TV:SKIP \"$DSTSERIES\" - more than 1 dir found... $DUPEDIRS"
							fi
						fi
					fi
					# Restore original date of rel dir
					if [ "$MV" = "DEBUG" ] && [ "$DEBUG" -ge 1 ]; then
						echo "[DEBUG] TV: touch -c -d $DIRDATE" $TVARCHIVE/$CHKSERIES/$SEASON/$BASEDIR" (dry-run MV=$MV)"
					elif [ "$MV" = "YES" ] && [ "$( func_find $TVARCHIVE/$CHKSERIES/$SEASON/$BASEDIR $(dm 0) $(dx 0) $(ty d) )" ]; then
						touch -c -d "$DIRDATE" $TVARCHIVE/$CHKSERIES/$SEASON/$BASEDIR
					else
						echo "[ERROR] TV:SKIP touch \"$TVARCHIVE/$DSTSERIES/$SEASON/$BASEDIR\" - move failed/no dir found (MV=$MV)"
					fi
				fi
			fi
		fi
	if [ "$DEBUG" -ge 1 ]; then
		if [ "$DEBUG" -eq 2 ]; then
			DBG_AGE=" (DIRAGE_MIN=$DIRAGE_MIN MINS_OLD=$MINS_OLD)"
		fi
		echo "[DEBUG] TV:POSTCHK REL=$REL DSTSERIES=\"$DSTSERIES\" SEASON=\"$SEASON\" SKIP=$SKIP AGE_OK=$DIRAGE_OK${DBG_NUM_TV}${DBG_AGE}"
	fi
	done
done

################################################################################
# MP3
################################################################################
# Move and resort mp3 daydirs
# shellcheck disable=SC2086
if [ -d "$MP3SRC" ]; then
	for i in $( seq $MP3MONTHS ); do
		DATE="$( $DATEBIN --date="$i months ago" +"${MP3FMT}" )"
		if [ "$DATE" != "" ]; then
			for DIR in "${MP3SRC}/${DATE}"*; do
				DAYDIR="$( basename "${DIR}" )"
				if [ "${DAYDIR}" != "" ]; then
					if [ -d "${DIR}" ] && [ ! -d "${MP3DST}/${DAYDIR}" ]; then
						if [ "$DEBUG" -ge 1 ]; then
							echo "[DEBUG] mv -n ${DIR} ${MP3DST}/"
							for REL in "${MP3SRC}/${DAYDIR}/"*; do
								if [ -d "${REL}" ] && [ ! -h "${REL}" ]; then
									C_REL="$( echo "${REL}" | sed "s|${GLDIR}||g" )"
									# For debug purposes we'll use mp3src instead (since rels are not actually moved)
									echo "[DEBUG] MP3: $CHROOT $GLDIR $AUDIOSORT $C_REL (showing $MP3SRC instead of ${MP3DST}!)"
								fi
							done
						else
							mv -n "${DIR}" "${MP3DST}/"
							for REL in "${MP3DST}/${DAYDIR}/"*; do
								if [ -d "${REL}" ] && [ ! -h "${REL}" ]; then
									C_REL="$( echo "${REL}" | sed "s|${GLDIR}||g" )"
									$CHROOT $GLDIR "$AUDIOSORT" "$C_REL" >/dev/null 2>&1
								fi
							done
						fi
					fi
				fi
				if [ "$DEBUG" -ge 1 ]; then
					echo "[DEBUG] MP3:POSTCHK DIR=$DIR"
				fi
			done
		fi
	done
fi

################################################################################
# MUSICVIDEOS
################################################################################
# Move mv weekdirs
# shellcheck disable=SC2086
if [ -d "$MVSRC" ]; then
	for i in $( seq $MVWEEKS ); do
		DATE="$( "$DATEBIN" --date="$i weeks ago" +"${MVFMT}" )"
		DIR="${MVSRC}/${DATE}"
		if [ "$DATE" != "" ] && [ -d "${DIR}" ] && [ ! -d "${MVDST}/${DATE}" ]; then
			if [ "$DEBUG" -ge 1 ]; then
				echo "[DEBUG] MV: mv -n ${DIR} ${MVDST}/"
			else
				mv -n "${DIR}" "${MVDST}/"
			fi
		fi
	if [ "$DEBUG" -ge 1 ]; then
		echo "[DEBUG] MV:POSTCHK DIR=$DIR"
	fi
	done
fi

# vim: set noet ci pi sts=0 sw=4 ts=4:
