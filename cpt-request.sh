#!/bin/bash
##############################################################
## lelijk eendje // cpt-request v0.3.4-ng-compat                
##############################################################
## Description:
## Requestscript for glftpd+pzs-ng (r1450 and up). If you don't
## know what this is, you probably don't need it.
##
## Thanks:
##   - pzs-ng team for giving feedback on code
##   - testers. you know who you are :)
##
## Support is for wussies, but here we go anyway:
##
## REQDIR:
##   full path to the directory where you want the request directories
##   you need $GLROOTPATH/ in front to make it work from both
##   the ftp and irc
##
## GLLOG:
##   full path to glftpd.log. Used for logging requests and
##   announcing it on irc. If you don't want announces/logs, set
##   it to /dev/null or something
##   you need $GLROOTPATH/ in front to make it work from both
##   the ftp and irc.
##
## REQFILE:
##   File where we can put a little 'database' of requests.
##   create the file yourself and chmod 666 it, or things can
##   get messy.
##
## FILLEDFILE:
##   The 'database' file for all the filled requests. You also 
##   have to create this file yourself and chmod 666 it.
##
## Sitename:
##   Set this to some short version of your sitename. Used for
##   debug announces and the request list.
##
## ZSTFILE:
##   TODO: let the debug files use pzs-ng's zst for announce-
##   layout. [ not used currently ]
##
## REQDIRPREFIX:
##   The prefix for newly created requests. You need a prefix.
##
## FILLEDDIRPREFIX:
##   The prefix for filled requests. You need a prefix.
##
## MAXNUMBEROFREQS:
##   The maximum number of requests your site can have. Don't
##   set this too high, it will make your site look like crap. :-)
##
## SEPERATOR:
##   A seperator for the reqfile (on popular request). This character
##   will seperate the different entries in the req/filled-file.
##   Don't change this unless you know what you're doing BLAH BLAH.
##
## DEBUG:
##   Enable debug information. Nothing fancy, best to disable it.
##############################################################

## DO NOT TOUCH THIS
if [ -r /bin/glstrings.bin ]; then
    TODO=$1
    WHAT=$2
    REQUSER=$USER
    SITEREQ="TRUE" # request is being made from glftpd
    GLROOTPATH=""
else
    REQUSER=$1
    TODO=$2
    WHAT=$3
    GLROOTPATH="/glftpd" # request is being made from irc (or something)
    GROUP=`grep "^GROUP " $GLROOTPATH/ftp-data/users/$REQUSER | head -n 1 | cut -d ' ' -f2`
    TAGLINE=`grep "^TAGLINE " $GLROOTPATH/ftp-data/users/$REQUSER | sed 's/^TAGLINE //'` 
    SITEREQ="FALSE"
fi

## You can start configging below

REQDIR="$GLROOTPATH/site/requests/"
GLLOG="$GLROOTPATH/ftp-data/logs/glftpd.log"
REQFILE="$GLROOTPATH/ftp-data/logs/reqfile"
FILLEDFILE="$GLROOTPATH/ftp-data/logs/filledfile"
SITENAME=""
#ZSTFILE="/glftpd/sitebot/pzs-ng/themes/default.zst"
REQDIRPREFIX="REQ-"
FILLEDDIRPREFIX="FILLED-"
MAXNUMBEROFREQS=20
SEPERATOR=':'

DEBUG="FALSE"

## CONFIG STOPS HERE. edit below and seal your fate.

NUMBEROFREQUESTS=`cat $REQFILE | wc -l | sed 's/ //g'`

case "$TODO" in
    add)
    
    if [ "$WHAT" = "" ]; then
	echo "Usage: !!request <release>"
        exit 0
    else
        if [ $MAXNUMBEROFREQS -le $NUMBEROFREQUESTS ]; then
	    echo "There are too many requests. Fill/del/wipe some :)."
	    exit 0
	fi
	#we don't want spaces in files. that's ugly. if you disagree, you can suck my hairy bawls.
	WHAT=`echo $WHAT | tr ' ' '.'` 
	ALREADYTHERE="$( ls $REQDIR | grep $WHAT )"
	if [ -z "$ALREADYTHERE" ]; then
    	    mkdir -m777 "$REQDIR/$REQDIRPREFIX$WHAT"
	    echo "`date +%d%m`$SEPERATOR$REQUSER$SEPERATOR$GROUP$SEPERATOR$WHAT" >> $REQFILE
	    echo `date "+%a %b %e %T %Y"` REQUEST: \"$WHAT\" \"$REQUSER\" \"$GROUP\" \"$TAGLINE\" >> $GLLOG
    	else
    	    echo "Already a request named like that, try to rephrase"
    	    exit 0
	fi
    fi
    ;;

    del)
    
    if [ "$WHAT" = "" ]; then
	echo "Specify a request to delete... Usage: !!delreq <releasename> or !!delreq #<number>"
	exit 0
    else
	if [ `echo "$WHAT" | grep "#"` ]; then
	    whatisnumber="TRUE"
	    reqnumber=`echo $WHAT | tr -cd '0-9'`
	    if [ $reqnumber -gt `cat $REQFILE | wc -l | tr -s ' '` ];then
		echo "That number isn't correct. You can count, right?"
		exit 0
	    else
		WHAT=`head -n $reqnumber $REQFILE | tail -n 1 | cut -d $SEPERATOR -f4`
	    fi
	else
	    whatisnumber="FALSE"
	fi
	

	REQUEST=`grep "$WHAT" $REQFILE | head -n1 | cut -d $SEPERATOR -f4`
	if [ "$REQUEST" = $WHAT ]; then
    	    ACTUALLYTHERE="$( ls $REQDIR | grep $WHAT )"
	    
	    if [ "$ACTUALLYTHERE" != "" ]; then
		# do not delete requestdirs that have files in them. we might not be able to remove the dir
		# (different ownership on the files in the dir)
		if [ ! -z `ls -1 $REQDIR/$REQDIRPREFIX$WHAT 2>/dev/null` ]; then
		    echo "You can't delete that. The directory is not empty"
		    exit 0
		fi
		if [ "$DEBUG" = "ON" ]; then
    		    echo "DEBUG: Dirname has been entered correctly and is in the reqfile"
		fi
		
		REQUESTDATE=`grep "$WHAT" $REQFILE | head -n1 | cut -d $SEPERATOR -f1`
		REQUESTEDBY=`grep "$WHAT" $REQFILE | head -n1 | cut -d $SEPERATOR -f2`
		REQUESTEDBYGROUP=`grep "$WHAT" $REQFILE | head -n1 | cut -d $SEPERATOR -f3`
		
		if [ "$REQUESTEDBY" = "$REQUSER" ]; then
    		    rm -rf $REQDIR/$REQDIRPREFIX$REQUEST
    		    grep -v "$REQUEST" "$REQFILE" > $GLROOTPATH/tmp/.reqfile.tmp
		    cp -f "$GLROOTPATH/tmp/.reqfile.tmp" "$REQFILE"
		    rm -f "$GLROOTPATH/tmp/.reqfile.tmp"
		    echo `date "+%a %b %e %T %Y"` REQDEL: \"$REQUEST\" \"$REQUSER\" \"$GROUP\" \"$TAGLINE\" >> $GLLOG
		    if [ "$DEBUG" = "ON" ]; then
    			echo "DEBUG: Request has been deleted"
		    fi
		else
    		    echo "You're not the one who has requested this release."
		fi		    
    	    else
    		echo "Dir wasn't found. Removing it from the reqlog. Please reqwipe/reqdel through this script next time."
    		grep -v "$REQUEST" "$REQFILE" > $GLROOTPATH/tmp/.reqfile.tmp
		cp -f "$GLROOTPATH/tmp/.reqfile.tmp" "$REQFILE"
		rm -f "$GLROOTPATH/tmp/.reqfile.tmp"
    		exit 0
	    fi
	else
	    echo "Please enter the *EXACT* dirname. Thank you :)"
	fi
    fi
    ;;

    wipe)

    if [ "$WHAT" = "" ]; then
	echo "Specify a request to wipe... Usage: !!reqwipe <releasename> or !!reqwipe #<number>"
	exit 0
    else
	if [ `echo "$WHAT" | grep "#"` ]; then
	    whatisnumber="TRUE"
	    reqnumber=`echo $WHAT | tr -cd '0-9'`
	    if [ $reqnumber -gt `cat $REQFILE | wc -l | tr -s ' '` ];then
		echo "That number isn't correct."
		exit 0
	    else
		WHAT=`head -n $reqnumber $REQFILE | tail -n 1 | cut -d $SEPERATOR -f4`
	    fi
	else
	    whatisnumber="FALSE"
	fi


	REQUEST=`grep "$WHAT" $REQFILE | head -n 1 | cut -d $SEPERATOR -f4`
	if [ "$REQUEST" = $WHAT ]; then
    	    ACTUALLYTHERE="$( ls $REQDIR | grep $WHAT )"
	    if [ "$ACTUALLYTHERE" != "" ]; then
		if [ ! -z `ls -1 $REQDIR/$REQDIRPREFIX$WHAT 2>/dev/null` ]; then
		    echo "You can't delete that. The directory is not empty."
		    exit 0
		fi
		REQUESTDATE=`grep "$WHAT" $REQFILE | head -n1 | cut -d $SEPERATOR -f1`
		REQUESTEDBY=`grep "$WHAT" $REQFILE | head -n1 | cut -d $SEPERATOR -f2`
		REQUESTEDBYGROUP=`grep "$WHAT" $REQFILE | head -n1 | cut -d $SEPERATOR -f3`

		if [ "$DEBUG" = "ON" ]; then
    		    echo "DEBUG: Dirname has been entered correctly and is in the reqfile"
		fi
    		rm -rf $REQDIR/$REQDIRPREFIX$REQUEST
		echo `date "+%a %b %e %T %Y"` REQWIPE: \"$REQUEST\" \"$REQUSER\" \"$GROUP\" \"$TAGLINE\" \"$REQUESTEDBY\" \"$REQUESTEDBYGROUP\" >> $GLLOG
    		grep -v "$REQUEST" "$REQFILE" > $GLROOTPATH/tmp/.reqfile.tmp
		cp -f "$GLROOTPATH/tmp/.reqfile.tmp" "$REQFILE"
		rm -f "$GLROOTPATH/tmp/.reqfile.tmp"   
#		echo "Wiped Request: $REQUEST"
    	    else
    		echo "Dir wasn't found. Removing it from the reqlog. Please reqwipe/reqdel through this script next time."
		if [ "$DEBUG" = "ON" ]; then
    		    echo "DEBUG: Going to grep -v "$REQUEST" from "$REQFILE" to "$GLROOTPATH/tmp/.reqfile.tmp""
		fi
		grep -v "$REQUEST" "$REQFILE" > "$GLROOTPATH/tmp/.reqfile.tmp"
		cp -f "$GLROOTPATH/tmp/.reqfile.tmp" "$REQFILE"
		rm -f "$GLROOTPATH/tmp/.reqfile.tmp"
#		grep -v $RELEASE $REQFILE > $REQFILE
    		exit 0
	    fi
	else
	    echo "Please enter the *EXACT* dirname. Thank you :)"
	fi
    fi
    ;;

    fill)
    if [ "$WHAT" = "" ]; then
	echo "Specify a request to fill... Usage: !!reqfill <releasename> or !!reqfill #<number>"
	exit 0
    else
	if [ `echo "$WHAT" | grep "#"` ]; then
	    whatisnumber="TRUE"
	    reqnumber=`echo $WHAT | tr -cd '0-9'`
	    if [ $reqnumber -gt `cat $REQFILE | wc -l | tr -s ' '` ] || [ $reqnumber = 0 ];then
		echo "That number isn't correct."
		exit 0
	    else
		WHAT=`head -n $reqnumber $REQFILE | tail -n 1 | cut -d $SEPERATOR -f4`
	    fi
	else
	    whatisnumber="FALSE"
	fi
	
	REQUEST=`grep "$WHAT" $REQFILE | head -n1 | cut -d $SEPERATOR -f4`
	if [ "$REQUEST" = $WHAT ]; then
    	    ACTUALLYTHERE="$( ls $REQDIR | grep $WHAT )"
	    if [ "$ACTUALLYTHERE" != "" ]; then
		if [ -z "`ls -1 $REQDIR/$REQDIRPREFIX$WHAT 2> /dev/null`" ]; then
		    echo "You can't fill that. $WHAT is still empty."
		    exit 0
		fi
		REQUESTDATE=`grep "$WHAT" $REQFILE | head -n1 | cut -d $SEPERATOR -f1`
		REQUESTEDBY=`grep "$WHAT" $REQFILE | head -n1 | cut -d $SEPERATOR -f2`
		REQUESTEDBYGROUP=`grep "$WHAT" $REQFILE | head -n1 | cut -d $SEPERATOR -f3`

		if [ "$DEBUG" = "ON" ]; then
    		    echo "DEBUG: Dirname has been entered correctly and is in the reqfile"
		fi
#		ACTUALLYFILLED="$( ls $REQDIR/$REQDIRPREFIX$REQUEST | 
#		if 
		MSGED="0"
		echo "`date +%d%m`$SEPERATOR$REQUESTEDBY$SEPERATOR$REQUESTEDBYGROUP$SEPERATOR$REQUSER$SEPERATOR$GROUP$SEPERATOR$REQUEST$SEPERATOR$MSGED" >> $FILLEDFILE

		mv -f "$REQDIR/$REQDIRPREFIX$REQUEST" "$REQDIR/$FILLEDDIRPREFIX$REQUEST"
		echo `date "+%a %b %e %T %Y"` REQFILL: \"$REQUEST\" \"$REQUSER\" \"$GROUP\" \"$TAGLINE\" \"$REQUESTEDBY\" \"$REQUESTEDBYGROUP\" >> $GLLOG
    		grep -v "$REQUEST" "$REQFILE" > $GLROOTPATH/tmp/.reqfile.tmp
		cp -f "$GLROOTPATH/tmp/.reqfile.tmp" "$REQFILE"
		rm -f "$GLROOTPATH/tmp/.reqfile.tmp"
    	    else
    		echo "Dir wasn't found. Removing it from the reqlog. Please reqwipe/reqdel through this script next time. And don't try to reqfill something that isn't there, bastard ;-)"
		if [ "$DEBUG" = "ON" ]; then
    		    echo "DEBUG: Going to grep -v "$REQUEST" from "$REQFILE" to "$GLROOTPATH/tmp/.reqfile.tmp""
		fi
		grep -v "$REQUEST" "$REQFILE" > "$GLROOTPATH/tmp/.reqfile.tmp"
		cp -f "$GLROOTPATH/tmp/.reqfile.tmp" "$REQFILE"
		rm -f "$GLROOTPATH/tmp/.reqfile.tmp"
#		grep -v $RELEASE $REQFILE > $REQFILE
    		exit 0
	    fi
	else
	    echo "Please enter the *EXACT* dirname. Thank you :)"
	fi
    fi
    ;;

    list)
    REQNUM=0
    for LINE in `cat $REQFILE` ; do
        let REQNUM=$REQNUM+1
        DATE=`echo $LINE | cut -d $SEPERATOR -f1`
        REQUESTEDBY=`echo $LINE | cut -d $SEPERATOR -f2`
        REQUESTEDBYGROUP=`echo $LINE | cut -d $SEPERATOR -f3`
        REQUEST=`echo $LINE | cut -d $SEPERATOR -f4`
        echo "($REQNUM) $REQUEST on $DATE by $REQUESTEDBY of group $REQUESTEDBYGROUP"
    done
    if [ `cat $REQFILE | wc -l` = 0 ]; then
	echo "There are no requests at the moment, try again later ;)"
	exit 0
    fi
    ;;
    joincheck)
    for LINE in `cat $FILLEDFILE`; do
        DATE=`echo $LINE | cut -d $SEPERATOR -f1`
        REQUESTEDBY=`echo $LINE | cut -d $SEPERATOR -f2`
        REQUESTEDBYGROUP=`echo $LINE | cut -d $SEPERATOR -f3`
        FILLEDBY=`echo $LINE | cut -d $SEPERATOR -f4`
        FILLEDBYGROUP=`echo $LINE | cut -d $SEPERATOR -f5`
        REQUEST=`echo $LINE | cut -d $SEPERATOR -f6`
        MSGED=`echo $LINE | cut -d $SEPERATOR -f7`
	if [[ "$REQUESTEDBY" = "$REQUSER" && $MSGED -eq 0 ]]; then
	    echo "`date +%d%m` $REQUESTEDBY $REQUESTEDBYGROUP $FILLEDBY $FILLEDBYGROUP $REQUEST"
    	    grep -v "$REQUEST" "$FILLEDFILE" > "$GLROOTPATH/tmp/.reqfile.tmp"
	    cp -f "$GLROOTPATH/tmp/.reqfile.tmp" "$FILLEDFILE"
	    rm -f "$GLROOTPATH/tmp/.reqfile.tmp"
	    MSGED=1
	    echo "`date +%d%m`$SEPERATOR$REQUESTEDBY$SEPERATOR$REQUESTEDBYGROUP$SEPERATOR$FILLEDBY$SEPERATOR$FILLEDBYGROUP$SEPERATOR$REQUEST$SEPERATOR$MSGED" >> $FILLEDFILE
	fi
    done
    ;;
    *)
	echo "Use this script correctly"
	exit 0
    ;;
esac
