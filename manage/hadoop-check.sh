#!/bin/bash

# Hadoop集群状态检查脚本
# 基于Ubuntu Server 25.04
# 用于监控集群健康状况

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
    echo "Hadoop 集群状态检查工具"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -h, --help              显示此帮助信息"
    echo "  -b, --basic             基础检查 (默认)"
    echo "  -f, --full              完整检查"
    echo "  -d, --detailed          详细检查特定组件"
    echo "  -c, --component COMP    指定组件 (hdfs|yarn|dfs|all)"
    echo "  -n, --node NODE         检查特定节点"
    echo ""
    echo "示例:"
    echo "  $0                      执行基础检查"
    echo "  $0 -f                   执行完整检查"
    echo "  $0 -d -c hdfs           详细检查HDFS"
    echo "  $0 -n hadoop-slave1     检查hadoop-slave1节点"
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
    
    print_message "Hadoop环境检查通过"
}

# 基础检查
basic_check() {
    print_section "基础检查"
    
    # 显示进程状态
    print_message "进程状态:"
    jps
    
    # 检查NameNode状态
    if jps | grep -q NameNode; then
        print_message "NameNode 运行中"
    else
        print_error "NameNode 未运行"
        return 1
    fi
    
    # 检查DataNode状态
    if jps | grep -q DataNode; then
        print_message "DataNode 运行中"
    else
        print_warning "当前节点上DataNode未运行"
    fi
    
    # 检查ResourceManager状态
    if jps | grep -q ResourceManager; then
        print_message "ResourceManager 运行中"
    else
        print_error "ResourceManager 未运行"
    fi
    
    # 检查NodeManager状态
    if jps | grep -q NodeManager; then
        print_message "NodeManager 运行中"
    else
        print_warning "当前节点上NodeManager未运行"
    fi
    
    # 显示HDFS状态概览
    if jps | grep -q NameNode; then
        print_message "HDFS状态概览:"
        local hdfs_report=$($HADOOP_HOME/bin/hdfs dfsadmin -report | head -n 20)
        echo "$hdfs_report"
    fi
    
    # 显示YARN状态概览
    if jps | grep -q ResourceManager; then
        print_message "YARN状态概览:"
        local yarn_nodes=$($HADOOP_HOME/bin/yarn node -list | grep RUNNING | wc -l)
        local total_nodes=$(cat $HADOOP_HOME/etc/hadoop/workers | grep -v "^#" | grep -v "^$" | wc -l)
        
        print_message "活动NodeManager: $yarn_nodes / $total_nodes"
    fi
    
    # 显示Web界面访问信息
    local hostname=$(hostname)
    print_message "Web界面:"
    print_message "  NameNode: http://$hostname:9870"
    print_message "  ResourceManager: http://$hostname:8088"
}

# 详细检查HDFS
check_hdfs_detailed() {
    print_section "HDFS详细检查"
    
    # 检查NameNode状态
    if ! jps | grep -q NameNode; then
        print_error "NameNode未运行，无法完成HDFS详细检查"
        return 1
    fi
    
    # 检查HDFS目录结构
    print_message "HDFS目录结构:"
    $HADOOP_HOME/bin/hdfs dfs -ls /
    
    # 检查HDFS报告
    print_message "HDFS状态报告:"
    $HADOOP_HOME/bin/hdfs dfsadmin -report
    
    # 检查HDFS安全模式
    local safe_mode=$($HADOOP_HOME/bin/hdfs dfsadmin -safemode get)
    print_message "安全模式状态: $safe_mode"
    
    # 检查HDFS容量
    print_message "HDFS容量统计:"
    $HADOOP_HOME/bin/hdfs dfs -du -h /
    
    # 检查HDFS健康状态
    print_message "HDFS健康检查:"
    $HADOOP_HOME/bin/hdfs fsck / | grep -E "Status|Total|CORRUPT|MISSING|HEALTHY"
    
    # 检查DataNode状态
    print_message "DataNode状态:"
    local workers=$(cat $HADOOP_HOME/etc/hadoop/workers | grep -v "^#" | grep -v "^$")
    for worker in $workers; do
        print_message "  检查 $worker 的DataNode状态"
        if ssh -o BatchMode=yes -o ConnectTimeout=5 $worker "jps | grep -q DataNode"; then
            print_message "  $worker: DataNode 运行中"
        else
            print_error "  $worker: DataNode 未运行"
        fi
    done
}

# 详细检查YARN
check_yarn_detailed() {
    print_section "YARN详细检查"
    
    # 检查ResourceManager状态
    if ! jps | grep -q ResourceManager; then
        print_error "ResourceManager未运行，无法完成YARN详细检查"
        return 1
    fi
    
    # 检查YARN应用
    print_message "YARN应用状态:"
    $HADOOP_HOME/bin/yarn application -list
    
    # 检查YARN节点
    print_message "YARN节点状态:"
    $HADOOP_HOME/bin/yarn node -list -all
    
    # 检查YARN队列
    print_message "YARN队列状态:"
    $HADOOP_HOME/bin/yarn queue -status default
    
    # 检查ResourceManager状态
    print_message "ResourceManager状态:"
    $HADOOP_HOME/bin/yarn rmadmin -getServiceState rm1 2>/dev/null || echo "ResourceManager状态获取失败"
    
    # 检查NodeManager状态
    print_message "NodeManager状态:"
    local workers=$(cat $HADOOP_HOME/etc/hadoop/workers | grep -v "^#" | grep -v "^$")
    for worker in $workers; do
        print_message "  检查 $worker 的NodeManager状态"
        if ssh -o BatchMode=yes -o ConnectTimeout=5 $worker "jps | grep -q NodeManager"; then
            print_message "  $worker: NodeManager 运行中"
        else
            print_error "  $worker: NodeManager 未运行"
        fi
    done
}

# 检查特定节点
check_node() {
    local node=$1
    print_section "节点检查: $node"
    
    # 检查节点可达性
    if ! ping -c 1 -W 3 $node > /dev/null 2>&1; then
        print_error "无法ping通节点 $node"
        return 1
    fi
    print_message "节点 $node 可达"
    
    # 检查SSH连接
    if ! ssh -o BatchMode=yes -o ConnectTimeout=5 $node exit 0 > /dev/null 2>&1; then
        print_error "无法SSH免密登录到 $node"
        return 1
    fi
    print_message "SSH免密登录到 $node 成功"
    
    # 检查节点上的进程
    print_message "节点 $node 上的进程:"
    ssh $node "jps"
    
    # 检查磁盘空间
    print_message "节点 $node 的磁盘空间:"
    ssh $node "df -h"
    
    # 检查内存使用情况
    print_message "节点 $node 的内存使用情况:"
    ssh $node "free -h"
    
    # 检查CPU负载
    print_message "节点 $node 的CPU负载:"
    ssh $node "uptime"
    
    # 检查Hadoop目录
    print_message "节点 $node 的Hadoop目录:"
    ssh $node "ls -la ~/hadoop"
    
    # 检查Hadoop数据目录
    print_message "节点 $node 的Hadoop数据目录:"
    ssh $node "ls -la ~/hadoopdata"
    
    # 检查Hadoop日志
    print_message "节点 $node 的Hadoop日志:"
    ssh $node "ls -la ~/hadoop/logs"
    
    # 检查最近的日志内容
    print_message "节点 $node 的最近日志内容:"
    ssh $node "find ~/hadoop/logs -type f -name \"*.log\" -mtime -1 | xargs tail -n 5"
}

# 完整检查
full_check() {
    print_section "完整检查"
    
    # 基础检查
    basic_check
    
    # 详细检查HDFS
    check_hdfs_detailed
    
    # 详细检查YARN
    check_yarn_detailed
    
    # 检查所有节点
    local workers=$(cat $HADOOP_HOME/etc/hadoop/workers | grep -v "^#" | grep -v "^$")
    for worker in $workers; do
        check_node $worker
    done
}

# 主函数
main() {
    # 默认参数
    local CHECK_TYPE="basic"
    local COMPONENT="all"
    local NODE=""
    
    # 解析命令行参数
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -b|--basic)
                CHECK_TYPE="basic"
                shift
                ;;
            -f|--full)
                CHECK_TYPE="full"
                shift
                ;;
            -d|--detailed)
                CHECK_TYPE="detailed"
                shift
                ;;
            -c|--component)
                COMPONENT="$2"
                shift 2
                ;;
            -n|--node)
                NODE="$2"
                shift 2
                ;;
            *)
                print_error "未知选项: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # 检查Hadoop环境
    check_hadoop_env
    
    # 根据检查类型执行检查
    if [ ! -z "$NODE" ]; then
        # 检查特定节点
        check_node "$NODE"
    elif [ "$CHECK_TYPE" = "basic" ]; then
        # 基础检查
        basic_check
    elif [ "$CHECK_TYPE" = "full" ]; then
        # 完整检查
        full_check
    elif [ "$CHECK_TYPE" = "detailed" ]; then
        # 详细检查特定组件
        case $COMPONENT in
            hdfs|dfs)
                check_hdfs_detailed
                ;;
            yarn)
                check_yarn_detailed
                ;;
            all)
                check_hdfs_detailed
                check_yarn_detailed
                ;;
            *)
                print_error "未知组件: $COMPONENT"
                show_help
                exit 1
                ;;
        esac
    else
        print_error "未知检查类型: $CHECK_TYPE"
        exit 1
    fi
    
    print_section "检查完成"
}

# 执行主函数
main "$@" 