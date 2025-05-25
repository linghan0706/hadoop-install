#!/bin/bash

# Hadoop集群测试脚本
# 基于Ubuntu Server 25.04
# 用于测试集群功能是否正常

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
    echo "Hadoop 集群测试工具"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -h, --help              显示此帮助信息"
    echo "  -a, --all               执行所有测试 (默认)"
    echo "  -b, --basic             执行基础测试"
    echo "  -d, --dfs               执行HDFS测试"
    echo "  -y, --yarn              执行YARN/MapReduce测试"
    echo "  -c, --clean             测试完成后清理测试数据"
    echo "  -s, --size SIZE         测试数据大小 (MB，默认: 10)"
    echo ""
    echo "示例:"
    echo "  $0                      执行所有测试"
    echo "  $0 -d                   只执行HDFS测试"
    echo "  $0 -b -c                执行基础测试并清理"
    echo "  $0 -a -s 100            执行所有测试，使用100MB测试数据"
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
    
    # 检查集群是否运行
    if ! jps | grep -q NameNode; then
        print_error "NameNode未运行，请先启动Hadoop集群"
        print_message "可以使用以下命令启动集群:"
        echo "  $HOME/hadoop/sbin/start-dfs.sh"
        echo "  $HOME/hadoop/sbin/start-yarn.sh"
        exit 1
    fi
    
    print_message "Hadoop环境检查通过"
}

# 创建测试数据
create_test_data() {
    local size=$1  # Size in MB
    print_section "创建测试数据 (${size}MB)"
    
    # 创建测试目录
    mkdir -p $HOME/hadoop_test
    
    # 创建测试文件
    print_message "生成 ${size}MB 的测试文件..."
    dd if=/dev/urandom of=$HOME/hadoop_test/test_data.txt bs=1M count=$size
    
    # 创建测试文本文件
    print_message "生成测试文本文件..."
    cat > $HOME/hadoop_test/words.txt << EOF
Hello Hadoop
Welcome to Hadoop world
Hadoop is a framework for distributed storage and processing
HDFS is the Hadoop Distributed File System
YARN is Yet Another Resource Negotiator
MapReduce is a programming model for large-scale data processing
Hadoop ecosystem includes many projects
Spark Hive HBase Storm Kafka Zookeeper
Big Data analytics with Hadoop
EOF
    
    print_message "测试数据创建完成"
}

# 测试HDFS基本功能
test_hdfs_basic() {
    print_section "测试HDFS基本功能"
    
    # 确保测试目录存在
    print_message "创建HDFS测试目录..."
    $HADOOP_HOME/bin/hdfs dfs -mkdir -p /test
    
    # 上传测试文件
    print_message "上传测试文件到HDFS..."
    $HADOOP_HOME/bin/hdfs dfs -put $HOME/hadoop_test/words.txt /test/
    
    # 检查文件是否上传成功
    print_message "检查文件是否上传成功..."
    if $HADOOP_HOME/bin/hdfs dfs -test -e /test/words.txt; then
        print_message "文件上传成功"
    else
        print_error "文件上传失败"
        return 1
    fi
    
    # 读取文件内容
    print_message "读取HDFS上的文件内容..."
    $HADOOP_HOME/bin/hdfs dfs -cat /test/words.txt
    
    # 检查文件权限
    print_message "检查文件权限..."
    $HADOOP_HOME/bin/hdfs dfs -ls /test/
    
    # 复制文件
    print_message "复制文件..."
    $HADOOP_HOME/bin/hdfs dfs -cp /test/words.txt /test/words_copy.txt
    
    # 检查副本是否创建成功
    if $HADOOP_HOME/bin/hdfs dfs -test -e /test/words_copy.txt; then
        print_message "文件复制成功"
    else
        print_error "文件复制失败"
        return 1
    fi
    
    print_message "HDFS基本功能测试通过"
}

# 测试HDFS性能
test_hdfs_performance() {
    print_section "测试HDFS性能"
    
    local size=$1  # Size in MB
    local file_path="$HOME/hadoop_test/test_data.txt"
    
    # 上传大文件
    print_message "上传 ${size}MB 文件到HDFS (计时)..."
    local start_time=$(date +%s)
    
    $HADOOP_HOME/bin/hdfs dfs -put $file_path /test/
    
    local end_time=$(date +%s)
    local upload_time=$((end_time - start_time))
    
    local upload_speed=$(echo "scale=2; $size / $upload_time" | bc)
    print_message "上传完成: ${upload_time}秒, 速度: ${upload_speed}MB/s"
    
    # 下载大文件
    print_message "从HDFS下载文件 (计时)..."
    rm -f $HOME/hadoop_test/test_data_download.txt
    
    start_time=$(date +%s)
    
    $HADOOP_HOME/bin/hdfs dfs -get /test/test_data.txt $HOME/hadoop_test/test_data_download.txt
    
    end_time=$(date +%s)
    local download_time=$((end_time - start_time))
    
    local download_speed=$(echo "scale=2; $size / $download_time" | bc)
    print_message "下载完成: ${download_time}秒, 速度: ${download_speed}MB/s"
    
    # 检查文件是否一致
    print_message "检查文件完整性..."
    local original_md5=$(md5sum $file_path | awk '{print $1}')
    local downloaded_md5=$(md5sum $HOME/hadoop_test/test_data_download.txt | awk '{print $1}')
    
    if [ "$original_md5" = "$downloaded_md5" ]; then
        print_message "文件完整性检查通过"
    else
        print_error "文件完整性检查失败"
        return 1
    fi
    
    # 检查副本
    print_message "检查文件副本..."
    $HADOOP_HOME/bin/hdfs fsck /test/test_data.txt -files -blocks -locations
    
    print_message "HDFS性能测试通过"
}

# 测试WordCount MapReduce作业
test_mapreduce_wordcount() {
    print_section "测试MapReduce WordCount"
    
    # 确保输入目录存在
    print_message "准备MapReduce输入..."
    $HADOOP_HOME/bin/hdfs dfs -mkdir -p /test/wordcount/input
    
    # 上传测试文件
    print_message "上传测试文件..."
    $HADOOP_HOME/bin/hdfs dfs -put $HOME/hadoop_test/words.txt /test/wordcount/input/
    
    # 确保输出目录不存在
    $HADOOP_HOME/bin/hdfs dfs -rm -r -f /test/wordcount/output
    
    # 运行WordCount作业
    print_message "运行WordCount MapReduce作业..."
    local start_time=$(date +%s)
    
    $HADOOP_HOME/bin/hadoop jar $HADOOP_HOME/share/hadoop/mapreduce/hadoop-mapreduce-examples-*.jar wordcount /test/wordcount/input /test/wordcount/output
    
    local end_time=$(date +%s)
    local job_time=$((end_time - start_time))
    
    print_message "MapReduce作业完成: ${job_time}秒"
    
    # 检查作业结果
    print_message "检查MapReduce作业结果:"
    $HADOOP_HOME/bin/hdfs dfs -cat /test/wordcount/output/part-r-00000
    
    print_message "MapReduce WordCount测试通过"
}

# 测试更复杂的MapReduce作业：Pi计算
test_mapreduce_pi() {
    print_section "测试MapReduce Pi计算"
    
    # 运行Pi计算作业
    print_message "运行Pi计算MapReduce作业..."
    local start_time=$(date +%s)
    
    $HADOOP_HOME/bin/hadoop jar $HADOOP_HOME/share/hadoop/mapreduce/hadoop-mapreduce-examples-*.jar pi 10 1000
    
    local end_time=$(date +%s)
    local job_time=$((end_time - start_time))
    
    print_message "Pi计算作业完成: ${job_time}秒"
    
    print_message "MapReduce Pi计算测试通过"
}

# 测试YARN资源管理
test_yarn_resources() {
    print_section "测试YARN资源管理"
    
    # 检查YARN应用状态
    print_message "检查YARN应用状态..."
    $HADOOP_HOME/bin/yarn application -list
    
    # 检查YARN节点
    print_message "检查YARN节点状态..."
    $HADOOP_HOME/bin/yarn node -list -all
    
    # 检查YARN队列
    print_message "检查YARN队列状态..."
    $HADOOP_HOME/bin/yarn queue -status default
    
    # 启动一个分布式Shell应用
    print_message "启动分布式Shell应用..."
    local start_time=$(date +%s)
    
    # 运行一个简单的分布式shell命令
    $HADOOP_HOME/bin/yarn jar $HADOOP_HOME/share/hadoop/yarn/hadoop-yarn-applications-distributedshell-*.jar \
        -jar $HADOOP_HOME/share/hadoop/yarn/hadoop-yarn-applications-distributedshell-*.jar \
        -shell_command "hostname" \
        -num_containers $(cat $HADOOP_HOME/etc/hadoop/workers | grep -v "^#" | grep -v "^$" | wc -l) \
        -master_memory 256
    
    local end_time=$(date +%s)
    local job_time=$((end_time - start_time))
    
    print_message "分布式Shell应用完成: ${job_time}秒"
    
    print_message "YARN资源管理测试通过"
}

# 清理测试数据
clean_test_data() {
    print_section "清理测试数据"
    
    # 清理HDFS上的测试数据
    print_message "清理HDFS上的测试数据..."
    $HADOOP_HOME/bin/hdfs dfs -rm -r -f /test
    
    # 清理本地测试数据
    print_message "清理本地测试数据..."
    rm -rf $HOME/hadoop_test
    
    print_message "测试数据清理完成"
}

# 执行基础测试
run_basic_tests() {
    test_hdfs_basic
}

# 执行HDFS测试
run_hdfs_tests() {
    test_hdfs_basic
    test_hdfs_performance $TEST_SIZE
}

# 执行YARN/MapReduce测试
run_yarn_tests() {
    test_mapreduce_wordcount
    test_mapreduce_pi
    test_yarn_resources
}

# 执行所有测试
run_all_tests() {
    test_hdfs_basic
    test_hdfs_performance $TEST_SIZE
    test_mapreduce_wordcount
    test_mapreduce_pi
    test_yarn_resources
}

# 主函数
main() {
    # 默认参数
    local RUN_BASIC=false
    local RUN_HDFS=false
    local RUN_YARN=false
    local RUN_ALL=true
    local CLEAN_DATA=false
    local TEST_SIZE=10  # 10MB
    
    # 解析命令行参数
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -a|--all)
                RUN_ALL=true
                RUN_BASIC=false
                RUN_HDFS=false
                RUN_YARN=false
                shift
                ;;
            -b|--basic)
                RUN_BASIC=true
                RUN_ALL=false
                shift
                ;;
            -d|--dfs)
                RUN_HDFS=true
                RUN_ALL=false
                shift
                ;;
            -y|--yarn)
                RUN_YARN=true
                RUN_ALL=false
                shift
                ;;
            -c|--clean)
                CLEAN_DATA=true
                shift
                ;;
            -s|--size)
                TEST_SIZE="$2"
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
    
    # 创建测试数据
    create_test_data $TEST_SIZE
    
    # 执行测试
    if [ "$RUN_ALL" = true ]; then
        run_all_tests
    else
        [ "$RUN_BASIC" = true ] && run_basic_tests
        [ "$RUN_HDFS" = true ] && run_hdfs_tests
        [ "$RUN_YARN" = true ] && run_yarn_tests
    fi
    
    # 清理测试数据
    if [ "$CLEAN_DATA" = true ]; then
        clean_test_data
    else
        print_message "测试数据未清理，可以使用 '$0 -c' 清理测试数据"
    fi
    
    print_section "测试完成"
    print_message "所有测试已完成"
}

# 执行主函数
main "$@" 