#!/bin/bash

# Hadoop主节点配置脚本
# 基于Ubuntu Server 25.04

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

# 参数解析
parse_args() {
    while [[ "$#" -gt 0 ]]; do
        case $1 in
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
            *)
                print_error "未知选项: $1"
                exit 1
                ;;
        esac
    done

    # 检查必要参数
    if [ -z "$MASTER_IP" ] || [ -z "$SLAVE1_IP" ] || [ -z "$HOSTNAME" ] || [ -z "$GATEWAY" ]; then
        print_error "缺少必要参数: --master-ip, --slave1-ip, --hostname, --gateway"
        exit 1
    fi
}

# 配置网络
configure_network() {
    print_section "配置网络"
    
    # 备份网络配置文件
    if [ -f /etc/netplan/50-cloud-init.yaml ]; then
        cp /etc/netplan/50-cloud-init.yaml /etc/netplan/50-cloud-init.yaml.bak
        print_message "已备份原网络配置文件"
    fi
    
    # 检测网络接口
    local network_interface=$(ip link show | grep -E '^[0-9]+:' | grep -v 'lo:' | awk -F': ' '{print $2}' | head -1)
    if [ -z "$network_interface" ]; then
        print_error "无法检测到网络接口"
        exit 1
    fi
    print_message "使用网络接口: $network_interface"
    
    # 创建新的网络配置
    cat > /etc/netplan/50-cloud-init.yaml << EOF
network:
  ethernets:
    $network_interface:
      addresses: [$MASTER_IP/24]
      gateway4: $GATEWAY
      nameservers:
        addresses: [8.8.8.8, 8.8.4.4]
  version: 2
EOF
    
    print_message "已创建新的网络配置"
    
    # 应用网络配置
    netplan apply
    print_message "已应用网络配置"
    
    # 等待网络就绪
    sleep 5
    
    # 检查网络连接
    if ping -c 3 8.8.8.8 > /dev/null 2>&1; then
        print_message "网络连接正常"
    else
        print_warning "网络连接可能存在问题，请手动检查"
    fi
}

# 修复DNS解析问题
fix_dns_resolution() {
    print_section "修复DNS解析"
    
    # 检查DNS服务器
    if command -v resolvectl &> /dev/null; then
        print_message "检查DNS服务器配置"
        resolvectl status
    fi
    
    # 检查resolv.conf文件
    if grep -q "127.0.0.53" /etc/resolv.conf; then
        print_warning "发现本地DNS解析器(127.0.0.53)，尝试手动设置DNS"
        
        # 询问用户是否手动设置DNS
        read -p "是否手动设置DNS服务器? (y/n): " answer
        if [[ "$answer" =~ ^[Yy]$ ]]; then
            # 备份原resolv.conf
            cp /etc/resolv.conf /etc/resolv.conf.bak
            
            # 删除原文件
            rm /etc/resolv.conf
            
            # 设置新的DNS服务器
            echo "nameserver 8.8.8.8" > /etc/resolv.conf
            echo "nameserver 8.8.4.4" >> /etc/resolv.conf
            
            # 防止文件被覆盖
            chattr +i /etc/resolv.conf
            
            print_message "已手动设置DNS服务器为Google DNS (8.8.8.8, 8.8.4.4)"
            print_message "已防止resolv.conf被覆盖(chattr +i)"
        fi
    else
        print_message "DNS解析配置正常"
    fi
    
    # 询问是否需要更新软件源
    read -p "是否需要配置国内软件源以加速下载? (y/n): " answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        # 备份sources.list
        cp /etc/apt/sources.list /etc/apt/sources.list.bak
        
        # 设置阿里云源
        cat > /etc/apt/sources.list << EOF
deb http://mirrors.aliyun.com/ubuntu/ noble main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ noble-updates main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ noble-backports main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ noble-security main restricted universe multiverse
EOF
        
        print_message "已配置阿里云软件源"
        
        # 更新软件包列表
        apt update
        print_message "软件包列表已更新"
    fi
}

# 配置主机名
configure_hostname() {
    print_section "配置主机名"
    
    # 设置主机名
    hostnamectl set-hostname "$HOSTNAME"
    print_message "已设置主机名为: $HOSTNAME"
    
    # 配置hosts文件
    if grep -q "$MASTER_IP $HOSTNAME" /etc/hosts; then
        print_message "主机名已存在于hosts文件中"
    else
        # 备份hosts文件
        cp /etc/hosts /etc/hosts.bak
        
        # 添加集群节点信息到hosts文件
        cat >> /etc/hosts << EOF
$MASTER_IP $HOSTNAME
$SLAVE1_IP hadoop-slave1
EOF

        # 如果提供了slave2的IP，也添加
        if [ ! -z "$SLAVE2_IP" ]; then
            echo "$SLAVE2_IP hadoop-slave2" >> /etc/hosts
        fi
        
        print_message "已更新hosts文件"
    fi
}

# 安装Java
install_java() {
    print_section "安装Java"
    
    # 检查Java是否已安装
    if command -v java > /dev/null 2>&1; then
        print_message "Java已安装，版本信息:"
        java -version
    else
        print_message "Java未安装，提供两种安装方式："
        echo "1) 自动安装OpenJDK 11 (推荐)"
        echo "2) 手动安装Java (适用于离线环境)"
        read -p "请选择安装方式 [1/2]: " java_install_method
        
        case $java_install_method in
            1)
                # 更新软件包列表
                apt update
                
                # 安装OpenJDK 11 headless版本
                apt install openjdk-11-jdk-headless -y
                
                print_message "已安装OpenJDK 11 headless版本，版本信息:"
                java -version
                ;;
            2)
                print_message "请按照以下步骤手动安装Java:"
                echo "1. 下载OpenJDK 11"
                echo "   - 从GitHub、华为云或阿里云下载"
                echo "   - 对于隔离环境，可以使用Docker:"
                echo "     docker pull swr.cn-north-4.myhuaweicloud.com/ddn-k8s/docker.io/openjdk:11"
                echo "2. 通过FTP上传到服务器"
                echo "3. 解压并安装:"
                echo "   sudo mkdir -p /usr/lib/jvm"
                echo "   sudo tar -xzf your_openJdkname -C /usr/lib/jvm"
                echo "   sudo mv /usr/lib/jvm/jdk-11.0.27+6 /usr/lib/jvm/java-11-openjdk-amd64"
                echo "4. 设置环境变量:"
                echo '   echo "export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64" >> ~/.bashrc'
                echo '   echo "export PATH=\$PATH:\$JAVA_HOME/bin" >> ~/.bashrc'
                echo "   source ~/.bashrc"
                
                read -p "按Enter键继续安装过程，或按Ctrl+C退出手动安装Java..." continue
                
                # 检查Java是否已安装
                if ! command -v java > /dev/null 2>&1; then
                    print_error "未检测到Java安装，请手动安装后重新运行此脚本"
                    exit 1
                fi
                ;;
            *)
                print_error "无效的选择，退出安装"
                exit 1
                ;;
        esac
    fi
    
    # 确保JAVA_HOME设置正确
    if [ -z "$JAVA_HOME" ]; then
        # 首先尝试标准位置
        if [ -d "/usr/lib/jvm/java-11-openjdk-amd64" ]; then
            JAVA_HOME="/usr/lib/jvm/java-11-openjdk-amd64"
        else
            # 尝试从java命令路径获取
            JAVA_HOME=$(readlink -f /usr/bin/java | sed "s:/bin/java::")
        fi
        
        if [ -n "$JAVA_HOME" ]; then
            print_message "设置JAVA_HOME: $JAVA_HOME"
            echo "export JAVA_HOME=$JAVA_HOME" >> /etc/profile.d/java.sh
            echo "export PATH=\$PATH:\$JAVA_HOME/bin" >> /etc/profile.d/java.sh
            chmod +x /etc/profile.d/java.sh
            source /etc/profile.d/java.sh
        else
            print_error "无法自动设置JAVA_HOME，请手动设置"
        fi
    fi
    
    print_message "JAVA_HOME路径: $JAVA_HOME"
}

# 安装SSH服务器
install_ssh() {
    print_section "安装SSH服务器"
    
    # 检查SSH服务器是否已安装
    if systemctl is-active --quiet sshd; then
        print_message "SSH服务器已安装并运行中"
    else
        # 安装SSH服务器
        apt install openssh-server -y
        
        # 启动SSH服务
        systemctl start sshd
        systemctl enable sshd
        
        print_message "已安装并启动SSH服务器"
    fi
}

# 创建Hadoop用户
create_hadoop_user() {
    print_section "创建Hadoop用户"
    
    # 检查hadoop用户是否已存在
    if id -u hadoop > /dev/null 2>&1; then
        print_message "hadoop用户已存在"
    else
        # 创建hadoop用户
        adduser --gecos "" --disabled-password hadoop
        
        # 设置密码
        echo "hadoop:hadoop" | chpasswd
        
        # 添加到sudo组
        usermod -aG sudo hadoop
        
        print_message "已创建hadoop用户"
    fi
    
    # 配置sudo权限，允许hadoop用户不输入密码执行renice命令
    if [ ! -f /etc/sudoers.d/hadoop ]; then
        echo "hadoop ALL=(ALL) NOPASSWD: /usr/bin/renice" > /etc/sudoers.d/hadoop
        chmod 440 /etc/sudoers.d/hadoop
        print_message "已为hadoop用户配置renice权限"
    fi
}

# 配置SSH免密登录
configure_ssh_keys() {
    print_section "配置SSH免密登录"
    
    # 切换到hadoop用户
    su - hadoop << EOF
    # 检查SSH密钥是否已存在
    if [ -f ~/.ssh/id_rsa ]; then
        echo "SSH密钥已存在"
    else
        # 创建.ssh目录
        mkdir -p ~/.ssh
        chmod 700 ~/.ssh
        
        # 生成SSH密钥
        ssh-keygen -t rsa -P "" -f ~/.ssh/id_rsa
        
        # 将公钥添加到授权密钥
        cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
        chmod 600 ~/.ssh/authorized_keys
        
        echo "已生成SSH密钥"
    fi
EOF
    
    print_message "已配置SSH密钥"
    print_warning "请稍后手动运行以下命令将SSH公钥复制到从节点:"
    echo "su - hadoop"
    echo "ssh-copy-id hadoop@hadoop-slave1"
    if [ ! -z "$SLAVE2_IP" ]; then
        echo "ssh-copy-id hadoop@hadoop-slave2"
    fi
}

# 下载并安装Hadoop
download_hadoop() {
    print_section "下载并安装Hadoop"
    
    # 切换到hadoop用户
    su - hadoop << EOF
    # 检查Hadoop是否已下载
    if [ -d ~/hadoop ]; then
        echo "Hadoop目录已存在"
    else
        # Hadoop版本和下载信息
        HADOOP_VERSION="3.4.1"
        HADOOP_URL="https://dlcdn.apache.org/hadoop/common/hadoop-\${HADOOP_VERSION}/hadoop-\${HADOOP_VERSION}.tar.gz"
        HADOOP_FILE="hadoop-\${HADOOP_VERSION}.tar.gz"
        
        echo "开始下载Hadoop \${HADOOP_VERSION}..."
        
        # 下载Hadoop（带重试机制）
        local retry_count=0
        local max_retries=3
        
        while [ \$retry_count -lt \$max_retries ]; do
            if wget --timeout=30 --tries=3 "\$HADOOP_URL"; then
                echo "Hadoop下载成功"
                break
            else
                retry_count=\$((retry_count + 1))
                echo "下载失败，重试 \$retry_count/\$max_retries"
                if [ \$retry_count -eq \$max_retries ]; then
                    echo "下载失败，请检查网络连接"
                    exit 1
                fi
                sleep 5
            fi
        done
        
        # 验证文件大小（基本完整性检查）
        if [ ! -s "\$HADOOP_FILE" ]; then
            echo "下载的文件为空或不存在"
            exit 1
        fi
        
        echo "开始解压Hadoop..."
        # 解压Hadoop
        if ! tar -xzf "\$HADOOP_FILE"; then
            echo "解压失败，文件可能损坏"
            rm -f "\$HADOOP_FILE"
            exit 1
        fi
        
        # 移动到~/hadoop目录
        mv "hadoop-\${HADOOP_VERSION}" ~/hadoop
        
        # 删除压缩包
        rm "\$HADOOP_FILE"
        
        echo "已下载并安装Hadoop \${HADOOP_VERSION}"
    fi
EOF
    
    print_message "已完成Hadoop安装"
}

# 配置Hadoop环境变量
configure_hadoop_env() {
    print_section "配置Hadoop环境变量"
    
    # 切换到hadoop用户
    su - hadoop << EOF
    # 检查.bashrc中是否已有Hadoop环境变量
    if grep -q "HADOOP_HOME" ~/.bashrc; then
        echo "Hadoop环境变量已配置"
    else
        # 添加Hadoop环境变量到.bashrc
        cat >> ~/.bashrc << EOL
export HADOOP_HOME=~/hadoop
export PATH=\$PATH:\$HADOOP_HOME/bin:\$HADOOP_HOME/sbin
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
EOL
        
        # 应用环境变量
        source ~/.bashrc
        
        echo "已配置Hadoop环境变量"
    fi
EOF
    
    print_message "已配置Hadoop环境变量"
}

# 配置Hadoop
configure_hadoop() {
    print_section "配置Hadoop"
    
    # 切换到hadoop用户
    su - hadoop -c "
        # 配置JAVA_HOME
        echo 'export JAVA_HOME=$JAVA_HOME' >> ~/hadoop/etc/hadoop/hadoop-env.sh
        
        # 配置core-site.xml
        cat > ~/hadoop/etc/hadoop/core-site.xml << EOF
<configuration>
    <property>
        <name>fs.defaultFS</name>
        <value>hdfs://hadoop-master:9000</value>
    </property>
</configuration>
EOF
        
        # 配置hdfs-site.xml
        cat > ~/hadoop/etc/hadoop/hdfs-site.xml << EOF
<configuration>
    <property>
        <name>dfs.namenode.http-address</name>
        <value>hadoop-master:9870</value>
    </property>
    <property>
        <name>dfs.namenode.name.dir</name>
        <value>file:///home/hadoop/hadoopdata/hdfs/namenode</value>
    </property>
    <property>
        <name>dfs.replication</name>
        <value>2</value>
    </property>
</configuration>
EOF
        
        # 配置yarn-site.xml
        cat > ~/hadoop/etc/hadoop/yarn-site.xml << EOF
<configuration>
    <property>
        <name>yarn.resourcemanager.hostname</name>
        <value>hadoop-master</value>
    </property>
    <property>
        <name>yarn.resourcemanager.webapp.address</name>
        <value>hadoop-master:8088</value>
    </property>
    <property>
        <name>yarn.nodemanager.aux-services</name>
        <value>mapreduce_shuffle</value>
    </property>
    <property>
        <name>yarn.nodemanager.linux-container-executor.nonsecure-mode.limit-users</name>
        <value>false</value>
    </property>
</configuration>
EOF
        
        # 配置mapred-site.xml
        cat > ~/hadoop/etc/hadoop/mapred-site.xml << EOF
<configuration>
    <property>
        <name>mapreduce.framework.name</name>
        <value>yarn</value>
    </property>
</configuration>
EOF
        
        # 配置workers文件
        echo 'hadoop-slave1' > ~/hadoop/etc/hadoop/workers
        
        # 如果提供了slave2的IP，也添加到workers
        if [ ! -z \"$SLAVE2_IP\" ]; then
            echo 'hadoop-slave2' >> ~/hadoop/etc/hadoop/workers
        fi
        
        # 创建NameNode数据目录
        mkdir -p ~/hadoopdata/hdfs/namenode
    "
    
    print_message "Hadoop配置完成"
}

# 格式化HDFS
format_hdfs() {
    print_section "格式化HDFS"
    
    # 切换到hadoop用户
    su - hadoop -c "
        # 格式化HDFS
        ~/hadoop/bin/hdfs namenode -format
    "
    
    print_message "已格式化HDFS"
}

# 显示完成信息
show_completion_info() {
    print_section "配置完成"
    
    print_message "主节点配置已完成！"
    print_message "请确保所有从节点都已配置完成，然后手动执行以下步骤:"
    
    echo "1. 复制配置文件到从节点 (作为hadoop用户执行):"
    echo "   scp ~/hadoop/etc/hadoop/* hadoop@hadoop-slave1:~/hadoop/etc/hadoop/"
    if [ ! -z "$SLAVE2_IP" ]; then
        echo "   scp ~/hadoop/etc/hadoop/* hadoop@hadoop-slave2:~/hadoop/etc/hadoop/"
    fi
    
    echo "2. 启动Hadoop服务 (作为hadoop用户执行):"
    echo "   ~/hadoop/sbin/start-dfs.sh"
    echo "   ~/hadoop/sbin/start-yarn.sh"
    
    echo "3. 验证集群状态 (作为hadoop用户执行):"
    echo "   jps"
    
    echo "4. 访问Web界面:"
    echo "   NameNode: http://$HOSTNAME:9870"
    echo "   ResourceManager: http://$HOSTNAME:8088"
}

# 主函数
main() {
    # 解析命令行参数
    parse_args "$@"
    
    # 检查是否为root用户
    if [ "$EUID" -ne 0 ]; then
        print_error "请以root权限运行此脚本"
        exit 1
    fi
    
    # 执行配置步骤
    configure_network
    fix_dns_resolution
    configure_hostname
    install_java
    install_ssh
    create_hadoop_user
    configure_ssh_keys
    download_hadoop
    configure_hadoop_env
    configure_hadoop
    format_hdfs
    show_completion_info
}

# 执行主函数
main "$@"