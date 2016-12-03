#!/bin/sh

# Change some files if your glftpd install is not in the default location
# so compiling bins works and sets MAXDIRLOGSIZE a bit higher.

if [ "$( echo $PWD | grep -v bin/sources$ )" ]; then
  echo
  echo "ERROR: run \"$0\" in glftpd/bin/sources dir. exiting"
  echo
  exit 1
fi

#FILES="compile.sh glconf.h olddirclean2.c test.bla test2"
FILES="compile.sh glconf.h olddirclean2.c"
GLROOT="/jail/glftpd"
GLCONF="$GLROOT/glftpd.conf"
MAXDIRLOGSIZE=150000
DEBUG="FALSE"

RESET='\033[0m'
RED='\033[31m'
GREEN='\003[32m'
BLUE='\033[34m'
WHITEB='\033[97;1m'
WHITEBU='\033[97;1;4m'

NRFILES="$( echo $FILES | wc -w )"
COUNT=0
echo
for i in $FILES; do
  if [ -f $i ]; then
    if [ ! -f $i.bak ]; then
      printf "${WHITEBU}* changing \"$i\"...${RESET}\n"
      if [ "$DEBUG" = "TRUE" ]; then set -x; fi
      case "$i" in
        compile.sh)
            sed -i.bak -e "s@^\(glroot=\)\(/glftpd\)@#\\1\\2\\n\\1$GLROOT@" -e "s/^\(echo \"You did not edit the file first!\" && exit 1\)/#\\1/" $i; EXITCODE=$?
        ;;
        glconf.h)
            sed -i.bak "s@^\(#define GLCONF\\t\)\"\(/etc/glftpd.conf\)\"\(.*\)@// \\1\"\\2\"\\3\\n\\1\"$GLCONF\"\\3@" $i; EXITCODE=$?
        ;;
        olddirclean2.c)
            sed -i.bak "s@^\(#define MAXDIRLOGSIZE\) 10000@// \\1 10000\\n\\1 $MAXDIRLOGSIZE@" $i; EXITCODE=$?
        ;;
        *)
            { set +x; } 2>/dev/null
            echo "* ERROR: no changes defined for \"$i\"... skipping"
            echo
            continue
      esac
      { set +x; } 2>/dev/null
      if [ "$EXITCODE" != "0" ]; then
        echo "* ERROR: a problem occured while changing \"$i\". exit code: $EXITCODE"
      else
        COUNT="$( expr "$COUNT" \+ "1" )"
        echo "* changes were made successfully. showing diff:"
        diff -s -u0 $i.bak $i | sed 's/^-/\x1b[31m-/;s/^+/\x1b[32m+/;s/^@/\x1b[34m@/;s/$/\x1b[0m/'
      fi
    else
      echo "* ERROR: \"$i.bak\" already exists... skipping $i"
    fi
  else
    echo "* ERROR: \"$i\" doesn't exist... skipping"
  fi
  if [ "$COUNT" -eq "$NRFILES" ]; then
    printf "\n${WHITEB}* now run \"./compile.sh\" if you want to apply the changes${RESET}.\n"
  fi
  echo
done
