#!/bin/sh
#
# The following is a simple script that would work well with one interface
# You can go ahead and parse the network by looking at the $mask (i.e. network class) and the $ip address, but that's not so easy on the eyes with scripting
# so I don't bother to do that
#

FALLBACK_DNS=8.8.8.8

if [ ! $1 = bound ] ; then
	echo "$0 $@ arguments were called. ip=$ip"
	exit 0
fi

echo "DHCP address received: interface=$interface ip=$ip/$mask (subnet=$subnet) gw=$router dns=$dns"

ip addr add $ip/$subnet dev $interface
ip route add default via $router

if [ -n "$dns" ] ; then
	echo "nameserver $dns" > /etc/resolv.conf
else
	echo "nameserver $FALLBACK_DNS" > /etc/resolv.conf
fi


