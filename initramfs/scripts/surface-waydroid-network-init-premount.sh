#!/bin/sh

# Load the bridge, veth, and legacy iptables stack before switch_root.  The
# target OS may have no matching module tree for this kernel, while Waydroid
# needs these modules after the real root is mounted.

set -u

krel=$(cat /proc/sys/kernel/osrelease 2>/dev/null || true)
module_root="/usr/lib/modules/$krel"
insmod_bin=/usr/bin/insmod
[ -x "$insmod_bin" ] || insmod_bin=/sbin/insmod

load_module() {
	module_path=$1
	[ -r "$module_root/$module_path" ] || return 0
	"$insmod_bin" "$module_root/$module_path" 2>/dev/null || true
}

# Dependencies first: llc/stp/bridge, then connection tracking/NAT, then
# the iptables tables and targets used by waydroid-net.sh.
load_module kernel/net/llc/llc.ko
load_module kernel/net/802/stp.ko
load_module kernel/net/bridge/bridge.ko
load_module kernel/net/bridge/br_netfilter.ko
load_module kernel/drivers/net/veth.ko
load_module kernel/net/netfilter/x_tables.ko
load_module kernel/net/ipv4/netfilter/nf_defrag_ipv4.ko
load_module kernel/net/ipv6/netfilter/nf_defrag_ipv6.ko
load_module kernel/net/netfilter/nf_conntrack.ko
load_module kernel/net/netfilter/nf_nat.ko
load_module kernel/net/ipv4/netfilter/ip_tables.ko
load_module kernel/net/ipv4/netfilter/iptable_filter.ko
load_module kernel/net/ipv4/netfilter/iptable_nat.ko
load_module kernel/net/ipv4/netfilter/iptable_mangle.ko
load_module kernel/net/netfilter/xt_tcpudp.ko
load_module kernel/net/netfilter/xt_MASQUERADE.ko
load_module kernel/net/netfilter/xt_CHECKSUM.ko
