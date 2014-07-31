#!/bin/bash

# This script will set gnome proxy configuration for each SSID
# Version: 1.51
#
# Authors and contributors:
# - Berend Deschouwer
# - Ivan Gusev
# - Julien Blitte            <julien.blitte@gmail.com>
# - Milos Pejovic
# - Sergiy S. Kolesnikov
# - Tom Herrmann
#
# To install this file, place it in directory (with +x mod):
# /etc/NetworkManager/dispatcher.d
#
# For each new SSID, after a first connection, complete the genreated file
# /etc/proxydriver.d/<ssid_name>.conf and then re-connect to AP, proxy is now set!
#
# Tested under Ubuntu with GNOME and NetworkManager.
# Tested under Fedora with GNOME, NetworkManager and nmcli.
# Tested under Arch Linux.
#

conf_dir='/etc/proxydriver.d'
log_tag='proxydriver'
running_device='/var/run/proxydriver.device'

logger -p user.debug -t $log_tag "script called: $*"

# vpn disconnection handling
if [ "$2" == "up" ]
then
	echo "$1" > "$running_device"
elif [ "$2" == "vpn-down" ]
then
	set -- `cat "$running_device"` "up"
fi

if [ "$2" == "up" -o "$2" == "vpn-up" ]
then
	logger -p user.notice -t $log_tag "interface '$1' now up, will try to setup proxy configuration..."

	[ -d "$conf_dir" ] || mkdir --parents "$conf_dir"
	
#	if type -P nmcli &>/dev/null
#	then
		# retrieve connection/vpn name
#		networkID=`nmcli -t -f name,devices,vpn con status | \
#			awk -F':' "BEGIN { device=\"$1\"; event=\"$2\" } \
#				event == \"up\" && \\$2 == device && \\$3 == \"no\" { print \\$1 } \
#				event == \"vpn-up\" && \\$3 == \"yes\" { print \#"vpn_\" \\$1 }"`
#	else
		# try ESSID if nmcli is not installed
#		logger -p user.notice -t $log_tag "nmcli not detected, will use essid"

		networkID=`iwgetid --scheme`
		[ $? -ne 0 ] && networkID='default'
#	fi
	
	# strip out anything hostile to the file system
	networkID=`echo "$networkID" | tr -c '[:alnum:]-' '_' | sed 's/.$/\n/'`

	conf="$conf_dir/$networkID.conf"

	logger -p user.notice -t $log_tag "using configuration file '$conf'"

	if [ ! -e "$conf" ]
	then
		logger -p user.notice -t $log_tag "configuration file empty! generating skeleton..."

		touch "$conf"

		cat <<EOF > "$conf"
# configuration file for proxydriver
# file auto-generated, please complete me!

# proxy active or not
enabled="false"

# main proxy settings
proxy="proxy.companydomain.com"
port=8080

# use same proxy for all protocols
same="true"

# protocols other than http (if same is set to "false")
https_proxy="proxy.companydomain.com"
https_port=8080
ftp_proxy="proxy.companydomain.com"
ftp_port=8080
socks_proxy="proxy.companydomain.com"
socks_port=8080

# authentication
auth="false"
login="smith"
pass="r00t"

# ignore-list
ignorelist='localhost,127.0.0.0/8,10.0.0.0/8,192.168.0.0/16,172.16.0.0/12'

EOF

		chown root:dip "$conf"
		chmod 0664 "$conf"

	fi

	source "$conf"

	# select mode using enabled value
	if [ "$enabled" == "true" -o "$enabled" == "1" ]
	then
		enabled="true" # gsettings/gnome3 likes 'true'/'false'
		kdeenabled="1" # KDE likes 1/0
		mode="manual"
		
#		# set standard proxy vars to use in ~/.profile
#		echo "export https_proxy=$https_proxy:$https_port"> /etc/proxy.conf
#		echo "export http_proxy=${proxy:-"192.168.126.1:800"}">> /etc/proxy.conf
#		echo "export ftp_proxy=$ftp_proxy:$ftp_port">> /etc/proxy.conf

	else
		enabled="false"
		kdeenabled="0"
		mode="none"
		# set standard proxy vars to use in ~/.profile
                echo "export https_proxy="> /etc/proxy.conf
                echo "export http_proxy=" >> /etc/proxy.conf
                echo "export ftp_proxy=">> /etc/proxy.conf

		#rm -rf /etc/proxy.conf
	fi

	# to be compliant with older version
	if [ "$same" == "" ]
	then
		same="false"
		https_proxy="$proxy"
		https_port="$port"
		ftp_proxy="$proxy"
		ftp_port="$port"
		socks_proxy="$proxy"
		socks_port="$port"
	fi
	ignorelist=`echo $ignorelist | sed 's/^\[\(.*\)\]$/\1/'`
	
	# gnome2 needs [localhost,127.0.0.0/8]
	# gnome3 needs ['localhost','127.0.0.0/8']
	# neither work with the other's settings
	quoted_ignorelist=`echo $ignorelist | sed "s/[^,]\+/'\0'/g"`
	gnome2_ignorelist="[${ignorelist}]"
	gnome3_ignorelist="[${quoted_ignorelist}]"
	
	# Gnome likes *.example.com; kde likes .example.com:
	kde_ignorelist=`echo "${ignorelist}" | sed -e 's/\*\./\./g'`

	if [ "$enabled" == "true" -o "$enabled" == "1" ]
        then
        #        enabled="true" # gsettings/gnome3 likes 'true'/'false'
         #       kdeenabled="1" # KDE likes 1/0
                mode="manual"
#
                # set standard proxy vars to use in ~/.profile
                echo "export https_proxy=$https_proxy:$https_port"> /etc/proxy.conf
                echo "export http_proxy=$proxy:$port" >> /etc/proxy.conf
                echo "export ftp_proxy=$ftp_proxy:$ftp_port">> /etc/proxy.conf

	fi	
# uncomment following lines if n-m connects before your session starts
#
#	# wait if no users are logged in (up to 5 minutes)
#	COUNTER=0
#	while [ "$(users)" == "" -a $COUNTER -lt 360 ]
#	do
#		let COUNTER=COUNTER+10
#		sleep 10
#	done
#	
#	# a user just logged in; give some time to settle things down
#	if [ $COUNTER -gt 0 -a $COUNTER -lt 360 ]
#	then
#		sleep 15
#	fi

	machineid=$(dbus-uuidgen --get)
	for user in `users | tr ' ' '\n' | sort --unique`
	do
		logger -p user.notice -t $log_tag "setting configuration for '$user'"


		cat <<EOS | su -l "$user"
export \$(DISPLAY=':0.0' dbus-launch --autolaunch="$machineid")

# active or not
gconftool-2 --type bool --set /system/http_proxy/use_http_proxy "$enabled"
gsettings set org.gnome.system.proxy.http enabled "$enabled"
gconftool-2 --type string --set /system/proxy/mode "$mode"
gsettings set org.gnome.system.proxy mode "$mode"
kwriteconfig --file kioslaverc --group 'Proxy Settings' --key ProxyType "${kdeenabled}"

# proxy settings
gconftool-2 --type string --set /system/http_proxy/host "$proxy"
gsettings set org.gnome.system.proxy.http host '"$proxy"'
gconftool-2 --type int --set /system/http_proxy/port "$port"
gsettings set org.gnome.system.proxy.http port "$port"
kwriteconfig --file kioslaverc --group 'Proxy Settings' --key httpProxy "${proxy}:${port}"

gconftool-2 --type bool --set /system/http_proxy/use_same_proxy "$same"
gsettings set org.gnome.system.proxy use-same-proxy "$same"
# KDE handles 'same' in the GUI configuration, not the backend.

gconftool-2 --type string --set /system/proxy/secure_host "$https_proxy"
gsettings set org.gnome.system.proxy.https host '"$https_proxy"'
gconftool-2 --type int --set /system/proxy/secure_port "$https_port"
gsettings set org.gnome.system.proxy.https port "$https_port"
kwriteconfig --file kioslaverc --group 'Proxy Settings' --key httpsProxy "${https_proxy}:${https_port}"

gconftool-2 --type string --set /system/proxy/ftp_host "$ftp_proxy"
gsettings set org.gnome.system.proxy.ftp host '"$ftp_proxy"'
gconftool-2 --type int --set /system/proxy/ftp_port "$ftp_port"
gsettings set org.gnome.system.proxy.ftp port "$ftp_port"
kwriteconfig --file kioslaverc --group 'Proxy Settings' --key ftpProxy "ftp://${ftp_proxy}:${ftp_port}/"

gconftool-2 --type string --set /system/proxy/socks_host "$socks_proxy"
gsettings set org.gnome.system.proxy.socks host '"$socks_proxy"'
gconftool-2 --type int --set /system/proxy/socks_port "$socks_port"
gsettings set org.gnome.system.proxy.socks port "$socks_port"
# KDE no socks?  Just shoes?

# authentication
gconftool-2 --type bool --set /system/http_proxy/use_authentication "$auth"
gsettings set org.gnome.system.proxy.http use-authentication "$auth"
gconftool-2 --type string --set /system/http_proxy/authentication_user "$login"
gsettings set org.gnome.system.proxy.http authentication-user "$login"
gconftool-2 --type string --set /system/http_proxy/authentication_password "$pass"
gsettings set org.gnome.system.proxy.http authentication-password "$pass"
# KDE Prompts 'as needed'
kwriteconfig --file kioslaverc --group 'Proxy Settings' --key Authmode 0

# ignore-list
gconftool-2 --type list --list-type string --set /system/http_proxy/ignore_hosts "${gnome2_ignorelist}"
gsettings set org.gnome.system.proxy ignore-hosts "${gnome3_ignorelist}"
kwriteconfig --file kioslaverc --group 'Proxy Settings' --key NoProxyFor "${kde_ignorelist}"

# gconftool-2 --type string --set /system/proxy/autoconfig_url "$URL"
# gsettings set org.gnome.system.proxy autoconfig-url "$URL"

# When you modify kioslaverc, you need to tell KIO.
dbus-send --type=signal /KIO/Scheduler org.kde.KIO.Scheduler.reparseSlaveConfiguration string:''


EOS
	done

	logger -p user.notice -t $log_tag "configuration done."


	
fi
