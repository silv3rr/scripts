
; .---------------------------------------------------------.
; |                   |                                     |
; |  :: CBFTP API ::  |  Needs: JSONFormIRC 2.0.2001+       |
; |  ---------------  |  Usage: /CbHelp /CbSite /CbInvite   |
; |       PoC         |         /CbSearch /CbDupe /CbReq    |
; |                   |                                     |
; `---------------------------------------------------------'
;                                              slv 20200131

; :: INSTALLATION
; -----------------------------------------------------------
;
; > Get https://github.com/SReject/JSON-For-Mirc
; > Copy .mrc and .js files from 'src' to mIRC scripts dir
; > Copy this script to mIRC scripts dir
; > Load as remote scripts
; 
; :: CONFIGURATION
; -----------------------------------------------------------
; > Set Cbftp HTTPS/JSON REST API URL, include plaintext
;   password -or- leave empty and set a fish10 or micryption
;   key for user 'cbftp' to use that as password instead
;
; > Set sites to use: "SITE1","SITE2" or 'all' (default)
;
; > Optionally limit number of output characters
;   in results or '0' for unlimited (default: 4000)
;
; *Or* use /CbSet [arguments], see /CbHelp for details
;
; > cb_url    : https://:<API_Password>@127.0.0.1:443
; > cb_sites  : "SITE1" | "SITE1","SITE2" | all | get
;
alias CbInit {
  set %cb_url https://:Passwd@127.0.0.1:62443
  set %cb_sites  all
  set %cb_climit 4000
}
; ---------------------------------------------------------
; CONFIG END 
; ---------------------------------------------------------

; API COMMAND EXAMPLES:
; ---------------------
; These aliases set a site command with and call CbCmd with args:
;  /CbSite WHO, /CbSite KICK foo, /CbSite DELUSER bar

;; SITE <cmd> <args>

alias CbSite {
  set %cb_cmd SITE | CbCmd $1-
}

;; SITE INVITE <nick>

alias CbInvite {
  if ($1) { var %inick = $1 }
  else {
    var %i = 0 | while ($scon(0) > %i) {
      if ( $scon(%i).$network = $1 ) {   
        var %inick = $scon(%i).me
      }
      inc %i
    }
  }
  if (%inick) { set %cb_cmd SITE INVITE | CbCmd %inick }
}

;; SITE DUPE <query>

alias CbDupe { 
  if ($1) { set %cb_cmd SITE DUPE | CbCmd $1- }
  else { echo -ast CBDUPE: ERROR > no query, try /CbHelp }
}

;; SITE SEARCH <query>

alias CbSearch {
  if ($1) { set %cb_cmd SITE SEARCH | CbCmd $1- }
  else { echo -ast CBSEARCH: ERROR > no query, try /CbHelp }
}

;; SITE REQUEST <release>

alias CbReq {
  if ($1) { set %cb_cmd SITE REQUEST | CbCmd $1- }
  else { echo -ast CBREQ: ERROR > no release, try /CbHelp }
}


; SEND/RECEIVE JSON
; -----------------
; Using 'JSON For Mirc' CbCmd sends command to the CB API and handles the result

alias -l CbCmd {
  var %cb_args = $1-
  .CbCheck
  if (!%cb_sites) {
    echo -ast CBCMD: INFO > no sites selected, using 'all' (try /CbHelp)
    set %cb_sites all
  }
  if (!%cb_cmd) {
    echo -ast CBCMD: ERROR > command missing, try /CbHelp | return
  }
  ;; Send 'raw command' JSON to one or more site(s)
  if (%cb_sites != all) {
    var %cb_data = {"command":  " $+ %cb_cmd %cb_args $+ ", "sites":[ $+ %cb_sites $+ ], "path":"/", "timeout":10, "async":false}
  }
  ;; Send 'raw command' JSON to *all* sites
  else {
    var %cb_data = {"command": " $+ %cb_cmd %cb_args $+ ", "sites_all": true, "path":"/", "timeout":10, "async":false}
  }

  JSONClose -w cbftp*
  var %cb_hn = cbftp  $+ $rand(1,10000)
  var %cb_urn = /raw
  var %cb_method = POST
  JSONOpen -uwi %cb_hn $CbUri(%cb_url,%cb_urn)
  CbHttpHeaders %cb_hn
  JSONHttpMethod %cb_hn %cb_method
  JSONHttpFetch %cb_hn %cb_data

  if (%cb_debug >= 2) {
    echo $CbHttpDebug(%cb_url,%cb_urn,%cb_hn,%cb_method,%cb_data)
  }

  ;; check json error
  if (!$JSONError) { 
    echo -as $crlf
    if (%cb_debug >= 1) {
      echo -ast DEBUG: OK (no JSONError)
    }
    if (%cb_sites) {
      var %cb_len = 0
      if ($json(%cb_hn).length > 0) {
        var %cb_len = $json(%cb_hn).length
      }
      if (%cb_debug >= 2) {
        echo -ast DEBUG: JSONForEach walk (cb_len= $+ %cb_len $+ )
      }
      ;; walk json calling CbItem for each item
      noop $JSONForEach(%cb_hn,CbItem %cb_len).walk
    }
  }
  else {
    echo -atm CBAPI: ERROR > JSONError $JSONError $JSON(%cb_hn).error (hn: %cb_hn uri: %cb_uri $+ )
    JSONClose %cb_hn
    return
  }
  if (%cb_debug >= 1) {
    echo -ast ---
    echo -ast END
    echo -ast ---
  }
  JSONClose -w cbftp*
  if (!%cb_gotres) {
    echo CBAPI: no results
    echo -as $crlf
  }
}

; JSONItem
; --------
; handle JSON items in $JSONForEach and call CbResult

alias CbItem {
  ; Args: 1=%cb_len 2=<item>  
  var %cb_cmax = 8000
  var %cb_snum = $regsubex($json($2-).path,/.* (\d+) .*/,\1)
  var %cb_bvar = $JSONItem(valuetobvar)
  var %cb_blen = $bvar(%cb_bvar,0)
  if ((%cb_climit > 0) && (%cb_blen > %cb_climit)) {
    var %cb_trun = $calc(%cb_blen - %cb_cmax)
    echo -as CBAPI: WARNING result of %cb_blen characters of is over limit of %cb_climit ( $+ %cb_trun characters truncated)
    var %cb_blen = %cb_climit
  }
  if (%cb_blen > %cb_cmax ) {
    var %cb_trun = $calc(%cb_blen - %cb_cmax) 
    echo -as CBAPI: ERROR result of %cb_blen characters is too large ( $+ %cb_trun characters truncated)
    var %cb_blen = %cb_cmax
  }  
  var %cb_btxt = $bvar(%cb_bvar,1,%cb_blen).text
  var %cb_ntok = $numtok($json($2).path,32)
  var %i = 0 | while (%i <= %cb_ntok) {
    var %cb_gtok = $gettok($json($2).path,%cb_ntok,32)
    inc %i
  }
  if (%cb_debug >= 2) {
    echo -ast DEBUG: CbItem cb_blen= $+ %cb_blen len_bvar= $+ $len($bvar(%cb_bvar,1,9999).text)
    echo -ast DEBUG: CbItem cb_snum= $+ %cb_snum json.length= $+ $json($2).length json.path= $+ $json($2-).path
    echo -ast DEBUG: CbItem cb_ntok= $+ %cb_ntok cb_gtok= $+ %cb_gtok
    if (%cb_debug >= 3) { echo -ast DEBUG: CbItem cb_btxt= $+ %cb_btxt }
  }
  if ((%cb_btxt) && (%cb_gtok == name)) {
    set -eu5 %cb_name %cb_btxt

  }
  elseif ((%cb_btxt) && (%cb_gtok == result)) {
    CbResult $iif(%cb_snum,$v1,0) $iif($1,$v1,0) $iif(%cb_name,$v1,SITE) %cb_btxt 
  }
}

; LOCAL HELPER ALIASES
; --------------------


alias -l CbCheck {
  ;; check for lib and vars
  if (!$regex($nopath($isalias(JSONOpen).fname),/^json for mirc.mrc$/i)) {
    if (%cb_debug != 0) {
      echo -ast DEBUG: JSONFormIRC not loaded
    }
    else {
      echo -ast CBCMD: ERROR > JSONFormIRC not loaded, see 'INSTALLATION' inside script | halt
    }
  }
  if (!%cb_url) {
    echo -ast CBCMD: ERROR > https api url not set, try /CbHelp | return
  }
  if (!$CbPasswd) {
    echo -ast CBCMD: ERROR > api password not set, try /CBHelp | return
  }
  if (!$var(%cb_climit)) {
    set %cb_climit 4000
  }
}

alias -l CbResult {
  ; Args: 1=%cb_snum 2=%cb_len 3=%cb_name 4=%cb_result
  if (%cb_raw) {
    var %cb_result = $4-
  }
  else {
    ;; use regexps to clean up result then output lines split on CR
    var %cb_re_all = $regsubex($4-,/200- |(200 Command Successful.\r\n)/g,)
    ;; SITE SEARCH and DUPE results
    if ($regex(%cb_cmd,/^SITE (DUPE|SEARCH)$/)) {
      var %cb_re1_1 = \(Values displayed after dir names are Files/Megs/Age\)
      var %cb_re1_2 = Doing case-insensitive search for ' $+ .* $+ ':
      var %cb_re1_3 = 200 0 directory found.|200- /.*/(Sample|Subs|Proof) \(.*
      var %cb_re1_4 = 200- [0-9]+ of [0-9]+ dupes listed. \([0-9]+ total\)
      var %cb_re1 = /( $+ %cb_re1_1 $+ $chr(124) $+ %cb_re1_2 $+ $chr(124) $+ %cb_re1_3 $+ $chr(124) $+ %cb_re1_4 $+ )\r\n|200- /g
      var %cb_re2 = 200 ((?:[1-9]|[1-9][0-9]+) director(?:ies|y) found.)
      var %cb_re_ds = $null | noop $regsubex(cbreds,%cb_re_all,%cb_re1,,%cb_re_ds)
      var %cb_result = $regsubex(%cb_re_ds,%cb_re2,\1)
    }
    else {
      var %cb_result = %cb_re_all
    }
  }
  var %cb_rnum = $gettok(%cb_result,0,13)
  if (%cb_result) {
    set -eu5 %cb_gotres 1
    var %cnt = 1 | while (%cnt < %cb_rnum) {
      ;; debug output: SITENAME ( sitenum/allsites resultline/total) $result
      if (%cb_debug >= 3)  {
        echo -as CBAPI:  $+ $3 $+  ( $+ $1 $+ / $+ $2 %cnt $+ / $+ %cb_rnum $+ ) $gettok(%cb_result,%cnt,13)
      }
      else {
        echo -as CBAPI:  $+ $3 $+  $gettok(%cb_result,%cnt,13)
      }
      inc %cnt
    }
    echo -as $crlf
  }
}

alias -l CbUri {
  if ($regsubex(cburl,$1 $+ $iif($2,$v1,/),/^(https://)(?::?.+@)(.+:\d+/.*)$/,\1\2,%cb_uri)) {
    return %cb_uri
  }
  return
}

alias -l CbPasswd {
  var %cb_passwd = $null
  ; fish10: return key for 'cbftp'
  if ($dll(%FiSH_dll,FiSH_GetKey10, cbftp cbftp)) {
    return $v1
  }
  ; Micryption: return key for 'cbftp'
  elseif ($dll(%mc_scriptdll, mc_displaykey, cbftp)) {
    return $v1
  }
  ; Micryption: decrypt encrypted passwd text using '_mcloggingkey'
  elseif ($regsubex(cbpw,$iif($1,$v1,%cb_url),/^https://:?(«m«.*=»m»)@.*:\d+$/,\1,%cb_passwd)) {
    return $dll(%mc_scriptdll, mc_decrypt2, $mc_loggingkey %cb_passwd)
  }
  ; plaintext
  elseif ($regsubex(cbpw,$iif($1,$v1,%cb_url),/^https://:?(.+)@.*:\d+$/,\1,%cb_passwd)) { 
    return %cb_passwd 
  }
  return
}

alias -l CbHttpHeaders {
  ; Args = 1:%cn_hn
  JSONHttpHeader $1 Authorization Basic $encode(: $+ $CbPasswd, m)
  JSONHttpHeader $1 Content-Type application/x-www-form-urlencoded
}

alias -l CbHttpDebug {
  ; Args: 1=URL 2=URN 3=%cb_hn 4=METHOD 5=%cb_data
  echo -ast DEBUG: JSONOpen $3 $CbUri($1,$2)
  echo -ast DEBUG: JSONHttpHeader $3 Authorization $encode(: $+ $CbPasswd, m)
  echo -ast DEBUG: JSONHttpHeader $3 Content-Type application/x-www-form-urlencoded
  echo -ast DEBUG: JSONHttpMethod $3 $4
  echo -ast DEBUG: JSONHttpFetch $3 $5
}

; HELP AND SET ALIASES
; --------------------

alias CbHelp {
  echo -ast CBHELP: SETTINGS:
  if (!%cb_url || !$CbPasswd) {
    echo -ast CBHELP: 
    echo -ast CBHELP: > Edit settings in Script and run '/CbInit' to activate
    echo -ast CBHELP: > Settings can also be changed using '/CbSet [arguments]'
    echo -ast CBHELP: > For details see comments in Script under 'CONFIGURATION'
    echo -ast CBHELP: 
  }
  echo -ast CBHELP: Show settings   : /CbSet
  echo -ast CBHELP: Change settings : /CbSet [api_url] [SITES|all]
  echo -ast CBHELP:                    /CbSet overrides '/CbInit' settings
  echo -ast CBHELP: USAGE:
  echo -ast CBHELP: site <cmd>      : /CbSite <cmd> <arguments>
  echo -ast CBHELP: site invite      : /CbInvite <nick>
  echo -ast CBHELP: site search     : /CbSearch <pattern>
  echo -ast CBHELP: site dupe        : /CbDupe <pattern>
  echo -ast CBHELP: site request     : /CbReq <release>
}

alias CbSet {
  .CbInit
  if ($regex($1,/^https://:?.*@.+:\d+$/)) { set %cb_url $1 | CbPasswd $1 | echo -ast CBAPI: url set to $2 }
  if ($regex($2,all|("[A-Z0-9],?")+)) { set %cb_sites $2 | echo -ast CBAPI: sites set to $2 }
  echo -ast CBSET: CURRENT SETTINGS:
  echo -ast CBSET: cb_url = $CbUri(%cb_url)
  echo -ast CBSET: cb_passwd = $iif($CbPasswd,is set,is not set)
  echo -ast CBSET: cb_sites = %cb_sites
  echo -ast CBSET: * cb_climit = %cb_climit
  echo -ast CBSET: + cb_raw = %cb_raw
  echo -ast CBSET: + cb_debug = %cb_debug
}

; set 1 to enable raw ouput, debug can be set to 1-3

alias CbRaw {
  if ($regex($1,^\d+$)) { set %cb_raw $1 | echo -ast CBSET: raw $iif(%cb_raw,set,unset) }
}
alias CbDebug {
  if ($regex($1,^\d+$)) { set %cb_debug $1 | echo -ast CBSET: debug $iif(%cb_debug,set to $v1,unset) }
}

; 'GET' ALL SITES EXAMPLE:
; ------------------------
; CbGetSites sends 'GET /sites' to the cbftpd api and returns formatted site names

alias CbGetSites {
  .CbCheck
  JSONClose -w cbftp*
  var %cb_hn = cbftp $+ $rand(1,10000)
  var %cb_urn = /sites
  var %cb_method = GET
  JSONOpen -uwi %cb_hn $CbUri(%cb_url,%cb_urn)
  CbHttpHeaders %cb_hn
  JSONHttpFetch %cb_hn
  if (%cb_debug >= 2) {
    echo $CbHttpDebug(%cb_url,%cb_urn,%cb_hn,%cb_method,%cb_data)
  }
  ;; check jsonerror
  if (!$JSONError) {
    if (%cb_debug >= 2) {
      echo -ast GETSITES: OK (no JSONError)
    }
    var %cb_len = $json(%cb_hn,sites).length
    var %cb_name = $json(%cb_hn,successes, $+ %i $+ ,name).value
    var %i = 0 | while (%i <= %cb_len) {
      var %cb_sv = $json(%cb_hn,sites, $+ %i $+).value
      if (%cb_sv) {
        var %cb_stmp = %cb_stmp $+ " $+ %cb_sv $+ " $+ $chr(44)
      }
      inc %i
    } 
    var %cb_getsites = $regsubex(%cb_stmp,$chr(44) $+ $,)
    if (%cb_debug >= 2) {
      echo -ast DEBUG: getsites cb_len= $+ %cb_len
      echo -ast DEBUG: getsites cb_getsites= $+ %cb_getsites cb_stmp= $+ %cb_stmp
    }
  }
  else {
    echo -atm CBGETSITES: ERROR > JSONError $JSONError $JSON(%cb_hn).error (hn: %cb_hn uri: %cb_uri $+ )
    JSONClose %cb_hn
    return
  }
  JSONClose -w cbftp*
  return %cb_getsites    
}
