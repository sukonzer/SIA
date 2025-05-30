#!/bin/sh

# 配置参数
TPROXY_PORT=7895  # 与 sing-box 模板 inbounds 中 listen_port 保持一致
ROUTING_MARK=666  # 与 sing-box 模板 outbounds 中 default_mark 保持一致
PROXY_FWMARK=1
PROXY_ROUTE_TABLE=100
INTERFACE=$(ip route show default | awk '/default/ {print $5; exit}')

# 保留 IP 地址集合
ReservedIP4='{ 127.0.0.0/8, 10.0.0.0/8, 100.64.0.0/10, 169.254.0.0/16, 172.16.0.0/12, 192.0.0.0/24, 192.0.2.0/24, 198.51.100.0/24, 192.88.99.0/24, 192.168.0.0/16, 203.0.113.0/24, 224.0.0.0/4, 240.0.0.0/4, 255.255.255.255/32 }'
CustomBypassIP='{ 192.168.0.0/16, 10.0.0.0/8 }'  # 自定义绕过的 IP 地址集合

# 清理现有防火墙规则
clean_rules() {
    echo "清理 sing-box 相关的防火墙规则..."
    nft list table inet sing-box >/dev/null 2>&1 && nft delete table inet sing-box
    ip rule del fwmark $PROXY_FWMARK lookup $PROXY_ROUTE_TABLE 2>/dev/null
}

# 创建防火墙规则
create_rules() {
    echo "创建 sing-box 相关的防火墙规则..."

    # 设置路由规则
    ip rule add fwmark $PROXY_FWMARK table $PROXY_ROUTE_TABLE
    if ! ip route show table $PROXY_ROUTE_TABLE | grep -q "local default"; then
        ip route add local default dev "$INTERFACE" table $PROXY_ROUTE_TABLE
    fi
}

echo "开始配置 TProxy 防火墙规则..."

# 清理已存在的规则
clean_rules

# 创建新规则
create_rules

# 打开端口转发
# 打开端口转发
sysctl -w net.ipv4.ip_forward=1 > /dev/null

# 确保目录存在
mkdir -p /etc/sing-box/nft

# 手动创建 inet 表
nft add table inet sing-box

# 设置 TProxy 模式下的 nftables 规则
cat > /etc/sing-box/nft/nftables.conf <<EOF
table inet sing-box {
    set RESERVED_IPSET {
        type ipv4_addr
        flags interval
        auto-merge
        elements = $ReservedIP4
    }

    chain prerouting {
        type filter hook prerouting priority mangle; policy accept;

        # DNS 请求重定向到本地 TProxy 端口
        meta l4proto { tcp, udp } th dport 53 tproxy to :$TPROXY_PORT accept

        # 自定义绕过地址
        ip daddr $CustomBypassIP accept

        # 拒绝访问本地 TProxy 端口
        fib daddr type local meta l4proto { tcp, udp } th dport $TPROXY_PORT reject with icmpx type host-unreachable

        # 本地地址绕过
        fib daddr type local accept

        # 保留地址绕过
        ip daddr @RESERVED_IPSET accept

        #放行所有经过 DNAT 的流量
        ct status dnat accept comment "Allow forwarded traffic"

        # 重定向剩余流量到 TProxy 端口并设置标记
        meta l4proto { tcp, udp } tproxy to :$TPROXY_PORT meta mark set $PROXY_FWMARK
    }

    chain output {
        type route hook output priority mangle; policy accept;

        # 放行本地回环接口流量
        meta oifname "lo" accept

        # 本地 sing-box 发出的流量绕过
        meta mark $ROUTING_MARK accept

        # DNS 请求标记
        meta l4proto { tcp, udp } th dport 53 meta mark set $PROXY_FWMARK

        # 绕过 NBNS 流量
        udp dport { netbios-ns, netbios-dgm, netbios-ssn } accept

        # 自定义绕过地址
        ip daddr $CustomBypassIP accept

        # 本地地址绕过
        fib daddr type local accept

        # 保留地址绕过
        ip daddr @RESERVED_IPSET accept

        # 标记并重定向剩余流量
        meta l4proto { tcp, udp } meta mark set $PROXY_FWMARK
    }
}
EOF

# 应用防火墙规则和 IP 路由
echo "加载 sing-box table..."
nft -f /etc/sing-box/nft/nftables.conf

# 检查是否有错误
if [ $? -ne 0 ]; then
    echo "应用 nftables 规则时出错。请检查配置。"
    exit 1
fi

# 持久化防火墙规则
nft list ruleset > /etc/nftables.conf

echo "TProxy 防火墙规则应用完成。"