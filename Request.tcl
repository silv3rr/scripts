#################################################################################
# dZSbot/ngBot - Request Plug-in v0.2.5                                         #
#################################################################################
#
# Requirements:
#  - NickDb.tcl installed and operational.
#  - cpt-request.sh
#
# Description:
#  - Can create/fill/wipe/del requests from either within glftpd, or from irc (if
#    using NickDb.tcl)
#  - Thanks to NickDb, we will know which user is actually making the request. Old
#    requestscripts always used the irc nickname. This might prevent trouble.
#
# Important notes:
#  - This script is not finished, but it is working. It's not using the nicest
#    code either, but it should be easy to modify it to suit your own needs.
#  - If you have some feedback on my crappy code, please tell me on irc:
#    compieter@EFnet. Feature requests/suggestions are always welcome, but please
#    note that i (try to) have a social life too.
#
# Installation:
# 1. copy cpt-request.sh to your glftpd/bin directory
#    http://compieter.nl.eu.org/scripts/cpt-request.sh
#
# 2. Edit the configuration options below.
#
# 3. Add the following to your eggdrop.conf:
#    source pzs-ng/plugins/Request.tcl
#
# 4. Add the following lines to your dZSbot.conf (the default settings for REQUEST should be okay):
#    set variables(REQFILL)  "%releasename %u_name %g_name %u_tagline %u_requester %g_requester"
#    set variables(REQWIPE)  "%releasename %u_name %g_name %u_tagline %u_requester %g_requester"
#    set variables(REQDEL)   "%releasename %u_name %g_name %u_tagline"
#    set variables(FILLEDMSG) "%date %u_requester %g_requester %u_filler %g_filler %releasename"
#    set variables(REQMSG)   "%msg"
#
#    set disable(REQFILL)       0
#    set disable(REQWIPE)       0
#    set disable(REQDEL)        0
#    set disable(REQMSG)        0
#    set disable(FILLEDMSG)     0
#
# 5. Add the following line to your theme file (defaults for REQUEST are okay again):
#    announce.REQFILL           = "[%b{filled}] %b{%u_name} of %g_name just filled %b{%releasename} for %b{%u_requester}."
#    announce.REQWIPE           = "[%b{r-wipe}] %b{%u_name} of %g_name just reqwiped %b{%releasename}. Too bad %b{%u_requester} ;)"
#    announce.REQDEL            = "[%b{reqdel}] %b{%u_name} of %g_name just deleted his request (%b{%releasename})."
#    announce.REQMSG            = "[%b{reqmsg}] %msg"
#    announce.FILLEDMSG         = "Hello %u_requester. Your request(%releasename) has been filled by %b{%u_filler} on %b{%date}. Go give him/her a nice hug."
#
# 6. Add "REQFILL REQWIPE REQDEL REQMSG FILLEDMSG" to the msgtypes(DEFAULT) array (in dZSbot.conf
#    or dZSbot.conf.defaults. Please note that .defaults will be overwritten on updates)
#
# 7. Rehash or restart your eggdrop for the changes to take effect.
#
#################################################################################

namespace eval ::ngBot::plugin::Request {
    variable ns [namespace current]
    ## Config Settings ###############################
    ##
    ## Choose one of two settings, the first when using ngBot, the second when using dZSbot
    variable np [namespace qualifiers [namespace parent]]
    #variable np ""
    ##
    ## Path to your requestscript. Please note that only cpt-request works with
    ## this tcl, but maybe tur will change his script?
    variable reqscript "/glftpd/bin/cpt-request.sh"
    ##
    ## Permissions! who can request?
    ## Leave the default to allow siteops, nukers and users with flag +J to request
    variable permsrequest "1 A J =siteops"
    ##
    ## Permissions! who can wipe requests?
    ## Leave the default to allow siteops, nukers and users with flag +J to wipe
    variable permswipe "1 =siteops"
    ##
    ## Display debug information? It's not really usable info, best to disable it
    variable debug False
    ##################################################

    namespace import ${np}::plugin::NickDb::*
#    bind evnt -|- prerehash [namespace current]::DeInit

    interp alias {} IsTrue {} string is true -strict
    interp alias {} IsFalse {} string is false -strict

    if {[string equal "" $np]} {
            bind evnt -|- prerehash ${ns}::deinit
    }

    ####
    # init
    #
    # Called on initialization; registers the event handler. Yeah, nothing fancy.
    #
    proc init {} {
        variable ns
        ## Bind event callbacks.
        bind pub -|- !request ${ns}::Request
        bind pub -|- !reqwipe ${ns}::Reqwipe
        bind pub -|- !reqdel ${ns}::Reqdel
        bind pub -|- !reqfill ${ns}::Reqfill
        bind pub -|- !reqfilled ${ns}::Reqfill
        bind pub -|- !requests ${ns}::Reqlist
#        bind join -|- "*" ${ns}::OnJoin
        putlog "\[ngBot\] Request :: Loaded successfully."
        return
    }

    ####
    # deinit
    #
    # Called on rehash; unregisters the event handler.
    #
    proc deinit {args} {
        variable ns
        ## Remove event callbacks.
        catch {unbind pub -|- "!request" ${ns}::Request}
        catch {unbind pub -|- "!reqwipe" ${ns}::Reqwipe}
        catch {unbind pub -|- "!reqdel" ${ns}::Reqdel}
        catch {unbind pub -|- "!reqfill" ${ns}::Reqfill}
        catch {unbind pub -|- "!reqfilled" ${ns}::Reqfill}
        catch {unbind pub -|- "!requests" ${ns}::Reqlist}
        #catch {unbind evnt -|- prerehash ${ns}::DeInit}
        catch {unbind join -|- "*" ${ns}::OnJoin}

        namespace delete $ns
        return
    }

    ####
    # GetInfo
    #
    # gets $group and $flags from the userfile
    #
    proc GetInfo {ftpUser groupVar flagsVar} {
        variable np
        global ${np}::location
        upvar $groupVar group $flagsVar flags
        set group ""; set flags ""

        if {![catch {set handle [open "$location(USERS)/$ftpUser" r]} error]} {
            set data [read $handle]
            close $handle
            foreach line [split $data "\n"] {
                switch -exact -- [lindex $line 0] {
                    "FLAGS" {set flags [lindex $line 1]}
                    "GROUP" {set group [lindex $line 1]}
                }
            }
    	return 1
        } else {
            putlog "\[ngBot\] error: Unable to open user file for \"$ftpUser\" ($error)."
            return 0
        }
    }

    ####
    # Request
    #
    # Add a new request
    #
    proc Request {nick host handle channel text} {
        variable np
        global ${np}::location
        variable reqscript
        variable debug
        variable permsrequest

        set ftpUser [GetFtpUser $nick]
        if {[string equal "" $nick]} {return}

        if {[GetInfo $ftpUser group flags]} {
            if {[${np}::rightscheck $permsrequest $ftpUser $group $flags]} {
        	    foreach line [split [exec $reqscript $ftpUser add $text] "\n"] {
    		if {[IsFalse $debug]} {
    		    if { [lindex $line 0] != "DEBUG:" } {
    			puthelp "PRIVMSG $channel :$line"
    		    }
    		} elseif { [lindex $line 0] == "REQMSG:" } {
    		    ${np}::sndall REQMSG DEFAULT [ng_format "REQMSG" "DEFAULT" \"$line\"]
    		} else {
    		    puthelp "PRIVMSG $channel :$line"
    		}
    	    }
    	} else {
    	    set line "Sorry, you're not allowed to request."
#	     ${np}::sndall REQMSG DEFAULT [ng_format "REQMSG" "DEFAULT" \"$line\"]
    	    puthelp "PRIVMSG $channel :$line"

    	}
        } else {
    	set line "Sorry, you don't exist. Try inviting yourself again."
#	     ${np}::sndall REQMSG DEFAULT [ng_format "REQMSG" "DEFAULT" \"$line\"]
            puthelp "PRIVMSG $channel :$line"
        }
    }

    ####
    # Reqwipe
    #
    # Wipes requests! isn't it amazing?
    #
    proc Reqwipe {nick host handle channel text} {
        variable np
        global ${np}::location
        variable reqscript
        variable debug
        variable permswipe

        set ftpUser [GetFtpUser $nick]
        if {[string equal "" $nick]} {return}

        if {[GetInfo $ftpUser group flags]} {
            if {[${np}::rightscheck $permswipe $ftpUser $group $flags]} {
                foreach line [split [exec $reqscript $ftpUser wipe $text] "\n"] {
                    if {[IsFalse $debug]} {
                        if { [lindex $line 0] != "DEBUG:" } {
                            puthelp "PRIVMSG $channel :$line"
                        }
                    } elseif { [lindex $line 0] == "REQMSG:" } {
                        ${np}::sndall REQMSG DEFAULT [ng_format "REQMSG" "DEFAULT" \"$line\"]
                    } else {
                        puthelp "PRIVMSG $channel :$line"
                    }
                }
            } else {
                set line "Sorry, you're not allowed to wipe requests."
                puthelp "PRIVMSG $channel :$line"
#	         ${np}::sndall REQMSG DEFAULT [ng_format "REQMSG" "DEFAULT" \"$line\"]
            }
        }
    }

    ####
    # Reqdel
    #
    # Deletes requests! things keep on getter better and better
    #
    variable np
    proc Reqdel {nick host handle channel text} {
        variable reqscript
        variable debug

        set ftpUser [GetFtpUser $nick]
        if {[string equal "" $nick]} {return}

        foreach line [split [exec $reqscript $ftpUser del $text] "\n"] {
            if {[IsFalse $debug]} {
                if { [lindex $line 0] != "DEBUG:" } {
                    puthelp "PRIVMSG $channel :$line"
                }
            } elseif { [lindex $line 0] == "REQMSG:"} {
                ${np}::sndall REQMSG DEFAULT [ng_format "REQMSG" "DEFAULT" \"$line\"]
            } else {
                puthelp "PRIVMSG $channel :$line"
            }
        }
    }

    ####
    # Reqfill
    #
    # You know the drill.
    #
    variable np
    proc Reqfill {nick host handle channel text} {
        variable reqscript
        variable debug

        set ftpUser [GetFtpUser $nick]
        if {[string equal "" $nick]} {return}

        foreach line [split [exec $reqscript $ftpUser fill $text] "\n"] {
            if {[IsFalse $debug]} {
                if { [lindex $line 0] != "DEBUG:" } {
                          puthelp "PRIVMSG $channel :$line"
                }
            } elseif { [lindex $line 0] == "REQMSG:" } {
                ${np}::sndall REQMSG DEFAULT [ng_format "REQMSG" "DEFAULT" \"$line\"]
            } else {
                puthelp "PRIVMSG $channel :$line"
            }
        }
    }

    ####
    # Reqlist
    #
    # Lists all the requests
    #
    proc Reqlist {nick host handle channel text} {
        variable reqscript
        variable debug

        set ftpUser [GetFtpUser $nick]
        if {[string equal "" $nick]} {return}

        foreach line [split [exec $reqscript $ftpUser list $text] "\n"] {
            if {[IsFalse $debug]} {
                if { [lindex $line 0] != "DEBUG:" } {
                    putquick "PRIVMSG $channel :$line"
                }
            } else {
#	     ${np}::sndall REQMSG DEFAULT [ng_format "REQMSG" "DEFAULT" \"$line\"]
                putquick "PRIVMSG $channel :$line"
            }
        }
    }

    ####
    # OnJoin
    #
    # Called when a user joins the channel.
    #
    proc OnJoin {nick host handle channel} {
        variable reqscript
        global announce

        ## Lookup the user's FTP user name.
        set ftpUser [GetFtpUser $nick]
        if {[string equal "" $nick]} {return}

        set status [exec $reqscript $ftpUser joincheck]
        if {[string equal "" $status]} {return}
        set date [lindex $status 0]
        set requester [lindex $status 1]
        set requesterg [lindex $status 2]
        set filler [lindex $status 3]
        set fillerg [lindex $status 4]
        set release [lindex $status 5]
        set output [replacebasic $announce(FILLEDMSG) "FILLEDMSG"]
        set output [replacevar $output "%date" $date]
        set output [replacevar $output "%u_requester" $requester]
        set output [replacevar $output "%g_requester" $requesterg]
        set output [replacevar $output "%u_filler" $filler]
        set output [replacevar $output "%g_filler" $fillerg]
        set output [replacevar $output "%releasename" $release]
        set output [themereplace $output "none"]
        puthelp "NOTICE $nick :$output"

        #return 1
    }
}

if {[string equal "" $::ngBot::plugin::Request::np]} {
        ::ngBot::plugin::Request::init
}
