;
;                  " ...but what does it doooo? well, not much "
;
; .---------------------------------------------------------------------------.
; |                   |  > Needs: JSONFormIRC 2.0.2001+                       |
; |  :: CBFTP API ::  |  > Usage: /CbHelp /CbSet /CbSite /CbInvite            |
; |  ---------------  |           /CbSearch /CbDupe /CbReq /CbAddsite         |
; |       beta3       |           /CbSpread /CbFxp /CbList /CbInc ..etc       |
; |                   |           ( Or right click for CBFTP API menu )       |
; `---------------------------------------------------------------------------'
;                                                                 slv 20210803
; :: USAGE
; -----------------------------------------------------------------------------
; This is meant to show how the Cbftp JSON REST API can be used with mIRC.
; All API endpoints should be there as Aliases. Commands can be send to 
; one or more sites. Most responses should be handled reasonably well (though
; that part is messy). Some management of sites/sections is also possible.
;
; This is not a trade tool. If you want one you're better off using the UDP API
; and diff client. As-is I could maybe see siteops using this as an admin tool.
;
;
; :: INSTALLATION
; -----------------------------------------------------------------------------
; > Get https://github.com/SReject/JSON-For-Mirc
; > Copy .mrc and .js files from 'src' dir to mIRC\scripts dir
; > Copy this script to the same dir
; > Load both .mrc files as remote scripts, JSONFormIRC first
;
; :: CHANGELOG
; -----------------------------------------------------------------------------
; > beta3: added transfer, filelist, incomplete cmd (and more),
;          menu's and dialogs, improved config
; > PoC:   added site cmds, getsites (1st public rls)
;
; :: CONFIGURATION
; -----------------------------------------------------------------------------
; > Settings can be changed in multiple ways:
;    - initial setup in script, see 'CbInit' below
;    - by using alias /CbSet
;    - using gui menu: right click, select 'CBFTP API', Settings
;
; > Set Cbftp REST API url (http/json) including plaintext password (*)
;   Example: https://:<API_Password>@127.0.0.1:443
;
; > Set sites: "SITE1","SITE2" OR 'all' (default)
;
; > Optionally limit number of output characters in results
;   or use '0' for 'unlimited' (default: 4000)
;
; > In cases of issues, try: /CbSet debug 3
;
; (*) NOTE: Alternatively, leave password empty in API url and instead set:
;             1) in fish10 plugin: add a new key for user 'cbftp'
;             2) use micryption
;           ..this will use decrypted key as password in API url
;
;
; :: INITIAL SETUP
; -----------------------------------------------------------------------------
;
alias CbInit {
  set %cb_url https://:bestpass@127.0.0.1:62443
  set %cb_sites all
  set %cb_login myusername:SecretPassword
  set %cb_maxchars 4000
  ;; Show credits from SITE STAT output in own window *new*
  set %cb_creditwin 0
  set %cb_creditwname CRDS
}
;
; -----------------------------------------------------------------------------
;  CONFIG END
; -----------------------------------------------------------------------------


; API SITE COMMAND EXAMPLES:
; --------------------------
; Raw Commands: 
;    /CbRawCmd PWD, /CbRawCmd STAT -al /Path
; For SITE commands, call CbSiteCmd:
;   /CbSiteCmd WHO, /CbSiteCmd KICK foo, /CbSiteCmd DELUSER bar
; Or use aliases, set %cb_cmd to e.g. 'SITE USERS' and call CbCmd like:
;   /CbStat, CbDupe or /CbRequest
; These aliases can be also used as indentifier e.g. //echo test: $CbList(arg1, aag2, arg3)
;   /CbGetSites /CbSections /CbList
;
; By default cmds are send to %cb_sites as set by '/CbSet sites' or Settings menu
;
; To use specific site(s) for cmd and tmp override %cb_sites for ONE run of CbCmd:
;   set %cb_cmd_sites to SITE1,SITE1,...
;   or use alias: /CbCmdSites

alias CbCmdSites {
  set %cb_cmd_sites $1- | echo -ast CBAPI: cb_cmd_sites set to: $1-
}


;; RAW <cmd> [args]

alias CbRawCmd {
  set %cb_cmd RAW | CbCmd $1-
}

;; SITE <cmd> [args]

alias CbSiteCmd {
  set %cb_cmd SITE | CbCmd $1-
}

;; SITE INVITE [nick]

alias CbInvite {
  if ($1) {
    var %nick = $1
    if ($2) {
      set %cb_cmd_sites $2
    }
  }
  else {
    var %i = 0 | while ($scon(0) > %i) {
      if ( $scon(%i).$network = $1 ) {   
        var %nick = $scon(%i).me
      }
      inc %i
    }
  }
  if (%nick) { set %cb_cmd SITE INVITE | CbCmd %nick }
}

;; SITE DUPE <query>

alias CbDupe { 
  if ($1) {
    set %cb_cmd SITE DUPE
    echo -ast CBDUPE: " $+ $1- $+ " ( $+ $CbArray(%cb_sites) $+ )
    CbCmd $1-
  }
  else { $CbError(DUPE,query) }
}

;; SITE SEARCH <query>

alias CbSearch {
  if ($1) {
    set %cb_cmd SITE SEARCH
    echo -ast CBSEARCH: " $+ $1- $+ " on sites: $CbArray(%cb_sites)
    CbCmd $1-
  }
  else { $CbError(SEARCH,query) }
}

;; SITE REQUEST <release>

alias CbReq {
  if ($1) { set %cb_cmd SITE REQUEST | CbCmd $1- }
  else { $CbError(REQ,release) }
}

;; SITE STAT

alias CbStat {
  set %cb_cmd SITE STAT | CbCmd
}


; GET SITES COMMAND:
; ------------------
; Handles all 'sites' related stuff e.g. list all sites or details for 1 site
; By default sends 'GET /sites' to cbftpd api and returns formatted site names
; Used by: /CbSite, 'SITE INVITE' and the site list in the 'Settings' menu

;; CbGetSites [site] [section] or [filter]  (default: all sites)

alias CbGetSites {
  .CbCheck
  JSONClose -w cbftp*
  var %cb_hn = cbftp $+ $rand(1,10000)
  var %cb_urn = /sites
  ; List all sites (default)
  var %mode = all
  if ($1) {
    ; Section filter
    if (section= isin $1) {
      %cb_urn = %cb_urn $+ ? $+ $1
    }
    ; Get sections for a site
    elseif (/sections isin $1-) {
      %cb_urn = %cb_urn $+ / $+ $1-
      %mode = site_sections
    }
    ; Single section for site
    elseif ($1 && $2) {
      %cb_urn = %cb_urn $+ / $+ $1 $+ /sections/ $+ $2
      %mode = site_onesec
    }
    ; Show site details
    else {
      %mode = site_details
      %cb_urn = %cb_urn $+ / $+ $1
    }
  }
  var %cb_method = GET
  JSONOpen -uwi %cb_hn $CbUri(%cb_url,%cb_urn)
  CbHttpHeaders %cb_hn
  JSONHttpFetch %cb_hn
  if (%cb_debug >= 2) {
    echo -ast DEBUG: CbGetSites HttpDebug.. | echo $CbHttpDebug(%cb_url,%cb_urn,%cb_hn,%cb_method,%cb_data)
  }
  if (!$JSONError) {
    if (%cb_debug >= 2) {
      echo -ast DEBUG: CbGetSites OK (no JSONError)
    }
    if (%mode == site_details) {
      var %attr = addresses user max_logins
      var %ntok = $numtok(%attr,32)
      var %i = 1
      var %result = $null
      while (%i <= %ntok) {
        var %tok = $gettok(%attr,%i,32)
        %result = %result %tok $+ : $json(%cb_hn, $+ %tok $+).String $+ $iif(%i < %ntok, $chr(44))
        inc %i
      }       
      if ($json(%cb_hn,sections).length > 0) {
        var %j = 0
        var %sections = $null
        while (%j < $json(%cb_hn,sections).length) {
          %sections = %sections $json(%cb_hn,sections,%j,name).String
          inc %j
        }
        %result = %result $+ ,  sections: %sections
      }
      if ($json(%cb_hn,affils).length > 0) {
        %affils = $regsubex($json(%cb_hn,affils).String,^\[(.*)\]$,\1))
        %result = %result $+ , affils: $replace(%affils,$chr(44), $chr(32))
      }
      echo -as CBSITES:  $+ $1  $+ > %result
    }
    elseif (%mode == site_sections) {
      var %i = 0 
      var %sections = $null
      var %len = $json(%cb_hn).length 
      while (%i < %len) {
        var %sections =  %sections $replace($json(%cb_hn,%i,name).String,",) $+ : $&
          $json(%cb_hn,%i,path).String  $+ $iif($calc(%i + 1) < %len, $chr(44))
        inc %i 
      }
      echo -as CBSITES: SECTIONS > %sections ( $+ %len  $+ sections)
    }
    elseif (%mode == site_onesec) {
      noop $regsub(res,$json(%cb_hn).HttpBody,/[{}]\s?/g,,%section)
      echo -as CBSITES: $1 > SECTION: %section

    }

    ;; All sites, dont format if called as identifier

    else {
      set %cb_getsites $replace($regsubex($json(%cb_hn).String,^\[(.*)\]$,\1),",)

      JSONClose -w cbftp*
      if ($isid) {
        return %cb_getsites
      }
      else {
        if (%cb_sites != all) {
          var %i = 1
          var %sites = $null
          while (%i <= $numtok(%cb_getsites,44)) {
            if ($numtok(%cb_getsites,44)) {
              if (" $+ $gettok(%cb_getsites,%i,44) $+ " isin %cb_sites) {
                %sites = %sites $gettok(%cb_getsites,%i,44)
              }
              else {
                %sites = %sites 14 $+ $gettok(%cb_getsites,%i,44)  $+ 
              }
            }
            inc %i
          }
        }
        else {
          %sites = $replace(%cb_getsites, $chr(44), $chr(32))
        }
      }
      ; .echo -as CBSITES: $replace(%cb_getsites,$chr(44), $chr(44) $chr(32)) (enabled: all)
      .echo -as CBSITES: %sites
    }
    if (%cb_debug >= 2) {
      echo -ast DEBUG: CbGetSites $  $+ json.debug $json(%cb_hn).debug
      echo -ast DEBUG: CbGetSites cb_getsites= $+ %cb_getsites
    }
  }
  else {
    if ($isid) {
      return $false
    }
    else {
      JSONClose %cb_hn
      echo -ast CBSITES: ERROR > JSONError $JSONError $JSON(%cb_hn).error (hn: %cb_hn uri: %cb_uri $+ )
    }
  }
}


;; CbSite calls CbGetSites (alias 'CbSites')
;; tries UPPERCASE sitename if lowercase site not found

alias CbSite {
  if ($1 && !$regex($1,/section=|/sections/) && !$2 && !$3) {
    if ($CbGetSites($1-) == $false) {
      if (%cb_debug >= 2) { echo -ast DEBUG: CbSite $1 not found, trying uppercase... }
      noop $CbGetSites($upper($1) $2-))
    }
  }
  else {
    CbGetSites $1-
  }
}
alias CbSites { CbSite $1- }



; TRANSFER CMDS & SITE MGMT API EXAMPLES:
; ---------------------------------------

;; GET /spreadjobs : [filter]

alias CbGetSpread {
  set %cb_cmd GETSPREAD | CbCmd $1- 
}

;; GET /transferjobs : [filter]

alias CbGetXfer {
  set %cb_cmd GETTRANSFERS | CbCmd $1- 
}

;; GET /sections [section]  (no arg: show all)

alias CbSection {
  set %cb_isid $isid
  set %cb_cmd GETSECTIONS | CbCmd $1-
}
alias CbSections { set %cb_isid $isid | CbSection $1- }

;; GET /filelist : <site> [path] [timeout]

alias CbList {
  if ($1) { 
    set %cb_isid $isid
    set %cb_cmd FILELIST | CbCmd $1- 
  }
  else { $CbError(LIST,site) }
}

;; INCOMPLETES : <section> <dstsite> <srcsite>  (uses filelist)

alias CbInc {
  if (($1 && (/ !isin $1)) && $2 && $3) {
    set %cb_cmd INCOMPLETES | CbCmd $2 $1 5 $3
  }
  else { $CbError(INC,section $+ $chr(44) dstsite or srcsite) }
}

;; POST /spreadjobs/JOBNAME/reset

alias CbResetSpread {
  if ($1) { set %cb_cmd RESETSPREAD | CbCmd $1- }
  else { $CbError(SPREAD,release) }
}

;; POST /spreadjobs/JOBNAME/abort

alias CbAbortSpread {
  if ($1) { set %cb_cmd ABORTSPREAD | CbCmd $1- }
  else { $CbError(SPREAD,release) }
}

;; POST /transferjobs/JOBNAME/reset (no body)

alias CbResetXfer {
  if ($1) { set %cb_cmd RESETTRANSFER | CbCmd $1- }
  else { $CbError(TRANSFER,release) }
}

;; POST /transferjobs/JOBNAME/abort (no body)

alias CbAbortXfer {
  if ($1) { set %cb_cmd ABORTTRANSFER | CbCmd $1- }
  else { $CbError(TRANSFER,release) }
}

;; DELETE /sites/SITE1 : <site>

alias CbDelSite {
  if ($1) { set %cb_cmd DELSITE | CbCmd $1- }
  else { $CbError(SITE,site to delete) }
}

;; DELETE /sites/SITE1/sections/SECTIONNAME : <site> <section>

alias CbDelSiteSection {
  if ($1) { set %cb_cmd DELSITESECTION | CbCmd $1- }
  else { $CbError(SITE,site and section to delete) }
}

;; DELETE /sections/SECTIONNAME : <section>

alias CbDelSection {
  if ($1) { set %cb_cmd DELSECTION | CbCmd $1- }
  else { $CbError(SECTION,section to delete) }
}


; JSON TEMPLATES
; --------------
; Commands like CbFxp, CbAddSite and CbSpread use JSON 'templates' in POST requests
; Usage: - always replace chars { } with $chr(123), 125 and [ ] with 91, 93
;        - these 2 chars $& mean 'continue on next line'
;        - changes json values using regexps, seems the 'best' way...

;; POST /transferjobs > FXP: <section> <srcsite> <dstsite> <release>

alias CbFxp {
  if (($1) && ($2) && ($3) && ($4)) {
    var %cb_tmpl_fxp_job = $chr(123)   $&
      "src_site": " $+ $2 $+ ",   $&
      "src_section": " $+ $1 $+ ",   $&
      "dst_site": " $+ $3 $+ ",   $&
      "dst_section": " $+ $1 $+ ",   $&
      "name": " $+ $4 $+ "   $&
      $chr(125)

    ; NOTE:
    ;  dst_path: dst_section or dst_path 
    ;  src_path: optional 

    if (%cb_debug >= 1) { echo -ast DEBUG: CbFxp cb_tmpl_fxp_job = %cb_tmpl_fxp_job }
    set %cb_cmd TRANSFER | CbCmd %cb_tmpl_fxp_job
  }
  else {
    $CbError(FXP,section $+ $chr(44) srcsite $+ $chr(44) dstsite or release)
  }
}

;; POST /transferjobs > DOWN: <site> <section> <release> [dstpath]

alias CbDown {
  if (($1) && ($2) && ($3)) { 
    var %cb_tmpl_down_job = $chr(123)   $&
      "src_site": " $+ $1 $+ ",   $&
      "src_section": " $+ $2 $+ ",   $&
      "name": " $+ $3 $+ ",   $&
      "dst_path": " $+ $iif($4,$v1,/tmp) $+ "   $&
      $chr(125)

    ; NOTE:
    ;  src_section: src_section or src_path
    ;  dst_path: optional

    if (%cb_debug >= 1) { echo -ast DEBUG: CbDown cb_tmpl_down_job = %cb_tmpl_down_job }
    set %cb_cmd TRANSFER | CbCmd %cb_tmpl_down_job
  }
  else {
    $CbError(DOWN,site $+ $chr(44) release or section)
  }
}

;; POST /transferjobs > UP: <site> <section> <release> [dstpath]

alias CbUp {
  if (($1) && ($2) && ($3)) { 
    var %cb_tmpl_up_job  = $chr(123)   $&
      "src_site": " $+ $1 $+ ",   $&
      "src_section": " $+ $2+ ",  $&
      "name": " $+ $3 $+ ",   $&
      "dst_path": " $+ $iif($4,$v1,/tmp) $+ "   $&
      $chr(125)

    ; NOTE:
    ;  dst_path: dst_section or dst_path
    ;  src_path: optional

    if (%cb_debug >= 1) { echo -ast DEBUG: CbUp cb_tmpl_up_job = %cb_tmpl_up_job }
    set %cb_cmd TRANSFER | CbCmd %cb_tmpl_up_job
  }
  else {
    $CbError(UP,site $+ $chr(44) section or release)
  }
}

;; POST /sites > ADD: <site> <bnc> or <bnc1,bnc2>

alias CbAddSite {
  if (($1) && ($2)) { 
    var %name = $1
    var %bncs = $2-
    ;
    ; site 'template'
    ;
    var %cb_tmpl_site = $chr(123)   $&
      "name": "",   $&
      "addresses": "",   $&
      "allow_download": "YES",   $&
      "allow_upload": "YES",   $&
      "base_path": "/",   $&
      "broken_pasv": false,   $&
      "cepr": true,   $&
      "cpsv": true,   $&
      "disabled": false,   $&
      "force_binary_mode": false,   $&
      "leave_free_slot": true,   $&
      "list_command": "STAT_L",   $&
      "max_idle_time": 60,   $&
      "max_logins": 3,     $&
      "max_sim_down": 2,   $&
      "max_sim_down_complete": 0,   $&
      "max_sim_down_pre": 0,   $&
      "max_sim_down_transferjob": 0,   $&
      "max_sim_up": 3,   $&
      "password": "",   $&
      "pret": false,   $&
      "priority": "HIGH",   $&
      "sscn": false,   $&
      "stay_logged_in": false,   $&
      "tls_mode": "AUTH_TLS",   $&
      "tls_transfer_policy": "PREFER_OFF",   $&
      "transfer_protocol": "IPV4_ONLY",   $&
      "transfer_source_policy": "ALLOW",   $&
      "transfer_target_policy": "BLOCK",   $&
      "user": "",   $&
      "xdupe": true   $&
      $chr(125)

    ; NOTE:
    ;
    ;  optional attributes
    ;
    ;    "allow_download": (YES/NO/MATCH_ONLY)
    ;    "allow_upload": (YES/NO)
    ;    "avg_speed": { "S1": 20000, "S2": 30000 }  speed SITE1 -> SITE2
    ;    "list_command": (STAT_L/LIST)
    ;    "priority": (VERY_LOW/LOW/NORMAL/HIGH/VERY_HIGH)
    ;    "list_frequency": (VERY_LOW/FIXED_LOW/FIXED_AVERAGE/ 
    ;                      FIXED_HIGH/FIXED_VERY_HIGH/AUTO/
    ;                      DYNAMIC_LOW/DYNAMIC_AVERAGE/
    ;                      DYNAMIC_HIGH/DYNAMIC_VERY_HIGH)
    ;    "proxy_type": (GLOBAL/NONE/USE)
    ;    "skiplist": [ {"action": (ALLOW/DENY/UNIQUE/SIMILAR) } ]
    ;    "tls_mode": "AUTH_TLS": (NONE/AUTH_TLS/IMPLICIT)
    ;    "tls_transfer_policy": (ALWAYS_OFF/PREFER_OFF/...)
    ;    "transfer_protocol": (IPV4_ONLY/PREFER_IPV4/...)
    ;    "transfer_source_policy": (ALLOW/BLOCK)

    ;; removed: "sections": $chr(91) $chr(123) "name": "SEC1", "path": "" $chr(125) $chr(93) ,   $&
    ;; removed:  noop $regsubex(cb,%cb_tmpl_site, ("name": "SEC1", "path":) "" ,\1 "/sec1", %cb_tmpl_site)

    noop $regsubex(cb_site, %cb_tmpl_site, ("name":) "" $+ $chr(44),     \1 " $+ %name $+ " $+ $chr(44), %cb_tmpl_site)
    noop $regsubex(cb_site, %cb_tmpl_site, ("addresses":) "" $+ $chr(44),\1 $+ $CbArray(%bncs) $+ $chr(44), %cb_tmpl_site)
    noop $regsubex(cb_site, %cb_tmpl_site, ("user":) "" $+ $chr(44),     \1 " $+ $CbLogin(u %cb_login) $+ " $+ $chr(44), %cb_tmpl_site)
    noop $regsubex(cb_site, %cb_tmpl_site, ("password":) "" $+ $chr(44), \1 " $+ $CbLogin(p %cb_login) $+ " $+ $chr(44), %cb_tmpl_site)

    if (%cb_debug >= 1) { echo -ast DEBUG: CbAddSite cb_tmpl_site = %cb_tmpl_site }
    ;return
    set %cb_cmd ADDSITE | CbCmd %cb_tmpl_site
  }
  else {
    $CbError(SITE,site and bncs(s))
  }
}

;; POST /sites/SITE1/sections : <site> <section> <path>

alias CbAddSiteSection {
  if ($1 && $2 && &3) {
    var %cb_tmpl_section = $chr(123) "name": " $+ $2 $+ ", "path": " $+ $3 $+ " $chr(125)
    if (%cb_debug >= 1) { echo -ast DEBUG: CbAddSiteSection cb_tmpl_section = %cb_tmpl_section }
    set %cb_cmd ADDSITESECTION | CbCmd $1 %cb_tmpl_section
  }
  else {
    $CbError(SECTION,site $+ $chr(44) section and path to add)
  }

}

;; POST /sections > ADD: <section>

alias CbAddSection {
  if ($1) { 
    var %name = $1
    ;
    ; section 'template'
    ;
    var %cb_tmpl_section = $chr(123)   $&
      "name": "",   $&
      "skiplist": $chr(91)   $&
      $chr(123)   $&
      "action": "DENY",   $&
      "dir": false,   $&
      "file": true,   $&
      "pattern": "",   $&
      "regex": false,   $&
      "scope": "ALL"   $&
      $chr(125)   $&
      $chr(93)   $&
      $chr(125)   

    ; NOTE:
    ;  "hotkey": optional, 0-9
    ;  "action":(ALLOW/DENY/UNIQUE/SIMILAR)
    ;  "scope": (IN_RACE/ALL)

    noop $regsubex(cb_section, %cb_tmpl_section, ("name":) "" $+ $chr(44), \1 " $+ %name $+ " $+ $chr(44), %cb_tmpl_section)

    if (%cb_debug >= 1) { echo -ast DEBUG: CbAddSection %cb_tmpl_section }
    set %cb_cmd ADDSECTION | CbCmd %cb_tmpl_section
  }
  else {
    $CbError(ADDSECTION,section)
  }
}

;; POST /spreadjobs > STARTNEW : <section> <release> [sites]

alias CbSpread {
  if (($1) && ($2)) {
    %cb_spread_sites = %cb_sites
    if ($3) {
      var %cb_spread_sites = $3
    }
    if (%cb_debug >= 1) { echo -ast DEBUG: CbSpread cb_spread_sites = %cb_spread_sites }
    ;
    ; spread 'template'
    ;
    var %cb_tmpl_spread = $chr(123)   $&
      "section": " $+ $1 $+ ",   $&
      "name": " $+ $2 $+ ",   $&
      "sites": "",   $&
      "sites_dlonly": "",   $&
      "sites_all": true,   $&
      "reset": true,   $&
      "profile": "RACE"   $&
      $chr(125)

    ; NOTE:
    ;  sites_dlonly: (optional)
    ;  sites_all: (optional) whether to add all sites with the section defined
    ;  reset: (optional) whether to reset the job if it already exists
    ;  profile: RACE/DISTRIBUTE/PREPARE

    noop $regsubex(cb_spread, %cb_tmpl_spread, ("section":) "" $+ $chr(44), \1 " $+ $1 $+ " $+ $chr(44), %cb_tmpl_spread)
    noop $regsubex(cb_spread, %cb_tmpl_spread, ("name":) "" $+ $chr(44),    \1 " $+ $2 $+ " $+ $chr(44), %cb_tmpl_spread)
    if (%cb_spread_sites == all) {
      if (%cb_debug > 1) { echo -ast DEBUG: CbSpread got 'all' }
      noop $regsubex(cb_spread, %cb_tmpl_spread, "sites": "" $+ $chr(44),,%cb_tmpl_spread)
    }
    else { 
      noop $regsubex(cb_spread, %cb_tmpl_spread, ("sites":) "" $+ $chr(44), \1 $CbArray(%cb_spread_sites) $chr(44), %cb_tmpl_spread)
      noop $regsubex(cb_spread, %cb_tmpl_spread, "sites_all": true $+ $chr(44),,%cb_tmpl_spread)
    }

    if (%cb_debug >= 1) { echo -ast DEBUG: CbSpread cb_tmpl_spread = %cb_tmpl_spread }
    return

    set %cb_cmd SPREAD | CbCmd %cb_tmpl_spread
  }
  else {
    $CbError(SPREAD,section and release)
  }
}

;; PATCH /sites/SITE1 : <site> <bnc> or <bnc1,bnc2>

alias CbModSite {
  if (($1) && ($2)) {
    var %cb_site = $chr(123) "name": " $+ $1 $+ ",  "addresses": $CbArray($2) $chr(125)
    if (%cb_debug >= 1) { echo -ast DEBUG: CbModSite %cb_tmpl_site }
    set %cb_cmd MODSITE | CbCmd $1 %cb_tmpl_site
  }
  else {
    $CbError(SITE,site and bncs(s) to modify)
  }
}

;; PATCH /sections/SECTIONNAME : <section> <newname>

alias CbModSection {
  if ($1) { 
    var %cb_tmpl_section = $chr(123) "name": " $+ $2 $+ " $chr(125)   
    if (%cb_debug >= 1) { echo -ast DEBUG: CbModSection %cb_tmpl_section = %cb_tmpl_section }
    set %cb_cmd MODSECTION | CbCmd $1 %cb_tmpl_section
  }
  else {
    $CbError(SECTION,section)
  }
}

;; PATCH /sites/SITE1/sections/SECTIONNAME : <site> <section> <path>

alias CbModSiteSection {
  if ($1 && $2 && &3) {
    var %cb_tmpl_section = $chr(123) "path": " $+ $3 $+ " $chr(125)
    if (%cb_debug >= 1) { echo -ast DEBUG: CbModSiteSection cb_tmpl_section = %cb_tmpl_section }
    set %cb_cmd MODSITESECTION | CbCmd $1 $2 %cb_tmpl_section
  }
  else {
    $CbError(SECTION,site $+ $chr(44) section and path to add)
  }

}


; CbCmd: SEND/RECEIVE JSON
; ------------------------
; Using 'JSON For Mirc' CbCmd sends command to the CB API and handles result

alias -l CbCmd {
  var %cb_args = $1-
  .CbCheck
  if (%cb_cmd_sites) {
    set %cb_savesites %cb_sites
    set %cb_sites %cb_cmd_sites
  }
  if (!%cb_sites) {
    echo -ast CBCMD: INFO > no sites selected, using 'all' (try /CbHelp)
    set %cb_sites all
    unset %cb_savesites
  }
  if (!%cb_cmd) {
    $CbError(SPREAD,command) | return
  }

  ;; Handle SITE and RAW command to /raw endpoint for 1 or more or all site(s)

  ; NOTE:
  ;  sites: run on these sites
  ;  sites_with_sections: run on sites with these sections defined
  ;  sites_all: run on all sites
  ;  path: the path to cwd to before running command
  ;  path_section: section to cwd to before running command
  ;  timeout: max wait before failing
  ;  async: if false, wait for command to finish before responding.
  ;         if true, respond with a request id and let command run in the background

  if ($regex(%cb_cmd,/^(SITE\s?|RAW)/)) {
    if (%cb_cmd == RAW) {
      set %cb_cmd %cb_args
      unset %cb_args
    }
    var %cb_urn = /raw
    var %cb_method = POST
    if (%cb_sites == all) {
      var %cb_data = {"command": " $+ %cb_cmd $+ $iif(%cb_args,$chr(32) $v1) $+ ",   $&
        "sites_all": true,   $&
        "path":"/",   $& 
        "timeout":10,   $& 
        "async":false}
    }
    else {
      var %cb_data = {"command": " $+ %cb_cmd $+ $iif(%cb_args,$chr(32) $v1) $+ ",    $&
        "sites": $CbArray(%cb_sites) $+ , $&
        "path":"/",   $&
        "timeout":10,   $&
        "async":false}
    }
    unset %cb_cmd_sites
  }

  ;; Handle other commands: sites, sections, transfer, ...
  ;; set api url, http request method and json data

  elseif (%cb_cmd == ADDSITE) {
    var %cb_urn = /sites
    var %cb_method = POST
    var %cb_data = $1-
  }
  elseif (%cb_cmd == DELSITE) {
    var %cb_urn = /sites/ $+ $1
    var %cb_method = DELETE
  }
  elseif (%cb_cmd == SPREAD) {
    var %cb_urn = /spreadjobs
    var %cb_method = POST
    var %cb_data = $1-
  }
  elseif (%cb_cmd == TRANSFER) {
    var %cb_urn = /transferjobs
    var %cb_method = POST
  }
  elseif (%cb_cmd == ABORTSPREAD) {
    var %cb_urn = /spreadjobs/ $+ $1 $+ /abort
    var %cb_method = POST
  }
  elseif (%cb_cmd == RESETSPREAD) {
    var %cb_urn = /spreadjobs/ $+ $1 $+ /reset
    var %cb_method = POST
  }
  elseif (%cb_cmd == ABORTTRANSFER) {
    var %cb_urn = /transferjobs/ $+ $1 $+ /abort
    var %cb_method = POST
  ;; Initial Setup 
  }
  elseif (%cb_cmd == RESETTRANSFER) {
    var %cb_urn = /transferjobs/ $+ $1 $+ /reset
    var %cb_method = POST
  }
  elseif (%cb_cmd == ADDSECTION) {
    var %cb_urn = /sections
    var %cb_method = POST
    var %cb_data = $2-
  }
  elseif (%cb_cmd == GETSPREAD) {
    var %cb_urn = /spreadjobs $+ $iif($1-,/ $+ $v1)
    var %cb_method = GET
  }
  elseif (%cb_cmd == GETSECTIONS) {
    var %cb_urn = /sections $+ $iif($1-,/ $+ $v1)
    var %cb_method = GET
  }
  elseif (%cb_cmd == GETTRANSFERS) {
    var %cb_urn = /transferjob $+ $iif($1-,/ $+ $v1)
    var %cb_method = GET
  }
  elseif (%cb_cmd == DELSECTION) {
    var %cb_urn = /sections/ $+ $1
    var %cb_method = DELETE
  }
  elseif (%cb_cmd == ADDSITESECTION) {
    var %cb_urn = /sites/ $+ $1 $+ /sections
    var %cb_method = POST
    var %cb_data = $2-
  }
  elseif (%cb_cmd == DELSITESECTION) {
    var %cb_urn = /sites/ $+ $1 $+ /sections/ $+ $2
    var %cb_method = DELETE
  }
  elseif (%cb_cmd == MODSITE) {
    var %cb_urn = /sites/ $+ $1
    var %cb_method = PATCH
    var %cb_data = $2-
  }
  elseif (%cb_cmd == MODSECTION) {
    var %cb_urn = /sections/ $+ $1
    var %cb_method = PATCH
    var %cb_data = $2-
  }
  elseif (%cb_cmd == MODSITESECTION) {
    var %cb_urn = /sites/ $+ $1 $+ /sections/ $+ $2
    var %cb_method = PATCH
    var %cb_data = $3-
  }
  elseif ($regex(%cb_cmd,/^(FILELIST|INCOMPLETES)/)) {
    var %cb_urn = /filelist?site= $+ $1 $+ &path= $+ $iif($2,$v1,/) $+ $iif($3,&timeout= $+ $v1)
    var %cb_method = GET
  }
  else {
    echo -ast CBCMD: ERROR > unsupported command
    return
  }

  set %cb_gotres 0

  ;; Call 'JSONFormIRC' to get data from API

  JSONClose -w cbftp*
  var %cb_hn = cbftp  $+ $rand(1,10000)
  JSONOpen -uwi %cb_hn $CbUri(%cb_url,%cb_urn)
  CbHttpHeaders %cb_hn
  JSONHttpMethod %cb_hn %cb_method
  JSONHttpFetch %cb_hn %cb_data
  if (%cb_debug >= 2) {
    echo $CbHttpDebug(%cb_url,%cb_urn,%cb_hn,%cb_method,%cb_data)
    echo $JSON(%cb_hn).debug
  }
  if (%cb_debug >= 4) {
    echo -ast DEBUG: HttpResponse $json(%cb_hn).HttpResponse
    echo -ast DEBUG: HttpStatus $json(%cb_hn).HttpStatus 
    echo -ast DEBUG: HttpStatusText $json(%cb_hn).HttpStatusText
    echo -ast DEBUG: HttpHeaders $json(%cb_hn).HttpHeaders
    echo -ast DEBUG: HttpHeader $json(%cb_hn).HttpHeader
    echo -ast DEBUG: HttpBody $json(%cb_hn).HttpBody
  }

  ;; Check JSON for error and handle results

  if (!$JSONError) { 
    if (%cb_debug >= 1) {
      echo -ast DEBUG: CbCmd OK, no JSONError
    }

    ;; HTTP Status 201+ succesful, 4xx: client error and 5xx: server error

    if ($regex($JSON(%cb_hn).HttpStatus,/^2(0[1-9]|[1-9][0-9])$/)) {
      echo -as CBAPI: OK > $JSON(%cb_hn).HttpStatus $JSON(%cb_hn).HttpStatusText   
      JSONClose %cb_hn
      return
    }
    if ($regex($JSON(%cb_hn).HttpStatus,/^[4-5]\d\d$)) {
      echo -ast CBAPI: ERROR > $JSON(%cb_hn).HttpStatus $JSON(%cb_hn).HttpStatusText $JSON(%cb_hn).HttpBody
      JSONClose %cb_hn
      return
    }

    ;; DELSITE/SECTION: HTTP Status 2xx and a non-empty reponse

    elseif ($regex(%cb_cmd,/^DEL(SITE|SECTION)/)) {
      if ($regex($json(%cb_hn).HttpStatus,/^2/)) { 
        if ($json(%cb_hn).length > 0) {
          set %cb_gotres 1 
        }
      }
    }

    ;; Show array with all sections names

    elseif (%cb_cmd == GETSECTIONS) {
      if ($regex($json(%cb_hn).HttpStatus,/^2/)) { 
        if ($json(%cb_hn).length > 0) {
          set %cb_gotres 1
          if ($1) {
            noop $regsubex(res,$json(%cb_hn).HttpBody,/[{}]/g,,%details)
            echo -as CBSITES: SECTION >  $+ $1 $+  $+ %details
          }
          else {
            var %i = 0 
            var %sections = $null
            while (%i < $json(%cb_hn).length) {
              var %sections = $json(%cb_hn,%i,name).String %sections
              inc %i
            }
            set %cb_getsections $replace(%sections,",)
            if (%cb_isid == $true) {
              echo  %cb_getsections
            }
            else {
              echo -as CBSITES: ALL SECTIONS > %sections ( $+ $json(%cb_hn).length  $+ sections)
            }
          }
        }
      }
    }

    ;; Walk JSON calling CbSiteItem for each site item

    ;elseif ($regex(%cb_cmd,/^(SITE|GET)/)) {
    elseif ($regex(%cb_cmd,/^SITE (DUPE|SEARCH|STAT)$/)) {
      echo -as $crlf
      if (%cb_sites) {
        var %cb_len = 0
        if ($json(%cb_hn).length > 0) {
          var %cb_len = $json(%cb_hn).length
        }
        if (%cb_debug >= 2) {
          echo -ast DEBUG: JSONForEach walk (cb_len= $+ %cb_len $+ )
        }
        noop $JSONForEach(%cb_hn,CbSiteItem %cb_len).walk
      }
    }

    ;; Parse JSON and call CbFileItem or CbIncItem for each dir name

    elseif (%cb_cmd == FILELIST) {
      set -eu30 %cnt_inc 0
      set -eu30 %cnt_nuked 0
      noop $JSONForEach(%cb_hn,CbFileItem $1 $2,name)
      if (%cb_isid == $false && $json(%cb_hn).length > 1) {
        echo -as CBLIST: $1 $2  $+ $json(%cb_hn).length $+  items $+ $&
          $iif(%cnt_inc > 0,$chr(44)  $+ %cnt_inc $+  incomplete) $+ $&
          $iif(%cnt_nuked > 0,$chr(44)  $+ %cnt_nuked $+  nuked)
      }
    }
    elseif (%cb_cmd == INCOMPLETES) {
      noop $JSONForEach(%cb_hn,CbIncItem $1-,name)
    }
  }
  else {

    ;; JSONError but with HTTP status 2xx

    if ($regex($JSON(%cb_hn).HttpStatus,/^2\d\d$)) {
      set %cb_gotres 1
      noop $regsub($JSON(%cb_hn).HttpResponse,/\n/, $chr(44) $chr(32) ,%fmtres)
      echo -as CBAPI: OK > %fmtres
    }
    else {    
      echo -ast CBAPI: ERROR > JSONError $JSONError $JSON(%cb_hn).error (hn: %cb_hn uri: %cb_uri $+ )
    }
    JSONClose %cb_hn
    return
  }

  ;; Got no results, try to show useful response

  var %cb_response = $json(%cb_hn).HttpResponse
  JSONClose -w cbftp*
  if (%cb_gotres == 0) {
    noop $regsubex(res,%cb_response,/(Content-Length: \d+|Content-Type: application/json)/g,,%r)
    if ($regex(%cb_cmd,/^SITE (DUPE|SEARCH)$/)) {
      noop $regsubex(res,%r,/\(Values displayed after dir names are Files/Megs/Age\)/g, ,%r)
      noop $regsubex(res,%r,/Doing case-insensitive search for '.+':/g, ,%r)
    }
    noop $regsubex(res,%r,/Command Successful./g, ,%r)
    noop $regsubex(res,%r,/("?200[- ]|[\]\[{}]|\\r\\n)/g,,%r)
    noop $regsubex(res,%r,/:\s $+ $chr(44),: none $+ $+ $chr(44),%r)
    noop $regsubex(res,%r,/\s\s\s/g, ,%r)
    if (%cb_cmd == INCOMPLETES) {
      echo -ast CBINC: no incompletes found
    }
    else {
      echo -ast CBAPI: $iif(%r, STATUS > ' $+ $v1 $+ ',empty response or no results)
    }
    echo -as $crlf
  }
  if (%cb_savesites) {
    set %cb_sites %cb_savesites
    unset %cb_savesites
  }
  if (%cb_debug >= 1) {
    echo -ast DEBUG: ---
    echo -ast DEBUG: END
    echo -ast DEBUG: ---
  }
}


; JSONItem
; --------

; handle JSON items in $JSONForEach, call CbSiteResult, CbFileItem or CbIncItem

;; CbSiteItem: meant to handle multiple sites (e.g. SITE DUPE or SEARCH)
;; It will call 'CbSiteResult' to output formatted results:
;;   SITE1 /RESULT/PATH/Foo-Dir (9F/10M/1d)
;;   SITE2 /More/Results/Bar-Dir (1F/1M/30d 1h)

alias CbSiteItem {
  ; Args: 1=%cb_len 2=<item>  
  var %cb_cmax = 8000
  var %cb_sitenum = $regsubex($json($2-).path,/.* (\d+) .*/,\1)
  var %cb_bvar = $JSONItem(valuetobvar)
  var %cb_blen = $bvar(%cb_bvar,0)
  if ((%cb_maxchars > 0) && (%cb_blen > %cb_maxchars)) {
    var %cb_trun = $calc(%cb_blen - %cb_cmax)
    echo -as CBAPI: WARNING result of %cb_blen characters of is over limit of %cb_maxchars ( $+ %cb_trun characters truncated)
    var %cb_blen = %cb_maxchars
  }
  if (%cb_blen > %cb_cmax ) {
    var %cb_trun = $calc(%cb_blen - %cb_cmax) 
    echo -as CBAPI: ERROR result of %cb_blen characters is too large ( $+ %cb_trun characters truncated)
    var %cb_blen = %cb_cmax
  }  
  var %cb_btxt = $bvar(%cb_bvar,1,%cb_blen).text
  var %cb_ntok = 
  var %i = 1 | while (%i <= $numtok($json($2).path,32)) {
    var %cb_gettok = $gettok($json($2).path,%i,32)
    inc %i
  }
  if (%cb_debug >= 2) {
    echo -ast DEBUG: CbSiteItem cb_blen= $+ %cb_blen len_bvar= $+ $len($bvar(%cb_bvar,1,9999).text)
    echo -ast DEBUG: CbSiteItem cb_sitenum= $+ %cb_sitenum json.length= $+ $json($2).length json.path= $+ $json($2-).path
    echo -ast DEBUG: CbSiteItem cb_ntok= $+ %cb_ntok cb_gettok= $+ %cb_gettok
    if (%cb_debug >= 3) { echo -ast DEBUG: CbSiteItem cb_btxt= $+ %cb_btxt }
  }
  if ((%cb_btxt) && (%cb_gettok == name)) {
    set -eu5 %cb_name %cb_btxt
  }
  elseif ((%cb_btxt) && (%cb_gettok == result)) {
    CbSiteResult $iif(%cb_sitenum,$v1,0) $iif($1,$v1,0) $iif(%cb_name,$v1,SITE) %cb_btxt 
  }
  elseif ((%cb_sitenum == error) || (%cb_gettok == error) || (json.path == error)) {
    echo -as CBAPI: ERROR got: ' $+ %cb_btxt $+ '
  }
}

;; CbFileItem: Show filelist items

alias CbFileItem {
  ; Args: 1=site 2=section
  var %re_inc = /^\((incomplete|no-(nfo|sample|sfv))\)-/
  var %re_nuked = /^.?NUKED.?-
  set %cb_gotres 1
  if (%cb_isid == $false) {
    if ($regex($JSONItem(Value),/^[._-]/)) {
      echo -as CBLIST: $1 $2 14 $+ $JSONItem(Value) $+ 
    }
    elseif ($regex($JSONItem(Value),%re_inc)) {
      inc %cnt_inc
      echo -as CBLIST: $1 $2 4 $+ $JSONItem(Value) $+ 
    }
    elseif ($regex($JSONItem(Value),%re_nuked)) {
      inc %cnt_nuked
      echo -as CBLIST: $1 $2 4 $+ $JSONItem(Value) $+ 
    }
    else {
      echo -as CBLIST: $1 $2  $+ $JSONItem(Value) $+ 
    }
  }
  else {
    echo $1 $JSONItem(Value)
  }
}

;; CbIncItem: Fxp incomplete items from specified src site

alias CbIncItem {
  ; Args: 1=section 2=dstsite 4=srcsite 
  var %inc_re = /^\((incomplete|no-(nfo|sample|sfv))\)-/
  if ($regex($JSONItem(Value), %inc_re)) {
    set %cb_gotres 1
    noop $regsub($JSONItem(Value),%inc_re,,%release)
    echo -as CBINC:  $+ $JSONItem(Value) $+ 
    .CbFxp $2 $4 $1 %release
  }
}


;; CbSiteResult: format site results
;; use regexps to clean up result then output lines split on CR

alias -l CbSiteResult {
  ; Args: 1=%cb_sitenum 2=%cb_len 3=%cb_name 4=%cb_result
  if (%cb_raw) {
    var %cb_result = $4-
  }
  else {
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
    ;; SITE STAT results
    elseif (%cb_cmd == SITE STAT) {
      var %cb_result = $4-
      noop $regex(%cb_result,/.*\r\n.*\[Credits: ([\d.]+)([MGT]i?B)\].*\r\n.*/)
      var %credits = 0
      var %crednum = $regml(1)
      var %credunit = $regml(2)
      if (%crednum && %credunit) {
        if ($regex(%credunit,/Mi?B/)) {
          var %credits = $round($calc($round(%crednum,1)/1024),2) GiB
        }
        elseif ($regex(%credunit,/Gi?B/)) {
          var %credits = %crednum GiB
        }      
        elseif ($regex(%credunit,/Ti?B/)) {
          var %credits = $round($calc($round(%crednum,1)*1024),2) GiB
        }
      }
      if (%cb_creditwin) {
        if (!$window(@ $+ %cb_creditwname )) { /window -lnk0g1z @ $+ %cb_creditwname Fixedsys 9 }
        .window -g0 @ $+ %cb_creditwname
        .window -z @ $+ %cb_creditwname
        .aline @ $+ %cb_creditwname $chr(91) $+ $date(mmdd) $+ ][ $+ $time $+ ] Credits on  $+ $3 $+ :3 %credits 
      }

    }
    ;; other results
    else {
      var %cb_result = %cb_re_all
    }
    var %cb_resnum = $gettok(%cb_result,0,13)
    if (%cb_result) {
      var %cnt = 1 | while (%cnt < %cb_resnum) {
        ;; debug output: SITENAME ( sitenum/all_sites result_line/total_lines ) <result>
        if (%cb_debug >= 3)  {
          echo -as CBAPI:  $+ $3 $+  ( $+ $1 $+ / $+ $2 %cnt $+ / $+ %cb_resnum $+ ) $gettok(%cb_result,%cnt,13)
        }
        else {
          echo -as CBAPI:  $+ $3 $+  $gettok(%cb_result,%cnt,13)
        }
        set %cb_gotres 1
        inc %cnt
      }
      if (%cnt > 1) { echo -as $crlf }
    }
  }
}


; LOCAL HELPER ALIASES
; --------------------

alias -l CbError {
  ; Args 1=prefix 2=missing arg
  echo -ast CB $+ $iif($1,$v1,API) $+ : ERROR > missing $iif($2,$v1,arguments(s)) $+ , try /CbHelp
}

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
    $CbError(CMD,'https api url') | return
  }
  if (!$CbPasswd) {
    $CbError(CMD,'api password') | return
  }
  if (!$var(%cb_maxchars)) {
    set %cb_maxchars 4000
  }
  if (!%cb_getsites) { 
    set %cb_getsites $replace($CbGetSites,$chr(34),)
  }
  if (!%cb_creditwname) { 
    set %cb_creditwname CRDS
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

alias -l CbArray {
  ;; format $1- as json array e.g. [ "foo", "bar" ]
  if ($1 = $null) {
    return $null
  }
  if ($1 = all) {
    return all
  }
  else {
    var %a = $replace($strip($1-),$chr(32),$chr(44),$chr(91),,$chr(93),,$chr(34),)
    var %nt = $numtok(%a,44)
    var %i 1 | while (%i <= %nt) {
      var %arr = %arr $+ " $+ $gettok(%a,%i,44) $+ " $+ $iif(%i < %nt, $chr(44) $chr(32),)
      if (%cb_debug >= 4) {
        echo -ast DEBUG: CbArray i = %i nt = %nt arr = %arr
      }
      inc %i
    }  
    return $chr(91) $+ %arr $+ $chr(93)
  }
}

alias CbLogin {
  tokenize 32 $strip($1-)
  if ($1 == u) {
    var %r = $regsubex($2-,^(.+)[: ].+$,\1)
  } 
  elseif ($1 == p) {
    var %r =  $regsubex($2-,^.+[: ](.+)$,\1)
  }
  return %r
}

;zeropad
alias zp {
  if ($len($1) == 1) {
    return 0 $+ $1 
  }
  return $1 
}

;space
alias -l sp {
  var %s = 
  return $str(%s $chr(32), $1)
}


; HELP
; ----
; CbHelp outputs to normal (status) window and to dialog

alias CbHelp {
  var %s = 
  var %n = $chr(13)
  var %h00 = CBHELP: %n 
  var %h01 = CBHELP: SETTINGS: %n %n
  var %h02 = CBHELP: %n 
  var %h03 = CBHELP: > Edit settings in Script and run /CbInit to activate %n
  var %h04 = CBHELP: > Settings can also be changed using /CbSet or in Menu %n
  var %h05 = CBHELP: > For details see comments in Script under 'CONFIGURATION' %n
  var %h06 = CBHELP: %n
  var %h07 = CBHELP: /CbSet [url|sites|login] <argument> %n 
  var %h08 = CBHELP: /CbSet [maxchars|creditwin|creditwname|raw|debug] <argument> %n 
  var %h09 = CBHELP: %n
  var %h10 = CBHELP: set api url e.g. https://:passwd@host_ip:port $sp(5) : /CbSet url <api_url> %n
  var %h11 = CBHELP: set multi sites e.g. SITE1 or SITE1,SITE2 or all     $sp(2) : /CbSet sites <sites|all> %n
  var %h12 = CBHELP: set default ftp username and password      $sp(13) : /CbSet login <user:pass> %n
  var %h13 = CBHELP: set output limit to max characters         $sp(16) : /CbSet maxchars <0-8000> %n
  var %h14 = CBHELP: show credits from statline in own window   $sp(10)  : /CbSet creditwin [0|1] %n
  var %h15 = CBHELP: set window name for credits                $sp(23) : /CbSet creditwname <Name> %n
  var %h16 = CBHELP: set debug verbosity                        $sp(31) : /CbSet debug [1-4] %n
  var %h17 = CBHELP: %n
  var %h18 = CBHELP: NOTE: /CbSet overrides /CbInit settings %n
  var %h19 = CBHELP: %n
  var %h20 = CBHELP: SITE MANAGEMENT CMDS: %n %n
  var %h21 = CBHELP: show site(s)              $sp(12) : /CbSite [site] [section] or [filter] %n
  var %h22 = CBHELP: add/modify site           $sp(9)  : /CbAddSite /CbModSite <site> <bnc> or <bnc1,bnc2> %n
  var %h23 = CBHELP: del site                  $sp(16) : /CbDelSite <site> %n
  var %h24 = CBHELP: show sections             $sp(11) : /CbSections [section] %n
  var %h25 = CBHELP: add/del section           $sp(9)  : /CbAddSection /CbDelSection <section> %n
  var %h26 = CBHELP: mod section               $sp(13)  : /CbModSection <section> <newname> %n
  var %h27 = CBHELP: add/mod section on site   $sp(1)  : /CbAddSiteSection /CbModSiteSection <site> <section> <path> %n
  var %h28 = CBHELP: del section from site     $sp(3)  : /CbDelSiteSection <site> <section> %n
  var %h29 = CBHELP: %n
  var %h30 = CBHELP: MULTI SITE CMDS: %n %n
  var %h31 = CBHELP: site <cmd>   $sp(3) : /CbSiteCmd <cmd> <arguments> %n
  var %h32 = CBHELP: site invite  $sp(2) : /CbInvite <nick> %n
  var %h33 = CBHELP: site search  $sp(2) : /CbSearch <pattern> %n
  var %h34 = CBHELP: site dupe    $sp(4) : /CbDupe <pattern> %n
  var %h35 = CBHELP: site request $sp(1) : /CbReq <release> %n 
  var %h36 = CBHELP: %n
  var %h37 = CBHELP: TRANSFER CMDS: %n %n
  var %h38 = CBHELP: spread job      $sp(6) : /CbSpread <section> <release> [sites] %n
  var %h39 = CBHELP: fxp job         $sp(9) : /CbFxp <section> <srcsite> <dstsite> <release> %n
  var %h40 = CBHELP: download job    $sp(4) : /CbDown <site> <section> <release> [srcpath]   (default: /tmp) %n
  var %h41 = CBHELP: upload job      $sp(6) : /CbUp <site> <section> <release> [dstpath]  (default: /tmp) %n
  var %h42 = CBHELP: get spreadjobs  $sp(2) : /CbGetSpread [release] %n
  var %h43 = CBHELP: get transfers   $sp(3) : /CbGetXfer [release] %n
  var %h44 = CBHELP: abort spread    $sp(4) : /CbAbortSpread <release> %n
  var %h45 = CBHELP: abort transfer  $sp(2) : /CbAbortXfer <release> %n
  var %h46 = CBHELP: get filelist    $sp(4) : /CbList <site> [path] [timeout] %n
  var %h47 = CBHELP: fxp incompletes $sp(1) : /CbInc <section> <dstsite> <srcsite> %n
  var %h48 = CBHELP: %n 
  var %h49 = CBHELP: Or, to use Menu: right click and select 'CBFTP API' %n
  var %h50 = CBHELP: %n 

  var %r
  ; show diff header for dialog box than status window
  if ($1) {
    %r = %r %n %n
    %r = %r %h01
  } 
  else {
    echo -as %h00
    echo -as %h01
    echo -as %h02
  }
  var %i = 02
  ; echo to status window
  while (%h [ $+ [ %i ] ]) {
    ; skip CbInit and CbSet info if url and passwd already set
    if ((%i == 02) && (%cb_url && $CbPasswd)) {
      var %i = 07
    }
    if ($1) {
      %r = %r %h [ $+ [ %i ] ]
    }
    else {
      echo -as %h [ $+ [ %i ] ]
    }
    inc %i
    %i = $zp(%i)
  }
  ; return output for dialog
  if ($1 && %r) {
    %r = %r %n
    return %r
  }
}


; SETTINGS
; --------

;; show config

alias -l CbConf {
  ; .CbInit
  var %s =  
  var %n = $chr(13) 
  var %s00 = CBSET: %n
  var %s01 = CBSET: SETTINGS: %n %n 
  var %s02 = CBSET: %n
  var %s03 = CBSET: Use: /CbSet [url|sites|login] <argument> %n
  var %s04 = CBSET: %s %s %s %s %s /CbSet [maxchars|creditwin|creditwname|raw|debug] <argument> %n 
  var %s05 = CBSET: %n
  var %s06 = CBSET: To use the Menu instead: right click, then goto 'CBFTP API' > Settings %n %n
  var %s07 = CBSET: %n
  var %s08 = CBSET: url          $sp(10) : cb_url = $CbUri(%cb_url) %n
  var %s09 = CBSET: $sp(16) cb_passwd = $iif($CbPasswd,is set,is not set) %n
  var %s10 = CBSET: sites         $sp(8) :  cb_sites = $CbArray(%cb_sites) %n %n
  var %s11 = CBSET: login         $sp(8) : cb_login = %cb_login %n
  var %s12 = CBSET: maxchars      $sp(5) : cb_maxchars = %cb_maxchars %n
  var %s13 = CBSET: creditwin     $sp(4) : cb_creditwin = %cb_creditwin %n %n
  var %s14 = CBSET: creditwname   $sp(2) : cb_creditwname = %cb_creditwname %n %n
  var %s15 = CBSET: raw           $sp(10) : cb_raw = %cb_raw %n
  var %s16 = CBSET: debug         $sp(8) : cb_debug = %cb_debug %n %n
  var %s17 = CBSET: %n
  var %r
  var %i = 00
  ; echo to status window
  while (%s [ $+ [ %i ] ]) {
    if ($1) {
      %r = %r %s [ $+ [ %i ] ]
    }
    else {
      echo -as %s [ $+ [ %i ] ]
    }
    inc %i
    %i = $zp(%i)
  }
  ; return output for dialog
  if ($1 && %r) {
    return %r
  }
}

;; change settings

alias CbSet {
  var %show_help 0
  if ($1 == url) {
    if ($regex($2,/^https://:?.*@.+:\d+$/)) {
      set %cb_url $1 | CbPasswd $1 | echo -ast CBAPI: url set to: $2
    }
    else {
      echo -ast  CBSET: ERROR > Incorrect argument, need /CbSet url https://:<API_Password>@127.0.0.1:443
      var %show_help 1
    }
  }
  elseif ($1 == sites) {
    ; limit sites to use
    if ($2) {
      if ($regex($2,/all/i)) { 
        set %cb_sites all | echo -ast  CBSET: sites $iif(%cb_sites,set to: $v1,unset)
        unset %cb_savesites
      }
      else {
        set %cb_sites $CbArray($2-) | echo -ast  CBSET: sites $iif(%cb_sites,set to: $v1,unset)
        unset %cb_savesites
      }
    }
    else {
      echo -ast  CBSET: Missing argument(s)
      var %show_help 1
    }
  }
  elseif ($1 == login) {
    ; default site login:passwd
    if ($regex($2-,^.+:.+$)) {
      set %cb_login $2 | echo -ast  CBSET: login $iif(%cb_login,set to: $v1,unset)
    }
    else {
      echo -ast CBSET: ERROR > Missing argument(s), need /CbSet login myusername:SecretPassword
      var %show_help 1
    }
  }
  elseif ($1 == maxchars) {
    ; set maxchars to 0-8000
    if ($regex($2,^\d+$)) {
      set %cb_maxchars $2 | echo -ast CBSET: maxchars $iif(%cb_maxchars,set to: $v1,unset)
    }
    else {
      echo -ast CBSET: ERROR > Incorrect argument, need /CbSet maxchars <0-8000>
      var %show_help 1
    }
  }
  elseif ($1 == creditwin ) {
    ; creditwname=1: display site stat results in own window
    if ($regex($2,^\d$)) {
      set %cb_creditwin $2 | echo -ast CBSET: creditwin $iif(%cb_creditwin,set,unset(0))
    }
    else {
      echo -ast CBSET: ERROR > Incorrect argument, need /CbSet creditwin [0|1]
      var %show_help 1
    }
  }
  elseif ($1 == creditwname) {
    ; set credits window name
    if ($regex($2,[^ ]+$)) {
      set %cb_creditwname $2 | echo -ast CBSET: creditwname $iif(%cb_creditwname,set to: $v1,unset)
    }
    else {
      echo -ast CBSET: ERROR > Incorrect argument, need /CbSet creditwname <Name>
      var %show_help 1
    }
  }
  elseif ($1 == raw) {
    ; cb_raw=1: enable raw ouput
    if ($regex($2,^\d$)) {
      set %cb_raw $2 | echo -ast CBSET: raw $iif(%cb_raw,set,unset(0))
    }
    else {
      echo -ast CBSET: ERROR > Incorrect argument, need /CbSet raw [0|1]
      var %show_help 1
    }
  }
  elseif ($1 == debug) {
    ; debug level: 1-4
    if ($regex($2,^\d+$)) {
      set %cb_debug $2 | echo -ast CBSET: debug $iif(%cb_debug,set to: $v1,unset(0))
    }
    else {
      echo -ast CBSET: ERROR > Incorrect argument, need /CbSet debug [1-4]
      var %show_help 1
    }
  }
  else {
    var %show_help 1
  }
  if (%show_help) {
    ; disabled: echo -ast  CBSET: To check current settings use:  $+ /CbConf $+ 
    .CbConf
    echo -ast  CBSET: ERROR > Need option and argument(s), for help try:  $+ /CbHelp $+ 
  }
}



; MENUS
; -----

menu * {
  CBFTP API
  .Help:/CbDialog CbHelpDg | /CbTxtDg CbHelpDg $CbHelp(1)
  ..$iif(!%cb_url || !$CbPasswd,Init settings,):/CbInit
  .Settings:/CbDialog CbSetDg
  .-
  .MULTI SITE COMMANDS
  ..SITE <ANYCMD>:/CbSite $$?="SITE <COMMAND> ( e.g. 'WHO' )"
  ..SEARCH:/CbSearch $$?="Search <query>:"
  ..DUPE:/CbDupe $$?="Dupe <query>"
  ..REQUEST:/CbReq $$?="Request <release>:"
  ..STAT:/CbStat
  ..GET FILELIST:/CbList $$?="<site> [path] [timeout]"
  .INVITE < $+ $me $+ > ALL:/CbInvite
  .INVITE < $+ $me $+ > on ...
  ..$submenu($CbInviteMenu($1))
  .-
  .SHOW SITE ...
  ..$submenu($CbSitesMenu($1))
  .SHOW SECTION ...
  ..$submenu($CbSectionsMenu($1))
  .MANAGE SITES
  ..ADD SITE:/CbAddSite $$?="<site> <bnc> or <bnc1,bnc2>"
  ..MODIFY SITE:/CbModSite $$?="<site> <bnc> or <bnc1,bnc2>"
  ..DELETE SITE:/CbDelSite $$?="<site>"
  ..ADD SITE SECTION:CbAddSiteSection $$?="<site> <section> <path>"
  ..MODIFY SITE SECTION:CbModSiteSection $$?="<site> <section> <path>"
  ..DELETE SITE SECTION:CbDelSiteSection $$?="<site> <section>"
  .MANAGE SECTIONS
  ..SHOW ALL SECTIONS:/CbSection
  ..ADD SECTION:CbAddSection $$?="<section>"
  ..MODIFY SECTION:CbModSection $$?="<section> <newname>"
  ..DELETE SECTION:CbDelSection $$?="<section>"
  .-
  .SPREAD:/CbSpread $$?="<section> <release> [sites]"
  .FXPJOB:/CbFxp $$?="<section> <srcsite> <dstsite> <release>"
  .DOWLOAD:/CbDown $$?="<site> <section> <release> [srcpath]  (default: /tmp)"
  .UPLOAD:/CbUp $$?="<site> <section> <release> [dstpath]  (default: /tmp)"
  .FXP INCOMPLETES:/CbInc $$?="<section> <dstsite> <srcsite>"
  .JOBS
  ..GET SPREADJOBS:/CbGetSpread
  ..GET TRANSFERS:/CbGetXfer
  ..ABORT SPREAD:/CbAbortSpread $$?="<release>"
  ..ABORT TRANSFER:/CbAbortXfer $$?="<release>"
  ..RESET SPREAD:/CbResetSpread $$?="<release>"
  ..RESET TRANSFER:/CbResetXfer $$?="<release>"
}

; removed:
;  .Show settings:/CbDialog CbConfDg | /CbTxtDg CbConfDg $CbConf(1)
;  .Change settings:/CbSet $$?="[api_url] [SITES] ( e.g. https://:Pass@1.2.3.4:443 S1;S2 )"
;  .Debug $chr(91) $+ %cb_debug $+ ]:$iif(%cb_debug,.CbDebug 0,.CbSet debug $$?="Debug level: <1-4>")
;  .RAW $chr(91) $+ %cb_raw $+ ]:$iif(%cb_raw,.CbSet raw 0,.CbSet raw 1)
;  .SHOW SITE:/CbSite $$?="[site] [section] or [filter]"
;  .GET SITES:/CbDialog CbGetSitesDg
;  .SHOW SECTION:/CbSection $$?="[site] [section] or [filer]"

; NOTE:
;
;  CbInviteMenu
;  - uses CbGetSites to create a 'dynamic submenu' for site invite
;  - between begin and end, $1 contains numbered items starting from 1 which we use to select a site
;  - before ':' set var %cb_sites to selected site, after: the invite command (uses $chr 'escape') 
;
;  CbSitesMenu and CbSectionMenu work similarly but use command directly e.g. 'CbSite <SITE>'
;

alias CbInviteMenu {
  ; Args 1=cnt(menu)
  if ($1 != begin && $1 != end) return $+($gettok(%cb_getsites,$1,44),:,set %cb_sites $+ $&
    $chr(32),$gettok(%cb_getsites,$1,44),$chr(32),$chr(124) CbSiteCmd INVITE $me) | return
}

;alias CbSitesMenu {
;  if ($1 != begin && $1 != end) return $iif($1 <= $numtok(%cb_getsites,44),$style(2),) $&
;    $+($gettok(%cb_getsites,$1,44),:,set %cb_sites $chr(32),$gettok(%cb_getsites,$1,44),$chr(32),) | return
;}

alias CbSitesMenu {
  if ($1 != begin && $1 != end) return $+($gettok(%cb_getsites,$1,44),:, $&
    CbSite $chr(32),$gettok(%cb_getsites,$1,44)) | return
}

alias CbSectionsMenu {
  if ($1 != begin && $1 != end) return $+($gettok(%cb_getsections,$1,32),:, $&
    CbSection $chr(32),$gettok(%cb_getsections,$1,32)) | return
}



; DIALOGS
; -------

; Usage: /CbDialog CbGetSitesDg  ( this calls /dialog -m CbGetSitesDg CbGetSitesDg )

alias CbDialog {
  if (%cb_debug >= 2) {
    echo -ast DEBUG: CbDialog args $ $+ 1-: $1-
  }
  if ($dialog($1).active == $null) {
    if (%cb_debug >= 2) {
      echo -ast DEBUG: CbDialog .active is null
    }
    /dialog -m $1 $1
    /dialog -v $1
  }
  if ($dialog($1).active == $false) {
    if (%cb_debug >= 2) {
      echo -ast DEBUG: CbDialog .active is false
    }
    /dialog -v $1
  }
}

;; dialog tables

;dialog -l CbConfDg {
;  title "CBAPI Show settings"
;  size -1 -1 160 130
;  option dbu
;  edit   "", 1, 10 10 140 90, read, multi, autohs, autovs
;  button "Ok",        2, 50 110 40 15, ok
;}

dialog -l CbHelpDg {
  title "CBAPI Help"
  size -1 -1 250 390
  option dbu
  edit   "", 1, 10 10 230 345, read, multi, autohs, autovs
  button "Ok",        2, 200 365 40 15, ok
}

dialog -l CbGetSitesDg {
  title "CBAPI Get Sites"
  size -1 -1 250 70
  option dbu
  edit   $CbGetSites, 1, 10 10 230 30, read, multi, autohs, autovs
  button "Ok",        2, 95 48 40 15, ok
}

dialog -l CbAboutDg {
  title "About CBAPI"
  size -1 -1 70 80
  option dbu
  edit  $CbAbout, 1, 10 10 50 40, read, multi, autohs, autovs, rich, disable
  button "Ok",        2, 18 58 35 15, ok
}

; main settings dialog table

; NOTE:
;  test: /CbDialog CbSetDg
;  dialog table syntax:
;    <component> ["text",] <id>, <x> <y> <width> <height>[, <style>] 

dialog -l CbSetDg {
  title "CBAPI Settings"
  size -1 -1 255 330
  option dbu

  ; menu, id's 801+ (future usage)

  ;menu "&File", 801
  ;item "&Exit", 802, cancel
  ;menu "&Help", 803
  ;item "&Show Help",804
  ;item "&About",805

  ; tabs, id's 901 (future usage)

  ;tab    "Main", 901, 10 5 235 310
  ;tab   "Tab2", 902
  ;tab   "Tab3", 903

  box    "Cbftp REST API",                      10,  25  20 205  32, tab 901
  text   "Url:",                                11,  33  33  12  10, tab 901
  edit   "",                                    20,  47  32 145  10, tab 901, multi, autohs, autovs
  ;text   "",                                   30,  65  25 120  10, tab 901
  text   "Select Sites for multi commands:"     70,  25  65  85  10, tab 901
  list                                          80,  25  80  88 200, tab 901, sort, extsel, vsbar
  button "All",                                170,  25 275  25  12, tab 901
  button "Clear",                              180,  55 275  25  12, tab 901
  button "Update",                             181,  85 275  29  12, tab 901
  box    "FTP Site login (default)"             89, 130  80 105  50, tab 901
  text   "Username:"                            90, 135  95  30  10, tab 901
  edit   "",                                   100, 165  95  50  10, tab 901
  text   "Password:"                           110, 135 110  30  10, tab 901
  edit   "",                                   120, 165 110  50  10, tab 901, autohs, autovs
  box    "Debugging"                           130, 130 140 105  50, tab 901
  check  "raw output"                          140, 135 155  40  10, tab 901
  text   "debug level (1-4)"                   150, 144 172  45  20, tab 901
  edit   "",                                   160, 135 170   7  10, tab 901
  box    "Output"                              200, 130 200 105  70, tab 901
  text   "Character limit:",                   210, 135 216  40  10, tab 901
  edit   "",                                   220, 175 215  20  10, tab 901, multi, autohs, autovs
  check  "Credits Window (SITE STAT results)", 230, 135 230  95  10, tab 901
  text   "Name: @",                            231, 135 245  22  10, tab 901
  edit   "",                                   232, 158 243  55  10, tab 901
  button "Ok",                                 190, 145 295  40  15, tab 901, default, ok
  button "Cancel",                             192, 195 295  40  15, tab 901, cancel
  text   "",                                   240, 25  295  90  15, tab 901, center, disable
}

; removed: combo  4, 40 30 100 10


;; helper: display text in dialog

alias -l CbTxtDg { 
  var %text = $strip($2-)
  if (%text) {
    if (%cb_debug >= 3) {
      echo -ast DEBUG: CbTxtDg $1 text: %text
    }
    var %i = 1
    if ($dialog($1)) {
      did -r $1 1      
      while (%i < $numtok(%text,13)) {
        var %line = $regsubex($gettok(%text,%i,13), /CB[A-Z]+: (.*)/g, \1) $crlf
        ;var %line = $gettok(%text,%i,13) $crlf
        did -a $1 1 %line 
        if (%cb_debug >= 2) {
          echo -ast DEBUG: CbTxtDg $1 i: %i line: %line
        }
        inc %i
      }
    }
  }
}

;; helper: create list of sites

alias -l CbSiteTok {
  var %i = 1
  while (%i <= $numtok(%cb_getsites,44)) {
    if ($numtok(%cb_getsites,44)) {
      if (%cb_debug >= 3) {
        echo -ast DEBUG: CbSiteTok i = %i $gettok(%cb_getsites,%i,44)
      }
      did -a CbSetDg 80 $gettok(%cb_getsites,%i,44)
      if ($gettok(%cb_getsites,%i,44) isin %cb_sites) {
        echo -ast DEBUG: CbSiteTok hit i = %i
        did -ck CbSetDg 80 %i %i
      }
    }
    inc %i
  }
}

alias -l CbAbout {
  var %n = $chr(13)
  var %r = $null
  var %r = %r  .--------------------. %n 
  var %r = %r  $chr(124) :: CBFTP API ::  $chr(124) %n 
  var %r = %r  `--------------------'   %n 
  var %r = %r  beta3 slv 20210803 %n 
  return %r %n 
}


; DIALOG EVENTS
; -------------
; Handle click, ok button, edit text field etc

; NOTE:
;
;  Controls:
;    Id   11: text     ( urkl: )
;    Id   20: edit     'cb_url'
;    Id   60: edit     ( max ... )
;    Id   80: list     'cb_sites'
;    Id  100: edit     'cb_login user'
;    Id  120: edit     'cb_login pass'
;    Id  140: check    'cb_raw'
;    Id  160: edit     'cb_debug'
;    Id  170: button   'All'
;    Id  180: button   'Clear'
;    Id  181: button   'Update'
;    Id  190: button   'Ok'
;    Id  192: button   'Cancel'
;    Id  220: edit     'maxchars'
;    Id  230; check    'creditwname'
;    Id  232: edit     'creditwname'
;    Id  240: text     'Site update...'
;

; main initial control values

on 1:dialog:CbSetDg:init:*: {
  if (!%cb_getsites) { 
    set %cb_getsites $replace($CbGetSites,$chr(34),)
  }
  $iif(%cb_url,did -a CbSetDg 20 $CbUri($v1),did -a CbSetDg 20 https://:Passw0rd@10.20.30.40:2443)
  did -a CbSetDg 100 $CbLogin(u %cb_login)
  did -a CbSetDg 120 $CbLogin(p %cb_login)
  $iif(%cb_raw,did -c CbSetDg 140,did -u CbSetDg 140)
  $iif(%cb_debug > 0,did -a CbSetDg 160 $v1,did -a CbSetDg 160 0)
  ; did -a CbSetDg 220 ( 0-8000 )
  $iif(%cb_maxchars > 0,did -a CbSetDg 220 $v1,did -a CbSetDg 220 0)
  $iif(%cb_creditwname,did -c CbSetDg 230,did -u CbSetDg 230)
  $iif($did(CbSetDg,230).state,did -n CbSetDg 232,did -m CbSetDg 232)
  $iif(%cb_creditwname,did -a CbSetDg 232 %cb_creditwname,did -a CbSetDg 232 Enter WindowName)
  did -a CbSetDg 240 Click 'Update' button to update Sites from Cbftp to slv-cbapi
  CbSiteTok
  if (%cb_sites == all) { 
    did -c CbSetDg 80
  }
  if (%cb_debug >= 3) {
    echo -ast DEBUG: CbSetDg:init cb_getsites = %cb_getsites
    echo -ast DEBUG: CbSetDg:init url = %cb_url
    echo -ast DEBUG: CbSetDg:init maxchars = %cb_maxchars creditwname = %cb_creditwname creditwname = %cb_creditwname  raw = %cb_raw debug = %cb_debug 
  }
}

; main menu 

on *:dialog:CbSetDg:menu:801-899:{
  if (%cb_debug >= 2) {
    echo -ast DEBUG: CbSetDg:menu 801-899 $did $did($dname, $did).text
  }
  if ($did == 802) {
    dialog -x CbSetDg
  }
  if ($did == 804) {
    /CbDialog CbHelpDg | /CbTxtDg CbHelpDg $CbHelp(1)
  }
  if ($did == 805) {
    /CbDialog CbAboutDg | /CbTxtDg CbAboutDg $CbAbout
  }
}

; main buttons, checkbox, etc components 

on *:dialog:CbSetDg:sclick:170-192,230:{
  if (%cb_debug >= 2) {
    echo -ast DEBUG: CbSetDg:sclick 170-192,230 $did $did($dname, $did).text is clicked
  }
  ; Id 170: button 'All'
  if ($did == 170) {
    if ($did(CbSetDg, 170).enabled) {
      set %cb_sites all
      did -c CbSetDg 80
    }
  }
  ; Id 180: button 'Clear'
  if ($did == 180) {
    if ($did(CbSetDg, 180).enabled) {
      did -u CbSetDg 80
    }
  }
  ; Id 181: button 'Update'
  if ($did == 181) {
    if ($did(CbSetDg, 181).enabled) {
      did -r CbSetDg 80
      set %cb_getsites $replace($CbGetSites,$chr(34),)
      CbSiteTok
      ;did -a CbSetDg 70 Select Sites to use: ( ... Updated )
      did -a CbSetDg 240 ...sites updated!
    }
  }
  ; Id 190: button 'Ok'
  if ($did == 190) {
    if ($did(CbSetDg, 190).enabled) {
      var %r = $null
      if (%cb_debug >= 2) {
        echo -ast DEBUG: CbSetDg:sclick 190 $did($dname, $did).text is clicked
        echo -ast DEBUG: CbSetDg:sclick 190 sel: $did(CbSetDg,80,0).sel lines: $did(CbSetDg,80).lines
      }
      if (%cb_debug >= 4) {
        echo -ast DEBUG: CbSetDg:sclick 190 list sel: $did(CbSetDg,80).sel
      }
      if ($did(CbSetDg,80,0).sel == $did(CbSetDg,80).lines) {
        if (%cb_debug >= 3) {
          echo -ast DEBUG: CbSetDg:sclick sel equals lines = all
        }
        set %cb_sites all
      } 
      ;
      ; ask user to confirm if no sites selected
      ;
      elseif ($did(CbSetDg,80,0).sel == 0) {
        if (%cb_debug >= 3) {
          echo -ast DEBUG: CbSetDg:sclick 80 sel is 0
        }
        $iif($input(Are you sure you want no sites selected? $crlf $&
          $crlf $+ Select to Yes to save $&
          $crlf $+ No keeps current setting $str($chr(160),40) ,y,Confirm Sites setting), set %cb_sites $null,)
      }
      else {
        ; 
        ; save site settings
        ;
        var %i = 1, %j = 0
        while (%i <= $did(CbSetDg,80).lines) {
          if (%j >= $did(CbSetDg,80,0).sel) {
            break
          }
          if ($did(CbSetDg,80,%i).state) {
            %r = $chr(34) $+ $did(CbSetDg,80,%i).text $+ $chr(34) $+ $chr(44) $+ %r
            inc %j
          }
          if (%cb_debug >= 2) {
            echo -ast DEBUG: CbSetDg:sclick i = %i j = %j did = $did(CbSetDg,80,%i)
            echo -ast DEBUG: CbSetDg:sclick state = $did(CbSetDg,80,0,%i).state sel = $did(CbSetDg,80,0).sel r = %r
          }
          inc %i
        }
        if (%cb_debug >= 2) {
          echo -ast DEBUG: CbSetDg:sclick r = $regsubex(%r,$chr(44) $+ $,)
        }
        set %cb_sites $regsubex(%r,$chr(44) $+ $,)
      }
      ;
      ; save other settings
      ;
      if (($did(CbSetDg,100,0).text) && ($did(CbSetDg,120,0).text)) {
        if (%cb_debug >= 2) {
          echo -ast DEBUG: CbSetDg:sclick login is $did(CbSetDg,100,0).text $+ : $+ $did(CbSetDg,120,0).text
        }
        set %cb_login $did(CbSetDg,100,0).text $+ : $+ $did(CbSetDg,120,0).text
      }
      if ($did(CbSetDg,160,0).text != $null) {
        if (%cb_debug >= 2) {
          echo -ast DEBUG: CbSetDg:sclick debug is $did(CbSetDg,160,0).text
        }
        $iif(%cb_debug > 0,set %cb_debug $v1,set %cb_debug 0)
      }
      if ($did(CbSetDg,220,0).text != $null) {
        if (%cb_debug >= 2) {
          echo -ast DEBUG: CbSetDg:sclick maxchars is $did(CbSetDg,220,0).text
        }
        $iif(%cb_maxchars > 0,set %cb_limit $v1,set %cb_limit 0)
      }
      if ($did(CbSetDg,232,0).text) {
        if (%cb_debug >= 2) {
          echo -ast DEBUG: CbSetDg:sclick creditwname is $did(CbSetDg,232,0).text
        }
        set %cb_creditwname $did(CbSetDg,232,0).text
      }
      if (%cb_debug >= 2) {
        echo -ast DEBUG: CbSetDg:sclick raw is $did(CbSetDg,140,0).state
        echo -ast DEBUG: CbSetDg:sclick creditwname is $did(CbSetDg,230,0).state
      }
      set %cb_raw $did(CbSetDg,140,0).state
      set %cb_creditwname $did(CbSetDg,230,0).state
      unset %cb_savesites
    }

  }
  ; Id 192: button 'Cancel'
  if ($did == 192) {
    if (%cb_debug >= 2) {
      echo -ast DEBUG: CbSetDg:sclick 192 $did($dname, $did).text is clicked
    }
    noop
  }
  if (%cb_debug >= 2) {
    echo -ast DEBUG: CbSetDg:sclick 232 $did($dname, $did).text is clicked
  }
  ; Id 230: checkbox creditwname
  if ($did == 230) {
    if (%cb_debug >= 2) {
      echo -ast DEBUG: CbSetDg:sclick 230 $did($dname, $did).state is clicked
    }
    $iif($did(CbSetDg,230).state,did -n CbSetDg 232,did -m CbSetDg 232)
  }
}

;; TEST

; help txt lines

alias testHelpVar {
  var %r = var_r
  var %n = $chr(13) 
  var %v1 line1 %n
  var %v2 line2 %n
  var %v3 line3 %n
  var %i = 0, | while (%i <= 4) {
    var %r = %r %v [ $+ [ %i ] ]
    inc %i
  }
  var %j = 0
  echo r: %r
  ; CbTxtDg CbHelpDg $CbHelp(1)
  ; CbTxtDg(%r)
}

alias testHelpTestBvar  {
  bset -t &v -1 \1line1 $crlf
  bset -t &v -1 \2line2
  bset -t &v -1 \3line3
  var %len = $bvar(&v,0)
  echo len %len
  echo bvar $bvar(&v,1,%len).text
  var %i = 0, %j = 1 | while (%i <= 4) {
    if (%cb_debug >= 2) {
      echo i= $+ %i j= $+ %j bf= $+  %bf
    }
    var %bf = $bfind(&v, 1, \ $+ %i).text
    ;,$calc(%bf-1)
    if (%bf) {
      echo $bvar(&v,%bf,%len).text
    }
    inc %i
    ;%j = %j + %bf
  }
}

alias testDg {
  ;/CbDialog CbHelpDg | /CbTxtDg CbHelpDg $CbGetSites
  /CbDialog CbGetSitesDg
}

alias test2 {
  if ($isid) {
    return 1: $1 2: $2 3: $3
  }
  else {
    echo debug 1: $1 2: $2 3: $3
    echo TEST: /sites $+ $iif(section isin $1-, $+ ? $+ $v2,bla)
  }
}
