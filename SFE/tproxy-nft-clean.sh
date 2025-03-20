#!/bin/sh

# 删除 nftables sing-box 标记文件
if [ -d "/etc/sing-box/nft" ]; then
    rm -rf /etc/sing-box/nft
    echo "nftables sing-box 标记文件已清除。"
fi

# 清理 sing-box 相关的防火墙规则
nft list table inet sing-box >/dev/null 2>&1 && nft delete table inet sing-box >/dev/null 2>&1
echo "nftables sing-box 动态标记规则已清除。"

ip rule del fwmark 1 table 100 2>/dev/null
ip route flush table 100 2>/dev/null
echo "流量转发路由表 & 规则已清除。"

# 如果 nftables.conf 存在则删除
if [ -f "/etc/nftables.conf" ]; then
  rm -f /etc/nftables.conf
fi
echo "nftables.conf 已删除"

echo "sing-box 相关配置已清除。"