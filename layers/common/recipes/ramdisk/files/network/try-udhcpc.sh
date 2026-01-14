#!/bin/sh
# This is a best effort case to get a dhcp client

#
# $1: interface to try and get dhcp address for
#
dhclient_interface() {
		DHCP_HOOK_SCRIPT=/network/thepscg-simple-dhcp-hook.sh
		ip link set $1 up
		# If there is only one, reliable network interface it is OK to not run it in the background
		# Otherwise, it is better to run it in the background, to avoid the script blocking on a misbehaving interface
		udhcpc $1 -s $DHCP_HOOK_SCRIPT &
}

if [ -n "$DOCKERENV" ] ; then
	echo "Skipping dhcp for the docker client. If you want to modify the network settings we assume you know very well what you are doing..."
	exit 0
fi

if [ -n "$1" ] ; then
# Use the argument as the interface for dhcp if it is valid
		if [ -L /sys/class/net/$1 ] && [ ! "$1" = "lo" -a ! "$1" = "sit0" ] ; then
			dhclient_interface $1
			exit $?
		else
			echo "$1 is not a valid device for udhcpc"
			exit 1
		fi
else
	# Use any interace that is not lo, sit0 or dummy0
	for i in /sys/class/net/* ; do
		interface=$(basename $i)
		if [ ! "$interface" = "lo" -a ! "$interface" = "sit0" -a ! "$interface" = "dummy0" ] ; then
			dhclient_interface $interface
		fi
	done
fi
