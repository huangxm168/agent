#!/bin/bash

# VPS Agent 部署管理脚本

set -e

# ============================================================
# 全局配置
# ============================================================

# 路径配置
INSTALL_DIR="/opt/agent"
BINARY_NAME="vps-agent"
SERVICE_NAME="vps-agent"
ENV_FILE="$INSTALL_DIR/.env"
ENV_EXAMPLE_FILE="$INSTALL_DIR/.env.example"
CONFIG_DIR="$INSTALL_DIR/config"

# GitHub 配置
GITHUB_REPO="huangxm168/agent"
GITHUB_RAW_URL="https://raw.githubusercontent.com/$GITHUB_REPO/main"
GITHUB_RELEASE_URL="https://github.com/$GITHUB_REPO/releases"

# 历史版本列表显示数量
VERSION_LIST_COUNT=10

# ============================================================
# 颜色定义
# ============================================================

# 基础颜色
RED='\033[38;5;124m'
RED_BOLD='\033[1;38;5;196m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
YELLOW_BRIGHT='\033[38;5;226m'
YELLOW_LIGHT='\033[38;2;238;242;46m'
ORANGE='\033[38;5;208m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color

# 语义颜色
COLOR_TITLE="$WHITE"         # 标题
COLOR_MENU="$CYAN"           # 菜单选项
COLOR_PROMPT="$YELLOW"       # 输入提示
COLOR_SUCCESS="$GREEN"       # 成功信息
COLOR_ERROR="$RED"           # 错误信息
COLOR_WARN="$YELLOW_BRIGHT"  # 警告信息
COLOR_INFO="$BLUE"           # 一般信息
COLOR_HINT="$GRAY"           # 提示/说明文字
COLOR_VALUE="$MAGENTA"       # 显示的值
COLOR_STEP="$CYAN"           # 步骤标识

# ============================================================
# 工具函数
# ============================================================

# 打印分隔线
print_separator_1() {
    echo -e "${COLOR_HINT}═════════════════════════════════════════${NC}"
}

print_separator_2() {
    echo -e "${COLOR_HINT}═══════════════════════════════════════════════════${NC}"
}

print_separator_3() {
    echo -e "${COLOR_HINT}***********************${NC}"
}

# 打印标题
print_title() {
    echo ""
    print_separator_1
    echo -e "${COLOR_TITLE}       $1${NC}"
    print_separator_1
    echo ""
}

# 打印步骤
print_step() {
    echo -e "${COLOR_STEP}[$1]${NC} $2"
}

# 打印成功
print_success() {
    echo -e "${COLOR_SUCCESS}✓${NC} $1"
}

# 打印错误
print_error() {
    echo -e "${COLOR_ERROR}× 错误：${NC}$1"
}

# 打印警告
print_warn() {
    echo -e "${COLOR_WARN}⚠️ 警告：${NC}$1"
}

# 打印信息
print_info() {
    echo -e "${COLOR_INFO}→${NC} $1"
}

# 打印提示
print_hint() {
    echo -e "${COLOR_HINT}  $1${NC}"
}

# 打印环境变量配置提示（无缩进，用于配置阶段）
print_env_hint() {
    echo -e "${COLOR_HINT}$1${NC}"
}

# 获取用户输入
# 参数：$1=提示文字, $2=默认值（可选）, $3=提示类型（可选）
# 提示类型：
#   - 不传或空：有默认值时显示 "[默认: xxx]"，无默认值时只显示提示文字
#   - "skip"：显示 "[按回车键跳过]"
get_input() {
    local prompt="$1"
    local default="$2"
    local hint_type="$3"
    local input

    # 提示信息输出到 stderr，避免被 $() 捕获
    if [ "$hint_type" = "skip" ]; then
        echo -ne "${COLOR_PROMPT}$prompt${NC}${COLOR_HINT}[按回车键跳过]${NC}: " >&2
    elif [ -n "$default" ]; then
        echo -ne "${COLOR_PROMPT}$prompt${NC}${COLOR_HINT}[默认: $default]${NC}: " >&2
    else
        echo -ne "${COLOR_PROMPT}$prompt${NC}: " >&2
    fi

    read -r input

    if [ -z "$input" ] && [ -n "$default" ]; then
        echo "$default"
    else
        echo "$input"
    fi
}

# 获取是否确认（Y/n）
confirm() {
    local prompt="$1"
    local default="${2:-y}"
    local input

    if [ "$default" = "y" ]; then
        echo -ne "${COLOR_PROMPT}$prompt${NC}${COLOR_HINT}[Y/n]${NC}: "
    else
        echo -ne "${COLOR_PROMPT}$prompt${NC}${COLOR_HINT}[y/N]${NC}: "
    fi

    read -r input
    input="${input:-$default}"

    [[ "$input" =~ ^[Yy]$ ]]
}

# 敏感操作确认（需要输入 CONFIRM）
# 返回值：0=确认，1=取消
confirm_dangerous() {
    local prompt="$1"
    local input

    echo -e "${YELLOW_BRIGHT}警告：${NC}${RED_BOLD}$prompt${NC}"
    echo ""
    echo -e "${COLOR_HINT}此操作不可逆，请输入 ${NC}${COLOR_ERROR}CONFIRM${NC}${COLOR_HINT} 确认执行，或输入其他内容取消${NC}"
    echo ""
    echo -ne "${COLOR_PROMPT}请输入${NC}: "
    read -r input

    [ "$input" = "CONFIRM" ]
}

# 检查命令是否存在
check_command() {
    command -v "$1" &> /dev/null
}

# ============================================================
# 主菜单
# ============================================================

show_main_menu() {
    local installed_version=$(get_installed_version)
    local status_text
    local service_file="/etc/systemd/system/$SERVICE_NAME.service"

    if [ -n "$installed_version" ]; then
        if [ -f "$service_file" ]; then
            # 服务文件存在，检查运行状态
            if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
                status_text="${COLOR_SUCCESS}运行中${NC} ${COLOR_VALUE}$installed_version${NC}"
            else
                status_text="${COLOR_WARN}已停止${NC} ${COLOR_VALUE}$installed_version${NC}"
            fi
        else
            # 二进制存在但服务未配置（中途退出）
            status_text="${ORANGE}未完成安装${NC} ${COLOR_VALUE}$installed_version${NC}"
        fi
    else
        status_text="${COLOR_HINT}未安装${NC}"
    fi

    print_title "VPS Agent 部署管理工具"

    echo -e "当前状态: $status_text"
    echo ""
    echo -e "${COLOR_INFO}请选择操作：${NC}"
    echo ""
    echo -e "  ${COLOR_MENU}1.${NC} 部署服务"
    echo ""
    echo -e "  ${COLOR_MENU}2.${NC} 更新服务"
    echo ""
    echo -e "  ${COLOR_MENU}3.${NC} 服务管理"
    echo -e "  ${COLOR_MENU}4.${NC} 查看日志"
    echo ""
    echo -e "  ${COLOR_MENU}5.${NC} 卸载"
    echo ""
    echo -e "  ${COLOR_MENU}0.${NC} 退出"
    echo ""

    local choice=$(get_input "请输入选项")

    case "$choice" in
        1) do_fresh_install ;;
        2) show_update_menu ;;
        3) show_service_menu ;;
        4) do_view_logs ;;
        5) show_uninstall_menu ;;
        0) exit 0 ;;
        *)
            echo ""
            print_error "输入有误，无效选项"
            show_main_menu
            ;;
    esac
}

# ============================================================
# 更新服务子菜单
# ============================================================

show_update_menu() {
    print_title "更新服务"

    echo -e "${COLOR_INFO}请选择更新方式：${NC}"
    echo ""
    echo -e "  ${COLOR_MENU}1.${NC} 完整更新${COLOR_HINT}（二进制文件 + 配置文件）${NC}"
    echo ""
    echo -e "  ${COLOR_MENU}2.${NC} 仅更新二进制文件"
    echo -e "  ${COLOR_MENU}3.${NC} 仅更新配置文件"
    echo ""
    echo -e "  ${COLOR_MENU}4.${NC} 修改环境变量配置"
    echo ""
    echo -e "  ${COLOR_MENU}0.${NC} 返回主菜单"
    echo ""

    local choice=$(get_input "请输入选项")

    case "$choice" in
        1) do_update_agent ;;
        2) do_update_binary ;;
        3) do_update_config ;;
        4) do_modify_config ;;
        0) show_main_menu ;;
        *)
            echo ""
            print_error "无效选项"
            show_update_menu
            ;;
    esac
}

# ============================================================
# 环境检查
# ============================================================

check_environment() {
    echo ""
    print_step "1/6" "环境检查"
    echo ""

    local has_error=false

    # 检查操作系统
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        print_success "操作系统: $NAME $VERSION_ID"
    else
        print_warn "无法检测操作系统"
    fi

    # 检查架构
    local arch=$(uname -m)
    if [ "$arch" = "x86_64" ]; then
        print_success "系统架构: amd64"
    else
        print_error "不支持的架构: $arch（仅支持 x86_64）"
        has_error=true
    fi

    # 检查 root 权限
    if [ "$EUID" -eq 0 ]; then
        print_success "运行权限: root"
    else
        print_error "需要 root 权限运行此脚本"
        has_error=true
    fi

    # 检查 systemd
    if check_command systemctl; then
        print_success "systemd: 可用"
    else
        print_error "systemd 不可用"
        has_error=true
    fi

    # 检查 curl
    if check_command curl; then
        print_success "curl: 可用"
    else
        print_error "curl 未安装"
        has_error=true
    fi

    # 检查/安装 yq
    if check_command yq; then
        print_success "yq: 可用"
    else
        print_info "正在安装 yq..."
        if install_yq; then
            print_success "yq: 已安装"
        else
            print_error "yq 安装失败"
            has_error=true
        fi
    fi

    echo ""

    if [ "$has_error" = true ]; then
        print_error "环境检查未通过，请解决上述问题后重试"
        exit 1
    fi

    print_success "环境检查通过"
}

# 安装 yq
install_yq() {
    local yq_url="https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64"
    curl -fsSL "$yq_url" -o /usr/local/bin/yq && chmod +x /usr/local/bin/yq
}

# ============================================================
# 版本管理
# ============================================================

# 获取已安装版本
get_installed_version() {
    if [ -x "$INSTALL_DIR/$BINARY_NAME" ]; then
        "$INSTALL_DIR/$BINARY_NAME" --version 2>/dev/null | head -1 | awk '{print $2}'
    else
        echo ""
    fi
}

# 获取最新 Release 版本
get_latest_version() {
    curl -fsSL "https://api.github.com/repos/$GITHUB_REPO/releases/latest" 2>/dev/null | \
        grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/'
}

# 获取版本列表（带发布时间）
# 输出格式：tag_name|published_at（每行一个）
get_versions_with_time() {
    curl -fsSL "https://api.github.com/repos/$GITHUB_REPO/releases" 2>/dev/null | \
        grep -E '"tag_name"|"published_at"' | \
        sed -E 's/.*"(tag_name|published_at)": "([^"]+)".*/\2/' | \
        paste - - | \
        awk '{print $1"|"$2}'
}

# 验证版本号格式
# 格式：v + 8位日期 + 短横线 + 7位commit哈希
validate_version_format() {
    local version="$1"
    [[ "$version" =~ ^v[0-9]{8}-[a-f0-9]{7}$ ]]
}

# 规范化版本号（自动补全v前缀）
normalize_version() {
    local version="$1"
    # 如果没有v前缀，自动补上
    if [[ "$version" =~ ^[0-9]{8}-[a-f0-9]{7}$ ]]; then
        echo "v$version"
    else
        echo "$version"
    fi
}

# 格式化发布时间（从 ISO 8601 转为易读格式）
format_publish_time() {
    local iso_time="$1"
    # 输入格式：2025-11-24T15:30:00Z
    # 输出格式：2025-11-24 15:30:00
    echo "$iso_time" | sed 's/T/ /; s/Z//'
}

# 版本选择菜单（公共函数）
# 参数：$1=最新版本号, $2=返回选项文字（可选，默认"返回"）
# 返回值：0=成功选择，1=用户选择返回
# 设置全局变量：SELECTED_VERSION
# 注意：调用前需确保 $1 非空
select_version_menu() {
    local latest_version="$1"
    local return_text="${2:-返回}"

    echo -e "  ${COLOR_MENU}1.${NC} 最新版本 ${COLOR_VALUE}($latest_version)${NC}"
    echo -e "  ${COLOR_MENU}2.${NC} 历史版本"
    echo -e "  ${COLOR_MENU}3.${NC} 手动输入"
    echo ""
    echo -e "  ${COLOR_MENU}0.${NC} $return_text"
    echo ""

    local choice=$(get_input "请选择")

    case "$choice" in
        1)
            SELECTED_VERSION="$latest_version"
            return 0
            ;;
        2)
            if select_from_history; then
                return 0
            fi
            return 2  # 需要重新显示菜单
            ;;
        3)
            if input_version_manually; then
                return 0
            fi
            return 2  # 需要重新显示菜单
            ;;
        0)
            return 1
            ;;
        *)
            echo ""
            print_error "无效选项"
            echo ""
            return 2  # 需要重新显示菜单
            ;;
    esac
}

# 选择版本（部署场景）
# 返回值：0=成功选择，1=用户选择返回
select_version() {
    print_step "2/6" "选择版本"
    echo ""

    local latest_version=$(get_latest_version)

    if [ -z "$latest_version" ]; then
        print_error "无法获取版本信息，请检查网络连接"
        echo ""
        echo -e "  ${COLOR_MENU}1.${NC} 重试"
        echo ""
        echo -e "  ${COLOR_MENU}0.${NC} 返回主菜单"
        echo ""
        local retry_choice=$(get_input "请选择")
        if [ "$retry_choice" = "1" ]; then
            select_version
            return $?
        else
            return 1
        fi
    fi

    while true; do
        select_version_menu "$latest_version" "返回主菜单"
        local result=$?

        case $result in
            0)
                # 选择成功
                echo ""
                echo -e "${GREEN}✓${NC} 已选择版本: ${COLOR_VALUE}$SELECTED_VERSION${NC}"
                return 0
                ;;
            1)
                # 用户选择返回
                return 1
                ;;
            2)
                # 需要重新显示菜单
                continue
                ;;
        esac
    done
}

# 从历史版本中选择
# 返回值：0=成功选择，1=用户选择返回
select_from_history() {
    echo ""
    print_info "获取版本列表..."

    # 获取版本列表
    local versions_data=$(get_versions_with_time)

    if [ -z "$versions_data" ]; then
        print_error "无法获取版本列表"
        return 1
    fi

    # 存储版本信息到数组
    local -a version_tags=()
    local -a version_times=()
    local count=0

    while IFS='|' read -r tag time; do
        if [ $count -ge $VERSION_LIST_COUNT ]; then
            break
        fi
        count=$((count + 1))
        version_tags+=("$tag")
        version_times+=("$(format_publish_time "$time")")
    done <<< "$versions_data"

    if [ ${#version_tags[@]} -eq 0 ]; then
        print_error "没有可用的版本"
        return 1
    fi

    echo ""
    echo -e "${COLOR_INFO}最近 ${#version_tags[@]} 个版本：${NC}"
    echo ""

    for i in "${!version_tags[@]}"; do
        local num=$((i + 1))
        echo -e "  ${COLOR_MENU}$num.${NC} ${COLOR_VALUE}${version_tags[$i]}${NC}  ${COLOR_HINT}(${version_times[$i]})${NC}"
    done

    echo ""
    echo -e "  ${COLOR_MENU}0.${NC} 返回"
    echo ""

    while true; do
        local choice=$(get_input "请选择")

        if [ "$choice" = "0" ]; then
            return 1
        fi

        # 验证输入是否为有效数字
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#version_tags[@]} ]; then
            local index=$((choice - 1))
            SELECTED_VERSION="${version_tags[$index]}"
            return 0
        else
            echo ""
            print_error "无效选项，请输入 1-${#version_tags[@]} 或 0 返回"
        fi
    done
}

# 手动输入版本号
# 返回值：0=成功输入，1=用户选择返回
input_version_manually() {
    echo ""
    print_hint "版本号格式：v + 8位日期 + 短横线 + 7位commit哈希"
    print_hint "例如：v20251124-76843f9"
    print_hint "可省略 v 前缀，脚本会自动补全"
    print_hint "输入 0 返回"
    echo ""

    while true; do
        local input=$(get_input "版本号")

        if [ "$input" = "0" ]; then
            return 1
        fi

        if [ -z "$input" ]; then
            print_error "版本号不能为空"
            continue
        fi

        # 规范化版本号（自动补全v前缀）
        local normalized=$(normalize_version "$input")

        # 验证格式
        if validate_version_format "$normalized"; then
            SELECTED_VERSION="$normalized"
            return 0
        else
            echo ""
            print_error "无效版本号格式，正确格式如：v20251124-76843f9"
            echo ""
        fi
    done
}

# ============================================================
# 下载文件
# ============================================================

# 下载文件
# 返回值：0=成功，1=用户选择返回，2=需要重新选择版本
download_files() {
    print_step "3/6" "下载文件"
    echo ""

    # 创建安装目录
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$CONFIG_DIR"

    # 下载二进制文件
    if ! download_binary; then
        return $?
    fi

    # 下载配置文件
    if ! download_config_files; then
        return $?
    fi

    # 下载 .env.example（必须成功，后续配置依赖此模板）
    if ! download_env_template; then
        return $?
    fi

    echo ""
    return 0
}

# 下载二进制文件
# 返回值：0=成功，1=用户选择返回主菜单，2=需要重新选择版本
download_binary() {
    print_info "下载 Agent 二进制文件..."
    local binary_url="$GITHUB_RELEASE_URL/download/$SELECTED_VERSION/$BINARY_NAME"

    # 尝试下载，捕获HTTP状态码
    local http_code
    http_code=$(curl -fsSL -w "%{http_code}" "$binary_url" -o "$INSTALL_DIR/$BINARY_NAME" 2>/dev/null)
    local curl_exit=$?

    if [ $curl_exit -eq 0 ]; then
        chmod +x "$INSTALL_DIR/$BINARY_NAME"
        echo -e "  ${GREEN}✓${NC} ${COLOR_HINT}vps-agent${NC}"
        return 0
    fi

    # 下载失败，根据错误类型显示不同信息
    echo ""
    if [ "$http_code" = "404" ]; then
        print_error "二进制文件下载失败，状态码：404"
        print_hint "版本 $SELECTED_VERSION 可能不存在"
    else
        print_error "二进制文件下载失败"
        print_hint "可能是网络问题，请检查连接"
    fi

    echo ""
    echo -e "  ${COLOR_MENU}1.${NC} 重新选择版本"
    echo -e "  ${COLOR_MENU}2.${NC} 重试下载"
    echo ""
    echo -e "  ${COLOR_MENU}0.${NC} 返回主菜单"
    echo ""

    while true; do
        local choice=$(get_input "请选择")
        case "$choice" in
            1)
                return 2  # 需要重新选择版本
                ;;
            2)
                download_binary
                return $?
                ;;
            0)
                return 1  # 返回主菜单
                ;;
            *)
                echo ""
                print_error "无效选项"
                ;;
        esac
    done
}

# 下载配置文件
# 返回值：0=成功，1=用户选择返回主菜单
download_config_files() {
    print_info "下载配置文件..."

    # 配置文件列表
    local config_files=(
        "config/probe-targets.yaml"
        "config/administrative-divisions/cn/cities-code.json"
        "config/administrative-divisions/cn/provinces-code.json"
        "config/administrative-divisions/global/cities-code.json"
        "config/administrative-divisions/global/countries-code.json"
        "config/network-providers/network-providers-code.json"
    )

    for file in "${config_files[@]}"; do
        local dir=$(dirname "$INSTALL_DIR/$file")
        mkdir -p "$dir"
        if curl -fsSL "$GITHUB_RAW_URL/$file" -o "$INSTALL_DIR/$file" 2>/dev/null; then
            echo -e "  ${GREEN}✓${NC} ${COLOR_HINT}$file${NC}"
        else
            echo -e "  ${RED}×${NC} ${COLOR_HINT}$file${NC} ${RED}下载失败${NC}"
            echo ""
            echo -e "  ${COLOR_MENU}1.${NC} 重试下载"
            echo ""
            echo -e "  ${COLOR_MENU}0.${NC} 返回主菜单"
            echo ""

            while true; do
                local choice=$(get_input "请选择")
                case "$choice" in
                    1)
                        download_config_files
                        return $?
                        ;;
                    0)
                        return 1
                        ;;
                    *)
                        echo ""
                        print_error "无效选项"
                        ;;
                esac
            done
        fi
    done

    return 0
}

# 下载环境变量模板
# 返回值：0=成功，1=用户选择返回主菜单
download_env_template() {
    print_info "下载环境变量模板..."

    if curl -fsSL "$GITHUB_RAW_URL/.env.example" -o "$ENV_EXAMPLE_FILE" 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} ${COLOR_HINT}.env.example${NC}"
        return 0
    fi

    # 下载失败
    echo -e "  ${RED}×${NC} ${COLOR_HINT}.env.example${NC} ${RED}下载失败${NC}"
    print_warn "此文件是后续配置的必要依赖"
    echo ""
    echo -e "  ${COLOR_MENU}1.${NC} 重试下载"
    echo ""
    echo -e "  ${COLOR_MENU}0.${NC} 返回主菜单"
    echo ""

    while true; do
        local choice=$(get_input "请选择")
        case "$choice" in
            1)
                download_env_template
                return $?
                ;;
            0)
                return 1
                ;;
            *)
                echo ""
                print_error "无效选项"
                ;;
        esac
    done
}

# ============================================================
# 监测目标配置
# ============================================================

# 解析并显示可用的监测目标
show_probe_targets() {
    local yaml_file="$CONFIG_DIR/probe-targets.yaml"

    if [ ! -f "$yaml_file" ]; then
        print_error "配置文件不存在: $yaml_file"
        exit 1
    fi

    echo -e "${COLOR_INFO}可用监测目标：${NC}"
    echo ""

    # 使用 yq 解析 YAML
    # 输出格式：target_id|target_name|icmp_addr_count|tcp_addr_count|probes_types
    local count=0
    while IFS= read -r line; do
        count=$((count + 1))
        local target_id=$(echo "$line" | cut -d'|' -f1)
        local target_name=$(echo "$line" | cut -d'|' -f2)
        local icmp_count=$(echo "$line" | cut -d'|' -f3)
        local tcp_count=$(echo "$line" | cut -d'|' -f4)
        local probes=$(echo "$line" | cut -d'|' -f5)

        # 构建协议显示
        local proto_display=""
        if [ "$icmp_count" -gt 0 ]; then
            proto_display="ICMP($icmp_count)"
        fi
        if [ "$tcp_count" -gt 0 ]; then
            [ -n "$proto_display" ] && proto_display="$proto_display, "
            proto_display="${proto_display}TCP($tcp_count)"
        fi

        echo -e "  ${COLOR_MENU}$count.${NC} $target_name: $proto_display"

        # 保存到数组供后续使用
        TARGET_IDS[$count]="$target_id"
        TARGET_NAMES[$count]="$target_name"
        TARGET_PROBES[$count]="$probes"
    done < <(yq eval '.targets[] |
        .target_id + "|" +
        .target_name + "|" +
        ([.probes[] | select(.type == "icmp") | .addrs[]] | length | tostring) + "|" +
        ([.probes[] | select(.type == "tcp") | .addrs[]] | length | tostring) + "|" +
        ([.probes[].type] | join(","))' "$yaml_file")

    TARGET_COUNT=$count
    echo ""
}

# 配置监测目标
configure_probe_targets() {
    print_info "加载监测目标"
    echo ""

    # 声明关联数组
    declare -A TARGET_IDS
    declare -A TARGET_NAMES
    declare -A TARGET_PROBES
    local TARGET_COUNT=0

    # 显示可用目标
    local yaml_file="$CONFIG_DIR/probe-targets.yaml"

    if [ ! -f "$yaml_file" ]; then
        print_error "配置文件不存在: $yaml_file"
        exit 1
    fi

    echo -e "${COLOR_INFO}请选择监测目标：${NC}"
    echo ""

    # 使用 yq 解析 YAML
    # 输出格式：target_id|target_name|icmp_addr_count|tcp_addr_count|probes_types
    local count=0
    while IFS= read -r line; do
        count=$((count + 1))
        local target_id=$(echo "$line" | cut -d'|' -f1)
        local target_name=$(echo "$line" | cut -d'|' -f2)
        local icmp_count=$(echo "$line" | cut -d'|' -f3)
        local tcp_count=$(echo "$line" | cut -d'|' -f4)
        local probes=$(echo "$line" | cut -d'|' -f5)

        # 构建协议显示
        local proto_display=""
        if [ "$icmp_count" -gt 0 ]; then
            proto_display="ICMP($icmp_count)"
        fi
        if [ "$tcp_count" -gt 0 ]; then
            [ -n "$proto_display" ] && proto_display="$proto_display, "
            proto_display="${proto_display}TCP($tcp_count)"
        fi

        echo -e "  ${COLOR_MENU}$count.${NC} $target_name: $proto_display"

        # 保存到数组
        TARGET_IDS[$count]="$target_id"
        TARGET_NAMES[$count]="$target_name"
        TARGET_PROBES[$count]="$probes"
    done < <(yq eval '.targets[] |
        .target_id + "|" +
        .target_name + "|" +
        ([.probes[] | select(.type == "icmp") | .addrs[]] | length | tostring) + "|" +
        ([.probes[] | select(.type == "tcp") | .addrs[]] | length | tostring) + "|" +
        ([.probes[].type] | join(","))' "$yaml_file")

    TARGET_COUNT=$count
    echo ""

    # 用户选择目标（循环验证）
    print_env_hint "支持选择多个监测目标，使用空格分隔，如: 1 2 3"
    echo ""

    local selected=""
    while true; do
        selected=$(get_input "选择监测目标")

        # 检查空输入
        if [ -z "$selected" ]; then
            echo ""
            print_error "必须至少选择一个监测目标"
            echo ""
            continue
        fi

        # 验证所有输入的编号
        local invalid_nums=()
        for num in $selected; do
            # 检查是否为正整数
            if ! [[ "$num" =~ ^[0-9]+$ ]]; then
                invalid_nums+=("$num")
            elif [ -z "${TARGET_IDS[$num]}" ]; then
                invalid_nums+=("$num")
            fi
        done

        # 如果有无效编号，显示警告并重新输入
        if [ ${#invalid_nums[@]} -gt 0 ]; then
            local invalid_str=$(IFS=', '; echo "${invalid_nums[*]}")
            echo ""
            print_warn "输入包含无效编号（$invalid_str）"
            echo ""
            continue
        fi

        # 所有输入有效，跳出循环
        break
    done

    # 解析选择并配置协议
    PING_TARGETS=()
    local target_index=0
    local need_protocol_selection=false

    # 先检查是否有需要选择协议的目标
    for num in $selected; do
        local tprobes="${TARGET_PROBES[$num]}"
        if [[ "$tprobes" == *"icmp"* ]] && [[ "$tprobes" == *"tcp"* ]]; then
            need_protocol_selection=true
            break
        fi
    done

    # 仅当有需要选择协议的目标时才显示提示
    if [ "$need_protocol_selection" = true ]; then
        echo ""
        echo -e "${COLOR_INFO}为双协议监测目标选择监测协议：${NC}"
    fi

    for num in $selected; do
        local tid="${TARGET_IDS[$num]}"
        local tname="${TARGET_NAMES[$num]}"
        local tprobes="${TARGET_PROBES[$num]}"

        # 检查支持的协议
        local has_icmp=false
        local has_tcp=false
        [[ "$tprobes" == *"icmp"* ]] && has_icmp=true
        [[ "$tprobes" == *"tcp"* ]] && has_tcp=true

        if [ "$has_icmp" = true ] && [ "$has_tcp" = true ]; then
            # 同时支持两种协议，需要用户选择
            echo ""
            echo -e "${COLOR_VALUE}$tname${NC}"
            echo ""
            echo -e "  ${COLOR_MENU}1.${NC} ICMP & TCP"
            echo -e "  ${COLOR_MENU}2.${NC} ICMP"
            echo -e "  ${COLOR_MENU}3.${NC} TCP"
            echo ""

            while true; do
                local proto_choice=$(get_input "选择协议")

                case "$proto_choice" in
                    1|"")
                        target_index=$((target_index + 1))
                        PING_TARGETS+=("PING_TARGET_$target_index=$tid:icmp")
                        target_index=$((target_index + 1))
                        PING_TARGETS+=("PING_TARGET_$target_index=$tid:tcp")
                        break
                        ;;
                    2)
                        target_index=$((target_index + 1))
                        PING_TARGETS+=("PING_TARGET_$target_index=$tid:icmp")
                        break
                        ;;
                    3)
                        target_index=$((target_index + 1))
                        PING_TARGETS+=("PING_TARGET_$target_index=$tid:tcp")
                        break
                        ;;
                    *)
                        echo ""
                        print_error "无效选项，请输入 1、2 或 3"
                        echo ""
                        ;;
                esac
            done
        elif [ "$has_icmp" = true ]; then
            target_index=$((target_index + 1))
            PING_TARGETS+=("PING_TARGET_$target_index=$tid:icmp")
        elif [ "$has_tcp" = true ]; then
            target_index=$((target_index + 1))
            PING_TARGETS+=("PING_TARGET_$target_index=$tid:tcp")
        fi
    done

    echo ""
    print_success "已配置 ${#PING_TARGETS[@]} 个监测目标"
}

# ============================================================
# 独立配置函数（供全新部署和修改配置复用）
# ============================================================

# 配置 VPS_ID
config_vps_id() {
    echo -e "${COLOR_INFO}请输入 VPS ID：${NC}"
    echo ""
    print_env_hint "VPS ID 必须和哪吒探针的 ID 相对应"
    echo ""
    ENV_VPS_ID=$(get_input "VPS_ID")
    while ! [[ "$ENV_VPS_ID" =~ ^[1-9][0-9]*$ ]]; do
        echo ""
        print_error "VPS_ID 必须是正整数"
        echo ""
        ENV_VPS_ID=$(get_input "VPS_ID")
    done
}

# 配置 VPS_NAME
config_vps_name() {
    echo -e "${COLOR_INFO}请输入 VPS 名称：${NC}"
    echo ""
    print_env_hint "VPS 名称将用于日志显示，建议直接拷贝哪吒探针配置的名称"
    echo ""
    ENV_VPS_NAME=$(get_input "VPS_NAME" "" "skip")
    if [ -n "$ENV_VPS_NAME" ]; then
        ENV_VPS_NAME_CONFIGURED=true
    else
        ENV_VPS_NAME_CONFIGURED=false
    fi
}

# 配置 HMAC_SECRET
config_hmac_secret() {
    echo -e "${COLOR_INFO}请输入 HMAC 密钥：${NC}"
    echo ""
    print_env_hint "HMAC 密钥用于上报数据前生成签名"
    print_env_hint "要求长度为 64 个字符，仅支持大小写字母和数字"
    echo ""
    echo -e "${YELLOW_BRIGHT}注意：HMAC 密钥必须和 Server 接收端保持一致${NC}"
    echo ""
    print_env_hint "按回车键自动生成随机密钥"
    echo ""

    local hmac_input=$(get_input "HMAC_SECRET")
    if [ -z "$hmac_input" ]; then
        ENV_HMAC_SECRET=$(head -c 512 /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 64)
        echo ""
        echo -e "${COLOR_SUCCESS}✓ 已生成密钥:${NC} ${COLOR_VALUE}$ENV_HMAC_SECRET${NC}"
        echo ""
        echo -e "${YELLOW_BRIGHT}注意：请务必将此密钥应用于 Server 接收端${NC}"
    else
        while true; do
            # 长度验证：必须 64 个字符
            if [ ${#hmac_input} -ne 64 ]; then
                echo ""
                print_error "输入有误，密钥长度必须为 64 个字符，当前 ${#hmac_input} 个"
                echo ""
                hmac_input=$(get_input "HMAC_SECRET")
                continue
            fi
            # 字符集验证：仅允许大小写字母和数字
            if [[ ! "$hmac_input" =~ ^[A-Za-z0-9]+$ ]]; then
                echo ""
                print_error "输入有误，密钥只能包含大小写字母和数字"
                echo ""
                hmac_input=$(get_input "HMAC_SECRET")
                continue
            fi
            break
        done
        ENV_HMAC_SECRET="$hmac_input"
    fi
}

# 配置 SERVER_URL
config_server_url() {
    echo -e "${COLOR_INFO}请输入 Server 接收端 URL：${NC}"
    echo ""
    print_env_hint "需输入完整的 API URL，包含协议、域名和路径"
    print_env_hint "示例：https://your-server.com/api/latency/report"
    echo ""

    while true; do
        ENV_SERVER_URL=$(get_input "SERVER_URL")

        # 检查非空
        if [ -z "$ENV_SERVER_URL" ]; then
            echo ""
            print_error "SERVER_URL 不能为空"
            echo ""
            continue
        fi

        # 检查协议前缀
        if ! [[ "$ENV_SERVER_URL" =~ ^https?:// ]]; then
            echo ""
            print_error "SERVER_URL 必须以 http:// 或 https:// 开头"
            echo ""
            continue
        fi

        # 检查域名格式（必须包含至少一个点，且点后有内容）
        local url_without_protocol="${ENV_SERVER_URL#*://}"
        local domain="${url_without_protocol%%/*}"

        if ! [[ "$domain" =~ \.[a-zA-Z]{2,} ]]; then
            echo ""
            print_error "域名格式无效，示例：example.com"
            echo ""
            continue
        fi

        # 检查是否包含路径（域名后必须有 /xxx）
        local path_part="${url_without_protocol#*/}"
        if [ "$path_part" = "$url_without_protocol" ] || [ -z "$path_part" ]; then
            echo ""
            print_error "必须包含 API 路径，示例：https://example.com/api/report"
            echo ""
            continue
        fi

        # 去掉末尾多余的 /
        ENV_SERVER_URL="${ENV_SERVER_URL%/}"

        break
    done
}

# 配置 PING_SCHEDULE_FREQUENCY
config_ping_frequency() {
    echo -e "${COLOR_INFO}请选择每分钟监测频率：${NC}"
    echo ""
    print_env_hint "监测频率决定每分钟执行监测任务的次数："
    echo ""
    print_env_hint "- 1：每分钟 1 次，任务超时 58 秒"
    print_env_hint "- 2：每分钟 2 次，任务超时 29 秒"
    echo ""
    ENV_PING_FREQUENCY=$(get_input "PING_SCHEDULE_FREQUENCY")
    while [ -z "$ENV_PING_FREQUENCY" ] || ! [[ "$ENV_PING_FREQUENCY" =~ ^[12]$ ]]; do
        echo ""
        if [ -z "$ENV_PING_FREQUENCY" ]; then
            print_error "PING_SCHEDULE_FREQUENCY 不能为空"
        else
            print_warn "输入有误，必须输入数字 1 或 2"
        fi
        echo ""
        ENV_PING_FREQUENCY=$(get_input "PING_SCHEDULE_FREQUENCY")
    done
}

# 配置 PING_SCHEDULE_OFFSET
config_ping_offset() {
    echo -e "${COLOR_INFO}请输入每分钟监测秒数：${NC}"
    echo ""
    print_env_hint "每分钟监测秒数决定每分钟第几秒执行监测任务"
    if [ "$ENV_PING_FREQUENCY" = "2" ]; then
        echo ""
        print_env_hint "当前监测频率为每分钟 2 次，两次执行间隔 30 秒，示例："
        print_env_hint "- 输入 0：第 0 秒和第 30 秒执行"
        print_env_hint "- 输入 15：第 15 秒和第 45 秒执行"
        print_env_hint "- 输入 50：第 20 秒和第 50 秒执行"
    else
        echo ""
        print_env_hint "当前监测频率为每分钟 1 次，示例："
        print_env_hint "- 输入 0：每分钟第 0 秒执行"
        print_env_hint "- 输入 15：每分钟第 15 秒执行"
    fi
    echo ""
    print_env_hint "默认值：0"
    echo ""
    local offset_input=$(get_input "PING_SCHEDULE_OFFSET")
    if [ -z "$offset_input" ]; then
        ENV_PING_OFFSET="0"
        ENV_PING_OFFSET_CONFIGURED=false
    else
        ENV_PING_OFFSET="$offset_input"
        ENV_PING_OFFSET_CONFIGURED=true
    fi
    while ! [[ "$ENV_PING_OFFSET" =~ ^[0-9]+$ ]] || [ "$ENV_PING_OFFSET" -gt 59 ]; do
        echo ""
        print_error "输入有误，必须输入 0-59 的整数数字"
        echo ""
        ENV_PING_OFFSET=$(get_input "PING_SCHEDULE_OFFSET")
        ENV_PING_OFFSET_CONFIGURED=true
    done
}

# 配置 PING_MODE
config_ping_mode() {
    echo -e "${COLOR_INFO}请选择 Ping 模式：${NC}"
    echo ""
    print_env_hint "Ping 模式决定每个目标的监测策略"
    echo ""
    echo -e "  ${COLOR_MENU}1.${NC} 单轮模式 ${COLOR_HINT}（每个目标仅监测一次）${NC}"
    echo -e "  ${COLOR_MENU}2.${NC} 多轮模式 ${COLOR_HINT}（每个目标监测多轮后取中位数）${NC}"
    echo ""
    print_env_hint "默认值：1"
    echo ""
    while true; do
        local ping_mode_choice=$(get_input "请选择（PING_MODE）")
        case "$ping_mode_choice" in
            1|"")
                ENV_PING_MODE="single"
                ENV_PING_MODE_CONFIGURED=false
                break
                ;;
            2)
                ENV_PING_MODE="multi"
                ENV_PING_MODE_CONFIGURED=true
                break
                ;;
            *)
                echo ""
                print_error "无效选项，必须输入数字 1 或 2"
                echo ""
                ;;
        esac
    done
}

# 配置 MULTI_PING_ROUND
config_multi_ping_round() {
    echo -e "${COLOR_INFO}请输入多轮监测轮数：${NC}"
    echo ""
    print_env_hint "多轮监测轮数决定每个目标重复监测的次数，取中位数作为最终结果"
    print_env_hint "轮数越多结果越稳定，但耗时越长，需结合 VPS 和监测目标地理位置综合决定"
    echo ""

    local min_round=3
    local max_round=8
    if [ "$ENV_PING_FREQUENCY" = "2" ]; then
        print_env_hint "当前监测频率为每分钟 2 次，任务超时 29 秒，允许范围：3-5 轮"
        max_round=5
    else
        print_env_hint "当前监测频率为每分钟 1 次，任务超时 58 秒，允许范围：3-8 轮"
    fi

    echo ""
    print_env_hint "默认值：5"
    echo ""
    local round_input=$(get_input "MULTI_PING_ROUND")
    if [ -z "$round_input" ]; then
        ENV_MULTI_PING_ROUND="5"
        ENV_MULTI_PING_ROUND_CONFIGURED=false
    else
        ENV_MULTI_PING_ROUND="$round_input"
        ENV_MULTI_PING_ROUND_CONFIGURED=true
    fi
    # 验证轮数范围
    while ! [[ "$ENV_MULTI_PING_ROUND" =~ ^[0-9]+$ ]] || \
          [ "$ENV_MULTI_PING_ROUND" -lt "$min_round" ] || \
          [ "$ENV_MULTI_PING_ROUND" -gt "$max_round" ]; do
        echo ""
        print_error "无效输入，轮数必须在 $min_round-$max_round 之间"
        echo ""
        ENV_MULTI_PING_ROUND=$(get_input "MULTI_PING_ROUND")
        ENV_MULTI_PING_ROUND_CONFIGURED=true
    done
}

# 配置 MULTI_PING_INTER_DELAY
config_multi_ping_inter_delay() {
    echo -e "${COLOR_INFO}请输入多轮监测的轮间间隔：${NC}"
    echo ""
    print_env_hint "轮间间隔控制每轮监测之间的缓冲时间"
    echo ""
    print_env_hint "默认值：200，单位：毫秒"
    echo ""
    local inter_delay_input=$(get_input "MULTI_PING_INTER_DELAY")
    if [ -z "$inter_delay_input" ]; then
        ENV_MULTI_PING_INTER_DELAY="200"
        ENV_MULTI_PING_INTER_DELAY_CONFIGURED=false
    else
        ENV_MULTI_PING_INTER_DELAY="$inter_delay_input"
        ENV_MULTI_PING_INTER_DELAY_CONFIGURED=true
    fi
}

# 配置 PING_INTRA_DELAY
config_ping_intra_delay() {
    echo -e "${COLOR_INFO}请输入轮内间隔：${NC}"
    echo ""
    print_env_hint "轮内间隔控制同一轮中不同监测点之间的缓冲时间"
    echo ""
    print_env_hint "默认值：100，单位：毫秒"
    echo ""
    local intra_delay_input=$(get_input "PING_INTRA_DELAY")
    if [ -z "$intra_delay_input" ]; then
        ENV_PING_INTRA_DELAY="100"
        ENV_PING_INTRA_DELAY_CONFIGURED=false
    else
        ENV_PING_INTRA_DELAY="$intra_delay_input"
        ENV_PING_INTRA_DELAY_CONFIGURED=true
    fi
}

# 配置 PING_TIMEOUT
config_ping_timeout() {
    echo -e "${COLOR_INFO}请输入单次 Ping 超时时长：${NC}"
    echo ""
    print_env_hint "单次 Ping 超时控制每次监测的最大等待时间"
    echo ""
    print_env_hint "默认值：2000，单位：毫秒"
    echo ""
    local timeout_input=$(get_input "PING_TIMEOUT")
    if [ -z "$timeout_input" ]; then
        ENV_PING_TIMEOUT="2000"
        ENV_PING_TIMEOUT_CONFIGURED=false
    else
        ENV_PING_TIMEOUT="$timeout_input"
        ENV_PING_TIMEOUT_CONFIGURED=true
    fi
}

# 配置 EXECUTION_MODE
config_execution_mode() {
    echo -e "${COLOR_INFO}请选择监测执行模式：${NC}"
    echo ""
    print_env_hint "执行模式决定双协议监测目标的 TCP 和 ICMP 监测执行顺序"
    echo ""
    echo -e "  ${COLOR_MENU}1.${NC} 顺序模式 ${COLOR_HINT}（TCP 完成后再执行 ICMP）${NC}"
    echo -e "  ${COLOR_MENU}2.${NC} 并行模式 ${COLOR_HINT}（TCP 和 ICMP 同时开始）${NC}"
    echo -e "  ${COLOR_MENU}3.${NC} 错峰模式 ${COLOR_HINT}（TCP 先启动，延迟后启动 ICMP）${NC}"
    echo ""
    print_env_hint "默认选项：顺序模式"
    echo ""
    while true; do
        local exec_mode_choice=$(get_input "请选择（EXECUTION_MODE）")
        case "$exec_mode_choice" in
            1|"")
                ENV_EXECUTION_MODE="sequential"
                ENV_EXECUTION_MODE_CONFIGURED=false
                break
                ;;
            2)
                ENV_EXECUTION_MODE="parallel"
                ENV_EXECUTION_MODE_CONFIGURED=true
                break
                ;;
            3)
                ENV_EXECUTION_MODE="staggered"
                ENV_EXECUTION_MODE_CONFIGURED=true
                break
                ;;
            *)
                echo ""
                print_error "无效选项，必须输入数字 1、2 或 3"
                echo ""
                ;;
        esac
    done
}

# 配置 STAGGERED_DELAY
config_staggered_delay() {
    echo -e "${COLOR_INFO}请输入错峰模式延迟：${NC}"
    echo ""
    print_env_hint "错峰延迟决定 TCP 监测启动后多久启动 ICMP"
    echo ""
    print_env_hint "默认值：500，单位：毫秒"
    echo ""
    local staggered_input=$(get_input "STAGGERED_DELAY")
    if [ -z "$staggered_input" ]; then
        ENV_STAGGERED_DELAY="500"
        ENV_STAGGERED_DELAY_CONFIGURED=false
    else
        ENV_STAGGERED_DELAY="$staggered_input"
        ENV_STAGGERED_DELAY_CONFIGURED=true
    fi
}

# 配置 DNS_CACHE_TTL
config_dns_cache_ttl() {
    echo -e "${COLOR_INFO}请输入 DNS 缓存 TTL：${NC}"
    echo ""
    print_env_hint "DNS 缓存 TTL 决定单个域名的 DNS 解析缓存时长"
    echo ""
    print_env_hint "默认值：60，单位：分钟"
    echo ""
    local dns_cache_input=$(get_input "DNS_CACHE_TTL")
    if [ -z "$dns_cache_input" ]; then
        ENV_DNS_CACHE_TTL="60"
        ENV_DNS_CACHE_TTL_CONFIGURED=false
    else
        ENV_DNS_CACHE_TTL="$dns_cache_input"
        ENV_DNS_CACHE_TTL_CONFIGURED=true
    fi
}

# 配置 DNS_TOTAL_TIMEOUT
config_dns_total_timeout() {
    echo -e "${COLOR_INFO}请输入 DNS 解析总超时时长：${NC}"
    echo ""
    print_env_hint "DNS 解析总超时时长决定单个域名完成 DNS 解析允许的最大耗时"
    print_env_hint "这包括了所有 DNS 上游，并非单一 DNS 上游超时时长"
    echo ""
    print_env_hint "默认值：3，单位：秒"
    echo ""
    local dns_total_input=$(get_input "DNS_TOTAL_TIMEOUT")
    if [ -z "$dns_total_input" ]; then
        ENV_DNS_TOTAL_TIMEOUT="3"
        ENV_DNS_TOTAL_TIMEOUT_CONFIGURED=false
    else
        ENV_DNS_TOTAL_TIMEOUT="$dns_total_input"
        ENV_DNS_TOTAL_TIMEOUT_CONFIGURED=true
    fi
}

# 配置 DNS_UPSTREAM_TIMEOUT
config_dns_upstream_timeout() {
    echo -e "${COLOR_INFO}请输入 DNS 单一上游超时时长：${NC}"
    echo ""
    print_env_hint "DNS 单一上游超时时长决定了解析单个域名中某个 DNS 上游解析允许的最大耗时"
    echo ""
    print_env_hint "默认值：2，单位：秒"
    echo ""
    local dns_upstream_input=$(get_input "DNS_UPSTREAM_TIMEOUT")
    if [ -z "$dns_upstream_input" ]; then
        ENV_DNS_UPSTREAM_TIMEOUT="2"
        ENV_DNS_UPSTREAM_TIMEOUT_CONFIGURED=false
    else
        ENV_DNS_UPSTREAM_TIMEOUT="$dns_upstream_input"
        ENV_DNS_UPSTREAM_TIMEOUT_CONFIGURED=true
    fi
}

# 配置 DNS_UPSTREAMS
config_dns_upstreams() {
    echo -e "${COLOR_INFO}请输入自定义 DNS 上游：${NC}"
    echo ""
    print_env_hint "自定义 DNS 上游将会覆盖除了系统 DNS 以外的默认 DNS 上游"
    print_env_hint "最多允许自定义 3 个 DNS 上游，仅限明文 DNS 协议（非加密），使用英文逗号分隔"
    echo ""
    print_env_hint "默认 DNS 上游："
    print_env_hint "- 1.1.1.1"
    print_env_hint "- 8.8.8.8"
    print_env_hint "- 114.114.114.114"
    echo ""
    local dns_upstreams_input=$(get_input "DNS_UPSTREAMS")
    if [ -z "$dns_upstreams_input" ]; then
        ENV_DNS_UPSTREAMS=""
        ENV_DNS_UPSTREAMS_CONFIGURED=false
    else
        ENV_DNS_UPSTREAMS="$dns_upstreams_input"
        ENV_DNS_UPSTREAMS_CONFIGURED=true
    fi
}

# 配置 LOGS_CLEANER_ENABLED
config_logs_cleaner_enabled() {
    echo -e "${COLOR_INFO}是否启用日志清理模块？${NC}"
    echo ""
    print_env_hint "日志清理模块会定时压缩和删除过期日志"
    echo ""
    echo -e "  ${COLOR_MENU}1.${NC} 启用 ${COLOR_HINT}（默认）${NC}"
    echo -e "  ${COLOR_MENU}2.${NC} 禁用"
    echo ""
    while true; do
        local choice=$(get_input "请选择（LOGS_CLEANER_ENABLED）")
        case "$choice" in
            1|"")
                ENV_LOGS_CLEANER_ENABLED="true"
                ENV_LOGS_CLEANER_ENABLED_CONFIGURED=false
                break
                ;;
            2)
                ENV_LOGS_CLEANER_ENABLED="false"
                ENV_LOGS_CLEANER_ENABLED_CONFIGURED=true
                break
                ;;
            *)
                echo ""
                print_error "无效选项，必须输入数字 1 或 2"
                echo ""
                ;;
        esac
    done
}

# 配置 LOGS_COMPRESS_RETENTION_DAYS
config_logs_compress_days() {
    echo -e "${COLOR_INFO}请输入日志压缩保留天数：${NC}"
    echo ""
    print_env_hint "日志压缩保留天数将决定执行日志压缩任务时，多少天内的日志不被压缩（不包括当天）"
    echo ""
    print_env_hint "默认值：15，单位：天"
    echo ""
    local compress_input=$(get_input "LOGS_COMPRESS_RETENTION_DAYS")
    if [ -z "$compress_input" ]; then
        ENV_LOGS_COMPRESS_DAYS="15"
        ENV_LOGS_COMPRESS_DAYS_CONFIGURED=false
    else
        ENV_LOGS_COMPRESS_DAYS="$compress_input"
        ENV_LOGS_COMPRESS_DAYS_CONFIGURED=true
    fi
}

# 配置 LOGS_DELETE_RETENTION_DAYS
config_logs_delete_days() {
    echo -e "${COLOR_INFO}请输入日志压缩文件删除保留天数：${NC}"
    echo ""
    print_env_hint "日志压缩文件删除保留天数将决定执行日志压缩文件删除任务时，多少天内的日志压缩文件不被删除（不包括当天）"
    echo ""
    print_env_hint "默认值：30，单位：天"
    echo ""
    local delete_input=$(get_input "LOGS_DELETE_RETENTION_DAYS")
    if [ -z "$delete_input" ]; then
        ENV_LOGS_DELETE_DAYS="30"
        ENV_LOGS_DELETE_DAYS_CONFIGURED=false
    else
        ENV_LOGS_DELETE_DAYS="$delete_input"
        ENV_LOGS_DELETE_DAYS_CONFIGURED=true
    fi
}

# ============================================================
# 环境变量配置
# ============================================================

configure_required_env() {
    print_step "4/6" "必要配置"
    echo ""

    config_vps_id
    echo ""

    config_vps_name
    echo ""

    config_hmac_secret
    echo ""

    config_server_url
    echo ""

    config_ping_frequency
    echo ""

    config_ping_offset
    echo ""

    # 配置监测目标
    configure_probe_targets
    echo ""

    # 配置 Ping 模式和执行模式
    configure_ping_and_execution_mode
}

# 配置 Ping 模式和执行模式（属于必选配置的一部分）
configure_ping_and_execution_mode() {
    echo ""

    config_ping_mode
    echo ""

    # 多轮模式专属配置
    if [ "$ENV_PING_MODE" = "multi" ]; then
        config_multi_ping_round
        echo ""

        config_multi_ping_inter_delay
        echo ""
    else
        # 单轮模式不需要多轮配置，但仍需设置默认值以便生成 .env
        ENV_MULTI_PING_ROUND="5"
        ENV_MULTI_PING_ROUND_CONFIGURED=false
        ENV_MULTI_PING_INTER_DELAY="200"
        ENV_MULTI_PING_INTER_DELAY_CONFIGURED=false
    fi

    config_ping_intra_delay
    echo ""

    config_ping_timeout
    echo ""

    config_execution_mode
    echo ""

    # STAGGERED_DELAY（仅错峰模式显示）
    if [ "$ENV_EXECUTION_MODE" = "staggered" ]; then
        config_staggered_delay
        echo ""
    else
        ENV_STAGGERED_DELAY="500"
        ENV_STAGGERED_DELAY_CONFIGURED=false
    fi
}

configure_optional_env() {
    print_step "5/6" "可选配置"
    echo ""

    # ========== DNS 配置 ==========

    if confirm "是否自定义 DNS 配置？" "n"; then
        echo ""

        config_dns_cache_ttl
        echo ""

        config_dns_total_timeout
        echo ""

        config_dns_upstream_timeout
        echo ""

        config_dns_upstreams
    else
        # 使用默认值
        ENV_DNS_CACHE_TTL="60"
        ENV_DNS_CACHE_TTL_CONFIGURED=false
        ENV_DNS_TOTAL_TIMEOUT="3"
        ENV_DNS_TOTAL_TIMEOUT_CONFIGURED=false
        ENV_DNS_UPSTREAM_TIMEOUT="2"
        ENV_DNS_UPSTREAM_TIMEOUT_CONFIGURED=false
        ENV_DNS_UPSTREAMS=""
        ENV_DNS_UPSTREAMS_CONFIGURED=false
    fi
    echo ""

    # ========== 日志清理模块配置 ==========

    if confirm "是否关闭日志清理模块？" "n"; then
        echo ""
        # 用户选择关闭
        ENV_LOGS_CLEANER_ENABLED="false"
        ENV_LOGS_CLEANER_ENABLED_CONFIGURED=true
        ENV_LOGS_COMPRESS_DAYS="15"
        ENV_LOGS_COMPRESS_DAYS_CONFIGURED=false
        ENV_LOGS_DELETE_DAYS="30"
        ENV_LOGS_DELETE_DAYS_CONFIGURED=false
    else
        echo ""
        # 用户选择不关闭（启用）
        ENV_LOGS_CLEANER_ENABLED="true"
        ENV_LOGS_CLEANER_ENABLED_CONFIGURED=false

        if confirm "是否自定义日志清理模块配置？" "n"; then
            echo ""

            config_logs_compress_days
            echo ""

            config_logs_delete_days
        else
            # 使用默认值
            ENV_LOGS_COMPRESS_DAYS="15"
            ENV_LOGS_COMPRESS_DAYS_CONFIGURED=false
            ENV_LOGS_DELETE_DAYS="30"
            ENV_LOGS_DELETE_DAYS_CONFIGURED=false
        fi
    fi
}

# 基于模板生成 .env 文件
# 从 .env.example 复制并替换用户配置的值
# 用户明确配置的值会被写入，使用默认值的会被注释掉
generate_env_file() {
    # 复制模板到目标文件
    cp "$ENV_EXAMPLE_FILE" "$ENV_FILE"

    # 替换环境变量值的辅助函数
    # 用法：replace_env_value KEY VALUE IS_CONFIGURED
    # IS_CONFIGURED: true=用户明确配置，false=使用默认值（注释掉）
    replace_env_value() {
        local key="$1"
        local value="$2"
        local is_configured="${3:-true}"

        if [ "$is_configured" = true ]; then
            # 用户明确配置，替换为新值
            sed -i "s|^${key}=.*|${key}=${value}|" "$ENV_FILE"
        else
            # 使用默认值，注释掉该行
            sed -i "s|^${key}=.*|#${key}=${value}|" "$ENV_FILE"
        fi
    }

    # 替换必选配置（这些都是用户明确配置的）
    replace_env_value "VPS_ID" "$ENV_VPS_ID" true
    replace_env_value "VPS_NAME" "$ENV_VPS_NAME" "$ENV_VPS_NAME_CONFIGURED"
    replace_env_value "HMAC_SECRET" "$ENV_HMAC_SECRET" true
    replace_env_value "SERVER_URL" "$ENV_SERVER_URL" true
    replace_env_value "PING_SCHEDULE_FREQUENCY" "$ENV_PING_FREQUENCY" true
    replace_env_value "PING_SCHEDULE_OFFSET" "$ENV_PING_OFFSET" "$ENV_PING_OFFSET_CONFIGURED"

    # 替换 Ping 模式和执行配置
    replace_env_value "PING_MODE" "$ENV_PING_MODE" "$ENV_PING_MODE_CONFIGURED"
    replace_env_value "PING_INTRA_DELAY" "$ENV_PING_INTRA_DELAY" "$ENV_PING_INTRA_DELAY_CONFIGURED"
    replace_env_value "PING_TIMEOUT" "$ENV_PING_TIMEOUT" "$ENV_PING_TIMEOUT_CONFIGURED"
    replace_env_value "MULTI_PING_ROUND" "$ENV_MULTI_PING_ROUND" "$ENV_MULTI_PING_ROUND_CONFIGURED"
    replace_env_value "MULTI_PING_INTER_DELAY" "$ENV_MULTI_PING_INTER_DELAY" "$ENV_MULTI_PING_INTER_DELAY_CONFIGURED"
    replace_env_value "EXECUTION_MODE" "$ENV_EXECUTION_MODE" "$ENV_EXECUTION_MODE_CONFIGURED"
    replace_env_value "STAGGERED_DELAY" "$ENV_STAGGERED_DELAY" "$ENV_STAGGERED_DELAY_CONFIGURED"

    # 替换可选配置
    replace_env_value "DNS_CACHE_TTL" "$ENV_DNS_CACHE_TTL" "$ENV_DNS_CACHE_TTL_CONFIGURED"
    replace_env_value "DNS_TOTAL_TIMEOUT" "$ENV_DNS_TOTAL_TIMEOUT" "$ENV_DNS_TOTAL_TIMEOUT_CONFIGURED"
    replace_env_value "DNS_UPSTREAM_TIMEOUT" "$ENV_DNS_UPSTREAM_TIMEOUT" "$ENV_DNS_UPSTREAM_TIMEOUT_CONFIGURED"
    replace_env_value "DNS_UPSTREAMS" "$ENV_DNS_UPSTREAMS" "$ENV_DNS_UPSTREAMS_CONFIGURED"
    replace_env_value "LOGS_COMPRESS_RETENTION_DAYS" "$ENV_LOGS_COMPRESS_DAYS" "$ENV_LOGS_COMPRESS_DAYS_CONFIGURED"
    replace_env_value "LOGS_DELETE_RETENTION_DAYS" "$ENV_LOGS_DELETE_DAYS" "$ENV_LOGS_DELETE_DAYS_CONFIGURED"
    replace_env_value "LOGS_CLEANER_ENABLED" "$ENV_LOGS_CLEANER_ENABLED" "$ENV_LOGS_CLEANER_ENABLED_CONFIGURED"

    # 特殊处理：替换监测目标
    # 1. 删除模板中的 PING_TARGET 示例行
    sed -i '/^PING_TARGET_[0-9]*=/d' "$ENV_FILE"

    # 2. 生成用户选择的目标内容
    local targets_content=""
    for target in "${PING_TARGETS[@]}"; do
        targets_content="${targets_content}${target}"$'\n'
    done

    # 3. 在 "# Ping Targets" 区块的分隔线后插入目标
    # 模板结构：
    #   ########################
    #   # Ping Targets
    #   ########################
    #   <空行> <- 在这里插入
    local temp_file=$(mktemp)
    local found_header=false
    local wait_for_separator=false
    local inserted=false

    while IFS= read -r line; do
        echo "$line" >> "$temp_file"

        if [[ "$line" == "# Ping Targets" ]]; then
            found_header=true
            wait_for_separator=true
        elif $wait_for_separator && [[ "$line" == "########################" ]]; then
            # 在分隔线后插入空行和目标
            echo "" >> "$temp_file"
            printf "%s" "$targets_content" >> "$temp_file"
            inserted=true
            wait_for_separator=false
        fi
    done < "$ENV_FILE"

    mv "$temp_file" "$ENV_FILE"

    echo ""
    print_success "环境变量配置文件已生成"
}

# ============================================================
# systemd 服务配置
# ============================================================

# 启动服务并显示状态详情
start_service_and_show_status() {
    print_info "启动服务..."
    systemctl start "$SERVICE_NAME"

    # 等待服务启动
    sleep 2

    # 检查服务状态并显示详情
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo -e "  ${GREEN}✓${NC} ${COLOR_HINT}服务已启动${NC}"
        echo ""

        # 显示服务状态详情
        echo -e "${COLOR_INFO}◎ 服务状态：${NC}"
        echo ""
        local pid=$(systemctl show "$SERVICE_NAME" --property=MainPID --value)
        local memory=$(systemctl show "$SERVICE_NAME" --property=MemoryCurrent --value)
        local active_enter=$(systemctl show "$SERVICE_NAME" --property=ActiveEnterTimestamp --value)

        # 格式化内存显示
        local memory_display="N/A"
        if [ "$memory" != "[not set]" ] && [ -n "$memory" ]; then
            local memory_mb=$(awk "BEGIN {printf \"%.1f\", $memory / 1024 / 1024}")
            memory_display="${memory_mb} MB"
        fi

        # 计算启动时长
        local uptime_display="N/A"
        if [ -n "$active_enter" ]; then
            local start_ts=$(date -d "$active_enter" +%s 2>/dev/null)
            local now_ts=$(date +%s)
            if [ -n "$start_ts" ]; then
                local uptime_sec=$((now_ts - start_ts))
                if [ $uptime_sec -lt 60 ]; then
                    uptime_display="${uptime_sec} 秒前"
                elif [ $uptime_sec -lt 3600 ]; then
                    uptime_display="$((uptime_sec / 60)) 分钟前"
                else
                    uptime_display="$((uptime_sec / 3600)) 小时前"
                fi
            fi
        fi

        echo -e "  PID:      ${COLOR_VALUE}$pid${NC}"
        echo -e "  状态:     ${COLOR_SUCCESS}运行中${NC}"
        echo -e "  内存占用: ${COLOR_VALUE}$memory_display${NC}"
        echo -e "  启动时间: ${COLOR_VALUE}$uptime_display${NC}"
    else
        echo -e "  ${RED}×${NC} ${COLOR_HINT}服务启动失败${NC}"
        echo ""

        # 显示最近的错误日志
        print_info "最近日志（最后 10 行）"
        echo -e "  ${COLOR_HINT}─────────────────────────────────${NC}"
        journalctl -u "$SERVICE_NAME" -n 10 --no-pager 2>/dev/null | while IFS= read -r line; do
            echo -e "  ${COLOR_HINT}$line${NC}"
        done
        echo -e "  ${COLOR_HINT}─────────────────────────────────${NC}"
        echo ""
        print_hint "提示: 请检查配置文件是否正确，修复后执行 systemctl start $SERVICE_NAME"
    fi
}

# 显示部署完成信息
show_deploy_complete_info() {
    print_separator_2
    echo ""
    echo -e "${COLOR_SUCCESS}✓ 部署完成！${NC}"
    echo ""
    local installed_version=$(get_installed_version)
    echo -e "  版本: ${COLOR_VALUE}$installed_version${NC}"
    echo -e "  安装目录: ${COLOR_VALUE}$INSTALL_DIR${NC}"
    local service_status=$(systemctl is-active "$SERVICE_NAME" 2>/dev/null)
    local status_display
    case "$service_status" in
        active)
            status_display="${COLOR_SUCCESS}${service_status}${NC}"
            ;;
        inactive)
            status_display="$service_status"
            ;;
        *)
            status_display="${COLOR_ERROR}${service_status}${NC}"
            ;;
    esac
    echo -e "  服务状态: $status_display"
    echo ""
    echo -e "  ${COLOR_HINT}查看日志: journalctl -u $SERVICE_NAME -f${NC}"
    echo -e "  ${COLOR_HINT}管理服务: systemctl [start|stop|restart] $SERVICE_NAME${NC}"
    echo ""
    print_separator_2
}

setup_systemd_service() {
    print_step "6/6" "配置 systemd 服务"
    echo ""

    local service_file="/etc/systemd/system/$SERVICE_NAME.service"

    # 创建服务配置文件
    print_info "创建服务配置..."
    cat > "$service_file" << EOF
[Unit]
Description=VPS Agent - Network Latency Monitor
After=network.target

[Service]
Type=simple
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/$BINARY_NAME
Restart=always
RestartSec=5
StandardOutput=null
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    echo -e "  ${GREEN}✓${NC} ${COLOR_HINT}$service_file${NC}"

    # 注册服务
    print_info "注册服务..."
    systemctl daemon-reload
    echo -e "  ${GREEN}✓${NC} ${COLOR_HINT}配置已重载${NC}"
    systemctl enable "$SERVICE_NAME" &>/dev/null
    echo -e "  ${GREEN}✓${NC} ${COLOR_HINT}开机自启已启用${NC}"
    echo ""

    # 询问是否立即启动
    if confirm "是否立即启动服务？"; then
        echo ""
        start_service_and_show_status
    else
        # 用户选择不启动
        echo ""
        print_success "服务配置完成，未启动"
        echo ""
        print_hint "手动启动: systemctl start $SERVICE_NAME"
        print_hint "查看状态: systemctl status $SERVICE_NAME"
    fi

    echo ""
}

# ============================================================
# 服务管理菜单
# ============================================================

show_service_menu() {
    print_title "服务管理"

    echo -e "  ${COLOR_MENU}1.${NC} 查看状态"
    echo -e "  ${COLOR_MENU}2.${NC} 启动服务"
    echo -e "  ${COLOR_MENU}3.${NC} 停止服务"
    echo -e "  ${COLOR_MENU}4.${NC} 重启服务"
    echo ""
    echo -e "  ${COLOR_MENU}0.${NC} 返回主菜单"
    echo ""

    local choice=$(get_input "请输入选项")

    case "$choice" in
        1)
            echo ""
            systemctl status "$SERVICE_NAME" --no-pager || true
            echo ""
            echo -ne "${COLOR_PROMPT}请按回车键返回${NC} "; read
            show_service_menu
            ;;
        2)
            echo ""
            if systemctl start "$SERVICE_NAME" 2>&1; then
                print_success "服务已启动"
            fi
            echo ""
            echo -ne "${COLOR_PROMPT}请按回车键返回${NC} "; read
            show_service_menu
            ;;
        3)
            echo ""
            if systemctl stop "$SERVICE_NAME" 2>&1; then
                print_success "服务已停止"
            fi
            echo ""
            echo -ne "${COLOR_PROMPT}请按回车键返回${NC} "; read
            show_service_menu
            ;;
        4)
            echo ""
            if systemctl restart "$SERVICE_NAME" 2>&1; then
                print_success "服务已重启"
            fi
            echo ""
            echo -ne "${COLOR_PROMPT}请按回车键返回${NC} "; read
            show_service_menu
            ;;
        0) show_main_menu ;;
        *)
            echo ""
            print_error "无效选项"
            show_service_menu
            ;;
    esac
}

# ============================================================
# 查看日志
# ============================================================

do_view_logs() {
    print_title "查看日志"

    echo -e "  ${COLOR_MENU}1.${NC} 查看历史日志 ${COLOR_HINT}(按 q 键退出)${NC}"
    echo -e "  ${COLOR_MENU}2.${NC} 实时跟踪日志 ${COLOR_HINT}(按 Ctrl+C 退出)${NC}"
    echo ""
    echo -e "  ${COLOR_MENU}0.${NC} 返回主菜单"
    echo ""

    local choice=$(get_input "请输入选项")

    case "$choice" in
        1)
            echo ""
            LESS='-R -X -F' journalctl -u "$SERVICE_NAME" -e
            echo ""
            echo -ne "${COLOR_PROMPT}请按回车键返回${NC} "; read
            do_view_logs
            ;;
        2)
            echo ""
            ( journalctl -u "$SERVICE_NAME" -f )
            echo ""
            echo -ne "${COLOR_PROMPT}请按回车键返回${NC} "; read
            do_view_logs
            ;;
        0) show_main_menu ;;
        *)
            echo ""
            print_error "无效选项"
            do_view_logs
            ;;
    esac
}

# ============================================================
# 原子清理函数（供卸载和重新安装复用）
# ============================================================

# 清理服务：停止 + 禁用 + 删除服务文件
perform_cleanup_service() {
    print_info "停止并禁用服务..."
    systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    systemctl disable "$SERVICE_NAME" 2>/dev/null || true
    print_success "服务已停止并禁用"

    local service_file="/etc/systemd/system/$SERVICE_NAME.service"
    if [ -f "$service_file" ]; then
        rm -f "$service_file"
        systemctl daemon-reload
        print_success "服务文件已删除"
    fi
}

# 清理二进制文件
perform_cleanup_binary() {
    if [ -f "$INSTALL_DIR/$BINARY_NAME" ]; then
        rm -f "$INSTALL_DIR/$BINARY_NAME"
        print_success "二进制文件已删除"
    fi
}

# 清理配置文件：config/ + .env + .env.example
perform_cleanup_config() {
    if [ -f "$ENV_FILE" ]; then
        rm -f "$ENV_FILE"
        print_success ".env 已删除"
    fi

    if [ -f "$ENV_EXAMPLE_FILE" ]; then
        rm -f "$ENV_EXAMPLE_FILE"
        print_success ".env.example 已删除"
    fi

    if [ -d "$CONFIG_DIR" ]; then
        rm -rf "$CONFIG_DIR"
        print_success "config/ 目录已删除"
    fi
}

# 清理日志：压缩并删除日志目录
# 参数：$1=压缩文件路径（可选，不传则自动生成）
# 返回：通过 CLEANUP_LOGS_ARCHIVE 变量返回压缩文件路径
perform_cleanup_logs() {
    local logs_dir="$INSTALL_DIR/logs"

    if [ -d "$logs_dir" ]; then
        local timestamp=$(date +%s)
        CLEANUP_LOGS_ARCHIVE="${1:-/tmp/vps-agent-logs-${timestamp}.tar.gz}"

        print_info "压缩日志目录..."
        tar -czf "$CLEANUP_LOGS_ARCHIVE" -C "$INSTALL_DIR" logs 2>/dev/null
        if [ -f "$CLEANUP_LOGS_ARCHIVE" ]; then
            print_success "日志已压缩保存：$CLEANUP_LOGS_ARCHIVE"
        fi
    fi
}

# 清理安装目录
perform_cleanup_install_dir() {
    if [ -d "$INSTALL_DIR" ]; then
        rm -rf "$INSTALL_DIR"
        print_success "安装目录已删除"
    fi
}

# ============================================================
# 卸载菜单
# ============================================================

show_uninstall_menu() {
    print_title "卸载 VPS Agent"

    echo -e "  ${COLOR_MENU}1.${NC} 完全卸载服务和配置文件"
    echo ""
    echo -e "  ${COLOR_MENU}2.${NC} 仅卸载服务"
    echo -e "  ${COLOR_MENU}3.${NC} 仅删除配置文件"
    echo ""
    echo -e "  ${COLOR_MENU}0.${NC} 返回主菜单"
    echo ""

    local choice=$(get_input "请输入选项")

    case "$choice" in
        1) do_full_uninstall ;;
        2) do_service_only_uninstall ;;
        3) do_delete_config ;;
        0) show_main_menu ;;
        *)
            echo ""
            print_error "无效选项"
            show_uninstall_menu
            ;;
    esac
}

do_full_uninstall() {
    echo ""

    # 预先计算日志压缩路径（仅用于显示）
    local timestamp=$(date +%s)
    local archive_file="/tmp/vps-agent-logs-${timestamp}.tar.gz"

    echo -e "${RED_BOLD}此操作将删除以下内容：${NC}"
    echo ""
    echo -e "  ${COLOR_ERROR}•${NC} systemd 服务（停止、禁用、删除服务文件）"
    echo -e "  ${COLOR_ERROR}•${NC} 二进制文件 ${COLOR_HINT}($INSTALL_DIR/$BINARY_NAME)${NC}"
    echo -e "  ${COLOR_ERROR}•${NC} 配置文件 ${COLOR_HINT}($ENV_FILE, $ENV_EXAMPLE_FILE, $CONFIG_DIR/)${NC}"
    echo -e "  ${COLOR_ERROR}•${NC} 日志目录 ${COLOR_HINT}($INSTALL_DIR/logs/)${NC}"
    echo -e "  ${COLOR_ERROR}•${NC} 安装目录 ${COLOR_HINT}($INSTALL_DIR/)${NC}"
    echo ""
    echo -e "${COLOR_INFO}日志将被压缩保存到临时目录：${NC}$archive_file"
    echo ""

    if ! confirm_dangerous "即将完全卸载 VPS Agent！"; then
        echo ""
        print_info "已取消操作"
        show_uninstall_menu
        return
    fi

    echo ""

    # 执行清理
    perform_cleanup_service
    perform_cleanup_logs "$archive_file"
    perform_cleanup_install_dir

    echo ""
    print_separator_3
    print_success "VPS Agent 已完全卸载"
    print_separator_3
    echo ""
    echo -ne "${COLOR_PROMPT}请按回车键返回${NC} "; read
    show_main_menu
}

do_service_only_uninstall() {
    echo ""

    echo -e "${RED_BOLD}此操作将删除以下内容：${NC}"
    echo ""
    echo -e "  ${COLOR_ERROR}•${NC} systemd 服务（停止、禁用、删除服务文件）"
    echo -e "  ${COLOR_ERROR}•${NC} 二进制文件 ${COLOR_HINT}($INSTALL_DIR/$BINARY_NAME)${NC}"
    echo ""
    echo -e "${COLOR_SUCCESS}以下内容将被保留：${NC}"
    echo ""
    echo -e "  ${COLOR_SUCCESS}•${NC} 配置文件 ${COLOR_HINT}($ENV_FILE, $ENV_EXAMPLE_FILE, $CONFIG_DIR/)${NC}"
    echo -e "  ${COLOR_SUCCESS}•${NC} 日志目录 ${COLOR_HINT}($INSTALL_DIR/logs/)${NC}"
    echo ""

    if ! confirm_dangerous "即将卸载 VPS Agent 服务！"; then
        echo ""
        print_info "已取消操作"
        show_uninstall_menu
        return
    fi

    echo ""

    # 执行清理
    perform_cleanup_service
    perform_cleanup_binary

    echo ""
    print_success "服务已卸载，配置文件和日志已保留"
    echo ""
    echo -ne "${COLOR_PROMPT}请按回车键返回${NC} "; read
    show_uninstall_menu
}

do_delete_config() {
    echo ""

    echo -e "${RED_BOLD}此操作将删除以下内容：${NC}"
    echo ""
    echo -e "  ${COLOR_ERROR}•${NC} 环境变量配置 ${COLOR_HINT}($ENV_FILE)${NC}"
    echo -e "  ${COLOR_ERROR}•${NC} 环境变量模板 ${COLOR_HINT}($ENV_EXAMPLE_FILE)${NC}"
    echo -e "  ${COLOR_ERROR}•${NC} 配置文件目录 ${COLOR_HINT}($CONFIG_DIR/)${NC}"
    echo ""
    echo -e "${COLOR_SUCCESS}以下内容将被保留：${NC}"
    echo ""
    echo -e "  ${COLOR_SUCCESS}•${NC} 二进制文件 ${COLOR_HINT}($INSTALL_DIR/$BINARY_NAME)${NC}"
    echo -e "  ${COLOR_SUCCESS}•${NC} systemd 服务文件（服务将被停止）"
    echo -e "  ${COLOR_SUCCESS}•${NC} 日志目录 ${COLOR_HINT}($INSTALL_DIR/logs/)${NC}"
    echo ""

    if ! confirm_dangerous "即将删除配置文件！"; then
        echo ""
        print_info "已取消操作"
        show_uninstall_menu
        return
    fi

    echo ""

    # 停止服务（不删除服务文件）
    print_info "停止服务..."
    systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    print_success "服务已停止"

    # 执行清理
    perform_cleanup_config

    echo ""
    print_success "配置文件已删除，服务和二进制文件已保留"
    echo ""
    echo -ne "${COLOR_PROMPT}请按回车键返回${NC} "; read
    show_uninstall_menu
}

# ============================================================
# 部署服务
# ============================================================

do_fresh_install() {
    print_title "部署服务"

    local service_file="/etc/systemd/system/$SERVICE_NAME.service"
    local has_binary=false
    local has_config=false
    local has_service=false
    local skip_download=false

    # 检测已安装的组件
    [ -x "$INSTALL_DIR/$BINARY_NAME" ] && has_binary=true
    [ -d "$CONFIG_DIR" ] || [ -f "$ENV_FILE" ] || [ -f "$ENV_EXAMPLE_FILE" ] && has_config=true
    [ -f "$service_file" ] && has_service=true

    # 如果存在任何已安装的文件，显示提示和菜单
    if [ "$has_binary" = true ] || [ "$has_config" = true ] || [ "$has_service" = true ]; then

        if [ "$has_service" = true ]; then
            # 完整安装：检查服务是否运行
            local service_running=false
            systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null && service_running=true

            if [ "$service_running" = true ]; then
                # 服务已运行：只显示重新部署和返回
                print_warn "检测到已完成部署，服务已启动"
                echo ""

                echo -e "  ${COLOR_MENU}1.${NC} 重新部署${COLOR_HINT}（停止服务并完全删除整个项目文件）${NC}"
                echo ""
                echo -e "  ${COLOR_MENU}0.${NC} 返回主菜单"
                echo ""

                while true; do
                    local choice=$(get_input "请选择")
                    case "$choice" in
                        1)
                            # 重新安装：敏感二次确认
                            echo ""
                            if ! confirm_dangerous "即将停止服务并完全删除整个项目文件，以便重新部署！"; then
                                echo ""
                                print_info "已取消操作"
                                echo ""
                                continue
                            fi
                            # 执行完整清理
                            echo ""
                            perform_cleanup_service
                            perform_cleanup_logs
                            perform_cleanup_install_dir
                            echo ""
                            break
                            ;;
                        0)
                            show_main_menu
                            return
                            ;;
                        *)
                            echo ""
                            print_error "无效选项"
                            echo ""
                            ;;
                    esac
                done
            else
                # 服务未启动：提供启动服务或重新部署选项
                print_warn "检测到已完成部署，服务未启动"
                echo ""

                echo -e "  ${COLOR_MENU}1.${NC} 启动服务"
                echo -e "  ${COLOR_MENU}2.${NC} 重新部署${COLOR_HINT}（移除 systemd 服务并删除整个项目文件，从头开始部署）${NC}"
                echo ""
                echo -e "  ${COLOR_MENU}0.${NC} 返回主菜单"
                echo ""

                while true; do
                    local choice=$(get_input "请选择")
                    case "$choice" in
                        1)
                            # 启动服务
                            echo ""
                            start_service_and_show_status

                            # 显示部署完成信息
                            echo ""
                            show_deploy_complete_info
                            echo ""
                            echo -ne "${COLOR_PROMPT}按回车键返回主菜单${NC} "; read
                            show_main_menu
                            return
                            ;;
                        2)
                            # 重新部署：敏感二次确认
                            echo ""
                            if ! confirm_dangerous "即将删除整个项目文件，以便重新部署！"; then
                                echo ""
                                print_info "已取消操作"
                                echo ""
                                continue
                            fi
                            # 执行完整清理
                            echo ""
                            perform_cleanup_service
                            perform_cleanup_logs
                            perform_cleanup_install_dir
                            echo ""
                            break
                            ;;
                        0)
                            show_main_menu
                            return
                            ;;
                        *)
                            echo ""
                            print_error "无效选项"
                            echo ""
                            ;;
                    esac
                done
            fi
        else
            # 未完成安装：显示完整菜单
            echo -e "  ${COLOR_MENU}1.${NC} 重新部署${COLOR_HINT}（删除已下载文件，从头开始部署）${NC}"
            echo -e "  ${COLOR_MENU}2.${NC} 继续部署${COLOR_HINT}（保留已下载文件，从环境变量配置步骤继续）${NC}"
            echo ""
            echo -e "  ${COLOR_MENU}0.${NC} 返回主菜单"
            echo ""

            while true; do
                local choice=$(get_input "请选择")
                case "$choice" in
                    1)
                        # 重新安装：敏感二次确认
                        echo ""
                        if ! confirm_dangerous "即将删除已下载的文件，以便重新部署！"; then
                            echo ""
                            print_info "已取消操作"
                            echo ""
                            continue
                        fi
                        # 根据实际存在的文件清理
                        echo ""
                        [ "$has_binary" = true ] && perform_cleanup_binary
                        [ "$has_config" = true ] && perform_cleanup_config
                        # 如果安装目录为空，删除目录本身
                        if [ -d "$INSTALL_DIR" ] && [ -z "$(ls -A "$INSTALL_DIR" 2>/dev/null)" ]; then
                            rmdir "$INSTALL_DIR" 2>/dev/null
                            print_success "安装目录已删除"
                        fi
                        echo ""
                        break
                        ;;
                    2)
                        # 继续安装：跳过步骤 1-3
                        SELECTED_VERSION=$(get_installed_version)
                        skip_download=true
                        break
                        ;;
                    0)
                        show_main_menu
                        return
                        ;;
                    *)
                        echo ""
                        print_error "无效选项"
                        echo ""
                        ;;
                esac
            done
        fi
    fi

    if [ "$skip_download" = true ]; then
        # 继续安装模式：跳过步骤 1-3
        echo ""
        print_info "继续安装，跳过环境检查和下载步骤"
        echo ""
        echo -e "${GREEN}✓${NC} 已选择版本: ${COLOR_VALUE}$SELECTED_VERSION${NC}"
    else
        # 正常安装模式：执行步骤 1-3

        # 步骤 1：环境检查
        check_environment
        echo ""

        # 步骤 2：选择版本（支持返回）
        while true; do
            if ! select_version; then
                # 用户选择返回主菜单
                show_main_menu
                return
            fi
            echo ""

            # 步骤 3：下载文件（支持返回和重新选择版本）
            download_files
            local download_result=$?

            if [ $download_result -eq 0 ]; then
                # 下载成功，继续下一步
                break
            elif [ $download_result -eq 1 ]; then
                # 用户选择返回主菜单
                show_main_menu
                return
            elif [ $download_result -eq 2 ]; then
                # 用户选择重新选择版本，继续循环
                echo ""
                continue
            fi
        done
    fi

    echo ""

    # 步骤 4：必要配置
    configure_required_env

    # 步骤 5：可选配置
    configure_optional_env

    # 生成配置文件
    generate_env_file
    echo ""

    # 步骤 6：配置 systemd 服务
    setup_systemd_service

    # 完成信息
    show_deploy_complete_info
    echo ""
    echo -ne "${COLOR_PROMPT}按回车键返回主菜单${NC} "; read
    show_main_menu
}

# ============================================================
# 更新功能 - 辅助函数
# ============================================================

# 检查是否已安装 Agent
# 返回值：0=已安装，1=未安装
check_agent_installed() {
    if [ ! -x "$INSTALL_DIR/$BINARY_NAME" ]; then
        print_error "未检测到已安装的 Agent，请先完成部署"
        echo ""
        echo -ne "${COLOR_PROMPT}请按回车键返回${NC} "; read
        return 1
    fi
    return 0
}

# 检查当前版本是否为最新版本
# 设置全局变量：
#   - INSTALLED_VERSION: 当前安装的版本
#   - LATEST_VERSION: 最新版本
#   - IS_LATEST: true/false
check_version_status() {
    INSTALLED_VERSION=$(get_installed_version)
    LATEST_VERSION=$(get_latest_version)

    if [ -z "$LATEST_VERSION" ]; then
        print_error "无法获取最新版本信息，请检查网络连接"
        echo ""
        echo -ne "${COLOR_PROMPT}请按回车键返回${NC} "; read
        return 1
    fi

    if [ "$INSTALLED_VERSION" = "$LATEST_VERSION" ]; then
        IS_LATEST=true
    else
        IS_LATEST=false
    fi

    return 0
}

# 为更新场景选择版本
# 参数：$1=步骤编号（如 "1/2" 或 "1/3"）
# 返回值：0=成功选择，1=用户选择返回
# 设置全局变量：SELECTED_VERSION
# 注意：调用前需确保 LATEST_VERSION 已设置
select_version_for_update() {
    local step="$1"

    print_step "$step" "选择版本"
    echo ""

    while true; do
        select_version_menu "$LATEST_VERSION" "返回"
        local result=$?

        case $result in
            0)
                # 选择成功
                echo ""
                echo -e "${GREEN}✓${NC} 已选择版本: ${COLOR_VALUE}$SELECTED_VERSION${NC}"
                return 0
                ;;
            1)
                # 用户选择返回
                return 1
                ;;
            2)
                # 需要重新显示菜单
                continue
                ;;
        esac
    done
}

# 停止服务（如果运行中）
# 返回值：0=成功或服务未运行，1=停止失败
stop_service_if_running() {
    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        print_info "停止服务..."
        if systemctl stop "$SERVICE_NAME" 2>/dev/null; then
            print_success "服务已停止"
        else
            print_error "服务停止失败"
            return 1
        fi
    fi
    return 0
}

# 执行二进制文件下载（纯下载，无交互）
# 返回值：0=成功，1=失败
perform_binary_download() {
    print_info "下载 Agent 二进制文件..."
    local binary_url="$GITHUB_RELEASE_URL/download/$SELECTED_VERSION/$BINARY_NAME"

    local http_code
    http_code=$(curl -fsSL -w "%{http_code}" "$binary_url" -o "$INSTALL_DIR/$BINARY_NAME" 2>/dev/null)
    local curl_exit=$?

    if [ $curl_exit -eq 0 ]; then
        chmod +x "$INSTALL_DIR/$BINARY_NAME"
        echo -e "  ${GREEN}✓${NC} ${COLOR_HINT}vps-agent${NC}"
        return 0
    fi

    # 下载失败
    echo ""
    if [ "$http_code" = "404" ]; then
        print_error "二进制文件下载失败，状态码：404"
        print_hint "版本 $SELECTED_VERSION 可能不存在"
    else
        print_error "二进制文件下载失败"
        print_hint "可能是网络问题，请检查连接"
    fi
    return 1
}

# 执行配置文件下载（纯下载，无交互）
# 返回值：0=成功，1=失败
perform_config_download() {
    print_info "下载配置文件..."

    local config_files=(
        "config/probe-targets.yaml"
        "config/administrative-divisions/cn/cities-code.json"
        "config/administrative-divisions/cn/provinces-code.json"
        "config/administrative-divisions/global/cities-code.json"
        "config/administrative-divisions/global/countries-code.json"
        "config/network-providers/network-providers-code.json"
    )

    for file in "${config_files[@]}"; do
        local dir=$(dirname "$INSTALL_DIR/$file")
        mkdir -p "$dir"
        if curl -fsSL "$GITHUB_RAW_URL/$file" -o "$INSTALL_DIR/$file" 2>/dev/null; then
            echo -e "  ${GREEN}✓${NC} ${COLOR_HINT}$file${NC}"
        else
            echo -e "  ${RED}×${NC} ${COLOR_HINT}$file${NC} ${RED}下载失败${NC}"
            return 1
        fi
    done

    return 0
}

# 执行环境变量模板下载（纯下载，无交互）
# 返回值：0=成功，1=失败
perform_env_template_download() {
    print_info "下载环境变量模板..."

    if curl -fsSL "$GITHUB_RAW_URL/.env.example" -o "$ENV_EXAMPLE_FILE" 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} ${COLOR_HINT}.env.example${NC}"
        return 0
    fi

    echo -e "  ${RED}×${NC} ${COLOR_HINT}.env.example${NC} ${RED}下载失败${NC}"
    return 1
}

# 显示配置文件更新说明
show_config_update_info() {
    echo -e "即将从 GitHub 仓库拉取最新配置文件："
    echo ""
    echo -e "  • config/probe-targets.yaml${COLOR_HINT}（监测目标配置）${NC}"
    echo -e "  • config/administrative-divisions/${COLOR_HINT}（行政区划配置）${NC}"
    echo -e "  • config/network-providers/${COLOR_HINT}（网络服务商配置）${NC}"
    echo -e "  • .env.example${COLOR_HINT}（环境变量模板）${NC}"
    echo ""
    echo -e "以下文件将被保留："
    echo ""
    echo -e "  • .env${COLOR_HINT}（您的环境变量配置）${NC}"
    echo ""
}

# ============================================================
# 更新功能 - 主函数
# ============================================================

do_update_agent() {
    print_title "完整更新"

    # 检查是否已安装
    if ! check_agent_installed; then
        show_update_menu
        return
    fi

    # 检查版本状态
    if ! check_version_status; then
        show_update_menu
        return
    fi

    # 显示版本信息（最新版本在上，当前版本在下）
    if [ "$IS_LATEST" = true ]; then
        echo -e "最新版本: ${COLOR_VALUE}$LATEST_VERSION${NC}"
        echo -e "当前版本: ${COLOR_VALUE}$INSTALLED_VERSION${NC}"
        echo ""
        echo -e "${COLOR_SUCCESS}✓ 当前二进制文件已是最新版本${NC}${COLOR_HINT}（跳过更新）${NC}"
        echo ""

        show_config_update_info

        if ! confirm "是否开始更新？"; then
            echo ""
            print_info "已取消操作"
            echo ""
            echo -ne "${COLOR_PROMPT}请按回车键返回${NC} "; read
            show_update_menu
            return
        fi

        echo ""

        # 步骤 1/2：下载配置文件
        print_step "1/2" "下载配置文件"
        echo ""

        if ! perform_config_download; then
            echo ""
            echo -e "  ${COLOR_MENU}1.${NC} 重试下载"
            echo ""
            echo -e "  ${COLOR_MENU}0.${NC} 返回"
            echo ""

            while true; do
                local choice=$(get_input "请选择")
                case "$choice" in
                    1)
                        do_update_agent
                        return
                        ;;
                    0)
                        show_update_menu
                        return
                        ;;
                    *)
                        echo ""
                        print_error "无效选项"
                        ;;
                esac
            done
        fi

        echo ""

        # 步骤 2/2：下载环境变量模板
        print_step "2/2" "下载环境变量模板"
        echo ""

        if ! perform_env_template_download; then
            echo ""
            echo -e "  ${COLOR_MENU}1.${NC} 重试下载"
            echo ""
            echo -e "  ${COLOR_MENU}0.${NC} 返回"
            echo ""

            while true; do
                local choice=$(get_input "请选择")
                case "$choice" in
                    1)
                        do_update_agent
                        return
                        ;;
                    0)
                        show_update_menu
                        return
                        ;;
                    *)
                        echo ""
                        print_error "无效选项"
                        ;;
                esac
            done
        fi

        echo ""
        echo -e "${COLOR_SUCCESS}✓ 配置文件更新完成${NC}"

        # 询问是否重启服务
        prompt_restart_service

    else
        # 有新版本，执行完整更新
        echo -e "最新版本: ${ORANGE}$LATEST_VERSION${NC}"
        echo -e "当前版本: ${COLOR_VALUE}$INSTALLED_VERSION${NC}"
        echo ""

        echo -e "完整更新将执行以下操作："
        echo ""
        echo -e "  • 更新二进制文件${COLOR_HINT}（选择版本）${NC}"
        echo -e "  • 更新配置文件${COLOR_HINT}（从 GitHub 仓库拉取最新文件）${NC}"
        echo ""

        if ! confirm "是否开始更新？"; then
            echo ""
            print_info "已取消操作"
            echo ""
            echo -ne "${COLOR_PROMPT}请按回车键返回${NC} "; read
            show_update_menu
            return
        fi

        echo ""

        # 步骤 1/3：选择版本
        while true; do
            if ! select_version_for_update "1/3"; then
                show_update_menu
                return
            fi

            echo ""

            # 步骤 2/3：下载二进制文件
            print_step "2/3" "下载二进制文件"
            echo ""

            # 停止服务
            if ! stop_service_if_running; then
                echo ""
                echo -ne "${COLOR_PROMPT}请按回车键返回${NC} "; read
                show_update_menu
                return
            fi

            echo ""

            if ! perform_binary_download; then
                echo ""
                echo -e "  ${COLOR_MENU}1.${NC} 重试下载"
                echo -e "  ${COLOR_MENU}2.${NC} 重新选择版本"
                echo ""
                echo -e "  ${COLOR_MENU}0.${NC} 返回"
                echo ""

                local retry_choice
                while true; do
                    retry_choice=$(get_input "请选择")
                    case "$retry_choice" in
                        1)
                            # 重试下载，继续内层循环
                            break
                            ;;
                        2)
                            # 重新选择版本，继续外层循环
                            echo ""
                            break 2
                            ;;
                        0)
                            show_update_menu
                            return
                            ;;
                        *)
                            echo ""
                            print_error "无效选项"
                            ;;
                    esac
                done
                continue
            fi

            # 二进制下载成功，跳出循环
            break
        done

        echo ""

        # 步骤 3/3：下载配置文件
        print_step "3/3" "下载配置文件"
        echo ""

        if ! perform_config_download; then
            echo ""
            echo -e "  ${COLOR_MENU}1.${NC} 重试下载"
            echo ""
            echo -e "  ${COLOR_MENU}0.${NC} 返回"
            echo ""

            while true; do
                local choice=$(get_input "请选择")
                case "$choice" in
                    1)
                        if perform_config_download; then
                            break
                        fi
                        ;;
                    0)
                        show_update_menu
                        return
                        ;;
                    *)
                        echo ""
                        print_error "无效选项"
                        ;;
                esac
            done
        fi

        echo ""

        if ! perform_env_template_download; then
            echo ""
            echo -e "  ${COLOR_MENU}1.${NC} 重试下载"
            echo ""
            echo -e "  ${COLOR_MENU}0.${NC} 返回"
            echo ""

            while true; do
                local choice=$(get_input "请选择")
                case "$choice" in
                    1)
                        if perform_env_template_download; then
                            break
                        fi
                        ;;
                    0)
                        show_update_menu
                        return
                        ;;
                    *)
                        echo ""
                        print_error "无效选项"
                        ;;
                esac
            done
        fi

        echo ""
        print_separator_2
        echo ""
        echo -e "${COLOR_SUCCESS}✓ 完整更新完成！${NC}"
        echo ""
        local new_version=$(get_installed_version)
        echo -e "  版本: ${COLOR_VALUE}$new_version${NC}"
        echo ""
        print_separator_2

        # 询问是否启动服务
        prompt_restart_service
    fi

    echo ""
    echo -ne "${COLOR_PROMPT}请按回车键返回${NC} "; read
    show_update_menu
}

do_update_binary() {
    print_title "更新二进制文件"

    # 检查是否已安装
    if ! check_agent_installed; then
        show_update_menu
        return
    fi

    # 检查版本状态
    if ! check_version_status; then
        show_update_menu
        return
    fi

    # 显示版本信息（最新版本在上，当前版本在下）
    if [ "$IS_LATEST" = true ]; then
        echo -e "最新版本: ${COLOR_VALUE}$LATEST_VERSION${NC}"
        echo -e "当前版本: ${COLOR_VALUE}$INSTALLED_VERSION${NC}"
        echo ""
        print_success "当前已是最新版本"
        echo ""
        echo -ne "${COLOR_PROMPT}请按回车键返回${NC} "; read
        show_update_menu
        return
    fi

    # 有新版本可用
    echo -e "最新版本: ${ORANGE}$LATEST_VERSION${NC}"
    echo -e "当前版本: ${COLOR_VALUE}$INSTALLED_VERSION${NC}"
    echo ""

    # 步骤 1/2：选择版本
    while true; do
        if ! select_version_for_update "1/2"; then
            show_update_menu
            return
        fi

        echo ""

        # 步骤 2/2：下载二进制文件
        print_step "2/2" "下载二进制文件"
        echo ""

        # 停止服务
        if ! stop_service_if_running; then
            echo ""
            echo -ne "${COLOR_PROMPT}请按回车键返回${NC} "; read
            show_update_menu
            return
        fi

        echo ""

        if ! perform_binary_download; then
            echo ""
            echo -e "  ${COLOR_MENU}1.${NC} 重试下载"
            echo -e "  ${COLOR_MENU}2.${NC} 重新选择版本"
            echo ""
            echo -e "  ${COLOR_MENU}0.${NC} 返回"
            echo ""

            local retry_choice
            while true; do
                retry_choice=$(get_input "请选择")
                case "$retry_choice" in
                    1)
                        # 重试下载
                        break
                        ;;
                    2)
                        # 重新选择版本
                        echo ""
                        break 2
                        ;;
                    0)
                        show_update_menu
                        return
                        ;;
                    *)
                        echo ""
                        print_error "无效选项"
                        ;;
                esac
            done
            continue
        fi

        # 下载成功，跳出循环
        break
    done

    echo ""
    print_success "二进制文件更新完成"
    echo ""
    local new_version=$(get_installed_version)
    echo -e "  当前版本: ${COLOR_VALUE}$new_version${NC}"

    # 询问是否重启服务
    prompt_restart_service

    echo ""
    echo -ne "${COLOR_PROMPT}请按回车键返回${NC} "; read
    show_update_menu
}

do_update_config() {
    print_title "更新配置文件"

    # 检查是否已安装
    if ! check_agent_installed; then
        show_update_menu
        return
    fi

    show_config_update_info

    if ! confirm "是否开始更新？"; then
        echo ""
        print_info "已取消操作"
        echo ""
        echo -ne "${COLOR_PROMPT}请按回车键返回${NC} "; read
        show_update_menu
        return
    fi

    echo ""

    # 步骤 1/2：下载配置文件
    print_step "1/2" "下载配置文件"
    echo ""

    if ! perform_config_download; then
        echo ""
        echo -e "  ${COLOR_MENU}1.${NC} 重试下载"
        echo ""
        echo -e "  ${COLOR_MENU}0.${NC} 返回"
        echo ""

        while true; do
            local choice=$(get_input "请选择")
            case "$choice" in
                1)
                    do_update_config
                    return
                    ;;
                0)
                    show_update_menu
                    return
                    ;;
                *)
                    echo ""
                    print_error "无效选项"
                    ;;
            esac
        done
    fi

    echo ""

    # 步骤 2/2：下载环境变量模板
    print_step "2/2" "下载环境变量模板"
    echo ""

    if ! perform_env_template_download; then
        echo ""
        echo -e "  ${COLOR_MENU}1.${NC} 重试下载"
        echo ""
        echo -e "  ${COLOR_MENU}0.${NC} 返回"
        echo ""

        while true; do
            local choice=$(get_input "请选择")
            case "$choice" in
                1)
                    do_update_config
                    return
                    ;;
                0)
                    show_update_menu
                    return
                    ;;
                *)
                    echo ""
                    print_error "无效选项"
                    ;;
            esac
        done
    fi

    echo ""
    echo -e "${COLOR_SUCCESS}✓ 配置文件更新完成${NC}"

    # 询问是否重启服务
    prompt_restart_service

    echo ""
    echo -ne "${COLOR_PROMPT}请按回车键返回${NC} "; read
    show_update_menu
}

# ============================================================
# 修改环境变量配置 - 辅助函数
# ============================================================

# 从 .env 文件读取指定环境变量的值
# 参数：$1=变量名
# 设置全局变量：
#   - ENV_VALUE: 读取到的值
#   - ENV_VALUE_STATUS: 状态（configured/commented/missing）
# 注意：不要使用 $() 调用此函数，否则全局变量无法传递
read_env_value() {
    local key="$1"
    local line

    if [ ! -f "$ENV_FILE" ]; then
        ENV_VALUE=""
        ENV_VALUE_STATUS="missing"
        return
    fi

    # 先查找未注释的行
    line=$(grep "^${key}=" "$ENV_FILE" 2>/dev/null | head -1)
    if [ -n "$line" ]; then
        ENV_VALUE="${line#*=}"
        ENV_VALUE_STATUS="configured"
        return
    fi

    # 再查找注释的行
    line=$(grep "^#${key}=" "$ENV_FILE" 2>/dev/null | head -1)
    if [ -n "$line" ]; then
        ENV_VALUE="${line#*=}"
        ENV_VALUE_STATUS="commented"
        return
    fi

    ENV_VALUE=""
    ENV_VALUE_STATUS="missing"
}

# 显示当前配置值
# 参数：$1=显示的值, $2=状态（configured/commented/missing）, $3=保留参数（未使用）
show_current_config() {
    local value="$1"
    local status="$2"
    # $3 保留但不使用

    echo -e "${COLOR_INFO}当前配置：${NC}"
    echo ""

    case "$status" in
        configured)
            echo -e "  ${COLOR_VALUE}$value${NC}"
            ;;
        commented)
            echo -e "  ${COLOR_HINT}未配置（当前已注释）${NC}"
            ;;
        missing)
            echo -e "  ${COLOR_HINT}未配置${NC}"
            ;;
    esac

    echo ""
}

# 根据 target_id 获取监测目标的显示名称
# 参数：$1=target_id
# 返回：目标名称，找不到则返回原 target_id
get_target_display_name() {
    local target_id="$1"
    local yaml_file="$CONFIG_DIR/probe-targets.yaml"

    if [ ! -f "$yaml_file" ]; then
        echo "$target_id"
        return
    fi

    local name=$(yq eval ".targets[] | select(.target_id == \"$target_id\") | .target_name" "$yaml_file" 2>/dev/null)

    if [ -n "$name" ] && [ "$name" != "null" ]; then
        echo "$name"
    else
        echo "$target_id"
    fi
}

# 显示当前监测目标配置
# 从 .env 读取 PING_TARGET 并解析显示
show_current_probe_targets() {
    echo -e "${COLOR_INFO}当前配置：${NC}"
    echo ""

    if [ ! -f "$ENV_FILE" ]; then
        echo -e "  ${COLOR_HINT}未配置${NC}"
        echo ""
        return
    fi

    local count=0
    while IFS= read -r line; do
        # 解析 PING_TARGET_N=target_id:protocol
        local value="${line#*=}"
        local target_id="${value%:*}"
        local protocol="${value#*:}"
        local display_name=$(get_target_display_name "$target_id")
        local protocol_upper=$(echo "$protocol" | tr '[:lower:]' '[:upper:]')

        count=$((count + 1))
        echo -e "  ${count}. ${display_name} (${protocol_upper})"
    done < <(grep "^PING_TARGET_[0-9]*=" "$ENV_FILE" 2>/dev/null | sort -t'_' -k3 -n)

    if [ $count -eq 0 ]; then
        echo -e "  ${COLOR_HINT}未配置${NC}"
    fi

    echo ""
}

# ============================================================
# 修改环境变量配置
# ============================================================

do_modify_config() {
    # 前置检查：.env 文件是否存在
    if [ ! -f "$ENV_FILE" ]; then
        print_title "修改环境变量配置"
        echo ""
        print_error "配置文件（.env）不存在，请先完成部署"
        echo ""
        echo -ne "${COLOR_PROMPT}请按回车键返回${NC} "; read
        show_update_menu
        return
    fi

    print_title "修改环境变量配置"

    echo -e "${COLOR_INFO}  基础配置${NC}"
    echo ""
    echo -e "  ${COLOR_MENU}1.${NC} VPS ID ${COLOR_HINT}(VPS_ID)${NC}"
    echo -e "  ${COLOR_MENU}2.${NC} VPS 名称 ${COLOR_HINT}(VPS_NAME)${NC}"
    echo -e "  ${COLOR_MENU}3.${NC} HMAC 密钥 ${COLOR_HINT}(HMAC_SECRET)${NC}"
    echo -e "  ${COLOR_MENU}4.${NC} Server 接收端 URL ${COLOR_HINT}(SERVER_URL)${NC}"
    echo ""
    echo -e "${COLOR_INFO}  调度配置${NC}"
    echo ""
    echo -e "  ${COLOR_MENU}5.${NC} 每分钟监测频率 ${COLOR_HINT}(PING_SCHEDULE_FREQUENCY)${NC}"
    echo -e "  ${COLOR_MENU}6.${NC} 每分钟监测秒数 ${COLOR_HINT}(PING_SCHEDULE_OFFSET)${NC}"
    echo ""
    echo -e "${COLOR_INFO}  监测目标配置${NC}"
    echo ""
    echo -e "  ${COLOR_MENU}7.${NC} 监测目标 ${COLOR_HINT}(PING_TARGET)${NC}"
    echo ""
    echo -e "${COLOR_INFO}  Ping 模式配置${NC}"
    echo ""
    echo -e "  ${COLOR_MENU}8.${NC} Ping 模式 ${COLOR_HINT}(PING_MODE)${NC}"
    echo -e "  ${COLOR_MENU}9.${NC} 多轮监测轮数 ${COLOR_HINT}(MULTI_PING_ROUND)${NC}"
    echo -e "  ${COLOR_MENU}10.${NC} 多轮监测轮间间隔 ${COLOR_HINT}(MULTI_PING_INTER_DELAY)${NC}"
    echo -e "  ${COLOR_MENU}11.${NC} 轮内间隔 ${COLOR_HINT}(PING_INTRA_DELAY)${NC}"
    echo -e "  ${COLOR_MENU}12.${NC} 单次 Ping 超时时长 ${COLOR_HINT}(PING_TIMEOUT)${NC}"
    echo ""
    echo -e "${COLOR_INFO}  执行模式配置${NC}"
    echo ""
    echo -e "  ${COLOR_MENU}13.${NC} 监测执行模式 ${COLOR_HINT}(EXECUTION_MODE)${NC}"
    echo -e "  ${COLOR_MENU}14.${NC} 错峰模式延迟 ${COLOR_HINT}(STAGGERED_DELAY)${NC}"
    echo ""
    echo -e "${COLOR_INFO}  DNS 解析和缓存配置${NC}"
    echo ""
    echo -e "  ${COLOR_MENU}15.${NC} DNS 缓存 TTL ${COLOR_HINT}(DNS_CACHE_TTL)${NC}"
    echo -e "  ${COLOR_MENU}16.${NC} DNS 解析总超时时长 ${COLOR_HINT}(DNS_TOTAL_TIMEOUT)${NC}"
    echo -e "  ${COLOR_MENU}17.${NC} DNS 单一上游超时时长 ${COLOR_HINT}(DNS_UPSTREAM_TIMEOUT)${NC}"
    echo -e "  ${COLOR_MENU}18.${NC} 自定义 DNS 上游 ${COLOR_HINT}(DNS_UPSTREAMS)${NC}"
    echo ""
    echo -e "${COLOR_INFO}  日志清理配置${NC}"
    echo ""
    echo -e "  ${COLOR_MENU}19.${NC} 日志清理模块开关 ${COLOR_HINT}(LOGS_CLEANER_ENABLED)${NC}"
    echo -e "  ${COLOR_MENU}20.${NC} 日志压缩保留天数 ${COLOR_HINT}(LOGS_COMPRESS_RETENTION_DAYS)${NC}"
    echo -e "  ${COLOR_MENU}21.${NC} 日志压缩文件删除保留天数 ${COLOR_HINT}(LOGS_DELETE_RETENTION_DAYS)${NC}"
    echo ""
    echo -e "  ${COLOR_MENU}0.${NC} 返回"
    echo ""

    local choice=$(get_input "请输入选项")

    case "$choice" in
        1) modify_single_config "VPS_ID" "VPS ID" ;;
        2) modify_single_config "VPS_NAME" "VPS 名称" ;;
        3) modify_single_config "HMAC_SECRET" "HMAC 密钥" ;;
        4) modify_single_config "SERVER_URL" "Server 接收端 URL" ;;
        5) modify_single_config "PING_SCHEDULE_FREQUENCY" "每分钟监测频率" ;;
        6) modify_single_config "PING_SCHEDULE_OFFSET" "每分钟监测秒数" ;;
        7) modify_probe_targets ;;
        8) modify_single_config "PING_MODE" "Ping 模式" ;;
        9) modify_single_config "MULTI_PING_ROUND" "多轮监测轮数" ;;
        10) modify_single_config "MULTI_PING_INTER_DELAY" "多轮监测轮间间隔" ;;
        11) modify_single_config "PING_INTRA_DELAY" "轮内间隔" ;;
        12) modify_single_config "PING_TIMEOUT" "单次 Ping 超时时长" ;;
        13) modify_single_config "EXECUTION_MODE" "监测执行模式" ;;
        14) modify_single_config "STAGGERED_DELAY" "错峰模式延迟" ;;
        15) modify_single_config "DNS_CACHE_TTL" "DNS 缓存 TTL" ;;
        16) modify_single_config "DNS_TOTAL_TIMEOUT" "DNS 解析总超时时长" ;;
        17) modify_single_config "DNS_UPSTREAM_TIMEOUT" "DNS 单一上游超时时长" ;;
        18) modify_single_config "DNS_UPSTREAMS" "自定义 DNS 上游" ;;
        19) modify_single_config "LOGS_CLEANER_ENABLED" "日志清理模块开关" ;;
        20) modify_single_config "LOGS_COMPRESS_RETENTION_DAYS" "日志压缩保留天数" ;;
        21) modify_single_config "LOGS_DELETE_RETENTION_DAYS" "日志压缩文件删除保留天数" ;;
        0) show_update_menu ;;
        *)
            echo ""
            print_error "无效选项"
            do_modify_config
            ;;
    esac
}

# 修改单个配置项
# 参数：$1=环境变量名, $2=中文名称
modify_single_config() {
    local env_key="$1"
    local display_name="$2"

    print_title "修改 $display_name"

    # 读取当前值（直接调用，不使用 $()，以保留全局变量）
    read_env_value "$env_key"
    local current_value="$ENV_VALUE"
    local status="$ENV_VALUE_STATUS"

    # 显示当前配置
    case "$env_key" in
        HMAC_SECRET)
            show_current_config "$current_value" "$status" true
            ;;
        *)
            show_current_config "$current_value" "$status"
            ;;
    esac

    # 对于依赖其他配置的项，先读取依赖值
    case "$env_key" in
        PING_SCHEDULE_OFFSET|MULTI_PING_ROUND)
            # 读取当前频率配置
            read_env_value "PING_SCHEDULE_FREQUENCY"
            ENV_PING_FREQUENCY="$ENV_VALUE"
            if [ -z "$ENV_PING_FREQUENCY" ]; then
                ENV_PING_FREQUENCY="2"
            fi
            ;;
    esac

    # 调用对应的配置函数
    case "$env_key" in
        VPS_ID) config_vps_id ;;
        VPS_NAME) config_vps_name ;;
        HMAC_SECRET) config_hmac_secret ;;
        SERVER_URL) config_server_url ;;
        PING_SCHEDULE_FREQUENCY) config_ping_frequency ;;
        PING_SCHEDULE_OFFSET) config_ping_offset ;;
        PING_MODE) config_ping_mode ;;
        MULTI_PING_ROUND) config_multi_ping_round ;;
        MULTI_PING_INTER_DELAY) config_multi_ping_inter_delay ;;
        PING_INTRA_DELAY) config_ping_intra_delay ;;
        PING_TIMEOUT) config_ping_timeout ;;
        EXECUTION_MODE) config_execution_mode ;;
        STAGGERED_DELAY) config_staggered_delay ;;
        DNS_CACHE_TTL) config_dns_cache_ttl ;;
        DNS_TOTAL_TIMEOUT) config_dns_total_timeout ;;
        DNS_UPSTREAM_TIMEOUT) config_dns_upstream_timeout ;;
        DNS_UPSTREAMS) config_dns_upstreams ;;
        LOGS_CLEANER_ENABLED) config_logs_cleaner_enabled ;;
        LOGS_COMPRESS_RETENTION_DAYS) config_logs_compress_days ;;
        LOGS_DELETE_RETENTION_DAYS) config_logs_delete_days ;;
    esac

    # 更新配置文件
    update_single_env_value "$env_key"

    echo ""
    print_success "配置已更新"

    # 询问是否重启服务
    prompt_restart_service

    echo ""
    echo -ne "${COLOR_PROMPT}请按回车键返回${NC} "; read
    do_modify_config
}

# 更新单个环境变量值到 .env 文件
# 参数：$1=环境变量名
update_single_env_value() {
    local key="$1"
    local value
    local is_configured

    # 根据环境变量名获取对应的值和配置状态
    case "$key" in
        VPS_ID)
            value="$ENV_VPS_ID"
            is_configured=true
            ;;
        VPS_NAME)
            value="$ENV_VPS_NAME"
            is_configured="$ENV_VPS_NAME_CONFIGURED"
            ;;
        HMAC_SECRET)
            value="$ENV_HMAC_SECRET"
            is_configured=true
            ;;
        SERVER_URL)
            value="$ENV_SERVER_URL"
            is_configured=true
            ;;
        PING_SCHEDULE_FREQUENCY)
            value="$ENV_PING_FREQUENCY"
            is_configured=true
            ;;
        PING_SCHEDULE_OFFSET)
            value="$ENV_PING_OFFSET"
            is_configured="$ENV_PING_OFFSET_CONFIGURED"
            ;;
        PING_MODE)
            value="$ENV_PING_MODE"
            is_configured="$ENV_PING_MODE_CONFIGURED"
            ;;
        MULTI_PING_ROUND)
            value="$ENV_MULTI_PING_ROUND"
            is_configured="$ENV_MULTI_PING_ROUND_CONFIGURED"
            ;;
        MULTI_PING_INTER_DELAY)
            value="$ENV_MULTI_PING_INTER_DELAY"
            is_configured="$ENV_MULTI_PING_INTER_DELAY_CONFIGURED"
            ;;
        PING_INTRA_DELAY)
            value="$ENV_PING_INTRA_DELAY"
            is_configured="$ENV_PING_INTRA_DELAY_CONFIGURED"
            ;;
        PING_TIMEOUT)
            value="$ENV_PING_TIMEOUT"
            is_configured="$ENV_PING_TIMEOUT_CONFIGURED"
            ;;
        EXECUTION_MODE)
            value="$ENV_EXECUTION_MODE"
            is_configured="$ENV_EXECUTION_MODE_CONFIGURED"
            ;;
        STAGGERED_DELAY)
            value="$ENV_STAGGERED_DELAY"
            is_configured="$ENV_STAGGERED_DELAY_CONFIGURED"
            ;;
        DNS_CACHE_TTL)
            value="$ENV_DNS_CACHE_TTL"
            is_configured="$ENV_DNS_CACHE_TTL_CONFIGURED"
            ;;
        DNS_TOTAL_TIMEOUT)
            value="$ENV_DNS_TOTAL_TIMEOUT"
            is_configured="$ENV_DNS_TOTAL_TIMEOUT_CONFIGURED"
            ;;
        DNS_UPSTREAM_TIMEOUT)
            value="$ENV_DNS_UPSTREAM_TIMEOUT"
            is_configured="$ENV_DNS_UPSTREAM_TIMEOUT_CONFIGURED"
            ;;
        DNS_UPSTREAMS)
            value="$ENV_DNS_UPSTREAMS"
            is_configured="$ENV_DNS_UPSTREAMS_CONFIGURED"
            ;;
        LOGS_CLEANER_ENABLED)
            value="$ENV_LOGS_CLEANER_ENABLED"
            is_configured="$ENV_LOGS_CLEANER_ENABLED_CONFIGURED"
            ;;
        LOGS_COMPRESS_RETENTION_DAYS)
            value="$ENV_LOGS_COMPRESS_DAYS"
            is_configured="$ENV_LOGS_COMPRESS_DAYS_CONFIGURED"
            ;;
        LOGS_DELETE_RETENTION_DAYS)
            value="$ENV_LOGS_DELETE_DAYS"
            is_configured="$ENV_LOGS_DELETE_DAYS_CONFIGURED"
            ;;
    esac

    # 更新文件
    if [ "$is_configured" = true ]; then
        # 用户明确配置，确保行未被注释并更新值
        # 先尝试替换未注释的行
        if grep -q "^${key}=" "$ENV_FILE"; then
            sed -i "s|^${key}=.*|${key}=${value}|" "$ENV_FILE"
        elif grep -q "^#${key}=" "$ENV_FILE"; then
            # 如果是注释行，取消注释并更新值
            sed -i "s|^#${key}=.*|${key}=${value}|" "$ENV_FILE"
        fi
    else
        # 使用默认值，注释掉该行
        if grep -q "^${key}=" "$ENV_FILE"; then
            sed -i "s|^${key}=.*|#${key}=${value}|" "$ENV_FILE"
        elif grep -q "^#${key}=" "$ENV_FILE"; then
            sed -i "s|^#${key}=.*|#${key}=${value}|" "$ENV_FILE"
        fi
    fi
}

# 修改监测目标配置
modify_probe_targets() {
    print_title "修改监测目标"

    # 显示当前配置
    show_current_probe_targets

    # 检查配置文件
    if [ ! -f "$CONFIG_DIR/probe-targets.yaml" ]; then
        print_error "监测目标配置文件不存在"
        echo ""
        echo -ne "${COLOR_PROMPT}请按回车键返回${NC} "; read
        do_modify_config
        return
    fi

    # 调用现有的配置函数
    configure_probe_targets

    # 更新 .env 文件中的监测目标
    # 1. 删除现有的 PING_TARGET 行
    sed -i '/^PING_TARGET_[0-9]*=/d' "$ENV_FILE"

    # 2. 生成新的目标内容
    local targets_content=""
    for target in "${PING_TARGETS[@]}"; do
        targets_content="${targets_content}${target}"$'\n'
    done

    # 3. 在 "# Ping Targets" 区块的分隔线后插入目标
    local temp_file=$(mktemp)
    local found_header=false
    local wait_for_separator=false
    local inserted=false

    while IFS= read -r line; do
        echo "$line" >> "$temp_file"

        if [[ "$line" == "# Ping Targets" ]]; then
            found_header=true
            wait_for_separator=true
        elif $wait_for_separator && [[ "$line" == "########################" ]]; then
            # 在分隔线后插入空行和目标
            echo "" >> "$temp_file"
            printf "%s" "$targets_content" >> "$temp_file"
            inserted=true
            wait_for_separator=false
        fi
    done < "$ENV_FILE"

    mv "$temp_file" "$ENV_FILE"

    echo ""
    print_success "配置已更新"

    # 询问是否重启服务
    prompt_restart_service

    echo ""
    echo -ne "${COLOR_PROMPT}请按回车键返回${NC} "; read
    do_modify_config
}

# ============================================================
# 通用工具函数（被多个功能使用）
# ============================================================

# 询问是否重启/启动服务并显示状态
prompt_restart_service() {
    local service_file="/etc/systemd/system/$SERVICE_NAME.service"

    # 检查服务文件是否存在
    if [ ! -f "$service_file" ]; then
        echo ""
        echo -e "${YELLOW_LIGHT}当前尚未配置 systemd 服务，无需重启或启动${NC}"
        return
    fi

    # 检查服务是否运行中
    local is_running=false
    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        is_running=true
    fi

    echo ""
    if [ "$is_running" = true ]; then
        # 服务运行中，询问是否重启
        if confirm "是否重启服务使配置生效？"; then
            do_restart_service "重启"
        fi
    else
        # 服务未运行，提示并询问是否启动
        echo -e "${YELLOW_LIGHT}◎ 服务未运行${NC}"
        echo ""
        if confirm "是否启动服务？"; then
            do_restart_service "启动"
        fi
    fi
}

# 执行重启/启动服务并显示状态
# 参数：$1=操作类型（"重启" 或 "启动"）
do_restart_service() {
    local action="$1"

    echo ""
    print_info "正在${action}服务..."
    systemctl restart "$SERVICE_NAME"

    # 等待服务启动
    sleep 2

    # 显示服务状态
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo -e "  ${GREEN}✓${NC} ${COLOR_HINT}服务已${action}${NC}"
        echo ""

        echo -e "${COLOR_INFO}◎ 服务状态：${NC}"
        echo ""
        local pid=$(systemctl show "$SERVICE_NAME" --property=MainPID --value)
        local memory=$(systemctl show "$SERVICE_NAME" --property=MemoryCurrent --value)
        local active_enter=$(systemctl show "$SERVICE_NAME" --property=ActiveEnterTimestamp --value)

        # 格式化内存显示
        local memory_display="N/A"
        if [ "$memory" != "[not set]" ] && [ -n "$memory" ]; then
            local memory_mb=$(awk "BEGIN {printf \"%.1f\", $memory / 1024 / 1024}")
            memory_display="${memory_mb} MB"
        fi

        # 计算启动时长
        local uptime_display="N/A"
        if [ -n "$active_enter" ]; then
            local start_ts=$(date -d "$active_enter" +%s 2>/dev/null)
            local now_ts=$(date +%s)
            if [ -n "$start_ts" ]; then
                local uptime_sec=$((now_ts - start_ts))
                if [ $uptime_sec -lt 60 ]; then
                    uptime_display="${uptime_sec} 秒前"
                elif [ $uptime_sec -lt 3600 ]; then
                    uptime_display="$((uptime_sec / 60)) 分钟前"
                else
                    uptime_display="$((uptime_sec / 3600)) 小时前"
                fi
            fi
        fi

        echo -e "  PID:      ${COLOR_VALUE}$pid${NC}"
        echo -e "  状态:     ${COLOR_SUCCESS}运行中${NC}"
        echo -e "  内存占用: ${COLOR_VALUE}$memory_display${NC}"
        echo -e "  启动时间: ${COLOR_VALUE}$uptime_display${NC}"
    else
        echo -e "  ${RED}×${NC} ${COLOR_HINT}服务${action}失败${NC}"
    fi
}

# ============================================================
# 入口
# ============================================================

main() {
    # 检查是否以 root 运行
    if [ "$EUID" -ne 0 ]; then
        print_error "请使用 root 权限运行此脚本"
        echo -e "${COLOR_HINT}使用: sudo $0${NC}"
        exit 1
    fi

    show_main_menu
}

main "$@"
