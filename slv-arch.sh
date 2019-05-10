#!/bin/sh
if [ "$( id -u )" -ne 0 ] || [ "$LOGNAME" != "root" ]; then
echo "You have to be root to run this script!"; exit 0; fi

################################################################################
# slv-arch(all) 20180330 silver
################################################################################
#
# slv-archiver - Moves releases from incoming to archive
#                Extra support for TV Series, 0DAY, MP3 and MV
#
# * Moves dirs to appropriate target dir in archive
#   e.g. /apps/* -> /archive/apps
#
# * Creates dirs in archive for tv series
#   e.g. /tv/Series.Name.S01E02-GRP -> /archive/tv/Series/S01
#        /0day/0310 -> /archive/0day/2013-03
#        /mp3/2013-03-10 -> /archive/mp3
#
# * Supports ".1 .2 .3" symlinks to multiple TV archive disks, like tur-links
#
# * It's also possible to use a seperate config file: "slv-arch.conf"
# * Needs: awk basename date find grep touch
#
################################################################################

###############################################################################
# GENERAL OPTIONS:
###############################################################################

DATEBIN="/bin/date"
GLDIR="/jail/glftpd"
CHROOT="/usr/sbin/chroot"
#LOGDIR="$GLDIR/ftp-data/logs"  # currently unused, logs to stdout

SKIP_PATH="^NUKED-.*|^\(.*|^_archive$|^FOO$|^BAR$"
CHECK_FOR="\(*M*F\ \-\ COMPLETE\ \)"
MINS_OLD="10080"  # releases need to be 1 week old before moving (7x24x60mins)
MIN_FREE="1048576"  # need 1GB+ free on MOUNT(s) before moving, 0 to disable

# Set CHECK_MOUNTS to "1" to check if MOUNTS are mounted before moving
# EXAMPLES:
# $GLDIR/site/archive
# /dev/mapper/archive2

CHECK_MOUNTS=0
#MOUNTS="
#/dev/mapper/site
#"

###############################################################################
# 0DAY SECTION:
###############################################################################
# Target dir for dated 0day archive, can optionally be used in MOVE dirs below
# EXAMPLES:
# To move '/0day/12?? -> /archive/0day/2013-12' when 6 months old, use in MOVE:
# $GLDIR/site/0DAY:^$(date -d "-6 month" +%m)[0-9][0-9]$:$ZDARCHIVE/$(date -d "-6 month" +%Y-%m)

ZDARCHIVE="$GLDIR/site/ARCHIVE/0DAY"

###############################################################################
# MP3 SECTION:
###############################################################################

# MP3FMT="%Y-%m"                    # dated dir format: year-month ("2013-12")
# MP3SRC="$GLDIR/site/mp3"          # source
# MP3DST="$GLDIR/site/archive/mp3"  # target
# MP3MONTHS="3 12"  # move all daydirs that are 4-12 months old
# AUDIOSORT="/bin/audiosort"

###############################################################################
# MUSICVIDEOS SECTION:
###############################################################################

# MVFMT="%Y-%W"                    # dated dir format: year-week ("2013-52")
# MVSRC="$GLDIR/glftpd/site/mv"    # source
# MVDST="$GLDIR/site/archive/mv"   # target
# MVWEEKS="25 53"  # move all weekdirs that are 25-53 weeks old

###############################################################################
# ALL SECTIONS:
###############################################################################
# Define which sections you want to move: apps, console, games, movies etc.
# MOVE does not use Series/Season structure. You can however add TV if you
# want to move it without using Series/Season, see EXAMPLES below

# SYNTAX: SOURCE_DIR:REGEXP:TARGET_DIR
# EXAMPLES:
MOVE="
$GLDIR/site/apps:*:$GLDIR/site/archive/apps
$GLDIR/site/divx:.*[._]G[eE][rR][mM][aA][nN][._].*:$GLDIR/site/archive/divx-de
$GLDIR/site/tv:^Holby.[cC]ity[._].*:$GLDIR/site/archive/tv-uk
$GLDIR/site/tv:.*-RiVER$:$GLDIR/site/archive/tv-uk
$GLDIR/site/x264:.*1080[pP].*$:$GLDIR/archive/x264-1080p
"

# NOTE: MOVE dirs are processed first (from top to bottom) and *before* TVDIRS

###############################################################################
# TV SECTION:
###############################################################################

# Source dir(s) for releases you want to move to Series/Season structure
# Comment to disable
TVDIRS="
$GLDIR/site/tv
"

# Target dir
# TVARCHIVE="$GLDIR/site/archive/tv"

# Uncomment to ignore MINS_OLD for TVDIRS and move 15 oldest releases instead:
# NUM_DIRS_TV="15"

# NOTE: I suggest you always leave MINS_OLD defined as "failsafe",
#       even if you use NUM_DIRS_TV instead

# Optionally set this variable if your tv archive uses symlinks to multiple
# "sub disks", like tur-links. E.g. your storage devices are mounted as:
# /archive/tv/.1 /archive/tv/.2 /archive/tv/.3 (or .mnt1 .mnt2 .mnt3 etc)
# TVARCSUBS=".1 .2 .3"

# NOTE: if you're having missing or dead symlinks using "sub disks", try
#       running "./slv-arch.sh links" manually to fix or crontab:
#       15 5 * * * /glftpd/bin/slv-arch.sh links DEL >/dev/null 2>&1


################################################################################
# END OF CONFIG
################################################################################

# ph33r what comes below ;)

# DEBUG: "./slv-arch.sh debug" does not actually mkdir and mv but
# just shows what actions the script would have executed instead
DEBUG=0

# Check if .conf file exist, source if it does
SCRIPT_CONF="$(dirname "$0")/$(basename -s '.sh' "$0").conf"
if [ -s "$SCRIPT_CONF" ]; then
	if [ "$DEBUG" -eq 1 ]; then echo "[DEBUG] Using SCRIPT_CONF=$SCRIPT_CONF"; fi
	. "$SCRIPT_CONF" || { echo "[ERROR] could not load $SCRIPT_CONF"; exit 1; }
fi

# Config checks
if [ -z $GLDIR ]; then
	echo "[ERROR] GLDIR is not set correctly, exiting..."; exit 1
fi
if echo "$MINS_OLD" | grep -qv "[0-9]\+"; then
	echo "[ERROR] MINS_OLD is not set correctly, exiting..."; exit 1
fi

# function to clean and create symlinks in tvarchive when using sub disks
func_lnk() {
	if [ ! -z "$TVARCSUBS" ]; then
		if [ "$1" = "DEL" ]; then
			find "$TVARCHIVE" -mindepth 1 -maxdepth 1 -xtype l -delete
		fi
		find "$TVARCHIVE" -mindepth 2 -maxdepth 2 -type d -printf '%P\n' | \
		while read -r i; do
			link="$(basename "$i")"
			if [ ! -L "$TVARCHIVE/$link" ]; then
				ln -s "$i" "$TVARCHIVE/$link"
			fi
		done
	fi
}

# function to convert kb mv gb tb
func_bc() {
	if echo "$1" | grep -q "[0-9]"; then
		U="$2"
		if [ "$U" = "" ]; then
			if [ "$1" -lt "1024" ]; then U="KB"
				elif [ "$1" -ge "1024" ] && [ "$1" -lt "1024000" ]; then U="MB"
				elif [ "$1" -ge "1024000" ] && [ "$1" -lt "1024000000" ]; then U="GB"
				elif [ "$1" -ge "1024000000" ]; then U="TB"
			fi
		fi
		if [ "$U" = "KB" ]; then RET="${1}KB"
			elif [ "$U" = "MB" ]; then RET="$(( $1 / 1024 ))MB"
			elif [ "$U" = "GB" ]; then RET="$(( $1 / 1024 / 1024 ))GB"
			elif [ "$U" = "TB" ]; then RET="$( echo "$1 1024" | awk '{ printf "%0.1f%s", $1 / $2 / $2 / $2, "TB"; }' )"
		fi
	fi
	echo "$RET"
}

# handle arguments
if echo "$1" | grep -iq "debug"; then DEBUG=1; fi
if echo "$1" | grep -iq "links"; then
	if echo "$2" | grep -iq "DEL"; then
		func_lnk DEL
	else
		func_lnk
	fi
	exit
fi

# get all mounts, for use in func_df below, run once
ALLMNT=""; i=0; MAX=0; MAX="$( echo "$MOUNTS" | wc -w )"
for M in $MOUNTS; do
	if [ $i -lt $(( MAX-1 )) ]; then ALLMNT="$ALLMNT\|$M"
	else ALLMNT=$M${ALLMNT}; fi
	i=$(( i+1 ))
done

# convert min free variable set by user in settings above, run once
MIN_FREE_GB="$( func_bc $MIN_FREE GB )"

# function to get free disk space, overwrites MIN_FREE_GB
func_df() {
	for d in "$@"; do
		DBGTXT="[DEBUG]"
		if [ ! -z $TVARCHIVE ]; then
			if echo "$d" | grep -q $TVARCHIVE; then DBGTXT="$DBGTXT TVARCHIVE:"; fi
		fi
		if [ ! -z $ZDARCHIVE ]; then
			if echo "$d" | grep -q $ZDARCHIVE; then DBGTXT="$DBGTXT 0DAYARCHIVE"; d="$ZDARCHIVE"; fi
		fi
		if [ "$CHECK_MOUNTS" -eq 1 ]; then
			if ! findmnt --target "$d" | grep -q "\(^\| \)\($ALLMNT\)\(/\.[0-9]\| \)"; then
				if [ "$DEBUG" -eq 1 ]; then
					if [ "$d" != "$mtmp" ]; then echo "$DBGTXT $d - NOK: device not mounted"; fi
					mtmp="$d"
				fi
				return 1
			fi
		fi
		FS=$( df "$d" | awk '{ print $1 }' | tail -1 )
		DF=$( df "$d" | awk '{ print $4 }' | tail -1 )
		if echo "$DF" | grep -q "[0-9]"; then
			if [ "$DF" -lt "$MIN_FREE" ]; then
				if [ "$DEBUG" -eq 1 ]; then
					if [ "$d" != "$dtmp" ]; then echo "$DBGTXT $d - NOK: not enough disk space on \"$FS\" ($(func_bc "$DF" GB) free, $MIN_FREE_GB needed)"; fi
				fi
				dtmp="$d"
				return 1
			else
				if [ "$DEBUG" -eq 1 ]; then
					if [ "$d" != "$dtmp" ]; then echo "$DBGTXT $d - OK: enough disk space on \"$FS\" ($(func_bc "$DF" GB) free, $MIN_FREE_GB needed)"; fi
				fi
				dtmp="$d"
				return 0
			fi
		else
			echo "[ERROR] could not get free disk space on $d"
			return 1
		fi
	done
}

################################################################################
# MOVE # move src dirs to target for all sections
################################################################################
for RULE in $MOVE; do
	SRCDIR="$( echo "$RULE" | awk -F ":" '{ print $1 }' )"
	REGEXP="$( echo "$RULE" | awk -F ":" '{ print $2 }' )"
	DSTDIR="$( echo "$RULE" | awk -F ":" '{ print $3 }' )"
	for RLS in $( find "$SRCDIR" -mindepth 1 -maxdepth 1 -type d -printf "%f\n" | sort | grep -Ev "$SKIP_PATH" ); do
		if ! func_df "$DSTDIR"; then 
			if [ "$DEBUG" -eq 1 ]; then 
				if [ "$DEBUG" -eq 1 ]; then if [ "$DSTDIR" != "$stmp" ]; then echo "[DEBUG] skipping $DSTDIR"; fi; fi
				stmp="$DSTDIR"
			fi
		 	continue
		fi
		SKIP="NO"
 		if ls -1 "$SRCDIR/$RLS" | grep -q -e "^[cC][dD][1-9]$" -e "^[dD][iI][sS][cCkK][1-9]$" -e "^[dD][vV][dD][1-9]$"; then
			for each_cd in $( ls -1 "$SRCDIR/$RLS" | grep -e "^[cC][dD][1-9]$" -e "^[dD][iI][sS][cCkK][1-9]$" -e "^[dD][vV][dD][1-9]$" ); do
				if [ -z "$( ls -1 "$SRCDIR/$RLS/$each_cd" | grep -E "$CHECK_FOR" )" ]; then
					if ls -1 "$SRCDIR/$RLS/$each_cd" | grep -q "\.[sS][fF][vV]$"; then
						SKIP="YES"
					else
						SKIP="NO"
					fi
				fi
			done
		else
			if [ -z "$( ls -1 "$SRCDIR/$RLS" | grep -E "$CHECK_FOR" )" ]; then
				if ls -1 "$SRCDIR/$RLS" | grep -q "\.[sS][fF][vV]$"; then
					SKIP="YES"
				else
					SKIP="NO"
				fi
			fi
		fi
                CURDATE_SEC="$( $DATEBIN +%s )"; DIRAGE_MIN=0
		DIRDATE_SEC="$( ls -ld --time-style='+%s' "$SRCDIR/$RLS" | awk '{ print $6 }' )"
		if echo "$DIRDATE_SEC" | grep -q "[0-9]"; then DIRAGE_MIN=$(( (CURDATE_SEC - DIRDATE_SEC) / 60 )); fi
		if [ "$DIRAGE_MIN" -ge "$MINS_OLD" ] && [ "$SKIP" = "NO" ]; then
			if echo "$RLS" | grep -Eq "$REGEXP"; then
				if [ ! "$( ls -1d "$DSTDIR" 2>/dev/null )" ]; then
					if [ "$DEBUG" -eq 1 ]; then
						echo "[DEBUG] mkdir $DSTDIR"
					else
						mkdir "$DSTDIR"
					fi
				fi
				if [ "$DEBUG" -eq 1 ]; then
					echo "[DEBUG] mv $SRCDIR/$RLS $DSTDIR"
				else
					mv "$SRCDIR/$RLS" "$DSTDIR"
				fi
			fi
		fi
		if [ "$DEBUG" -eq 1 ]; then
			echo "[DEBUG] SRCDIR/RLS: $SRCDIR/$RLS DSTDIR: $DSTDIR REGEXP: $REGEXP"
		fi
	done
done

################################################################################
# TV 
################################################################################

# get stuff to skip for tv
SKIP_SECTION=""
for DIR in $TVDIRS; do
	SKIP_SECTION="^$DIR\$|$SKIP_SECTION"
done
for RULE in $MOVE; do
	SRCDIR="$( echo "$RULE" | awk -F ":" '{ print $1 }' )"
	REGEXP="$( echo "$RULE" | awk -F ":" '{ print $2 }' )"
	DSTDIR="$( echo "$RULE" | awk -F ":" '{ print $3 }' )"
	if echo $TVDIRS | grep -q $SRCDIR; then
		if echo $DSTDIR | grep -q $TVARCHIVE; then
			SKIP_PATH="$REGEXP|$SKIP_PATH"
		fi
	fi
done

# check disk space for tvarchive, both if using subdisks or not
if [ -z "$TVARCSUBS" ]; then
	if [ ! -z "$TVARCHIVE" ]; then
		if ! func_df "$TVARCHIVE"; then
			if [ "$DEBUG" -eq 1 ]; then
				echo "[DEBUG] skipping $DSTDIR"
			fi
			exit 1
		fi
	fi
else
	# find initial sub disk with the most free disk space
	TVARCHSUB="$( \
			for i in $TVARCSUBS; do
				if func_df "$TVARCHIVE/$i" KB; then echo "$i $DF"; fi
			done | grep -v "[DEBUG]" | sort -k2 -n | tail -1 | awk '{ print $1 }' \
		   )"
	if [ "$TVARCHSUB" ]; then
		if [ "$DEBUG" -eq 1 ]; then
			echo "[DEBUG] TVARCHIVE: $TVARCHIVE - OK: subdisk \"$TVARCHSUB\" has the most disk space free (of \"$TVARCSUBS\")"; func_df "$TVARCHIVE/$TVARCHSUB"
		fi
	else
		if [ "$DEBUG" -eq 1 ]; then
			echo "[DEBUG] TVARCHIVE: $TVARCHIVE - NOK: none of the subdisks \"$TVARCSUBS\" are mounted and/or have enough disk space free"
		fi
		exit 1
	fi
fi

# move tv dirs
for TVDIR in $TVDIRS; do
	if echo "$NUM_DIRS_TV" | grep -q "[0-9]"; then
		CURDATE_SEC="$( "$DATEBIN" +%s )"
		# use this format for skip_path here: "/NUKED-|/\(|/_ARCHIVE\ |/_OLDER\ "
		SKIP_PATH_TMP="$( echo "$SKIP_PATH" | sed -e 's@\^@/@g' -e 's@\.\*@@g' -e 's@\$@\\\ @g' )"
		if [ "$DEBUG" -eq 1 ]; then echo "[DEBUG] TVARCHIVE: NUM_DIRS_TV $NUM_DIRS_TV SKIP_PATH_TMP $SKIP_PATH_TMP"; fi
		for DIR in $( ls -ldrt --time-style='+%s' "$TVDIR"/* | grep -Ev "$SKIP_PATH_TMP" | head -"$NUM_DIRS_TV" | sed "s@$GLDIR/site@@g" | sed 's/ /^/g' ); do
			DIRDATE_SEC="$( echo "$DIR" | awk -F \^ '{ print $6 }' )"
			if echo "$DIRDATE_SEC" | grep -q "[0-9]"; then DIRAGE_MIN=$(( (CURDATE_SEC - DIRDATE_SEC) / 60 )); fi
			if [ "$DEBUG" -eq 1 ]; then echo "[DEBUG] TVARCHIVE: DIR $DIR DIRDATE_SEC $DIRDATE_SEC DIRAGE_MIN $DIRAGE_MIN"; fi
		done
		if echo "$DIRAGE_MIN" | grep -q "[0-9]"; then MINS_OLD="$DIRAGE_MIN"; fi
	fi

	SKIP_REGEXP="$( echo "$SKIP_PATH" | sed "s@\^@\^$TVDIR/@g" )"
	for DIR in $( find "$TVDIR" -maxdepth 1 -regextype posix-egrep ! -regex "${SKIP_SECTION}${SKIP_REGEXP}" ); do
		# find sub disk which has currently the most free disk space
		if [ ! -z "$TVARCSUBS" ]; then
			TVARCHSUB="$( \
					for i in $TVARCSUBS; do
						if func_df "$TVARCHIVE/$i" KB; then echo "$i $DF"; fi
					done | grep -v "[DEBUG]" | sort -k2 -n | tail -1 | awk '{ print $1 }' \
				   )"
		fi
		SKIP="NO"
		if ls -1 "$DIR" | grep -q -e "^[cC][dD][1-9]$" -e "^[dD][iI][sS][cCkK][1-9]$" -e "^[dD][vV][dD][1-9]$"; then
			for each_cd in $( ls -1 "$DIR" | grep -e "^[cC][dD][1-9]$" -e "^[dD][iI][sS][cCkK][1-9]$" -e "^[dD][vV][dD][1-9]$" ); do
				if [ -z "$( ls -1 "$DIR/$each_cd" | grep -E "$CHECK_FOR" )" ]; then
					if ls -1 "$DIR/$each_cd" | grep -q "\.[sS][fF][vV]$"; then
						SKIP="YES"
					else
						SKIP="NO"
					fi
				fi
			done
		else
			if [ -z "$( ls -1 "$DIR" | grep -E "$CHECK_FOR" )" ]; then
				if ls -1 "$DIR" | grep -q "\.[sS][fF][vV]$"; then
					SKIP="YES"
				else
					SKIP="NO"
				fi
			fi
		fi
		CURDATE_SEC="$( $DATEBIN +%s )"
		DIRDATE_SEC="$( ls -ld --time-style='+%s' "$DIR" | awk '{ print $6 }' )"
		if echo "$DIRDATE_SEC" | grep -q "[0-9]"; then DIRAGE_MIN=$(( (CURDATE_SEC - DIRDATE_SEC) / 60 )); fi
		if [ "$DIRAGE_MIN" -ge "$MINS_OLD" ] && [ "$SKIP" = "NO" ]; then
			BASEDIR="$( basename "$DIR" )"
			# regexs to replace/remove tags from release name so we get better series titles
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
				-e 's/\.\(S[0-9]\+E[0-9]\+\)\..*//gi' \
				-e 's/\.\(S[0-9]\+E[0-9]\+\-E[0-9]\+\)\..*//gi' \
				-e 's/\.\(S[0-9]\+E[0-9]\+[E-][0-9]\+\)\..*//gi' \
				-e 's/\.\(S[0-9]\+\)\..*//gi' \
				-e 's/\.\(E[0-9]+\)\..*//gi' \
				-e 's/[._]\(\([0-9]\|[0-9]\)x[0-9]\+\)[._].*//gi' \
				-e 's/[._]\([0-9]\+[._][0-9]\+[._][0-9]\+\)[._].*//gi' \
				-e 's/[._-]\(hdtv\|pdtv\|dsr\|dsrip\|webrip\|web\|h264\|x264\|\|xvid\|720p\|1080p\|2160p\|ws\|dvdrip\|bluray\|uhd\)\($\|[._-]\).*//gi' \
				-e 's/[._-]\(dirfix\|proper\|repack\|nfofix\|preair\|pilot\|ppv\|extended\\|complete\|dual\|part.[0-9]\+\)\($\|[._-]\).*//gi' \
				-e 's/[._-]\(dutch\|german\|flemish\|french\|hungarian\|italian\|norwegian\|polish\|portuguese\|spanish\|russian\|swedish\)\($\|[._-]\).*//gi' )"
			SEASON="$( echo "$DIR" | sed -e 's/.*[._-]S\([0-9]\+\)E[0-9].*/\1/i' \
				-e 's/.*S\([0-9]\|[0-9][0-9]\+\)\..*/\1/i' \
				-e 's/.*[._-]\([0-9]\+\)x[0-9].*/\1/i' \
				-e 's/.*\([0-9][0-9][0-9][0-9]\).[0-9][0-9].[0-9][0-9].*/\1/i' )"
			if echo "$SEASON" | grep -q "^[0-9]$"; then SEASON="S0$SEASON"; else SEASON="S$SEASON"; fi
			if echo "$SEASON" | grep -qv "^S\([0-9]$\|[0-9][0-9]\|[0-9][0-9][0-9]\)$"; then SEASON=""; fi
			DSTSERIES="$( echo "$SRCSERIES" | sed 's/\(\w\)_/\1\./g' )"
			CHKSERIES="$( echo "$DSTSERIES" | sed 's/\([a-z]\|[A-Z]\)/[\L\1\U\1\]/g' )"
			DIRDATE="$( $DATEBIN --date "01/01/1970 +$DIRDATE_SEC seconds" +"%Y-%m-%d %H:%M:%S" )"
			MV=0
			if [ "$SEASON" = "" ]; then
				if [ ! "$( ls -1d $TVARCHIVE/$CHKSERIES 2>/dev/null )" ]; then
					if [ -z "$TVARCHSUB" ]; then
						if [ "$DEBUG" -eq 1 ]; then
							echo "[DEBUG] TVARCHIVE:" mkdir "$TVARCHIVE/$DSTSERIES"
						else
							mkdir "$TVARCHIVE/$DSTSERIES"
						fi
					else
						if [ "$DEBUG" -eq 1 ]; then
							if [ ! -d "$TVARCHIVE/$TVARCHSUB/$DSTSERIES" ]; then echo "[DEBUG] TVARCHIVE:" mkdir "$TVARCHIVE/$TVARCHSUB/$DSTSERIES"; fi
							if [ ! -L $TVARCHIVE/$CHKSERIES ]; then echo "[DEBUG] TVARCHIVE:" ln -s "$TVARCHSUB/$DSTSERIES" "$TVARCHIVE/$DSTSERIES"; fi
						else
							if [ ! -d "$TVARCHIVE/$TVARCHSUB/$DSTSERIES" ]; then mkdir "$TVARCHIVE/$TVARCHSUB/$DSTSERIES"; fi
							if [ ! -L $TVARCHIVE/$CHKSERIES ]; then ln -s "$TVARCHSUB/$DSTSERIES" "$TVARCHIVE/$DSTSERIES"; fi
						fi
					fi
				fi
				if [ "$( ls -1d $TVARCHIVE/$CHKSERIES 2>/dev/null )" ]; then
				        if [ "$( ls -1d $TVARCHIVE/$CHKSERIES | wc -l )" -eq 1 ]; then
						if [ -z "$TVARCHSUB" ]; then
							if [ "$DEBUG" -eq 1 ]; then
								echo "[DEBUG] TVARCHIVE:" mv "$DIR" $TVARCHIVE/$CHKSERIES/ && MV=1
							else
								mv "$DIR" $TVARCHIVE/$CHKSERIES/ && MV=1
							fi
						else
							if [ -L $TVARCHIVE/$CHKSERIES ]; then
								TVLINKSUB="$( dirname "$( readlink $TVARCHIVE/$CHKSERIES )" )"
								if [ "$TVLINKSUB" = "$TVARCHSUB" ]; then
									if [ "$DEBUG" -eq 1 ]; then
										echo "[DEBUG] TVARCHIVE:" mv "$DIR" $TVARCHIVE/$CHKSERIES/ && MV=255
									else
										mv "$DIR" $TVARCHIVE/$CHKSERIES/ && MV=1
									fi
								else
									if func_df "$TVARCHIVE/$TVLINKSUB"; then
										if [ "$DEBUG" -eq 1 ]; then
											echo "[DEBUG] TVARCHIVE:" mv "$DIR" $TVARCHIVE/$CHKSERIES/ "(on subdisk \"$TVLINKSUB\")" && MV=255
										else
											mv "$DIR" $TVARCHIVE/$CHKSERIES/ && MV=1
										fi
									else
										echo "[INFO] skipping mv $DIR - \"$DSTSERIES\" is not on \"$TVARCHSUB\"" and \"$TVLINKSUB\" is full/unmounted
									fi
								fi
							fi
						fi
					else
						MV=0
						echo "[ERROR] TVARCHIVE: skipping \"$DSTSERIES\" - more than 1 dir found... $(ls -1d $TVARCHIVE/$CHKSERIES|sed 's|'"$GLDIR"'/site||g'|tr '\n' ' ')"
					fi
				fi
				if [ "$MV" -eq 1 ] && [ -d "$( ls -1d $TVARCHIVE/$CHKSERIES/$BASEDIR 2>/dev/null )" ]; then
					if [ "$DEBUG" -eq 1 ]; then
						echo "[DEBUG] TVARCHIVE:" touch -d "$DIRDATE" $TVARCHIVE/$CHKSERIES/$BASEDIR
					else
						touch -c -d "$DIRDATE" $TVARCHIVE/$CHKSERIES/$BASEDIR
					fi
				else
					echo "[ERROR] TVARCHIVE: wont touch \"$TVARCHIVE/$DSTSERIES/$BASEDIR\" - move failed or no dir (MV=$MV)"
				fi
			else
				if [ ! "$( ls -1d $TVARCHIVE/$CHKSERIES 2>/dev/null )" ]; then
					if [ -z "$TVARCHSUB" ]; then
						if [ "$DEBUG" -eq 1 ]; then
							echo "[DEBUG] TVARCHIVE:" mkdir $TVARCHIVE/$DSTSERIES
						else
							mkdir $TVARCHIVE/$DSTSERIES
						fi
					else
						if [ "$DEBUG" -eq 1 ]; then
							if [ ! -d "$TVARCHIVE/$TVARCHSUB/$DSTSERIES" ]; then echo "[DEBUG] TVARCHIVE:" mkdir "$TVARCHIVE/$TVARCHSUB/$DSTSERIES"; fi
							if [ ! -L $TVARCHIVE/$CHKSERIES ]; then echo "[DEBUG] TVARCHIVE:" ln -s "$TVARCHSUB/$DSTSERIES" "$TVARCHIVE/$DSTSERIES"; fi
						else
							if [ ! -d "$TVARCHIVE/$TVARCHSUB/$DSTSERIES" ]; then mkdir "$TVARCHIVE/$TVARCHSUB/$DSTSERIES"; fi
							if [ ! -L $TVARCHIVE/$CHKSERIES ]; then ln -s "$TVARCHSUB/$DSTSERIES" "$TVARCHIVE/$DSTSERIES"; fi
						fi
					fi
				fi
				if [ ! "$( ls -1d $TVARCHIVE/$CHKSERIES/$SEASON 2>/dev/null )" ]; then
					if [ -z "$TVARCHSUB" ]; then
						if [ "$DEBUG" -eq 1 ]; then
							echo "[DEBUG] TVARCHIVE:" mkdir $( ls -1d $TVARCHIVE/$CHKSERIES 2>/dev/null || echo [LS_ERR]:$TVARCHIVE/$CHKSERIES )/$SEASON
						else
							#mkdir $TVARCHIVE/$TVARCHSUB/$DSTSERIES/$SEASON
							mkdir $( ls -1d $TVARCHIVE/$CHKSERIES 2>/dev/null )/$SEASON
						fi
					else
						if [ -L $TVARCHIVE/$CHKSERIES ]; then
							TVLINKSUB="$( dirname "$( readlink $TVARCHIVE/$CHKSERIES )" )"
							if [ "$TVLINKSUB" = "$TVARCHSUB" ]; then
								if [ "$DEBUG" -eq 1 ]; then
									#echo "[DEBUG] TVARCHIVE:" mkdir $TVARCHIVE/$TVARCHSUB/$DSTSERIES/$SEASON
									echo "[DEBUG] TVARCHIVE:" mkdir $( ls -1d $TVARCHIVE/$CHKSERIES 2>/dev/null || echo [LS_ERR]:$TVARCHIVE/$CHKSERIES )/$SEASON
								else
									mkdir $( ls -1d $TVARCHIVE/$CHKSERIES 2>/dev/null )/$SEASON
								fi
							else
								if func_df "$TVARCHIVE/$TVLINKSUB"; then 
									if [ "$DEBUG" -eq 1 ]; then
										echo "[DEBUG] TVARCHIVE:" mkdir $( ls -1d $TVARCHIVE/$CHKSERIES 2>/dev/null || echo [LS_ERR]:$TVARCHIVE/$CHKSERIES )/$SEASON "(on subdisk \"$TVLINKSUB\")"
									else	
										mkdir $( ls -1d $TVARCHIVE/$CHKSERIES 2>/dev/null )/$SEASON 
									fi
								else
									echo "[INFO] skipping mkdir $TVARCHIVE/$DSTSERIES/$SEASON - \"$DSTSERIES\" links to \"$TVLINKSUB\" which is full/unmounted (not on \"$TVARCHSUB\")"
								fi
							fi
						fi
					fi
				fi
				if [ "$( ls -1d $TVARCHIVE/$CHKSERIES/$SEASON 2>/dev/null )" ]; then
					if [ -z "$TVARCHSUB" ]; then
						if [ "$DEBUG" -eq 1 ]; then
							echo "[DEBUG] TVARCHIVE:" mv "$DIR" $TVARCHIVE/$CHKSERIES/$SEASON && MV=255
						else
							mv "$DIR" $TVARCHIVE/$CHKSERIES/$SEASON && MV=1
						fi
					else
                  				if [ "$( ls -1d $TVARCHIVE/$CHKSERIES | wc -l )" -eq 1 ]; then
							if [ -L $TVARCHIVE/$CHKSERIES ]; then
								TVLINKSUB="$( dirname "$( readlink $TVARCHIVE/$CHKSERIES )" )"
								if [ "$TVLINKSUB" = "$TVARCHSUB" ]; then
									if [ "$DEBUG" -eq 1 ]; then
										echo "[DEBUG] TVARCHIVE:" mv "$DIR" $TVARCHIVE/$CHKSERIES/$SEASON && MV=255
									else
										mv "$DIR" $TVARCHIVE/$CHKSERIES/$SEASON && MV=1
									fi
								else
									if func_df "$TVARCHIVE/$TVLINKSUB"; then 
										if [ "$DEBUG" -eq 1 ]; then
											echo "[DEBUG] TVARCHIVE:" mv "$DIR" $TVARCHIVE/$CHKSERIES/$SEASON "(on subdisk \"$TVLINKSUB\")" && MV=255
										else	
											mv "$DIR" $TVARCHIVE/$CHKSERIES/$SEASON && MV=1
										fi
									else
										MV=0
										echo "[INFO] TVARCHIVE: skipping mv $DIR - dir \"$DSTSERIES\" is not on \"$TVARCHSUB\"" and \"$TVLINKSUB\" is full or not mounted
									fi
								fi
							fi
                                                else
							MV=0
							echo "[ERROR] TVARCHIVE: skipping \"$DSTSERIES\" - more than 1 dir found... $(ls -1d $TVARCHIVE/$CHKSERIES|sed 's|'"$GLDIR"'/site||g'|tr '\n' ' ')"
                                                fi
					fi
				fi
				if [ "$MV" -eq 1 ] && [ -d "$( ls -1d $TVARCHIVE/$CHKSERIES/$SEASON/$BASEDIR 2>/dev/null )" ]; then
					if [ "$DEBUG" -eq 1 ]; then
						echo "[DEBUG] TVARCHIVE: " touch -d "$DIRDATE" $TVARCHIVE/$CHKSERIES/$SEASON/$BASEDIR
					else
						touch -c -d "$DIRDATE" $TVARCHIVE/$CHKSERIES/$SEASON/$BASEDIR
					fi
				else
					echo "[ERROR] TVARCHIVE: wont touch \"$TVARCHIVE/$DSTSERIES/$SEASON/$BASEDIR\" - move failed or no dir (MV=$MV)"
				fi
			fi
		fi
	done
done

################################################################################
# MP3 # move and resort mp3 daydirs:
################################################################################
if [ -d "$MP3SRC" ]; then
	for i in $( seq $MP3MONTHS ); do
		DATE="$( $DATEBIN --date="$i months ago" +${MP3FMT} )"
		if [ "$DATE" != "" ]; then
			for DIR in "${MP3SRC}/${DATE}"*; do
				DAYDIR="$( basename "${DIR}" )"
				if [ "${DAYDIR}" != "" ]; then
					if [ -d "${DIR}" ] && [ ! -d "${MP3DST}/${DAYDIR}" ]; then
						if [ "$DEBUG" -eq 1 ]; then
							echo "[DEBUG] mv -n ${DIR} ${MP3DST}/"
							for RLS in "${MP3SRC}/${DAYDIR}/"*; do
								if [ -d "${RLS}" ] && [ ! -h "${RLS}" ]; then
									CRLS="$( echo "${RLS}" | sed "s@${GLROOT}@@g" )"
									# for debug purposes we're using mp3src instead
									# reason is releases are not actually moved
									echo "[DEBUG] $CHROOT $GLROOT $AUDIOSORT $CRLS (USING $MP3SRC INSTEAD OF $MP3DST!)"
								fi
							done
						else
							mv -n "${DIR}" "${MP3DST}/"
							for RLS in "${MP3DST}/${DAYDIR}/"*; do
								if [ -d "${RLS}" ] && [ ! -h "${RLS}" ]; then
									CRLS="$( echo "${RLS}" | sed "s@${GLROOT}@@g" )"
									$CHROOT $GLROOT $AUDIOSORT "$CRLS" >/dev/null 2>&1
 								fi
							done
						fi
					fi
				fi
			done
		fi
	done
fi

################################################################################
# MV # move mv weekdirs:
################################################################################
if [ -d "$MVSRC" ]; then
	for i in $( seq $MVWEEKS ); do
		DATE="$( $DATEBIN --date="$i weeks ago" +${MVFMT} )"
		if [ "$DATE" != "" ]; then
			for DIR in "${MVSRC}/${DATE}"; do
				WEEKDIR="$( basename "${DIR}" )"
				if [ "${WEEKDIR}" != "" ]; then
					if [ -d "${DIR}" ] && [ ! -d "${MVDST}/${WEEKDIR}" ]; then
						if [ -d "${DIR}" ]; then
							if [ "$DEBUG" -eq 1 ]; then
								echo "[DEBUG] mv -n ${DIR} ${MVDST}/"
							else
								mv -n "${DIR}" "${MVDST}/"
							fi
						fi
					fi
				fi
			done
		fi
	done
fi
