putlog "slv-disk.tcl 20200518"

################################################################################
# Monitor (SW) RAID/HBA/MD/SMART/DISKS
################################################################################
#
# Check raid/disk status and output errors to irc channel
#
# SUPPORTED:
# - Adaptec, Areca, AMCC/3ware, LSI/Avago/Broadcom
# - Linux SW RAID (MD), Linux Block Devices, SMART, SnapRAID
#
# NEEDS:
# - Areca: 'arcmsr' 'cli64', AMCC: 'tw_cli', LSI: 'sas3ircu', 
#   Avago: 'MegaCli64' or 'storcli64', SMART: 'smartmontools'
#
# - Eggdrop: use latest, add 'souce scripts/slv-disk.tcl to 'eggdrop.conf'
#
# - sudo rights: for example run 'sudoedit /etc/sudoers.d/diskcheck' and -add-
#       sitebot ALL=NOPASSWD: /usr/local/sbin/cli64, /bin/dmesg -T,
#                             /usr/sbin/smartctl, /sbin/mdadm
# * if needed replace 'sitebot', and 'cli64' with path to binary of vendor util
# 
# TRIGGERS:
#   !disk                show disk status check
#   !disktimer [on/off]  check every n minutes, send message on error(s)
#
################################################################################

namespace eval checkDisk {
	variable ns [namespace current]

	# CONFIG SETTINGS:
	###################

	# first, set at least one of these to 1

	set conf(adaptec) 0
	set conf(areca) 0
	set conf(amcc) 0
	set conf(lsisas) 0
	set conf(megaraid) 0
	set conf(storcli) 0
	set conf(md) 1			;# linux software raid / md devices
	set conf(smartctl) 0		;# if set to 1: also set 'smart_unit' below
	set conf(block) 1		;# linux block devices (checks 'dmesg' kernel errors)
	set conf(snapraid) 0

	variable areca_dmesg 0		;# set to 1: check 'dmesg' for areca errors instead of cli util
	variable md_dev 2		;# set to number of md devices (e.g. 2 for mirror)
	variable md_proc 2		;# set to 1: use '/proc/mdstat' instead of mdadm

	# set one or more smart devices to check: /dev/sdX where X is a-z (e.g. "a b c d")
	variable smartctl_unit "a b c d e f g h i j k l m n o p q r s t u v w x y z"

	# irc output
	set conf(cmdpre)	"!"		;# trigger prefix
	set conf(cmdpre2)       "!zz"           ;# additional trigger prefix (>1 bots)
	set conf(staffchan)     "#mychan"       ;# message channel
	set conf(timermins)	180		;# run timer every n minutes (default: 180)
	set conf(maxlines)	5		;# output max n lines (default: 5)
	set conf(triggerstatus)	"disk"
	set conf(triggertimer)	"disktimer"
	set conf(theme)         "\[\002\0034checkdisk\017\] :: "

	# dont forget to edit sudoers and add any bin you want to use (see paths below)
	# also make sure to specify the correct user running your eggdrop

	# paths 
	variable adaptec_bin	/usr/local/sbin/arcconf
	variable areca_bin	/usr/local/sbin/cli64
	variable amcc_bin	/usr/local/sbin/tw_cli
	variable lsisas_bin	/usr/local/sbin/sas3ircu
	variable megaraid_bin	/usr/local/sbin/MegaCli64
	variable storcli_bin	/usr/local/sbin/storcli64
	variable snapraid_bin	/usr/local/bin/snapraid

	# END OF CONFIG
	###############################################################################

	variable debug 0

	# shell commands to execute
	if {[info exists conf(adaptec)] && $conf(adaptec) == 1} {
		lappend check(status)	"sudo $adaptec_bin getconf 1 PD | grep State"
		lappend check(errors)	"sudo $adaptec_bin getconf 1 PD | grep State | grep -v Online"
	}
	if {[info exists conf(areca)] && $conf(areca) == 1} {
		if {[info exists areca_dmesg)] && $areca_dmesg == 1} {
			variable pattern 	"error|fail|abort|time out"
			variable tail		"tail -n $conf(maxlines)"
			lappend check(status)	"sudo dmesg -T | (grep arcmsr | grep -E \"$pattern\" || echo \"No arcmsr errors\") | $tail"
			lappend check(errors)	"sudo dmesg -T | grep arcmsr | grep -E \"$pattern\" | tail -n 5"
		} else {
			lappend check(status)	"sudo $areca_bin disk info | grep \"^ *\[0-9\]\""
			lappend check(errors)	"sudo $areca_bin rsf info | grep \"^ *\[0-9\]\" | grep -v Normal"
		}
	}
	if {[info exists conf(amcc)] && $conf(amcc) == 1} {
		variable pattern 	"ERROR|WARNING"
		variable tail		"tail -n $conf(maxlines)"
		lappend check(status)	"sudo $amcc_bin /c0 status"
		lappend check(errors)	"sudo dmesg -T | grep \"3w-9xxx\" | grep -E \"$pattern\" | grep -v opcode=0x85 | $tail"
	}
	if {[info exists conf(lsisas)] && $conf(lsisas) == 1} {
		variable ircu_awk	"$lsisas_bin 0 display \| \
					 awk -F: '/Hard disk\$/,/^\\\\s+State/\{
					   if(\$1 ~ \"^\\\\s+(Slot\|State)\")\{if (i%2==0)\{printf \$2\} else \{printf \"\\n\"\$2;i--\}\}; i++
					 \}'"
		lappend check(status)	"sudo $ircu_awk"
		lappend check(errors)	"sudo $ircu_awk | grep -v Ready"
	}
	if {[info exists conf(megaraid)] && $conf(megaraid) == 1} {
		lappend check(status)	"sudo $megaraid_bin -PDList -aALL | grep \"Firmware state\""
		lappend check(errors)	"sudo $megaraid_bin -PDList -aALL | grep \"Firmware state\" | grep -v Online"
	}
	if {[info exists conf(storcli)] && $conf(storcli) == 1} {
		lappend check(status)	"sudo $storcli_bin /call/dall show | grep -E \"RAID|DRIVE\""
		lappend check(errors)	"sudo $storcli_bin /call/dall show | grep -E \"RAID|DRIVE\" | grep -Ev \"Optl|Onln\""
	}
	if {[info exists conf(md)] && $conf(md) == 1} {
		if {[info exists md_proc] && $md_proc == 1} {
			variable mdstat		"cat /proc/mdstat"
			variable md_up		[string repeat U $md_dev]
			lappend check(status)	"$mdstat | grep -A1 '^md\[0-9\]' | grep -v '^--'"
			lappend check(errors)	"$mdstat | grep \"blocks.*\\\[\" | grep -Ev \"\\\[${md_dev}/${md_dev}\\\] \\\[${md_up}\\\]\""
		} else {
			variable pattern	" Use mdadm --detail for more detail."
			lappend check(status)	"for i in /dev/md\[0-9\]*; do sudo mdadm -Q -t \$i | sed \"s/$pattern//g\"; done"
			lappend check(errors)	"for i in /dev/md\[0-9\]*; do sudo mdadm -Q -t \$i >/dev/null; done"
		}
	}
	if {[info exists conf(block)] && $conf(block) == 1} {
		# error pattern for normal and stacking (dm) drivers
		variable pattern	"end_request:|print_req_error:"
		variable sort_tail	"sort -u -k 7,11 | tail -n $conf(maxlines)"
		lappend check(status)	"sudo dmesg -T | (grep -E \"$pattern\" || echo \"No block device errors\") | $sort_tail"
		lappend check(errors)	"sudo dmesg -T | grep -E \"$pattern\" | $sort_tail"
	}
	if {[info exists conf(smartctl)] && $conf(smartctl) == 1} {
		variable smartctl_loop	"for i in $smartctl_unit; do
				           o=\$(sudo /usr/sbin/smartctl -a /dev/sd\$\{i\} | grep health) && echo \"sd\$\{i\} \$o\"
				         done"
		lappend check(status)	"$smartctl_loop"
		lappend check(errors)	"$smartctl_loop | grep -v PASSED"
	}
	if {[info exists conf(snapraid)] && $conf(snapraid) == 1} {
		variable pat_err	"DANGER|blocks:"
		variable pat_info	"No error detected|already in use"
		lappend check(status)	"echo \"running 'snapraid errors', please wait...\""
		# takes a while to run
		lappend check(status)	"sudo $snapraid_bin errors 2>&1 | grep -E \"$pat_err|$pat_info\""
		lappend check(errors)	"sudo $snapraid_bin errors 2>&1 | grep -E \"$pat_err\""
	}

	# helper proc to bind and unbind triggers
	proc triggerCmd {command type flags procname args} {
		variable ns
		variable conf
		foreach var {command type flags procname args conf(cmdpre)} {
			if {![info exists $var]} {
				putlog "ERROR: $var missing in triggerCmd"
				return 1
			}
		}
		foreach trigger [list {*}$args] {
			foreach cmdpre [expr {([info exists conf(cmdpre2)] == 1) ? "${conf(cmdpre)} ${conf(cmdpre2)}" : ${conf(cmdpre)}}] {
				catch {$command $type $flags ${cmdpre}$trigger $procname} 
			}
		}
	}

	proc init {} {
		variable ns
		variable conf
		variable check
		variable timer_id
		catch {bind evnt -|- prerehash ${ns}::deinit}
		# added '!raid' trigger as it was used in older versions
		${ns}::triggerCmd bind pub o|o ${ns}::showStatus raid ${conf(triggerstatus)}
		${ns}::triggerCmd bind pub o|o ${ns}::setTimer raidmsg ${conf(triggertimer)}
		if {![info exists timer_running]} {
			variable timer_id [timer $conf(timermins) ${ns}::errorMessage]
			set timer_running 1
		}
	}
	
	proc deinit {$args} {
		variable ns
		variable conf
		variable timer_id
		if {[catch {killtimer $timer_id} error] != 0} {
			if {[info exists timer_running]} {
				catch {unset -nocomplain timer_running}
			}
		}
		${ns}::triggerCmd unbind pub o|o ${ns}::showStatus raid ${conf(triggerstatus)}
		${ns}::triggerCmd unbind pub o|o ${ns}::setTimer raidmsg ${conf(triggertimer)}
		namespace delete $ns
		return
	}

	proc debugKillTimers {} {
		variable debug
		if {$debug == 1} { 
			foreach i [timers] {
				catch {putlog "DEBUG: killing timer=\"$i\" ([lindex $i 2])"}
				if {[catch {killtimer [lindex $i 2]} error] != 0} {
					putlog "DEBUG: failed to kill timer=\"$i\" error=\"$error\""
				}
			}
		}
	}

	proc debugShowStatus {} {
		variable debug
		if {$debug == 1} { 
			variable conf
			variable check
			foreach command $check(status) {
				putlog "DEBUG: command=$command"
				foreach line [split [exec bash -c $command] "\n" ] {
					if {![string equal [string trim $line] ""]} {
						putlog "$conf(staffchan) :$conf(theme) $line"
					}
				}
			}
		}
	}

	proc debugErrorMessage {} {
		variable debug
		if {$debug == 1} { 
			variable conf
			variable check
			foreach command $check(errors) {
				putlog "DEBUG: command=$command"
				variable errors [catch {exec bash -c $command} result]
				# putlog "DEBUG: errors=$errors"
				if {$errors == 0} {
					foreach line [split $result "\n"] {
						if {![string equal [string trim $line] ""]} {
							putlog "$conf(staffchan) :$conf(theme) $line"
						}
					}
				}
			}
		}
	}

	proc showStatus {nick uhost handle chan arg} {
		variable conf
		variable check
		if {$chan == $conf(staffchan)} {
			foreach command $check(status) {
				foreach line [split [exec bash -c $command] "\n" ] {
					if {![string equal [string trim $line] ""]} {
						putquick "PRIVMSG $conf(staffchan) :$conf(theme) $line"
					}
				}
			}
		}
	}

	proc errorMessage {} {
		variable ns
		variable conf
		variable check
		variable timer_id
		foreach command $check(errors) {
			variable errors [catch {exec bash -c $command} result]
			if {$errors == 0} {
				foreach line [split $result "\n"] {
					if {![string equal [string trim $line] ""]} {
						putquick "PRIVMSG $conf(staffchan) :$conf(theme) $line"
					}
				}
			}
		}
		variable timer_id [timer $conf(timermins) ${ns}::errorMessage]
	}

	proc setTimer {nick uhost handle chan arg} {
		variable ns
		variable conf
		variable timer_id
		if {$arg == "on" || $arg == 1} {
			if {![info exists timer_running]} {
					variable timer_id [timer $conf(timermins) ${ns}::errorMessage]
					set timer_running 1
					putquick "PRIVMSG $conf(staffchan) :$conf(theme) turned timer \002ON\002"
			} else {
					putquick "PRIVMSG $conf(staffchan) :$conf(theme) timer already on"
			}
		} elseif {$arg == "off" || $arg == 0} {
			catch {killtimer $timer_id}
			putquick "PRIVMSG $conf(staffchan) :$conf(theme) turned timer \002OFF\002"
		} else {
			unset -nocomplain timers
			foreach i [timers] {
				if {[regexp -all -- {.*errorMessage.*} $i result]} {
					append timers \"$result\" " "
				}
			}
			if {(![info exists timers]) || ([string equal [string trim $timers] ""])} {
				variable timers none
			}
			putquick "PRIVMSG $conf(staffchan) :$conf(theme) use !disktimer \[on|off\]. active timer: $timers"
		}
	}
}

checkDisk::init

# vim: set noai tabstop=8 softtabstop=0 shiftwidth=8 noexpandtab:
