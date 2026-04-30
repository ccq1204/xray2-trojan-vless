#!/bin/bash

# --- [ 1. 品牌定义与广告配置 ] ---
AUTHOR="极昼"
BRAND_NAME="xray2-Multi"
# 在这里定义新的广告信息
AD_MESSAGE_1="本系统由【极昼】独家冠名赞助"
AD_MESSAGE_2="商业合作请联系 Telegram: @jzllzf"

# 你的新仓库地址 (核心文件下载基础)
RAW_BASE="https://raw.githubusercontent.com/ccq1204/xray2-trojan-vless/main"
AUTH_DB="$RAW_BASE/auth_md5.txt"

GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
BLUE="\033[34m"
PLAIN="\033[0m"

# --- [ 2. 授权验证 (界面增加广告显示) ] ---
clear
echo -e "${BLUE}======================================================${PLAIN}"
echo -e "${GREEN}          $BRAND_NAME 商业版高性能转发系统${PLAIN}"
echo -e "${YELLOW}                 作者：${AUTHOR}${PLAIN}"
# === 增加广告显示 ===
echo -e "${BLUE}------------------------------------------------------${PLAIN}"
echo -e "${RED}⚠️  $AD_MESSAGE_1 ${PLAIN}"
echo -e "${RED}⚠️  $AD_MESSAGE_2 ${PLAIN}"
echo -e "${BLUE}======================================================${PLAIN}"

# 解决输入流冲突
exec < /dev/tty

# 预拉取授权列表
AUTH_LIST=$(curl -H "Cache-Control: no-cache" -Lfs --connect-timeout 10 "${AUTH_DB}?v=${RANDOM}" | tr -cd '[:alnum:]')

RETRY_COUNT=0
VALID_AUTH=false
while [ $RETRY_COUNT -lt 3 ]; do
    read -p "请输入授权码: " USER_INPUT
    CLEAN_INPUT=$(echo -n "$USER_INPUT" | tr -cd '[:alnum:]')
    if [[ "$AUTH_LIST" == *"$CLEAN_INPUT"* ]] && [ -n "$CLEAN_INPUT" ]; then
        echo -e "${GREEN}✅ 验证通过！${PLAIN}"; VALID_AUTH=true; break
    else
        RETRY_COUNT=$((RETRY_COUNT + 1))
        [ $RETRY_COUNT -lt 3 ] && echo -e "${YELLOW}授权码错误，请重试...${PLAIN}"
    fi
done
[ "$VALID_AUTH" = false ] && { echo -e "${RED}❌ 授权失败。${PLAIN}"; exit 1; }

# --- [ 3. 参数录入 (保持不变) ] ---
echo -e "${BLUE}------------------------------------------------------${PLAIN}"
read -p "选择协议 (1.Trojan 2.VLESS): " P_CHOICE
[[ "$P_CHOICE" == "2" ]] && NODE_TYPE="vless" || NODE_TYPE="trojan"

read -p "面板地址(ApiHost): " RAW_URL
C_URL=$(echo "$RAW_URL" | xargs | sed 's/\/$//g')
[[ "$C_URL" != http* ]] && C_URL="https://$C_URL"

read -p "面板密钥(ApiKey): " C_KEY
read -p "节点ID(NodeID): " C_ID
read -p "解析域名(CertDomain): " C_DOMAIN

# --- [ 4. 环境准备与资源同步 (保持不变) ] ---
mkdir -p /etc/xray2
mkdir -p /usr/local/xray2
apt-get update -y && apt-get install -y curl wget tar unzip psmisc

echo -e "${YELLOW}正在同步全量配置文件与规则库...${PLAIN}"
# 下载你仓库里那个“很重要”的文件 sing_origin.json
wget -q -O /etc/xray2/sing_origin.json $RAW_BASE/sing_origin.json
wget -q -O /etc/xray2/route.json $RAW_BASE/route.json
wget -q -O /etc/xray2/dns.json $RAW_BASE/dns.json

# 下载内核
ARCH=$(uname -m)
[ "$ARCH" == "x86_64" ] && D_URL="https://github.com/wyx2685/V2bX/releases/download/v0.4.0/V2bX-linux-64.zip" || D_URL="https://github.com/wyx2685/V2bX/releases/download/v0.4.0/V2bX-linux-arm64-v8a.zip"
wget -q -O /usr/local/xray2/core.zip "$D_URL"
unzip -o /usr/local/xray2/core.zip -d /usr/local/xray2
mv /usr/local/xray2/V2bX /usr/local/xray2/xray2_core
chmod +x /usr/local/xray2/xray2_core

# --- [ 5. 生成标准 config.json (保持不变) ] ---
# 严格按照要求的结构对齐，引用仓库下载的 sing_origin.json
cat <<EOF > /etc/xray2/config.json
{
    "Log": {
        "Level": "error",
        "Output": ""
    },
    "Cores": [
    {
        "Type": "sing",
        "Log": {
            "Level": "error",
            "Timestamp": true
        },
        "NTP": {
            "Enable": false,
            "Server": "time.apple.com",
            "ServerPort": 0
        },
        "OriginalPath": "/etc/xray2/sing_origin.json"
    }],
    "Nodes": [{
            "Core": "sing",
            "ApiHost": "$C_URL",
            "ApiKey": "$C_KEY",
            "NodeID": $C_ID,
            "NodeType": "$NODE_TYPE",
            "Timeout": 30,
            "ListenIP": "::",
            "SendIP": "0.0.0.0",
            "TCPFastOpen": true,
            "SniffEnabled": true,
            "CertConfig": {
                "CertMode": "none",
                "CertDomain": "$C_DOMAIN",
                "CertFile": "/etc/xray2/fullchain.cer",
                "KeyFile": "/etc/xray2/cert.key"
            }
        }]
}
EOF

# --- [ 6. 维护工具 x2 生成 (保持不变) ] ---
cat <<EOF > /usr/bin/x2
#!/bin/bash
case "\$1" in
    log) journalctl -u xray2 -f ;;
    restart) systemctl restart xray2 && echo "重启成功" ;;
    stop) systemctl stop xray2 && echo "已停止" ;;
    start) systemctl start xray2 && echo "已启动" ;;
    status) systemctl status xray2 ;;
    uninstall) 
        systemctl stop xray2
        systemctl disable xray2
        rm -rf /usr/local/xray2 /etc/xray2 /usr/bin/x2 /etc/systemd/system/xray2.service
        echo "已彻底卸载" ;;
    *) echo "使用方法: x2 {log|restart|stop|start|status|uninstall}" ;;
esac
EOF
chmod +x /usr/bin/x2

# --- [ 7. 系统服务构建 (保持不变) ] ---
cat <<EOF > /etc/systemd/system/xray2.service
[Unit]
Description=xray2 Service
After=network.target
[Service]
User=root
WorkingDirectory=/usr/local/xray2
ExecStart=/usr/local/xray2/xray2_core server -c /etc/xray2/config.json
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload && systemctl enable xray2 && systemctl restart xray2

# --- [ 8. 成功面板 (界面增加广告显示) ] ---
clear
echo -e "${GREEN}======================================================${PLAIN}"
echo -e "✅ $BRAND_NAME 部署成功！       作者：${AUTHOR}"
# === 增加广告显示 ===
echo -e "${BLUE}------------------------------------------------------${PLAIN}"
echo -e "${YELLOW}  $AD_MESSAGE_1 ${PLAIN}"
echo -e "${YELLOW}  $AD_MESSAGE_2 ${PLAIN}"
echo -e "${BLUE}------------------------------------------------------${PLAIN}"
# === 增加广告显示 ===
echo -e "协议: ${YELLOW}$NODE_TYPE${PLAIN} | 域名: ${YELLOW}$C_DOMAIN${PLAIN}"
echo -e "管理指令: ${GREEN}x2 {log|restart|stop|start|status|uninstall}${PLAIN}"
echo -e "请确保证书存放在: /etc/xray2/fullchain.cer 和 cert.key"
echo -e "${GREEN}======================================================${PLAIN}"
