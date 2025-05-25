#!/bin/bash

# Hadoop集群配置主脚本
# 基于Ubuntu Server 25.04
# 支持自动配置Hadoop 3.4.1分布式集群

set -e  # 遇到错误时停止执行

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 打印带颜色的消息
print_message() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_section() {
    echo -e "\n${BLUE}====== $1 ======${NC}"
}

# 检查脚本是否以root权限运行
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "请以root权限运行此脚本"
        exit 1
    fi
}

# 显示使用帮助
show_help() {
    echo "Hadoop 集群配置工具"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -h, --help              显示此帮助信息"
    echo "  -m, --master            配置主节点"
    echo "  -s, --slave             配置从节点"
    echo "  --master-ip IP          设置主节点IP (例如: 192.168.1.100)"
    echo "  --slave1-ip IP          设置从节点1 IP (例如: 192.168.1.101)"
    echo "  --slave2-ip IP          设置从节点2 IP (例如: 192.168.1.102)"
    echo "  --hostname NAME         设置当前节点主机名"
    echo "  --gateway IP            设置网关IP (例如: 192.168.1.1)"
    echo "  --postinstall           执行安装后配置 (复制脚本、设置权限等)"
    echo ""
    echo "示例:"
    echo "  $0 -m --master-ip 192.168.1.100 --slave1-ip 192.168.1.101 --slave2-ip 192.168.1.102 --hostname hadoop-master --gateway 192.168.1.1"
    echo "  $0 -s --master-ip 192.168.1.100 --hostname hadoop-slave1 --gateway 192.168.1.1"
    echo "  $0 --postinstall        # 执行安装后配置"
    echo ""
}

# 检查必要的依赖程序是否已安装
check_dependencies() {
    print_section "检查依赖"
    
    # 要检查的依赖列表
    local deps=("ssh" "netplan" "wget" "bc")
    local missing_deps=()
    
    for dep in "${deps[@]}"; do
        if ! command -v $dep &> /dev/null; then
            missing_deps+=($dep)
        fi
    done
    
    # 如果有缺失的依赖，尝试安装
    if [ ${#missing_deps[@]} -gt 0 ]; then
        print_warning "以下依赖未安装: ${missing_deps[*]}"
        print_message "尝试安装缺失的依赖..."
        
        # 更新软件包列表
        apt update
        
        # 安装缺失的依赖
        for dep in "${missing_deps[@]}"; do
            print_message "安装 $dep..."
            apt install -y $dep
            if [ $? -ne 0 ]; then
                print_error "安装 $dep 失败"
                exit 1
            fi
        done
        
        print_message "所有依赖已安装"
    else
        print_message "所有必要的依赖已安装"
    fi
}

# 检查系统依赖
check_dependencies() {
    print_section "检查系统依赖"
    
    # 检查必要的命令是否存在
    local required_commands=("wget" "tar" "ssh" "netplan" "hostnamectl")
    local missing_commands=()
    
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_commands+=("$cmd")
        fi
    done
    
    if [ ${#missing_commands[@]} -gt 0 ]; then
        print_error "缺少必要的命令: ${missing_commands[*]}"
        print_message "请安装缺少的软件包"
        exit 1
    fi
    
    # 检查网络连接
    if ! ping -c 1 8.8.8.8 &> /dev/null; then
        print_warning "网络连接可能存在问题，请检查网络配置"
    fi
    
    print_message "系统依赖检查通过"
}

# 自动检测网络接口
detect_network_interface() {
    print_section "检测网络接口"
    
    # 获取活动的网络接口（排除lo）
    local interfaces=$(ip link show | grep -E '^[0-9]+:' | grep -v 'lo:' | awk -F': ' '{print $2}' | head -1)
    
    if [ -z "$interfaces" ]; then
        print_error "无法检测到网络接口"
        print_message "请手动指定网络接口名称"
        exit 1
    fi
    
    NETWORK_INTERFACE="$interfaces"
    print_message "检测到网络接口: $NETWORK_INTERFACE"
}

# 复制管理脚本到hadoop用户目录
copy_management_scripts() {
    print_section "复制管理脚本"
    
    # 检查hadoop用户是否存在
    if ! id -u hadoop &> /dev/null; then
        print_error "hadoop用户不存在，请先配置节点"
        exit 1
    fi
    
    # 检查管理脚本是否存在
    local scripts=("hadoop-start.sh" "hadoop-check.sh" "hadoop-test.sh")
    local missing_scripts=()
    
    for script in "${scripts[@]}"; do
        if [ ! -f "./$script" ]; then
            missing_scripts+=($script)
        fi
    done
    
    if [ ${#missing_scripts[@]} -gt 0 ]; then
        print_error "以下管理脚本不存在: ${missing_scripts[*]}"
        exit 1
    fi
    
    # 复制脚本到hadoop用户目录
    print_message "复制管理脚本到hadoop用户目录..."
    cp ./hadoop-start.sh ./hadoop-check.sh ./hadoop-test.sh /home/hadoop/
    
    # 设置脚本权限
    print_message "设置脚本执行权限..."
    chown hadoop:hadoop /home/hadoop/hadoop-start.sh /home/hadoop/hadoop-check.sh /home/hadoop/hadoop-test.sh
    chmod +x /home/hadoop/hadoop-start.sh /home/hadoop/hadoop-check.sh /home/hadoop/hadoop-test.sh
    
    print_message "管理脚本已复制到hadoop用户目录"
}

# 执行安装后配置
do_postinstall() {
    print_section "执行安装后配置"
    
    # 检查root权限
    check_root
    
    # 复制管理脚本
    copy_management_scripts
    
    print_message "安装后配置完成"
    print_message "您现在可以使用以下命令管理集群:"
    echo "  su - hadoop"
    echo "  bash hadoop-start.sh -a  # 启动所有服务"
    echo "  bash hadoop-check.sh     # 检查集群状态"
    echo "  bash hadoop-test.sh      # 测试集群功能"
}

# 验证配置文件
validate_config() {
    local node_type=$1
    
    if [ "$node_type" == "master" ]; then
        if [ -z "$MASTER_IP" ] || [ -z "$SLAVE1_IP" ] || [ -z "$HOSTNAME" ] || [ -z "$GATEWAY" ]; then
            print_error "配置主节点需要指定 --master-ip, --slave1-ip, --hostname 和 --gateway"
            return 1
        fi
        
        # 验证IP地址格式
        if ! [[ $MASTER_IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            print_error "主节点IP格式不正确: $MASTER_IP"
            return 1
        fi
        
        if ! [[ $SLAVE1_IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            print_error "从节点1 IP格式不正确: $SLAVE1_IP"
            return 1
        fi
        
        if [ ! -z "$SLAVE2_IP" ] && ! [[ $SLAVE2_IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            print_error "从节点2 IP格式不正确: $SLAVE2_IP"
            return 1
        fi
        
    elif [ "$node_type" == "slave" ]; then
        if [ -z "$MASTER_IP" ] || [ -z "$HOSTNAME" ] || [ -z "$GATEWAY" ]; then
            print_error "配置从节点需要指定 --master-ip, --hostname 和 --gateway"
            return 1
        fi
        
        # 验证IP地址格式
        if ! [[ $MASTER_IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            print_error "主节点IP格式不正确: $MASTER_IP"
            return 1
        fi
    fi
    
    # 验证网关IP地址格式
    if ! [[ $GATEWAY =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        print_error "网关IP格式不正确: $GATEWAY"
        return 1
    fi
    
    return 0
}

# 检查所需文件是否存在
check_required_files() {
    local node_type=$1
    
    if [ "$node_type" == "master" ]; then
        if [ ! -f "./master-setup.sh" ]; then
            print_error "找不到主节点配置脚本: master-setup.sh"
            return 1
        fi
    elif [ "$node_type" == "slave" ]; then
        if [ ! -f "./slave-setup.sh" ]; then
            print_error "找不到从节点配置脚本: slave-setup.sh"
            return 1
        fi
    fi
    
    return 0
}

# 执行配置脚本
execute_setup_script() {
    local node_type=$1
    local script_name=""
    local script_args=""
    
    if [ "$node_type" == "master" ]; then
        script_name="./master-setup.sh"
        script_args="--master-ip \"$MASTER_IP\" --slave1-ip \"$SLAVE1_IP\" --hostname \"$HOSTNAME\" --gateway \"$GATEWAY\""
        
        if [ ! -z "$SLAVE2_IP" ]; then
            script_args="$script_args --slave2-ip \"$SLAVE2_IP\""
        fi
    elif [ "$node_type" == "slave" ]; then
        script_name="./slave-setup.sh"
        script_args="--master-ip \"$MASTER_IP\" --hostname \"$HOSTNAME\" --gateway \"$GATEWAY\""
    fi
    
    print_message "执行配置脚本: $script_name $script_args"
    
    # 使用eval执行命令，以便正确处理带引号的参数
    eval "$script_name $script_args"
    
    if [ $? -ne 0 ]; then
        print_error "配置脚本执行失败"
        return 1
    fi
    
    return 0
}

# 主函数
main() {
    if [ $# -eq 0 ]; then
        show_help
        exit 0
    fi

    # 解析命令行参数
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -m|--master)
                NODE_TYPE="master"
                shift
                ;;
            -s|--slave)
                NODE_TYPE="slave"
                shift
                ;;
            --master-ip)
                MASTER_IP="$2"
                shift 2
                ;;
            --slave1-ip)
                SLAVE1_IP="$2"
                shift 2
                ;;
            --slave2-ip)
                SLAVE2_IP="$2"
                shift 2
                ;;
            --hostname)
                HOSTNAME="$2"
                shift 2
                ;;
            --gateway)
                GATEWAY="$2"
                shift 2
                ;;
            --postinstall)
                DO_POSTINSTALL=true
                shift
                ;;
            *)
                print_error "未知选项: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # 如果指定了执行安装后配置
    if [ "$DO_POSTINSTALL" = true ]; then
        do_postinstall
        exit 0
    fi

    # 检查是否指定了节点类型
    if [ -z "$NODE_TYPE" ]; then
        print_error "请指定节点类型: -m/--master 或 -s/--slave"
        show_help
        exit 1
    fi

    # 检查root权限
    check_root
    
    # 检查依赖
    check_dependencies
    
    # 检测网络接口
    detect_network_interface
    
    # 验证配置
    if ! validate_config "$NODE_TYPE"; then
        exit 1
    fi
    
    # 检查所需文件
    if ! check_required_files "$NODE_TYPE"; then
        exit 1
    fi
    
    # 执行配置脚本
    if ! execute_setup_script "$NODE_TYPE"; then
        exit 1
    fi
    
    print_message "节点配置完成"
    print_message "使用 '$0 --postinstall' 复制管理脚本到hadoop用户目录"
}

# 执行主函数
main "$@"