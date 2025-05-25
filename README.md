# Hadoop 分布式集群配置脚本

基于 Ubuntu Server 25.04 的 Hadoop 3.4.1 多节点分布式集群配置脚本。

## 脚本简介

本项目提供了一组脚本，用于自动化部署和管理 Hadoop 分布式集群：

- `install/hadoop-cluster-setup.sh`: 主控脚本，根据参数调用其他脚本
- `install/master-setup.sh`: 主节点配置脚本
- `install/slave-setup.sh`: 从节点配置脚本
- `manage/hadoop-start.sh`: 集群启动脚本，管理集群服务的启动、停止和重启
- `manage/hadoop-check.sh`: 集群状态检查脚本，监控集群健康状况
- `test/hadoop-test.sh`: 集群功能测试脚本，验证集群功能是否正常

## 目录结构

- `install/`: 包含安装和配置脚本
- `manage/`: 包含集群管理脚本
- `test/`: 包含集群测试脚本
- `config/`: 包含配置文件
- `docs/`: 包含文档

## 使用方法

### 前提条件

- 已在 VMware 中创建多台 Ubuntu Server 25.04 虚拟机
- 虚拟机网络已配置好，可以互相访问
- 以 root 权限或 sudo 权限运行脚本

### 主节点配置

在主节点上执行：

```bash
sudo bash install/master-setup.sh --master-ip 192.168.1.100 --slave1-ip 192.168.1.101 --slave2-ip 192.168.1.102 --hostname hadoop-master --gateway 192.168.1.1
```

参数说明：
- `--master-ip`: 主节点 IP 地址
- `--slave1-ip`: 从节点1 IP 地址
- `--slave2-ip`: 从节点2 IP 地址（可选）
- `--hostname`: 主节点主机名
- `--gateway`: 网关 IP 地址

### 从节点配置

在从节点上执行：

```bash
sudo bash install/slave-setup.sh --master-ip 192.168.1.100 --hostname hadoop-slave1 --gateway 192.168.1.1
```

参数说明：
- `--master-ip`: 主节点 IP 地址
- `--hostname`: 当前从节点主机名
- `--gateway`: 网关 IP 地址

### 集群启动管理

在主节点上，以 hadoop 用户身份执行：

```bash
# 启动所有服务
bash manage/hadoop-start.sh -a

# 仅启动HDFS服务
bash manage/hadoop-start.sh -d

# 仅启动YARN服务
bash manage/hadoop-start.sh -y

# 重启HDFS服务
bash manage/hadoop-start.sh -r -d

# 停止所有服务
bash manage/hadoop-start.sh -s
```

### 集群状态检查

在主节点上，以 hadoop 用户身份执行：

```bash
# 基础检查
bash manage/hadoop-check.sh

# 完整检查
bash manage/hadoop-check.sh -f

# 详细检查HDFS
bash manage/hadoop-check.sh -d -c hdfs

# 检查特定节点
bash manage/hadoop-check.sh -n hadoop-slave1
```

### 集群功能测试

在主节点上，以 hadoop 用户身份执行：

```bash
# 执行所有测试
bash test/hadoop-test.sh

# 仅执行HDFS测试
bash test/hadoop-test.sh -d

# 执行基础测试并清理测试数据
bash test/hadoop-test.sh -b -c

# 执行所有测试，使用100MB测试数据
bash test/hadoop-test.sh -a -s 100
```

### 集群启动流程

主节点配置完成后，按照以下步骤启动集群：

1. 在主节点上，复制 SSH 公钥到从节点
   ```bash
   su - hadoop
   ssh-copy-id hadoop@hadoop-slave1
   ssh-copy-id hadoop@hadoop-slave2  # 如果有第二个从节点
   ```

2. 从主节点复制 Hadoop 到从节点
   ```bash
   su - hadoop
   scp -r ~/hadoop hadoop@hadoop-slave1:~
   scp -r ~/hadoop hadoop@hadoop-slave2:~  # 如果有第二个从节点
   ```

3. 从主节点复制配置文件到从节点
   ```bash
   su - hadoop
   scp ~/hadoop/etc/hadoop/* hadoop@hadoop-slave1:~/hadoop/etc/hadoop/
   scp ~/hadoop/etc/hadoop/* hadoop@hadoop-slave2:~/hadoop/etc/hadoop/  # 如果有第二个从节点
   ```

4. 启动 Hadoop 服务
   ```bash
   su - hadoop
   bash manage/hadoop-start.sh -a
   ```

5. 验证集群状态
   ```bash
   su - hadoop
   bash manage/hadoop-check.sh
   ```

## 配置文件说明

主要配置文件位于 `config/hadoop-config.conf`，支持的配置项包括：

- 网络配置：网络接口、DNS服务器、DNS解析修复
- Java配置：Java版本、安装方式（headless、full、manual）
- HDFS配置：NameNode和DataNode数据目录、副本因子
- YARN配置：资源管理器设置、内存配置
- 安全配置：SSH密钥类型、防火墙设置、进程优先级权限
- 集群配置：集群名称、主机名前缀

脚本会自动配置以下 Hadoop 配置文件：

- `hadoop-env.sh`: Hadoop 环境变量
- `core-site.xml`: 核心配置
- `hdfs-site.xml`: HDFS 配置
- `yarn-site.xml`: YARN 配置
- `mapred-site.xml`: MapReduce 配置
- `workers`: 从节点列表

## 故障排除

如果集群启动失败，请检查：

1. 网络连接是否正常（使用 `ping` 测试）
2. SSH 免密登录是否配置成功（使用 `ssh hadoop@hostname` 测试）
3. 查看 Hadoop 日志文件 `$HADOOP_HOME/logs/`
4. 使用 `manage/hadoop-check.sh` 脚本检查集群状态

### 常见问题解决方案

- **DNS解析问题**: 脚本提供了自动DNS修复功能，可以手动设置为Google DNS (8.8.8.8, 8.8.4.4)
- **Java兼容性问题**: Hadoop 3.4.1 需要 Java 11，脚本支持自动安装OpenJDK 11
- **进程优先级错误**: 脚本已添加 `renice` 权限配置和YARN配置修复
- **启动失败**: 确保主机名与配置一致，可通过 `hostname` 命令查看

## 注意事项

- 执行脚本前请备份重要数据
- 确保虚拟机有足够的资源（内存、磁盘空间）
- 如果只有一个从节点，可以不指定 `--slave2-ip` 参数
- 所有管理和测试脚本需要以 hadoop 用户身份运行
- 配置脚本需要以 root 用户或使用 sudo 运行
