#!/bin/bash
# 基础APK下载脚本（支持多仓库）

# 多仓库配置
declare -A REPOS=(
    ["netamade"]="z0brk/netamade-releases"
    ["vehicle"]="netcookies/Neta-Vehicle"
)

# 基础目录
BASE_DIR="/var/www/apk-downloads"
CHECK_INTERVAL=600

log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" | tee -a /var/log/apk-downloader.log
}

log_warn() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $1" | tee -a /var/log/apk-downloader.log
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" | tee -a /var/log/apk-downloader.log
}

# 获取GitHub Token
get_github_token() {
    # 从环境变量获取
    if [ -n "$GITHUB_TOKEN" ]; then
        echo "$GITHUB_TOKEN"
        return 0
    fi
    
    # 从/etc/profile获取
    if [ -f /etc/profile ]; then
        local token
        token=$(grep -E "^export GITHUB_TOKEN=" /etc/profile 2>/dev/null | cut -d'"' -f2)
        if [ -n "$token" ]; then
            echo "$token"
            return 0
        fi
    fi
    
    return 1
}

get_latest_release() {
    local repo_name="$1"
    local repo_path="${REPOS[$repo_name]}"
    local api_url="https://api.github.com/repos/${repo_path}/releases/latest"
    local github_token
    github_token=$(get_github_token)
    
    local response
    if [ -n "$github_token" ]; then
        response=$(curl -s -H "Accept: application/vnd.github+json" -H "Authorization: Bearer $github_token" -H "X-GitHub-Api-Version: 2022-11-28" "$api_url")
    else
        response=$(curl -s -H "Accept: application/vnd.github+json" -H "User-Agent: APK-Downloader" "$api_url")
    fi
    
    if [ $? -ne 0 ] || [ -z "$response" ]; then
        log_error "[$repo_name] 无法获取GitHub API响应"
        return 1
    fi
    
    if echo "$response" | grep -q '"message":'; then
        log_error "[$repo_name] GitHub API错误: $(echo "$response" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('message', 'Unknown error'))")"
        return 1
    fi
    
    echo "$response"
}

download_apk() {
    local repo_name="$1"
    local release_info="$2"
    local repo_dir="${BASE_DIR}/${repo_name}"
    
    # 确保仓库目录存在
    mkdir -p "$repo_dir"
    
    local apk_urls
    apk_urls=$(echo "$release_info" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for asset in data.get('assets', []):
    if asset['name'].lower().endswith('.apk'):
        print(asset['browser_download_url'])
")
    
    if [ -z "$apk_urls" ]; then
        log_warn "[$repo_name] 未找到APK文件"
        return 1
    fi
    
    # 下载每个APK
    while IFS= read -r download_url; do
        if [ -n "$download_url" ] && [ "$download_url" != "null" ]; then
            local apk_name
            apk_name=$(basename "$download_url")
            local apk_path="${repo_dir}/${apk_name}"
            local github_token
            github_token=$(get_github_token)
            
            log_info "[$repo_name] 下载APK: $apk_name"
            
            local curl_opts="-L -o \"$apk_path\""
            if [ -n "$github_token" ]; then
                curl_opts="$curl_opts -H \"Authorization: Bearer $github_token\""
            else
                curl_opts="$curl_opts -H \"User-Agent: APK-Downloader\""
            fi
            
            if eval curl $curl_opts "$download_url"; then
                log_info "[$repo_name] 下载成功: $apk_name"
                chmod 644 "$apk_path"
                
                # 清理旧文件，只保留最新的3个
                cd "$repo_dir" 2>/dev/null || return 0
                ls -t *.apk 2>/dev/null | tail -n +4 | xargs -r rm -f
                
                return 0
            else
                log_error "[$repo_name] 下载失败: $apk_name"
                rm -f "$apk_path"
                return 1
            fi
        fi
    done <<< "$apk_urls"
}

main_loop() {
    log_info "APK下载服务启动"
    log_info "监控仓库数量: ${#REPOS[@]}"
    log_info "检查间隔: ${CHECK_INTERVAL}秒"
    
    # 显示所有仓库
    for repo_name in "${!REPOS[@]}"; do
        log_info "  - ${repo_name}: ${REPOS[$repo_name]}"
    done
    
    # 首次检查所有仓库
    for repo_name in "${!REPOS[@]}"; do
        local release_info
        release_info=$(get_latest_release "$repo_name")
        if [ $? -eq 0 ] && [ -n "$release_info" ]; then
            download_apk "$repo_name" "$release_info"
        fi
    done
    
    # 主循环
    while true; do
        sleep "$CHECK_INTERVAL"
        
        for repo_name in "${!REPOS[@]}"; do
            local release_info
            release_info=$(get_latest_release "$repo_name")
            if [ $? -eq 0 ] && [ -n "$release_info" ]; then
                download_apk "$repo_name" "$release_info"
            fi
        done
    done
}

main_loop