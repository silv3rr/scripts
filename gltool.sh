#!/bin/bash

set -eo pipefail

# ------------------------------------------------------------------------------
SCRIPTNAME="gltool: glftpd user mgmt tool"
DESCRIPTION="directly manage users and groups, outside of glftpd"
REQUIREMENTS=" awk, cut, grep, sed, hashgen(slv), passchk(pzs-ng)"
# -------------------------------------------------------------------slv.2o24---

GLDIR="/glftpd"
AUTH=0
CHECK_SYS_BINS=0
CHECK_MASK=1
ALLOW_IPV6=1
ALLOW_IPMASK=1
ALLOW_CIDR=1
ALLOW_NUM_RANGE=1
ALLOW_HOSTMASK=1
ALLOW_NO_IDENT=1
ALLOW_ALL_IP=1
MIN_IP_OCT="0"
MAX_IP="99"

SCRIPTDIR="$(dirname "$(readlink -f -- "$0")")"
SCRIPT="$(basename "$0")"

# shellcheck disable=SC2016
COMMANDS="$(
  sed -n '/^case \$COMMAND in/,/^esac/{//d;p;}' "${SCRIPTDIR}/${SCRIPT}" | \
  sed -n 's/ *\([A-Z]\+\)).*/\1/p' | \
  sed -z 's/\n/ /g; s/.$//' | \
  sed 's/\(\([^ ]* \)\{7\}\)/\1\n  /g'
)"

# shellcheck disable=SC2016
OPTIONS="$(
  sed -n '/^ *case \$opt in/,/^ *\*) exit 1 && exit 0 ;;/{//d;p;}' "${SCRIPTDIR}/${SCRIPT}" | \
  sed -n 's/ *\([0-9a-z]\)) \(.*\)=.*#\(.*\)$/  -\1 \2\t\3/p'
)"

HELP="
$SCRIPTNAME
-----------------------------

$DESCRIPTION

USAGE:
  ./$SCRIPT -c <COMMAND> [options]

COMMANDS:

  $COMMANDS

OPTIONS:

$OPTIONS

REQUIRES: $REQUIREMENTS
"


################################################
# GET OPTIONS
################################################

OPTIND=1
while getopts ha:c:d:f:g:i:k:l:u:p:r:s:t:z: opt; do
  case $opt in
    a) GADMIN=$OPTARG ;;                      # (ADDUSERGROUP|USERGADMIN)
    c) COMMAND=$OPTARG ;;
    d) GROUPDESC=$OPTARG ;;                   # (ADDGROUP)
    f) FLAGS=$OPTARG ;;                       # (CHFLAG)
    g) GROUP=$OPTARG ;;                       # (ADDGROUP|DELGROUP|CHGRP)
    h) echo "$HELP" && exit 0 ;;
    i) MASK=$OPTARG ;;                        # (ADDIP|DELIP)
    k) CREDITS=$OPTARG ;;                     # (CHCREDITS)
    l) LOGINS=$OPTARG ;;                      # (CHLOGINS)
    u) USERNAME=$OPTARG ;;                    # (ADDUSER|DELUSER|AUTH|*IP|*USERGROUP|CH*)
    p) PASSWORD=$OPTARG ;;                    # (ADDUSER|CHPASS|AUTH)
    r) RATIO=$OPTARG ;;                       # (CHRATIO)
    s) PGROUP=$OPTARG ;;                      # (ADDPGROUP|DELPGROUP)
    t) TAGLINE=$OPTARG ;;                     # (CHTAG)
    z) ADMIN=$OPTARG ;;
    *) exit 1 ;;
  esac
done
shift "$((OPTIND-1))"

if [ -n "$*" ]; then
 echo "ERROR: invalid option \"$*\""
 exit 1
fi

if [ "$(readlink /proc/$$/exe 2>&1)" = "/bin/busybox" ]; then
  echo "ERROR: busybox detected"
  exit 1
fi

# support grep without -P option
GREP_PERL=1
if [ "${CHECK_SYS_BINS:-0}" -eq 1 ]; then
  for i in grep sed cut; do
    command -v $i >/dev/null 2>&1 || { echo "ERROR: missing $i"; exit 1; }
  done
  grep -P >/dev/null 2>&1 || GREP_PERL=0
fi

if [ -z "$COMMAND" ]; then
  echo "ERROR: missing option, try '-h'"
  exit 1
fi

if [ -z "$GLDIR" ] || [ ! -d "$GLDIR" ]; then
  GLDIR="/glftpd"
fi

# glftpd env
if [ -n "$USER" ] && [ -n "$FLAGS" ] && [ -n "$TAGLINE" ] && [ -n "$RATIO" ]; then
  USERNAME="$USER"
fi

USERFILE="$GLDIR/ftp-data/users/$USERNAME"
LOGFILE="$GLDIR/ftp-data/logs/gltool.log"
ID="$(id -un)"
SITEOP="${ADMIN:-"$ID"}"

if [ -n "$USER" ] && [ -n "$FLAGS" ] && [ -n  "$GROUP" ]; then
  SITEOP="$USER"
fi

func_check_ip() {
  grep IP "$USERFILE" | grep -F -w -m 1 "$MASK" | cut -d ' ' -f2 
}

func_check_user() {
  USERNAME="$1"
  if [ -z "$USERNAME" ]; then
    echo "ERROR: missing username"
    exit 1
  fi
  if [ -d "$GLDIR/ftp-data/users/$USERNAME" ]; then
    echo "ERROR: userfile"
    exit 1
  fi
  if [ ! -s "$USERFILE" ]; then
    echo "ERROR: userfile does not exist"
    exit 1
  fi
}

func_update_userfile() {
  if [ -s "$USERFILE.tmp" ]; then
    mv "${USERFILE}.tmp" "$USERFILE" || { echo "ERROR: updating userfile"; exit 1; }
  else
    echo "ERROR: userfile"
    exit 1
  fi
  if [ -s "$USERFILE.tmp" ]; then
    echo "ERROR: userfile"
    exit 1
  fi
}

func_clean_tmp() {
  if [ -e "$USERFILE.tmp" ]; then
    rm "$USERFILE.tmp" || { echo "ERROR: userfile"; exit 1; }
  fi
  if [ -e "$GLDIR/etc/passwd.tmp"  ]; then
    rm "$GLDIR/etc/passwd.tmp"  || { echo "ERROR: passwd file"; exit 1; }
  fi
  if [ -e "$GLDIR/etc/group.tmp"  ]; then
    rm "$GLDIR/etc/group.tmp"  || { echo "ERROR: group file"; exit 1; }
  fi
}

func_get_glconf() {
  for i in "$GLDIR/../glftpd.conf" "$GLDIR/glftpd.conf" "/etc/glftpd/glftpd.conf"; do
    if [ -s "$i" ]; then
      GLCONF="$i"
      break
    fi
  done
}

func_get_bin() {
  for i in "$GLDIR/bin/$1" "/usr/local/bin/$1"; do
    if [ -s "$i" ] && [ "$(./"$i" >/dev/null 2>&1)" ]; then
      echo "$i"
      break
    fi
  done
}

# ----------------------------------------------
# LISTIP
# ----------------------------------------------
func_listip() {
  if [ -n "$USERNAME" ]; then
    masks="$(grep IP "$USERFILE" | sed 's/IP //g' | sed ':a;N;$!ba;s/\n/ /g')"
    echo "User \"$USERNAME\" has these masks added: $masks"
  fi
}

# ----------------------------------------------
# LOG
# ----------------------------------------------
func_logmsg() {
  echo "$COMMAND: $( date '+%a %b %d %T %Y' ) \"$SITEOP\" $1" >> "$LOGFILE"
  echo "DONE: \"$SITEOP\" $1"
}

func_logtail() {
  if [ -e "$LOGFILE" ]; then
    tail -n 10 "$LOGFILE"
    exit 0
  else
    echo "INFO: log file not found"
    exit 1
  fi
}

func_logshow() {
  if [ -e "$LOGFILE" ]; then
    cat "$LOGFILE"
    exit 0
  else
    echo "INFO: log file not found"
    exit 1
  fi
}

# ----------------------------------------------
# LISTUSERS
# ----------------------------------------------
func_listusers() {
  ln="0"
  while IFS= read -r i; do
    group=""
    notes=""
    if [ -z "$i" ]; then
      echo "[error] passwd line $ln"
    elif [ ! -s "$GLDIR/ftp-data/users/$i" ]; then
      echo "[error] missing userfile $i"
    else
      if [ "${GREP_PERL:-1}" -eq 0 ]; then
        group="$(grep -m1 -ow "^GROUP [^ ]*" "$GLDIR/ftp-data/users/$i" | cut -d" " -f2-)"
        flags="$(grep -m1 -ow "^FLAGS .*" "$GLDIR/ftp-data/users/$i" | cut -d" " -f2-)"
      else
        group="$(grep -m1 -Pow "^GROUP \K[^ ]*" "$GLDIR/ftp-data/users/$i" || true | cut -d" " -f2)"
        flags="$(grep -m1 -Pow "^FLAGS \K.*" "$GLDIR/ftp-data/users/$i" || true | cut -d" " -f2)"
      fi
      if [ -n "$flags" ] && echo "$flags" | grep -q 1; then
        notes+=" (siteop)"
      fi
      echo "$i${group:+/${group}}$notes"
    fi
    ln=$((ln+1))
  done < <( cut -d: -f1 < "$GLDIR/etc/passwd" )
  echo "$ln users"
}

# ----------------------------------------------
# LISTGROUPS
# ----------------------------------------------
func_listgroups() {
  ln="0"
  while read -r i; do
    IFS=":" read -r group description gid unused <<<"$i"
    if [ -z "$i" ]; then
      echo "[error] group line $ln"
    elif [ "$group" != "NoGroup" ] && [ ! -s "$GLDIR/ftp-data/groups/$group" ]; then
      echo "[error] missing groupfile $i"
    else
      echo "$group ($description)"
    fi
    ln=$((ln+1))
  done < "$GLDIR/etc/group"
  echo "$ln groups"
}

# ----------------------------------------------
# RAW COMMANDS
# ----------------------------------------------

func_rawuserfile() {
  if [ -n "$USERNAME" ] && [ ! -d "$USERFILE" ] && [ -s "$USERFILE" ]; then
    cat "$USERFILE"
  fi
}

func_rawuserfilefield() {
  if [ -n "$USERNAME" ] && [ ! -d "$USERFILE" ] && [ -s "$USERFILE" ] && [ -n "$1" ]; then
    if [ "${GREP_PERL:-1}" -eq 0 ]; then
      grep -Pow "^$1 \K[^ ]*" "$USERFILE"
    else
      grep -ow "^$1 [^ ]*" "$USERFILE" | cut -d" " -f2-
    fi
  fi
}

func_rawusers() {
  cut -d: -f1 < "$GLDIR/etc/passwd" | while IFS= read -r i; do
    if [ -s "$GLDIR/ftp-data/users/$i" ]; then
      echo "$i"
    fi
  done
}

func_rawgroups() {
  while IFS= read -r i; do
    IFS=":" read -r groupname description gid unused <<<"$i"
    if [ "$groupname" != "NoGroup" ] && [ -s "$GLDIR/ftp-data/groups/$groupname" ]; then
      echo "$groupname $description"
    fi
  done < "$GLDIR/etc/group"
}

func_rawpgroups() {
  func_get_glconf
  if [ "${GREP_PERL:-1}" -eq 0 ]; then
    grep -ow "^\s*privgroup .*" "$GLCONF" | cut -d" " -f2- | while IFS= read -r i; do
      i=$(echo "$i"|sed -e 's/\s\s*/ /g' -e 's|\[:space:\]| |g')
      read -r groupname description <<<"$i"
      echo "$groupname $description"
    done
  else
    grep -Pow "^\s*privgroup \K.*" "$GLCONF" | while IFS= read -r i; do
      i=$(echo "$i"|sed -e 's/\s\s*/ /g' -e 's|\[:space:\]| |g')
      read -r groupname description <<<"$i"
      echo "$groupname $description"
    done
  fi
}

func_rawusergroup() {
  if [ -n "$USERNAME" ] && [ ! -d "$USERFILE" ] && [ -s "$USERFILE" ]; then
    if [ "${GREP_PERL:-1}" -eq 0 ]; then
      grep -ow "^GROUP \K[^ ]*" "$USERFILE" | cut -d" " -f2- | grep -v "^NoGroup$'"
    else
      grep -Pow "^GROUP \K[^ ]*" "$USERFILE" | grep -v "^NoGroup$'"
    fi
  fi
}

func_rawusersgroups() {
  cut -d: -f1 < "$GLDIR/etc/passwd" | while IFS= read -r i; do
    if [ -s "$GLDIR/ftp-data/users/$i" ]; then
      if [ "${GREP_PERL:-1}" -eq 0 ]; then
        group="$(grep -m1  -ow "^GROUP [^ ]*" "$GLDIR/ftp-data/users/$i" | cut -d" " -f2-)"
      else
        group="$(grep -m1 -Pow "^GROUP \K[^ ]*" "$GLDIR/ftp-data/users/$i" || true | cut -d" " -f2)"
      fi
      if [ "$group" == "NoGroup" ]; then
        group=""
      fi
      echo "$i $group"
    fi
  done
}

func_rawuserspgroups() {
  cut -d: -f1 < "$GLDIR/etc/passwd" | while IFS= read -r i; do
    if [ -s "$GLDIR/ftp-data/users/$i" ]; then
      if [ "${GREP_PERL:-1}" -eq 0 ]; then
        pgroup="$(grep -m1 -ow "^PRIVATE [^ ]*" "$GLDIR/ftp-data/users/$i" | cut -d" " -f2-)"
      else
        pgroup="$(grep -m1 -Pow "^PRIVATE \K[^ ]*" "$GLDIR/ftp-data/users/$i" || true | cut -d" " -f2)"
      fi
      echo "$i $pgroup"
    fi
  done
}

func_rawip() {
  if [ -n "$USERNAME" ] && [ ! -d "$USERFILE" ] && [ -s "$USERFILE" ]; then
    if [ "${GREP_PERL:-1}" -eq 0 ]; then
      grep -ow "^IP .*" "$USERFILE" | cut -d" " -f2-
    else
      grep -Pow "^IP \K.*" "$USERFILE"
    fi
  fi
}

# ----------------------------------------------
# IPMASK CHECKS
# ----------------------------------------------
func_mask_tests() {
  is_hostmask="$(echo "$MASK" | grep -Eq "^.*@[0-9a-zA-Z\.\*\-]+$" && echo 1 || echo 0)"
  has_octet="$(echo "$MASK" | grep -Eq "^.*@.*\.[0-9\*]$" && echo 1 || echo 0)"
  if ! echo "$MASK" | grep -q "@"; then
    echo "ERROR: mask \"$MASK\" is invalid";
    exit 1
  fi
  if [ "${ALLOW_ALL_IP:-0}" = 0 ] && echo "$MASK" | grep -Eq '^\*@\*'; then
    echo "ERROR: mask 'all' not allowed"
    exit 1
  fi
  if [ "${ALLOW_NO_IDENT:-0}" = 0 ] && echo "$MASK" | grep -Eq '^\*@'; then
    echo "ERROR: ident is required"
    exit 1
  fi
  if [ "${ALLOW_IPMASK:-1}" = 0 ] && [ "${is_ipmask:-0}" -eq 1 ]; then
    echo "ERROR: ipmasks are not allowed"
    exit 1
  fi
  if [ "${ALLOW_HOSTMASK:-0}" = 0 ] && [ ! "${has_octet:-0}" ] && [ "${is_hostmask:-0}" -eq 1 ]; then
    echo "ERROR: hostmasks are not allowed"
    exit 1
  fi
  if [ "${ALLOW_NUM_RANGE:-1}" = 0 ] && echo "$MASK" | grep -Eq "[\]\[\]?"; then
    echo "ERROR: number ranges are not allowed"
    exit 1
  fi
  if [ "${ALLOW_CIDR:-1}" = 0 ] && echo "$MASK" | grep -Eq "/"; then
    echo "ERROR: cidr not allowed"
    exit 1
  fi
  if [ "${ALLOW_IPV6:-0}" = 0 ] && echo "$MASK" | grep -Eq ":"; then
    echo "ERROR: ipv6 not allowed"
    exit 1
  fi
}

# ----------------------------------------------
# AUTH
# ----------------------------------------------
if [ "${AUTH:-0}" -eq 1 ]; then
  PASSCHK_BIN="$(func_get_bin passchk)"
  if [ -n "$PASSCHK_BIN" ] && [ -x "$PASSCHK_BIN" ]; then
    echo "ERROR: missing passchk"
    exit 1
  fi
  if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
    echo "ERROR: missing username/password"
    exit 1
  fi
  check_pass="$( "$PASSCHK_BIN" "$USERNAME" "$PASSWORD" "$GLDIR/etc/passwd" )"
  if echo "$check_pass" | grep -Eq '^(MATCH|NOMATCH)$'; then
    if [ "$check_pass" = "NOMATCH" ]; then
      echo "ERROR: incorrect password for user $USERNAME"
      exit 1
    fi
  else
    echo "ERROR: could not verify password"
    exit 1
  fi
fi

# ----------------------------------------------
# ADDIP
# ----------------------------------------------
func_addip() {
  func_check_user "$USERNAME"
  func_clean_tmp
  if [ -z "$MASK" ]; then
    echo "ERROR: missing mask"
    exit 1
  fi
  if [ "$(func_check_ip)" = "$MASK" ]; then
     #echo "INFO: \"$MASK\" is already added to \"$USERNAME\""
     exit 0
  fi
  ip_count="$(grep -cE "^IP" "$USERFILE" || true)"
  is_ipmask="$(echo "$MASK" | grep -Eq "^.*@[0-9\.\*]+$" && echo 1 || echo 0)"
  if [ "${ip_count:-0}" -ge "${MAX_IP:-10}" ]; then
    echo "ERROR: maximum ip's $MAX_IP reached"
    exit 1
  fi
  if [ "${CHECK_MASK:-1}" -eq 1 ]; then
    func_mask_tests
  fi
  oct=0
  set -f
  for i in $( echo "$MASK" | sed -e 's/.*@//' -e 's|\.| |g'); do
    if echo "$i" | grep -Eq '^[0-9]+$'; then
      oct=$((oct+1))
    fi
  done
  set +f
  if [ "${ALLOW_IPMASK:-1}" = 1 ] && [ "${is_ipmask:-0}" -eq 1 ]; then
    if [ "${oct:-0}" -lt "${MIN_IP_OCT:-0}" ]; then
      echo "ERROR: need at least $MIN_IP_OCT octet(s) of ip, but got $oct"
      exit
    fi
  fi
  { cat "$USERFILE"; echo "IP $MASK" >> "$USERFILE.tmp"; } >> "$USERFILE.tmp" || \
    { echo "ERROR: adding mask"; exit 1; }
  func_update_userfile
  func_logmsg "added \"$MASK\" to \"$USERNAME\""
}

# ----------------------------------------------
# DELIP
# ----------------------------------------------
func_delip() {
  func_check_user "$USERNAME"
  func_clean_tmp
  if [ -z "$MASK" ]; then
    echo "ERROR: missing mask"
    exit 1
  fi
  if [ -z "$(func_check_ip)" ]; then
    echo "ERROR: can't delete \"$MASK\" from user \"$USERNAME\", mask does not exist"
    exit
  fi
  cp "$USERFILE" "$USERFILE.tmp" || { echo "ERROR: updating userfile"; exit 1; }
  grep -F -v "IP $MASK" "$USERFILE" > "$USERFILE.tmp" || { echo "ERROR: deleting mask"; exit 1; }
  func_update_userfile
  func_logmsg "deleted \"$MASK\" from user \"$USERNAME\""
}

# ----------------------------------------------
# CHPASS
# ----------------------------------------------
func_chpass() {
  func_check_user "$USERNAME"
  func_clean_tmp
  PASSCHK_BIN="$(func_get_bin passchk)"
  HASHGEN_BIN="$(func_get_bin hashgen)"
  if [ -z "$PASSWORD" ]; then
    echo "ERROR: missing new password"
    exit 1
  fi
  if [ -n "$PASSCHK_BIN" ] && [ -x "$PASSCHK_BIN" ]; then
    check_pass="$( "$PASSCHK_BIN" "$USERNAME" "$PASSWORD" "$GLDIR/etc/passwd" )"
    if echo "$check_pass" | grep -Eq '^(MATCH|NOMATCH)$'; then
      if [ "$check_pass" = "MATCH" ]; then
        echo "ERROR: new password same as current"
        exit 1
      fi
    fi
  fi
  if [ -n "$HASHGEN_BIN" ] && [ ! -x "$HASHGEN_BIN" ]; then
    echo "ERROR: missing hashgen"
    exit 1
  fi
  if ! grep -Eq "^${USERNAME}:" "$GLDIR/etc/passwd"; then
    echo "ERROR: user not found in /etc/passwd"
    exit 1
  fi
  HASH="$($HASHGEN_BIN "$USERNAME" "$PASSWORD" | cut -d: -f2)"
  if ! echo "$HASH" | grep -Eq '^\$[0-9a-f]{8}\$[0-9a-f]{40}$'; then
    echo "ERROR: generating hash"
    exit 1
  fi
  sed -Ei "s|^$USERNAME:[^:]+:(.*)$|$USERNAME:$MASK:$HASH:\1|" "$GLDIR/etc/passwd" >> "$GLDIR/etc/passwd.tmp" || { echo "ERROR: changing /etc/passwd"; exit 1; }
  if [ -s "$GLDIR/etc/passwd.tmp" ]; then
    mv "$GLDIR/etc/passwd.tmp" "$GLDIR/etc/passwd" || { echo "ERROR: updating passwd file"; exit 1; }
  fi
  func_logmsg "changed password for \"$USERNAME\""
}

# ----------------------------------------------
# CHANGEGROUP
# ----------------------------------------------
func_chgrp() {
  func_check_user "$USERNAME"
  func_clean_tmp
  if [ -n "$PGROUP" ]; then
    func_chpgrp
    exit
  fi
  if [ -z "$GROUP" ]; then
    echo "ERROR: missing group"
    exit 1
  fi
  msg=""
  if grep -Eq "^GROUP $GROUP" "$USERFILE"; then
    sed "/^GROUP $GROUP/d" "$USERFILE" > "$USERFILE.tmp" || { echo "ERROR: removing from group"; exit 1; }
    msg="removed user \"$USERNAME\" from group \"$GROUP\""
  else
    { cat "$USERFILE"; echo "GROUP $GROUP 0"; } >> "$USERFILE.tmp" || { echo "ERROR: adding to group"; exit 1; }
    msg="added user \"$USERNAME\" to group \"$GROUP\""
  fi
  func_update_userfile
  func_logmsg "$msg"
}

func_chpgrp() {
  func_check_user "$USERNAME"
  func_clean_tmp
  msg=""
  if grep -Eq "^PRIVATE $PGROUP" "$USERFILE"; then
    sed "/^PRIVATE $PGROUP/d" "$USERFILE" > "$USERFILE.tmp" || { echo "ERROR: removing from private group"; exit 1; }
    msg="removed user \"$USERNAME\" from private group \"$PGROUP\""
  else
    { cat "$USERFILE"; echo "PRIVATE $PGROUP"; } >> "$USERFILE.tmp" || { echo "ERROR: adding private group"; exit 1; }
    msg="added user \"$USERNAME\" to private group \"$PGROUP\""
  fi
  func_update_userfile
  func_logmsg "$msg"
}

# ----------------------------------------------
# ADDUSERGROUP
# ----------------------------------------------
func_addusergroup() {
  func_check_user "$USERNAME"
  func_clean_tmp
  if [ -z "$GROUP" ]; then
    echo "ERROR: missing group"
    exit 1
  fi
  if ! grep -Eq "^GROUP $GROUP" "$USERFILE"; then
    if grep -Eq "^GROUP NoGroup" "$USERFILE"; then
       sed "s/^GROUP NoGroup/GROUP $GROUP ${GADMIN:-0}/" "$USERFILE" > "$USERFILE.tmp" || { echo "ERROR: adding to group"; exit 1; }
    else
      if grep -Eq "^GROUP .*"  "$USERFILE"; then
        #{ cat "$USERFILE"; echo "GROUP $GROUP 0"; } >> "$USERFILE.tmp" || { echo "ERROR: adding group"; exit 1; }
        sed '1h;1!H;$!d;x;/\(^.*GROUP [^\n]*\)/s//\1\nGROUP '"$GROUP ${GADMIN:-0}"'/' "$USERFILE" > "$USERFILE.tmp" || { echo "ERROR: adding to group"; exit 1; }
      else
        { cat "$USERFILE"; echo "GROUP $GROUP ${GADMIN:-0}"; } >> "$USERFILE.tmp" || { echo "ERROR: adding to group"; exit 1; }
      fi
    fi
  else
    #echo "INFO: user already added to group"
    exit 0
  fi
  func_update_userfile
  GADMIN_MSG=""
  if [ "${GADMIN:-0}" -eq 1 ]; then
    GADMIN_MSG="(as gadmin)"
  fi
  func_logmsg "added user \"$USERNAME\" to group \"$GROUP\"${GADMIN_MSG}"
}

# ----------------------------------------------
# DELUSERGROUP
# ----------------------------------------------
func_delusergroup() {
  func_check_user "$USERNAME"
  func_clean_tmp
  if [ -z "$GROUP" ]; then
    echo "ERROR: missing group"
    exit 1
  fi
  if grep -Eq "^GROUP $GROUP" "$USERFILE"; then
    sed "/^GROUP $GROUP/d" "$USERFILE" > "$USERFILE.tmp" || { echo "ERROR: removing from group"; exit 1; }
  else
    echo "ERROR: user not added to group"
    exit 1
  fi
  func_update_userfile
  func_logmsg "removed user \"$USERNAME\" from group \"$GROUP\""
}

# ----------------------------------------------
# ADDUSERPGROUP
# ----------------------------------------------
func_adduserpgroup() {
  func_check_user "$USERNAME"
  func_clean_tmp
  func_get_glconf
  if [ -z "$PGROUP" ]; then
    echo "ERROR: missing private group"
    exit 1
  fi
  if [ -z "$GLCONF" ]; then
    echo "ERROR: missing glconf"
    exit 1
  fi
  if grep -Eq "privgroup *[^ ]$PGROUP *" "$GLCONF"; then
    if ! grep -Eq "^PRIVATE $PGROUP" "$USERFILE"; then
      if grep -Eq "^PRIVATE .*"  "$USERFILE"; then
        sed '1h;1!H;$!d;x;/\(^.*PRIVATE [^\n]*\)/s//\1\nPRIVATE '"$PGROUP"'/' "$USERFILE" > "$USERFILE.tmp" || { echo "ERROR: adding to private group"; exit 1; }
      else
        { cat "$USERFILE"; echo "PRIVATE $PGROUP"; } >> "$USERFILE.tmp" || { echo "ERROR: adding to private group"; exit 1; }
      fi
    else
      exit 0
    fi
  else
    echo "ERROR: private group does not exist"
    exit 1
  fi
  func_update_userfile
  func_logmsg "added user \"$USERNAME\" to private group \"$PGROUP\""
}

# ----------------------------------------------
# DELUSERPGROUP
# ----------------------------------------------
func_deluserpgroup() {
  func_check_user "$USERNAME"
  func_clean_tmp
  if [ -z "$PGROUP" ]; then
    echo "ERROR: missing private group"
    exit 1
  fi
  if grep -Eq "^PRIVATE $PGROUP" "$USERFILE"; then
    sed "/^PRIVATE $PGROUP/d" "$USERFILE" > "$USERFILE.tmp" || { echo "ERROR: removing from private group"; exit 1; }
  else
    echo "ERROR: user not added to private group"
    exit 1
  fi
  func_update_userfile
  func_logmsg "removed user \"$USERNAME\" from private group \"$PGROUP\""
}

# ----------------------------------------------
# ADDUSER
# ----------------------------------------------
func_adduser() {
  HASHGEN_BIN="$(func_get_bin hashgen)"
  if [ -z "$USERNAME" ]; then
    echo "ERROR: missing username"
    exit 1
  fi
  if [ -z "$PASSWORD" ]; then
    echo "ERROR: missing password"
    exit 1
  fi
  if [ -s "$USERFILE" ]; then
    echo "ERROR: userfile already exists"
    exit 1
  fi
  if grep -Eq "^${USERNAME}:" "$GLDIR/etc/passwd"; then
    echo "ERROR: user already exists in /etc/passwd"
    exit 1
  fi
  if [ -n "$HASHGEN_BIN" ] && [ ! -x "$HASHGEN_BIN" ]; then
    echo "ERROR: missing hashgen"
    exit 1
  fi
  { echo "USER Added by $SITEOP"; \
    echo "ADDED 0 $SITEOP";  \
    grep -v '^#' "$GLDIR/ftp-data/users/default.user"; } \
    >"$USERFILE" || { echo "ERROR: creating userfile"; exit 1; }
  if [ ! -s "$USERFILE" ]; then
    echo "ERROR: userfile"
    exit 1
  fi
  # shellcheck disable=SC2034
  IFS=":" read -r username passwd uid gid date homedir unused <<< "$(tail -1 "$GLDIR/etc/passwd")"
  if ! echo "$uid" | grep -Eq '^[0-9]+$'; then 
      echo "ERROR: uid"
      exit 1
  fi
  uid=$((uid+1))
  if [ -z "$uid" ]; then
    echo "ERROR: uid"
    exit 1
  fi
  HASH="$($GLDIR/bin/hashgen "$USERNAME" "$PASSWORD" | cut -d: -f2)"
  if ! echo "$HASH" | grep -Eq '^\$[0-9a-f]{8}\$[0-9a-f]{40}$'; then 
    echo "ERROR: generating hash"
    exit 1
  fi
  cp "$GLDIR/etc/passwd" "$GLDIR/etc/passwd.tmp" || { echo "ERROR: updating passwd"; exit 1; }
  echo "${USERNAME}:${HASH}:${uid}:100:$(date +%d-%m-%y):/site:/bin/false" >> "$GLDIR/etc/passwd.tmp"
  if [ -s "$GLDIR/etc/passwd.tmp" ]; then
    mv "$GLDIR/etc/passwd.tmp" "$GLDIR/etc/passwd" || { echo "ERROR: updating passwd"; exit 1; }
  else
    echo "ERROR: passwd"
    exit 1
  fi
  if [ -s "$GLDIR/etc/passwd.tmp" ]; then
    echo "ERROR: passwd"
    exit 1
  fi
  func_logmsg "added user \"$USERNAME\""
}

# ----------------------------------------------
# DELUSER
# ----------------------------------------------
func_deluser() {
  func_check_user "$USERNAME"
  func_clean_tmp
  rm "$USERFILE" || { echo "ERROR: deleting userfile"; exit 1; }
  sed "/^${USERNAME}:/d" "$GLDIR/etc/passwd" >> "$GLDIR/etc/passwd.tmp" || { echo "ERROR: changing /etc/passwd"; exit 1; }
  if [ -s "$GLDIR/etc/passwd.tmp" ]; then
    mv "$GLDIR/etc/passwd.tmp" "$GLDIR/etc/passwd" || { echo "ERROR: updating passwd file"; exit 1; }
  else
    echo "ERROR: updating passwd file"
    exit 1;
  fi
  func_logmsg "deleted user \"$USERNAME\""
}

# ----------------------------------------------
# ADDGROUP
# ----------------------------------------------
func_addgroup() {
  if [ -z "$GROUP" ]; then
    echo "ERROR: missing group"
    exit 1
  fi
  GROUPFILE="$GLDIR/ftp-data/groups/$GROUP"
  if [ -s "$GROUPFILE" ]; then
    echo "ERROR: groupfile already exists"
    exit 1
  fi
  if grep -Eq "^${GROUP}:" "$GLDIR/etc/group"; then
    echo "ERROR: group already exists in /etc/group"
    exit 1
  fi
  { echo "GROUP Added by $SITEOP"; \
    grep -v '^#' "$GLDIR/ftp-data/groups/default.group" | \
    sed "s/^GROUPNFO/GROUPNFO ${GROUPDESC:GROUP}/"; } \
    >"$GROUPFILE" || { echo "ERROR: creating groupfile"; exit 1; }
  if [ ! -s "$GROUPFILE" ]; then
    echo "ERROR: groupfile"
    exit 1
  fi
  # shellcheck disable=SC2034
  IFS=":" read -r groupname description gid unused <<< "$(tail -1 "$GLDIR/etc/group")"
  if ! echo "$gid" | grep -Eq '^[0-9]+$'; then 
      echo "ERROR: gid"
      exit 1
  fi
  gid=$((gid+1))
  if [ -z "$gid" ]; then
    echo "ERROR: gid"
    exit 1
  fi
  { cat "$GLDIR/etc/group"; echo "${GROUP}:${GROUPDESC}:${gid}:"; } >> "$GLDIR/etc/group.tmp" || \
    { echo "ERROR: updating group file"; exit 1; }
  if [ -s "$GLDIR/etc/group.tmp" ]; then
    mv "$GLDIR/etc/group.tmp" "$GLDIR/etc/group" || { echo "ERROR: updating group file"; exit 1; }
  else
    echo "ERROR: group file"
    exit 1
  fi
  func_logmsg "added group \"$GROUP\""
}

# ----------------------------------------------
# DELGROUP
# ----------------------------------------------
func_delgroup() {
  func_clean_tmp
  if [ -z "$GROUP" ]; then
    echo "ERROR: missing group"
    exit 1
  fi
  GROUPFILE="$GLDIR/ftp-data/groups/$GROUP"
  if [ -d "$GROUPFILE" ]; then
    echo "ERROR: groupfile"
    exit 1
  fi
  rm "$GROUPFILE" || { echo "ERROR: deleting groupfile"; exit 1; }
  sed "/^$GROUP/d" "$GLDIR/etc/group" >> "$GLDIR/etc/group.tmp" || { echo "ERROR: changing /etc/group"; exit 1; }
  if [ -s "$GLDIR/etc/group.tmp" ]; then
    mv "$GLDIR/etc/group.tmp" "$GLDIR/etc/group" || { echo "ERROR: updating group file"; exit 1; }
  else
    echo "ERROR: group file"
    exit 1
  fi
  func_logmsg "deleted group \"$GROUP\""
}

# ----------------------------------------------
# CHANGETAG
# ----------------------------------------------
func_chtag() {
  func_check_user "$USERNAME"
  func_clean_tmp
  if [ -z "$TAGLINE" ]; then
    echo "ERROR: missing tagline"
    exit 1
  fi
  sed "s/^TAGLINE .*/TAGLINE $TAGLINE/" "$USERFILE" > "$USERFILE.tmp"
  func_update_userfile
  func_logmsg "changed tagline for \"$USERNAME\" to \"$TAGLINE\""
}

# ----------------------------------------------
# CHANGEFLAG
# ----------------------------------------------
func_chflag() {
  func_check_user "$USERNAME"
  func_clean_tmp
  if [ -z "$FLAGS" ]; then
    echo "ERROR: missing flag(s)"
    exit 1
  fi
  if [ "${GREP_PERL:-1}" -eq 0 ]; then
    CURRENT_FLAGS="$( grep -ow "^FLAGS \K.*" "$USERFILE" | cut -d" " -f2-)"
  else
    CURRENT_FLAGS="$( grep -Pow "^FLAGS \K.*" "$USERFILE" )"
  fi
  NEW_FLAGS="$CURRENT_FLAGS"
  # shellcheck disable=SC2001
  for i in $(echo "$FLAGS" | sed 's/./& /g'); do
    if echo "$NEW_FLAGS" | grep -q "$i"; then
      NEW_FLAGS="${NEW_FLAGS//$i/}"
    else
      NEW_FLAGS+="$i"
    fi
  done
  sed "s/^FLAGS .*/FLAGS $NEW_FLAGS/" "$USERFILE" > "$USERFILE.tmp" || { echo "ERROR: changing flags"; exit 1; }
  func_update_userfile
  func_logmsg "changed flags for \"$USERNAME\" from \"$CURRENT_FLAGS\" to \"$NEW_FLAGS\""
}

# ----------------------------------------------
# ADDFLAG
# ----------------------------------------------
func_addflag() {
  func_check_user "$USERNAME"
  func_clean_tmp
  if [ -z "$FLAGS" ]; then
    echo "ERROR: missing flag(s)"
    exit 1
  fi
  if ! echo "$FLAGS" | grep -Eq "[0-9A-Z]+"; then
    echo "ERROR: invalid flag(s)"
    exit 1
  fi
  if [ "${GREP_PERL:-1}" -eq 0 ]; then
    CURRENT_FLAGS="$(grep -ow "^FLAGS .*" "$USERFILE" | cut -d" " -f2-)"
  else
    CURRENT_FLAGS="$(grep -Pow "^FLAGS \K.*" "$USERFILE")"
  fi
  if [ -n "$CURRENT_FLAGS" ]; then
    # shellcheck disable=SC2001
    for i in $(echo "$FLAGS" | sed 's/./& /g'); do
      if ! echo "$CURRENT_FLAGS" | grep -q "$i"; then
        NEW_FLAGS+="$i"
        CNT=$((CNT+1))
      fi
    done
  else
    NEW_FLAGS="$FLAGS"
    CNT=1
  fi
  if [ "${CNT:-0}" -ge 1 ]; then
    sed "s/^\(FLAGS .*\)/\1${NEW_FLAGS}/" "$USERFILE" > "$USERFILE.tmp" || { echo "ERROR: adding flag"; exit 1; }
    func_update_userfile
    func_logmsg "added flags \"$FLAGS\" to \"$USERNAME\""
  fi
}

# ----------------------------------------------
# DELFLAG
# ----------------------------------------------
func_delflag() {
  func_check_user "$USERNAME"
  func_clean_tmp
  if [ -z "$FLAGS" ]; then
    echo "ERROR: missing flag(s)"
    exit 1
  fi
  if ! echo "$FLAGS" | grep -Eq "[0-9A-Z]+"; then
    echo "ERROR: invalid flag(s)"
    exit 1
  fi
  if [ "${GREP_PERL:-1}" -eq 0 ]; then
    NEW_FLAGS="$(grep -ow "^FLAGS .*" "$USERFILE" | cut -d" " -f2-)"
  else
    NEW_FLAGS="$( grep -Pow "^FLAGS \K.*" "$USERFILE" )"
  fi
  # shellcheck disable=SC2001
  for i in $(echo "$FLAGS" | sed 's/./& /g'); do
    if echo "$NEW_FLAGS" | grep -q "$i"; then
      NEW_FLAGS="${NEW_FLAGS//$i/}"
    fi
  done
  sed "s/^FLAGS .*/FLAGS $NEW_FLAGS/" "$USERFILE" > "$USERFILE.tmp" || { echo "ERROR: changing flags"; exit 1; }
  func_update_userfile
  func_logmsg "deleted flags \"$FLAGS\" from \"$USERNAME\""
}

# ----------------------------------------------
# CHANGELOGINS
# ----------------------------------------------
func_chlogins() {
  func_check_user "$USERNAME"
  func_clean_tmp
  if [ -z "$LOGINS" ]; then
    echo "ERROR: missing logins"
    exit 1
  fi
  if ! echo "$RATIO" | grep -Eq '^([0-9-] ?)+$'; then
    echo "ERROR: invalid logins"
  fi
  sed "s/^LOGINS .*/LOGINS $LOGINS/" "$USERFILE" > "$USERFILE.tmp"
  func_update_userfile
  func_logmsg "changed logins for \"$USERNAME\" to \"$LOGINS\""
}

# ----------------------------------------------
# CHANGERATIO
# ----------------------------------------------
func_chratio() {
  func_check_user "$USERNAME"
  func_clean_tmp
  if [ -z "$RATIO" ]; then
    echo "ERROR: missing ratio"
    exit 1
  fi
  if ! echo "$RATIO" | grep -Eq '^([0-9-] ?)+$'; then
    echo "ERROR: invalid ratio"
  fi
  sed "s/^RATIO .*/RATIO $RATIO/" "$USERFILE" > "$USERFILE.tmp"
  func_update_userfile
  func_logmsg "changed ratio for \"$USERNAME\" to \"$RATIO\""
}

# ----------------------------------------------
# CHANGECREDITS
# ----------------------------------------------
func_chcreds() {
  func_check_user "$USERNAME"
  func_clean_tmp
  if [ -z "$CREDITS" ]; then
    echo "ERROR: missing credits"
    exit 1
  fi
  if ! echo "$CREDITS" | grep -Eq '^([0-9-] ?)+$'; then
    echo "ERROR: invalid credits"
  fi
  sed "s/^CREDITS .*/CREDITS $CREDITS/" "$USERFILE" > "$USERFILE.tmp"
  func_update_userfile
  func_logmsg "changed credits for \"$USERNAME\" to \"$CREDITS\""
}

# ----------------------------------------------
# USERGADMIN
# ----------------------------------------------
func_usergadmin() {
  func_check_user "$USERNAME"
  func_clean_tmp
  if [ -z "$GROUP" ]; then
    echo "ERROR: missing group"
    exit 1
  fi
  if [ -z "$GADMIN" ]; then
    echo "ERROR: missing gadmin"
    exit 1
  fi
  # GADMIN=0 del (default), GADMIN=1 add
  if grep -Eq "^GROUP $GROUP" "$USERFILE"; then
    sed 's/^GROUP '"$GROUP"'.*/GROUP '"$GROUP ${GADMIN:-0}"'/' "$USERFILE" > "$USERFILE.tmp" || { echo "ERROR: gadmin"; exit 1; }
  else
    echo "ERROR: gadmin"
    exit 1
  fi
  func_update_userfile
  action="del"
  if [ "${GADMIN:-0}" -eq "1" ]; then
    action="add"
  fi
  func_logmsg "changed user \"$USERNAME\", $action as \"$GROUP\" gadmin"
}

# ----------------------------------------------
# CHANGEGADMIN
# ----------------------------------------------
func_chgadmin() {
  func_check_user "$USERNAME"
  func_clean_tmp
  if [ -z "$GROUP" ]; then
    echo "ERROR: missing group"
    exit 1
  fi
  action="del"
  if grep -Eq "^GROUP $GROUP 0" "$USERFILE"; then
    action="add"
    sed 's/^GROUP '"$GROUP"'.*/GROUP '"$GROUP 1"'/' "$USERFILE" > "$USERFILE.tmp" || { echo "ERROR: gadmin"; exit 1; }
  elif grep -Eq "^GROUP $GROUP 1" "$USERFILE"; then
    sed 's/^GROUP '"$GROUP"'.*/GROUP '"$GROUP 0"'/' "$USERFILE" > "$USERFILE.tmp" || { echo "ERROR: gadmin"; exit 1; }
  fi
  func_update_userfile
  func_logmsg "changed user \"$USERNAME\", $action as \"$GROUP\" gadmin"
}

# ----------------------------------------------
# STATS
# ----------------------------------------------

func_bc() {
  if echo "$1" | grep -Eq "^[0-9]"; then
    UNIT="$2"
    if [ "$UNIT" = "" ]; then
      if [ "$1" -lt "1024" ]; then
        UNIT="b"
      elif [ "$1" -ge "1024" ] && [ "$1" -lt "1024000" ]; then
        UNIT="KB"
      elif [ "$1" -ge "1024000" ] && [ "$1" -lt "1024000000" ]; then
        UNIT="MB"
      elif [ "$1" -ge "1024000000" ] && [ "$1" -lt "1024000000000" ]; then
        UNIT="GB"
      elif [ "$1" -ge "1024000000000" ]; then
        UNIT="TB"
      fi
    fi
    case "$UNIT" in
      b)  RESULT="$1${UNIT}" ;;
      KB) RESULT="$( echo "$1 1024" | awk '{ printf "%0.0f%s", $1/$2, "KB" }' )" ;;
      MB) RESULT="$( echo "$1 1024"  | awk '{ printf "%0.1f%s", $1/$2/$2, "MB" }' )" ;;
      GB) RESULT="$( echo "$1 1024"  | awk '{ printf "%0.1f%s", $1/$2/$2/$2, "GB" }' )" ;;
      TB) RESULT="$( echo "$1 1024"  | awk '{ printf "%0.2f%s", $1/$2/$2/$2/$2, "TB" }' )" ;;
    esac
  fi
  echo "$RESULT"
}

__func_bc() {
  if [ "$2" = "MB" ]; then
    echo | awk -v v="$1" '{ printf "%0.0fMB", v/1024/1024 }'
  elif [ "$2" = "GB" ]; then
    echo | awk -v v="$1" '{ printf "%0.1fGB", v/1024/1024/1024 }'
  fi
}

func_userstats() {
  COUNT=0
  INDEX=0
  SECTION=()
  if [ "${GREP_PERL:-1}" -eq 0 ]; then
    while read -d' '-r f; do
      case $((COUNT%3)) in
        0) FIELDS=""; FIELDS+="$f " ;;
        1) FIELDS+="$f " ;;
        2) FIELDS+="$f "; SECTION[INDEX]="${FIELDS/% /}" ;;
        *) break;
      esac
      COUNT=$((COUNT+1))
      if [ $((COUNT%3)) -eq 0 ]; then
        INDEX=$((INDEX+1))
      fi
    done < <(grep -ow "^$1 ([0-9]+ ?)+" "$USERFILE" | cut -d" " -f2-)
  else
    while read -d' '-r f; do
      case $((COUNT%3)) in
        0) FIELDS=""; FIELDS+="$f " ;;
        1) FIELDS+="$f " ;;
        2) FIELDS+="$f "; SECTION[INDEX]="${FIELDS/% /}" ;;
        *) break;
      esac
      COUNT=$((COUNT+1))
      if [ $((COUNT%3)) -eq 0 ]; then
        INDEX=$((INDEX+1))
      fi
    done < <(grep -Pow "^$1 \K([0-9]+ ?)+" "$USERFILE")
  fi
}

func_rawuserstats() {
  for p in DAYUP WKUP MONTHUP ALLUP DAYDN WKDN MONTHDN ALLDN NUKE; do
    func_userstats "$p"
    for ((i=0; i < ${#SECTION[@]} ; i++)); do
      echo "$p $i ${SECTION[i]}"
    done
  done
}

func_listuserstats() {
  func_check_user "$USERNAME"
  printf "PERIOD UP/DN:\tSTAT_SECTION:\t\tBytes / Files:\n" # / Time"
  printf -- "------------------------------------------------------------\n"
  for p in DAYUP WKUP MONTHUP ALLUP DAYDN WKDN MONTHDN ALLDN; do
    func_userstats "$p"
    for ((i=0 ; i < ${#SECTION[@]} ; i++)); do
      stat_section="$i         "
      if [ ${i:-255} -eq 0 ]; then
        stat_section="$i(DEFAULT)"
      fi
      if [ $i -eq 0 ] || [ "${SECTION[i]}" != "0 0 0" ]; then
        IFS=" " read -r files bytes _time <<<"${SECTION[i]}"
        printf "%s\t\t%s\t\t%s/%sf\n" "$p" "$stat_section"  "$(func_bc "$bytes")" "$files"
      fi
    done
    echo
  done #| sort -k 2n -k 1r
  printf "\t\t\t\t\tBytes / Times (Date):\n\n" # / Time"
  func_userstats "NUKE"
  for ((i=0; i < ${#SECTION[@]} ; i++)); do
    if [ "${SECTION[i]}" = "0 0 0" ]; then
      continue
    fi
    stat_section="$i"
    if [ ${i:-255} -eq 0 ]; then
      stat_section="$i(DEFAULT)"
    fi
    IFS=" " read -r last times bytes <<<"${SECTION[i]}"
    printf "%s\t\t%-10s\t\t%s %s (%s)\n" "NUKE" "$stat_section" "$(func_bc "$bytes")" "$times" "$(date -d@"$last" +'%F %H:%M')"
  done
  echo
  if [ "${GREP_PERL:-1}" -eq 0 ]; then
    IFS=" " read -r _numlogins lastlogin _maxtime _todaytime <<<"$(grep -ow "^TIME \K([0-9]+ ?)+" "$USERFILE" | cut -d" " -f2-)"
  else
    IFS=" " read -r _numlogins lastlogin _maxtime _todaytime <<<"$(grep -Pow "^TIME \K([0-9]+ ?)+" "$USERFILE")"
  fi
  if [ -n "$lastlogin" ]; then
    printf "LAST LOGIN: %s\n" "$(date -d@"$lastlogin" +'%F %H:%M')"
  fi
  echo
}

func_resetuserstats() {
  func_check_user "$USERNAME"
  func_clean_tmp
  cp "$USERFILE" "$USERFILE.tmp" || { echo "ERROR: updating userfile"; exit 1; }
  for p in DAYUP WKUP MONTHUP ALLUP DAYDN WKDN MONTHDN ALLDN NUKE; do
    sed -i "s/^$p .*/$p 0 0 0/" "$USERFILE.tmp"
  done || { echo "ERROR: resetting stats"; exit 1; }
  func_update_userfile
  func_logmsg "reset stats for \"$USERNAME\""
}


################################################
# COMMANDS
################################################

case $COMMAND in
  ADDUSER)
    func_adduser
    test -n "$GROUP" && func_addusergroup
    test -n "$MASK" && func_addip
    exit 0
  ;;
  LISTUSERS) func_listusers && exit 0 ;;
  LISTGROUPS) func_listgroups && exit 0 ;;
  RAWUSERFILE) func_rawuserfile && exit 0 ;;
  RAWUSERS) func_rawusers && exit 0 ;;
  RAWGROUPS) func_rawgroups && exit 0 ;;
  RAWPGROUPS) func_rawpgroups && exit 0 ;;
  RAWUSERSGROUPS) func_rawusersgroups && exit 0 ;;
  RAWUSERSPGROUPS) func_rawuserspgroups && exit 0 ;;
  RAWUSERGROUP) func_rawusergroup && exit 0 ;;
  RAWTAG) func_rawuserfilefield "TAGLINE" && exit 0 ;;
  RAWFLAG) func_rawuserfilefield "FLAGS" && exit 0 ;;
  RAWCREDS) func_rawuserfilefield "CREDITS" && exit 0 ;;
  DELUSER) func_deluser && exit 0 ;;
  ADDGROUP) func_addgroup && exit 0 ;;
  DELGROUP) func_delgroup && exit 0 ;;
  CHGRP) func_chgrp && exit 0 ;;
  ADDUSERGROUP) func_addusergroup && exit 0 ;;
  DELUSERGROUP) func_delusergroup && exit 0 ;;
  ADDUSERPGROUP) func_adduserpgroup && exit 0 ;;
  DELUSERPGROUP) func_deluserpgroup && exit 0 ;;
  USERGADMIN) func_usergadmin && exit 0 ;;
  CHGADMIN) func_chgadmin && exit 0 ;;
  LISTIP) func_listip && exit 0 ;;
  RAWIP) func_rawip && exit 0 ;;
  ADDIP) func_addip && exit 0 ;;
  DELIP) func_delip && exit 0 ;;
  CHPASS) func_chpass && exit 0 ;;
  CHTAG) func_chtag && exit 0 ;;
  CHFLAG) func_chflag && exit 0 ;;
  CHCREDITS) func_chcreds && exit 0 ;;
  CHLOGINS) func_chlogins && exit 0 ;;
  CHRATIO) func_chratio && exit 0 ;;
  ADDFLAG) func_addflag && exit 0 ;;
  DELFLAG) func_delflag && exit 0 ;;
  RAWUSERSTATS) func_rawuserstats && exit 0 ;;
  LISTUSERSTATS) func_listuserstats && exit 0 ;;
  RESETUSERSTATS) func_resetuserstats && exit 0 ;;
  LOGTAIL) func_logtail ;;
  LOGSHOW) func_logshow ;;
  *) echo "ERROR: no such cmd"; exit 1 ;;
esac
