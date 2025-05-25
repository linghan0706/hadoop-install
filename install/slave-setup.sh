#!/bin/bash

# Hadoop从节点配置脚本
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
    if [ -z "$MASTER_IP" ] || [ -z "$HOSTNAME" ] || [ -z "$GATEWAY" ]; then
        print_error "缺少必要参数: --master-ip, --hostname, --gateway"
        exit 1
    fi

    # 获取本机IP
    SLAVE_IP=$(hostname -I | awk '{print $1}')
    if [ -z "$SLAVE_IP" ]; then
        print_error "无法获取本机IP地址"
        exit 1
    fi
    print_message "本机IP地址: $SLAVE_IP"
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
      addresses: [$SLAVE_IP/24]
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
    if grep -q "$MASTER_IP hadoop-master" /etc/hosts; then
        print_message "主节点信息已存在于hosts文件中"
    else
        # 备份hosts文件
        cp /etc/hosts /etc/hosts.bak
        
        # 添加集群节点信息到hosts文件
        cat >> /etc/hosts << EOF
$MASTER_IP hadoop-master
$SLAVE_IP $HOSTNAME
EOF
        
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
    
    # 创建数据目录
    su - hadoop -c "mkdir -p ~/hadoopdata/hdfs/datanode"
    print_message "已创建Hadoop数据目录: /home/hadoop/hadoopdata/hdfs/datanode"
}

# 配置SSH免密登录
configure_ssh_keys() {
    print_section "配置SSH免密登录"
    
    # 切换到hadoop用户
    su - hadoop << EOF
    # 创建.ssh目录
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    touch ~/.ssh/authorized_keys
    chmod 600 ~/.ssh/authorized_keys
    
    echo "已配置SSH目录"
EOF
    
    print_message "已配置SSH目录"
    print_warning "请在主节点上运行ssh-copy-id命令，将主节点的SSH公钥复制到此节点"
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

# 显示完成信息
show_completion_info() {
    print_section "配置完成"
    
    print_message "从节点 $HOSTNAME 配置已完成！"
    print_message "请在主节点上继续完成以下步骤:"
    
    echo "1. 向此节点复制SSH公钥 (在主节点上执行):"
    echo "   su - hadoop"
    echo "   ssh-copy-id hadoop@$HOSTNAME"
    
    echo "2. 从主节点复制Hadoop到此节点 (在主节点上执行):"
    echo "   su - hadoop"
    echo "   scp -r ~/hadoop hadoop@$HOSTNAME:~"
    
    echo "3. 从主节点复制配置文件到此节点 (在主节点上执行):"
    echo "   su - hadoop"
    echo "   scp ~/hadoop/etc/hadoop/* hadoop@$HOSTNAME:~/hadoop/etc/hadoop/"
    
    echo "4. 在此节点上配置hdfs-site.xml (在此节点上执行):"
    echo "   su - hadoop"
    echo "   cat > ~/hadoop/etc/hadoop/hdfs-site.xml << EOL"
    echo "<configuration>"
    echo "    <property>"
    echo "        <name>dfs.datanode.data.dir</name>"
    echo "        <value>file:///home/hadoop/hadoopdata/hdfs/datanode</value>"
    echo "    </property>"
    echo "    <property>"
    echo "        <name>dfs.replication</name>"
    echo "        <value>2</value>"
    echo "    </property>"
    echo "</configuration>"
    echo "   EOL"
}

# 主函数
main() {
    parse_args "$@"
    show_banner
    check_root
    install_dependencies
    configure_network
    fix_dns_resolution
    configure_hostname
    install_java
    install_ssh
    create_hadoop_user
    configure_ssh_keys
    configure_hadoop_env
    show_completion_info
}

# 执行主函数
main "$@"