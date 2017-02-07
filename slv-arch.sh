#!/bin/sh

if [ "$LOGNAME" != "root" ]; then
  echo "You have to be root to run this script!"
  exit 0
fi

############################################################
# slv-arch 30032012 silver
############################################################
# 
# uses: awk basename date find grep mv
# - moves dirs to appropriate target dir in archive and
# - creates dirs in archive for tv series (show/season)
# 
############################################################

DATEBIN="/bin/date"
GLDIR="/jail/glftpd"
LOGDIR="$GLDIR/ftp-data/logs"
TVARCHIVE="$GLDIR/site/archive/tv"
SKIPDIRS="^NUKED-.*|^\(.*|^_archive$|^FOO$|^BAR$"
MINS_OLD="10080"
# uncomment to ignore MINS_OLD above and just move 15 oldest instead:
# NUM_DIRS_TV="15"
CHECK_FOR="\(*M*F\ \-\ COMPLETE\ \)"

# Examples:
MOVE="
$GLDIR/site/apps:*:$GLDIR/site/archive/apps
$GLDIR/site/dox:*:$GLDIR/site/archive/dox
$GLDIR/site/divx:.*[._][gG][eE][rR][mM][aA][nN][._].*:$GLDIR/site/archive/divx-german
$GLDIR/site/divx:*:$GLDIR/site/archive/divx
$GLDIR/site/tv:^Holby.[cC]ity[._].*:$GLDIR/site/archive/tv-uk
$GLDIR/site/tv:^Top.Gear[._].*:$GLDIR/site/archive/tv-uk
$GLDIR/site/tv:^[tT][hH][eE][._][uU][lL][tT][iI][mM][aA][tT][eE][._][fF][iI][gG][hH][tT][eE][rR][._].*:$GLDIR/site/archive/tv/MMA/The.Ultimate.Fighter
$GLDIR/site/tv:^[uU][fF][cC][._].*:$GLDIR/site/archive/tv/MMA/UFC
$GLDIR/site/tv:.*-RiVER$:$GLDIR/site/archive/tv-uk
$GLDIR/site/x264:.*720[pP].*$:$GLDIR/archive/x264-720p
$GLDIR/site/x264:.*1080[pP].*$:$GLDIR/archive/x264-1080p
"

TVDIRS="
$GLDIR/site/tv
"

############################################################
# end of config
############################################################

for FIELD in $MOVE; do
	SRCDIR="`echo $FIELD|awk -F ":" '{ print $1 }'`"
	REGEXP="`echo $FIELD|awk -F ":" '{ print $2 }'`"
	DSTDIR="`echo $FIELD|awk -F ":" '{ print $3 }'`"
	for RLS in `ls -1 $SRCDIR|egrep -v "$SKIPDIRS"`; do
		SKIP="NO"
		if [ "`ls -1 "$SRCDIR/$RLS" | grep -e "^[cC][dD][1-9]$" -e "^[dD][iI][sS][cCkK][1-9]$" -e ^[dD][vV][dD][1-9]$`" ]; then
			for each_cd in `ls -1 "$SRCDIR/$RLS" | grep -e "^[cC][dD][1-9]$" -e "^[dD][iI][sS][cCkK][1-9]$" -e ^[dD][vV][dD][1-9]$`; do
				if [ -z "`ls -1 "$SRCDIR/$RLS/$each_cd" | egrep "$CHECK_FOR"`" ]; then
					if [ "`ls -1 $SRCDIR/$RLS/$each_cd | grep "\.[sS][fF][vV]$"`" ]; then
						SKIP="YES"
						#break
					else
						SKIP="NO"
					fi
				fi
			done
		else
			if [ -z "`ls -1 "$SRCDIR/$RLS" | egrep "$CHECK_FOR"`" ]; then
				if [ "`ls -1 $SRCDIR/$RLS | grep "\.[sS][fF][vV]$"`" ]; then
					SKIP="YES"
					#break
				else
					SKIP="NO"
				fi
			fi
		fi
	        CURDATE_SEC="`$DATEBIN +%s`"
	        DIRDATE_SEC="`ls -ld --time-style='+%s' $SRCDIR/$RLS | awk '{ print $(NF-1) }'`"
	        DIRAGE_MIN=$[ ($CURDATE_SEC - $DIRDATE_SEC) / 60 ]
	        if [ "$DIRAGE_MIN" -gt "$MINS_OLD" ] && [ "$SKIP" = "NO" ]; then
			if [ "`echo $RLS|egrep "$REGEXP"`" ]; then
				if [ ! "`ls -1d $DSTDIR 2>/dev/null`" ]; then
					if [ "`echo $1|grep -i "debug"`" ]; then
						echo "DEBUG: mkdir $DSTDIR"
					else
						mkdir "$DSTDIR"
					fi
				fi
				if [ "`echo $1|grep -i "debug"`" ]; then
					echo "DEBUG: mv $SRCDIR/$RLS $DSTDIR"
				else
					mv "$SRCDIR/$RLS" $DSTDIR
				fi
			fi
		fi
	done
done

for SKIP in $TVDIRS; do
	ALLSKIP="^$SKIP\$|$ALLSKIP"
done

if [ "`echo $NUM_DIRS_TV|grep [0-9]*`" ]; then
	CURDATE_SEC="`$DATEBIN +%s`"
	for DIR in `ls -ldrt --time-style='+%s' /jail/glftpd/site/TV-X264/*|head -${NUM_DIRS_TV}|sed 's@/jail/glftpd/site@@g'|sed 's/ /^/g'`; do
		DIRDATE_SEC="`echo $DIR|awk -F \^ '{ print $(NF-1) }'`"
		DIRAGE_MIN=$[ ($CURDATE_SEC - $DIRDATE_SEC) / 60 ]
		if [ "`echo $1|grep -i "debug"`" ]; then
			echo "DEBUG: DIR $DIR DIRAGE_MIN $DIRAGE_MIN MINS_OLD $MINS_OLD"
		fi
	done
MINS_OLD="$DIRAGE_MIN"
fi

for TVDIR in $TVDIRS; do
	SKIPREGEXP="`echo $SKIPDIRS|sed "s@\^@\^$TVDIR/@g"`"
	for DIR in `find $TVDIR -maxdepth 1 -regextype posix-egrep ! -regex "$ALLSKIP$SKIPREGEXP"`; do
		SKIP="NO"
		if [ "`ls -1 "$DIR" | grep -e "^[cC][dD][1-9]$" -e "^[dD][iI][sS][cCkK][1-9]$" -e ^[dD][vV][dD][1-9]$`" ]; then
			for each_cd in `ls -1 "$DIR" | grep -e "^[cC][dD][1-9]$" -e "^[dD][iI][sS][cCkK][1-9]$" -e ^[dD][vV][dD][1-9]$`; do
				if [ -z "`ls -1 "$DIR/$each_cd" | egrep "$CHECK_FOR"`" ]; then
					if [ "`ls -1 $DIR/$each_cd | grep "\.[sS][fF][vV]$"`" ]; then
						SKIP="YES"
						#break
					else
						SKIP="NO"
					fi
				fi
			done
		else
			if [ -z "`ls -1 "$DIR" | egrep "$CHECK_FOR"`" ]; then
				if [ "`ls -1 "$DIR" | grep "\.[sS][fF][vV]$"`" ]; then
					SKIP="YES"
					#break
				else
					SKIP="NO"
				fi
			fi
		fi
		CURDATE_SEC="`$DATEBIN +%s`"
		DIRDATE_SEC="`ls -ld --time-style='+%s' $DIR | awk '{ print $(NF-1) }'`"
		DIRAGE_MIN=$[ ($CURDATE_SEC - $DIRDATE_SEC) / 60 ]
		if [ "$DIRAGE_MIN" -gt "$MINS_OLD" ]  && [ "$SKIP" = "NO" ]; then
			BASEDIR="`basename $DIR`"
			SRCSERIE="`echo $BASEDIR | sed \
			-e 's/\([._]\)A\([._]\)/\1a\2/g' \
			-e 's/\([._]\)And\([._]\)/\1and\2/g' \
			-e 's/\([._]\)In\([._]\)/\1in\2/g' \
			-e 's/\([._]\)The\([._]\)/\1the\2/g' \
			-e 's/\([._]\)Of\([._]\)/\1of\2/g' \
			-e 's/\([._]\)On\([._]\)/\1on\2/g' \
			-e 's/\([._]\)Or\([._]\)/\1or\2/g' \
			-e 's/\([._]\)With\([._]\)/\1with\2/g' \
			-e 's/\.\(S[0-9]*E[0-9]*\)\..*//gi' \
			-e 's/\.\(S[0-9]*E[0-9]*\-E[0-9]*\)\..*//gi' \
			-e 's/\.\(S[0-9]*E[0-9]*[E-][0-9]*\)\..*//gi' \
			-e 's/\.\(S[0-9]*\)\..*//gi' \
			-e 's/\.\(E[0-9]*\)\..*//gi' \
			-e 's/[._]\(\([0-9]\|[0-9]\)x[0-9]*\)[._].*//gi' \
			-e 's/[._]\([0-9]*[._][0-9]*[._][0-9]*\)[._].*//gi' \
			-e 's/[._-]\(hdtv\|pdtv\|dsr\|dsrip\|webrip\|web\|h264\|x264\|\|xvid\|720p\|1080p\|dvdrip\|ws\|dirfix\|proper\|repack\|nfofix\|preair\|pilot\|ppv\|dutch\|german\|extended\|part.[0-9]\+\)\($\|[._-]\).*//gi'`"
			SEASON="`echo $DIR | sed -e 's/.*[._-]S\([0-9]*\)E[0-9].*/\1/i' -e 's/.*S\([0-9]\|[0-9][0-9]*\)\..*/\1/i' -e 's/.*[._-]\([0-9]*\)x[0-9].*/\1/i' -e 's/.*\([0-9][0-9][0-9][0-9]\).[0-9][0-9].[0-9][0-9].*/\1/i'`"
			if [ "`echo "$SEASON" | grep "^[0-9]$"`" ]; then SEASON="S0$SEASON"; else SEASON="S$SEASON"; fi
			if [ "`echo "$SEASON" | grep -v "^S\([0-9]$\|[0-9][0-9]\|[0-9][0-9][0-9]\)$"`" ]; then SEASON=""; fi
			DSTSERIE="`echo $SRCSERIE | sed 's/\(\w\)_/\1\./g'`"
			CHKSERIE="`echo $DSTSERIE | sed 's/\([a-z]\|[A-Z]\)/[\L\1\U\1\]/g'`"
			DIRDATE="`$DATEBIN --date "01/01/1970 +$DIRDATE_SEC seconds" +"%Y-%m-%d %H:%M:%S"`"
			if [ "$SEASON" = "" ]; then
				if [ ! "`ls -1d $TVARCHIVE/$CHKSERIE 2>/dev/null`" ]; then
					if [ "`echo $1|grep -i "debug"`" ]; then
						echo "DEBUG: mkdir $TVARCHIVE/$DSTSERIE"
					else
						mkdir "$TVARCHIVE/$DSTSERIE"
					fi
				fi
				if [ "`ls -1d $TVARCHIVE/$CHKSERIE 2>/dev/null`" ]; then
					if [ "`echo $1|grep -i "debug"`" ]; then
						echo "DEBUG: mv $DIR $TVARCHIVE/$CHKSERIE/"
					else
						mv "$DIR" $TVARCHIVE/$CHKSERIE/
					fi
				fi
				if [ "`ls -1d $TVARCHIVE/$CHKSERIE/$BASEDIR 2>/dev/null`" ]; then
					if [ "`echo $1|grep -i "debug"`" ]; then
						echo "touch -d $DIRDATE $TVARCHIVE/$CHKSERIE/$BASEDIR"
					else
						touch -d "$DIRDATE" $TVARCHIVE/$CHKSERIE/$BASEDIR
					fi
				fi
			else
				if [ ! "`ls -1d $TVARCHIVE/$CHKSERIE 2>/dev/null`" ]; then
					if [ "`echo $1|grep -i "debug"`" ]; then
						echo "DEBUG: mkdir $TVARCHIVE/$DSTSERIE"
					else
						mkdir "$TVARCHIVE/$DSTSERIE"
					fi
				fi
				if [ ! "`ls -1d $TVARCHIVE/$CHKSERIE/$SEASON 2>/dev/null`" ]; then
					if [ "`echo $1|grep -i "debug"`" ]; then
						#echo "DEBUG: mkdir $TVARCHIVE/$DSTSERIE/$SEASON"
						echo "DEBUG: mkdir $( ls -1d $TVARCHIVE/$CHKSERIE )/$SEASON"
					else
						#mkdir "$TVARCHIVE/$DSTSERIE/$SEASON"
						mkdir "$( ls -1d $TVARCHIVE/$CHKSERIE )/$SEASON"
					fi
				fi
				if [ "`ls -1d $TVARCHIVE/$CHKSERIE/$SEASON 2>/dev/null`" ]; then
					if [ "`echo $1|grep -i "debug"`" ]; then
						echo "DEBUG: mv $DIR $TVARCHIVE/$CHKSERIE/$SEASON"
					else
						mv "$DIR" $TVARCHIVE/$CHKSERIE/$SEASON
					fi			
				fi
				if [ "`ls -1d $TVARCHIVE/$CHKSERIE/$SEASON/$BASEDIR 2>/dev/null`" ]; then
					if [ "`echo $1|grep -i "debug"`" ]; then
						echo "DEBUG: touch -d $DIRDATE $TVARCHIVE/$CHKSERIE/$SEASON/$BASEDIR"
					else
						touch -d "$DIRDATE" $TVARCHIVE/$CHKSERIE/$SEASON/$BASEDIR
					fi
				fi
			fi
		fi
	done
done
