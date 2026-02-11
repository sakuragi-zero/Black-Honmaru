#!/bin/bash
# エラー発生時に終了、未定義変数の使用を禁止、パイプライン内のエラーで終了
set -euo pipefail
# 内部フィールド区切り文字を改行とタブのみに設定（より安全な文字列分割）
IFS=$'\n\t'

# ========================================
# 1. Docker DNS設定の保存
# ========================================
# iptablesルールをフラッシュする前に、Docker内部DNS（127.0.0.11）の設定を抽出して保存
DOCKER_DNS_RULES=$(iptables-save -t nat | grep "127\.0\.0\.11" || true)

# ========================================
# 2. 既存のファイアウォールルールをクリア
# ========================================
# すべてのフィルタルールをフラッシュ（削除）
iptables -F
# すべてのユーザー定義チェーンを削除
iptables -X
# NATテーブルのルールをフラッシュ
iptables -t nat -F
# NATテーブルのユーザー定義チェーンを削除
iptables -t nat -X
# mangleテーブルのルールをフラッシュ
iptables -t mangle -F
# mangleテーブルのユーザー定義チェーンを削除
iptables -t mangle -X
# 既存のallowed-domains ipsetを削除（エラーは無視）
ipset destroy allowed-domains 2>/dev/null || true

# ========================================
# 3. Docker DNS設定の復元
# ========================================
# 保存しておいたDocker内部DNSルールを選択的に復元
if [ -n "$DOCKER_DNS_RULES" ]; then
    echo "Restoring Docker DNS rules..."
    # Docker用のカスタムチェーンを作成（既存の場合はエラーを無視）
    iptables -t nat -N DOCKER_OUTPUT 2>/dev/null || true
    iptables -t nat -N DOCKER_POSTROUTING 2>/dev/null || true
    # 保存したDNSルールを1行ずつ復元
    echo "$DOCKER_DNS_RULES" | xargs -L 1 iptables -t nat
else
    echo "No Docker DNS rules to restore"
fi

# ========================================
# 4. 基本的な通信を許可（制限前に設定）
# ========================================
# 送信DNS通信を許可（UDPポート53）
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
# 受信DNS応答を許可
iptables -A INPUT -p udp --sport 53 -j ACCEPT
# 送信SSH通信を許可（TCPポート22）
iptables -A OUTPUT -p tcp --dport 22 -j ACCEPT
# 受信SSH応答を許可（確立済み接続のみ）
iptables -A INPUT -p tcp --sport 22 -m state --state ESTABLISHED -j ACCEPT
# ローカルループバック通信を許可（localhost）
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# ========================================
# 5. 許可ドメイン用のIPセットを作成
# ========================================
# CIDR形式のネットワークアドレスを格納できるipsetを作成
ipset create allowed-domains hash:net

# ========================================
# 6. GitHubのIPアドレス範囲を取得して追加
# ========================================
echo "Fetching GitHub IP ranges..."
# GitHub APIからメタ情報（IPアドレス範囲）を取得
gh_ranges=$(curl -s https://api.github.com/meta)
if [ -z "$gh_ranges" ]; then
    echo "ERROR: Failed to fetch GitHub IP ranges"
    exit 1
fi

# APIレスポンスに必要なフィールドが含まれているか検証
if ! echo "$gh_ranges" | jq -e '.web and .api and .git' > /dev/null; then
    echo "ERROR: GitHub API response missing required fields"
    exit 1
fi

echo "Processing GitHub IPs..."
# GitHub IPアドレスを処理して追加
while read -r cidr; do
    # CIDR形式が正しいか検証（例：192.168.1.0/24）
    if [[ ! "$cidr" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        echo "ERROR: Invalid CIDR range from GitHub meta: $cidr"
        exit 1
    fi
    echo "Adding GitHub range $cidr"
    # ipsetにGitHubのIPアドレス範囲を追加
    ipset add allowed-domains "$cidr"
done < <(echo "$gh_ranges" | jq -r '(.web + .api + .git)[]' | aggregate -q)

# ========================================
# 7. その他の許可ドメインを解決して追加
# ========================================
# 許可するドメインのリスト：
# - registry.npmjs.org: npmパッケージレジストリ
# - api.anthropic.com: Anthropic API
# - sentry.io: エラートラッキングサービス
# - statsig.anthropic.com: Anthropic統計サービス
# - statsig.com: 統計サービス
# - marketplace.visualstudio.com: VS Code拡張機能マーケットプレイス
# - vscode.blob.core.windows.net: VS Codeリソースストレージ
# - update.code.visualstudio.com: VS Codeアップデートサーバー
for domain in \
    "registry.npmjs.org" \
    "api.anthropic.com" \
    "sentry.io" \
    "statsig.anthropic.com" \
    "statsig.com" \
    "marketplace.visualstudio.com" \
    "vscode.blob.core.windows.net" \
    "update.code.visualstudio.com"; do
    echo "Resolving $domain..."
    # digコマンドでドメインのAレコード（IPv4アドレス）を取得
    ips=$(dig +noall +answer A "$domain" | awk '$4 == "A" {print $5}')
    if [ -z "$ips" ]; then
        echo "ERROR: Failed to resolve $domain"
        exit 1
    fi
    
    # 取得した各IPアドレスを処理
    while read -r ip; do
        # IPアドレス形式が正しいか検証
        if [[ ! "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            echo "ERROR: Invalid IP from DNS for $domain: $ip"
            exit 1
        fi
        echo "Adding $ip for $domain"
        # ipsetにIPアドレスを追加
        ipset add allowed-domains "$ip"
    done < <(echo "$ips")
done

# ========================================
# 8. ホストネットワークの検出と許可
# ========================================
# デフォルトゲートウェイからホストIPを取得
HOST_IP=$(ip route | grep default | cut -d" " -f3)
if [ -z "$HOST_IP" ]; then
    echo "ERROR: Failed to detect host IP"
    exit 1
fi

# ホストIPから/24ネットワークを計算（例：192.168.1.0/24）
HOST_NETWORK=$(echo "$HOST_IP" | sed "s/\.[0-9]*$/.0\/24/")
echo "Host network detected as: $HOST_NETWORK"

# ========================================
# 9. ホストネットワークとの通信を許可
# ========================================
# ホストネットワークからの受信を許可
iptables -A INPUT -s "$HOST_NETWORK" -j ACCEPT
# ホストネットワークへの送信を許可
iptables -A OUTPUT -d "$HOST_NETWORK" -j ACCEPT

# ========================================
# 10. デフォルトポリシーを設定（すべて拒否）
# ========================================
# 受信トラフィックのデフォルトを拒否に設定
iptables -P INPUT DROP
# フォワードトラフィックのデフォルトを拒否に設定
iptables -P FORWARD DROP
# 送信トラフィックのデフォルトを拒否に設定
iptables -P OUTPUT DROP

# ========================================
# 11. 確立済み接続を許可
# ========================================
# すでに確立された、または関連する接続の受信を許可
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
# すでに確立された、または関連する接続の送信を許可
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# ========================================
# 12. 許可ドメインへの送信のみ許可
# ========================================
# ipsetに登録されたIPアドレスへの送信のみ許可
iptables -A OUTPUT -m set --match-set allowed-domains dst -j ACCEPT

# ========================================
# 13. その他すべての送信トラフィックを明示的に拒否
# ========================================
# 許可されていない送信トラフィックを即座にREJECT（接続拒否を通知）
iptables -A OUTPUT -j REJECT --reject-with icmp-admin-prohibited

# ========================================
# 14. ファイアウォール設定の検証
# ========================================
echo "Firewall configuration complete"
echo "Verifying firewall rules..."

# テスト1: example.comへの接続が拒否されることを確認（ファイアウォールが機能しているか）
if curl --connect-timeout 5 https://example.com > /dev/null 2>&1; then
    echo "ERROR: Firewall verification failed - was able to reach https://example.com"
    exit 1
else
    echo "Firewall verification passed - unable to reach https://example.com as expected"
fi

# テスト2: GitHub APIへの接続が成功することを確認（許可リストが機能しているか）
if ! curl --connect-timeout 5 https://api.github.com/zen > /dev/null 2>&1; then
    echo "ERROR: Firewall verification failed - unable to reach https://api.github.com"
    exit 1
else
    echo "Firewall verification passed - able to reach https://api.github.com as expected"
fi