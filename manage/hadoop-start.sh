#!/bin/bash

# Hadoop集群启动脚本
# 基于Ubuntu Server 25.04
# 支持一键启动Hadoop集群

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

# 显示使用帮助
show_help() {
    echo "Hadoop 集群启动工具"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -h, --help              显示此帮助信息"
    echo "  -a, --all               启动所有服务 (HDFS+YARN)"
    echo "  -d, --dfs               仅启动HDFS服务"
    echo "  -y, --yarn              仅启动YARN服务"
    echo "  -r, --restart           重启服务"
    echo "  -s, --stop              停止服务"
    echo ""
    echo "示例:"
    echo "  $0 -a                   启动所有Hadoop服务"
    echo "  $0 -r -d                重启HDFS服务"
    echo "  $0 -s                   停止所有Hadoop服务"
    echo ""
}

# 检查Hadoop环境
check_hadoop_env() {
    print_section "检查Hadoop环境"
    
    # 检查是否以hadoop用户运行
    if [ "$(whoami)" != "hadoop" ]; then
        print_error "请以hadoop用户运行此脚本"
        exit 1
    fi
    
    # 检查Hadoop目录是否存在
    if [ ! -d "$HOME/hadoop" ]; then
        print_error "Hadoop目录不存在: $HOME/hadoop"
        exit 1
    fi
    
    # 检查JAVA_HOME环境变量
    if [ -z "$JAVA_HOME" ]; then
        print_warning "JAVA_HOME环境变量未设置，尝试自动设置"
        export JAVA_HOME=$(readlink -f /usr/bin/java | sed "s:/bin/java::")
        if [ -z "$JAVA_HOME" ]; then
            print_error "无法自动设置JAVA_HOME，请手动设置"
            exit 1
        fi
        print_message "已设置JAVA_HOME: $JAVA_HOME"
    else
        print_message "JAVA_HOME: $JAVA_HOME"
    fi
    
    # 检查HADOOP_HOME环境变量
    if [ -z "$HADOOP_HOME" ]; then
        print_warning "HADOOP_HOME环境变量未设置，自动设置为 $HOME/hadoop"
        export HADOOP_HOME="$HOME/hadoop"
        export PATH=$PATH:$HADOOP_HOME/bin:$HADOOP_HOME/sbin
        print_message "已设置HADOOP_HOME: $HADOOP_HOME"
    else
        print_message "HADOOP_HOME: $HADOOP_HOME"
    fi
    
    # 检查SSH免密登录
    local workers=$(cat $HADOOP_HOME/etc/hadoop/workers | grep -v "^#" | grep -v "^$")
    for worker in $workers; do
        print_message "检查SSH免密登录到 $worker"
        if ! ssh -o BatchMode=yes -o ConnectTimeout=5 $worker exit 0 > /dev/null 2>&1; then
            print_error "无法SSH免密登录到 $worker，请确保已配置SSH密钥"
            print_warning "您可以使用以下命令复制SSH密钥:"
            echo "  ssh-copy-id hadoop@$worker"
            exit 1
        fi
    done
    
    print_message "Hadoop环境检查通过"
}

# 启动HDFS服务
start_dfs() {
    print_section "启动HDFS服务"
    
    # 检查NameNode是否已经在运行
    if jps | grep -q NameNode; then
        print_warning "NameNode已经在运行"
    else
        # 启动HDFS
        $HADOOP_HOME/sbin/start-dfs.sh
        
        # 等待服务启动
        sleep 5
        
        # 检查服务是否启动成功
        if jps | grep -q NameNode; then
            print_message "HDFS服务启动成功"
        else
            print_error "HDFS服务启动失败，请检查日志文件"
            exit 1
        fi
    fi
}

# 启动YARN服务
start_yarn() {
    print_section "启动YARN服务"
    
    # 检查ResourceManager是否已经在运行
    if jps | grep -q ResourceManager; then
        print_warning "ResourceManager已经在运行"
    else
        # 启动YARN
        $HADOOP_HOME/sbin/start-yarn.sh
        
        # 等待服务启动
        sleep 5
        
        # 检查服务是否启动成功
        if jps | grep -q ResourceManager; then
            print_message "YARN服务启动成功"
        else
            print_error "YARN服务启动失败，请检查日志文件"
            exit 1
        fi
    fi
}

# 停止HDFS服务
stop_dfs() {
    print_section "停止HDFS服务"
    
    # 检查NameNode是否在运行
    if jps | grep -q NameNode; then
        # 停止HDFS
        $HADOOP_HOME/sbin/stop-dfs.sh
        
        # 等待服务停止
        sleep 5
        
        # 检查服务是否停止成功
        if jps | grep -q NameNode; then
            print_error "HDFS服务停止失败"
            exit 1
        else
            print_message "HDFS服务停止成功"
        fi
    else
        print_warning "HDFS服务未运行"
    fi
}

# 停止YARN服务
stop_yarn() {
    print_section "停止YARN服务"
    
    # 检查ResourceManager是否在运行
    if jps | grep -q ResourceManager; then
        # 停止YARN
        $HADOOP_HOME/sbin/stop-yarn.sh
        
        # 等待服务停止
        sleep 5
        
        # 检查服务是否停止成功
        if jps | grep -q ResourceManager; then
            print_error "YARN服务停止失败"
            exit 1
        else
            print_message "YARN服务停止成功"
        fi
    else
        print_warning "YARN服务未运行"
    fi
}

# 显示集群状态
show_status() {
    print_section "集群状态"
    
    # 显示进程状态
    jps
    
    # 检查NameNode状态
    if jps | grep -q NameNode; then
        # 获取HDFS状态
        local hdfs_report=$($HADOOP_HOME/bin/hdfs dfsadmin -report)
        local live_nodes=$(echo "$hdfs_report" | grep "Live datanodes" | awk '{print $3}')
        local total_nodes=$(cat $HADOOP_HOME/etc/hadoop/workers | grep -v "^#" | grep -v "^$" | wc -l)
        
        print_message "HDFS状态: 活动DataNode $live_nodes / 总计 $total_nodes"
        
        # 如果有DataNode未启动，显示警告
        if [ "$live_nodes" -lt "$total_nodes" ]; then
            print_warning "有 $((total_nodes - live_nodes)) 个DataNode未启动，请检查"
        fi
    else
        print_warning "HDFS服务未运行"
    fi
    
    # 检查ResourceManager状态
    if jps | grep -q ResourceManager; then
        # 获取YARN节点状态
        local yarn_nodes=$($HADOOP_HOME/bin/yarn node -list | grep RUNNING | wc -l)
        local total_nodes=$(cat $HADOOP_HOME/etc/hadoop/workers | grep -v "^#" | grep -v "^$" | wc -l)
        
        print_message "YARN状态: 活动NodeManager $yarn_nodes / 总计 $total_nodes"
        
        # 如果有NodeManager未启动，显示警告
        if [ "$yarn_nodes" -lt "$total_nodes" ]; then
            print_warning "有 $((total_nodes - yarn_nodes)) 个NodeManager未启动，请检查"
        fi
    else
        print_warning "YARN服务未运行"
    fi
    
    # 显示Web界面访问信息
    local hostname=$(hostname)
    print_message "Web界面:"
    print_message "  NameNode: http://$hostname:9870"
    print_message "  ResourceManager: http://$hostname:8088"
}

# 主函数
main() {
    # 默认操作模式
    local MODE="start"
    local START_DFS=false
    local START_YARN=false
    
    # 解析命令行参数
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -a|--all)
                START_DFS=true
                START_YARN=true
                shift
                ;;
            -d|--dfs)
                START_DFS=true
                shift
                ;;
            -y|--yarn)
                START_YARN=true
                shift
                ;;
            -r|--restart)
                MODE="restart"
                shift
                ;;
            -s|--stop)
                MODE="stop"
                shift
                ;;
            *)
                print_error "未知选项: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # 如果没有指定服务，默认启动所有服务
    if [ "$START_DFS" = false ] && [ "$START_YARN" = false ]; then
        START_DFS=true
        START_YARN=true
    fi
    
    # 检查Hadoop环境
    check_hadoop_env
    
    # 根据操作模式执行操作
    case $MODE in
        start)
            if [ "$START_DFS" = true ]; then
                start_dfs
            fi
            if [ "$START_YARN" = true ]; then
                start_yarn
            fi
            ;;
        restart)
            if [ "$START_DFS" = true ]; then
                stop_dfs
                start_dfs
            fi
            if [ "$START_YARN" = true ]; then
                stop_yarn
                start_yarn
            fi
            ;;
        stop)
            if [ "$START_YARN" = true ]; then
                stop_yarn
            fi
            if [ "$START_DFS" = true ]; then
                stop_dfs
            fi
            ;;
        *)
            print_error "未知操作模式: $MODE"
            exit 1
            ;;
    esac
    
    # 显示集群状态
    show_status
    
    print_section "操作完成"
}

# 执行主函数
main "$@" 