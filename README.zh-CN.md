# Oracle 客户端 C++ 和 Objective-C 测试程序

该项目包含两个简单的应用程序，用于测试与 Oracle 数据库的连接并测量基本数据库操作的延迟。
*   一个使用 Oracle C++ Call Interface (OCCI) 的 C++ 应用程序。
*   一个使用 Oracle Call Interface (OCI) 的 Objective-C 应用程序。

它们设计用于在 macOS (x86_64) 和 Linux 上与 Oracle Instant Client 一起使用。

## 先决条件

1.  **Oracle Instant Client:** 为您的平台（macOS/Linux）下载并安装 Oracle Instant Client 和 Instant Client SDK。
    *   [Oracle Instant Client 下载](https://www.oracle.com/database/technologies/instant-client/downloads.html)

2.  **环境变量:** 将 `ORACLE_HOME` 环境变量设置为您安装 Instant Client 的路径。这对于 `Makefile` 找到必要的头文件和库至关重要。

    例如，如果您将客户端解压缩到 `/opt/oracle/instantclient_19_8`，则应如下设置：

    ```bash
    export ORACLE_HOME=/opt/oracle/instantclient_19_8
    ```

    在 Linux 上，您还需要设置 `LD_LIBRARY_PATH`：
    ```bash
    export LD_LIBRARY_PATH=$ORACLE_HOME:$LD_LIBRARY_PATH
    ```
    在 macOS 上，您可能需要设置 `DYLD_LIBRARY_PATH`：
    ```bash
    export DYLD_LIBRARY_PATH=$ORACLE_HOME:$DYLD_LIBRARY_PATH
    ```


## 构建

要在项目根目录中构建 C++ 和 Objective-C 程序，请运行 `make`：

```bash
make
```

这将编译 C++ 和 Objective-C 源文件，并创建两个可执行文件：
*   `build/oracle_test` (C++)
*   `build/oracle_test_objc` (Objective-C)

如果只想构建其中一个版本，可以指定目标：
*   仅 C++: `make build/oracle_test`
*   仅 Objective-C: `make build/oracle_test_objc`

要清除构建产物，可以运行：
```bash
make clean
```

## 用法

### C++ 版本

使用您的数据库凭据和连接字符串运行 C++ 可执行文件：

```bash
./build/oracle_test <username> <password> <connect_string>
```

*   `<username>`: 您的数据库用户名。
*   `<password>`: 您的数据库密码。
*   `<connect_string>`: Oracle 连接字符串（例如 `//your-db-host:1521/your-service-name`）。

#### 示例
```bash
./build/oracle_test myuser mypassword //db.example.com:1521/ORCL
```

### Objective-C 版本

使用您的数据库凭据和连接字符串运行 Objective-C 可执行文件：

```bash
./build/oracle_test_objc <username> <password> <connect_string>
```

*   `<username>`: 您的数据库用户名。
*   `<password>`: 您的数据库密码。
*   `<connect_string>`: Oracle 连接字符串（例如 `//your-db-host:1521/your-service-name`）。

#### 示例
```bash
./build/oracle_test_objc myuser mypassword //db.example.com:1521/ORCL
```

### 在 macOS 上设置环境

要运行此应用程序，您需要配置几个环境变量和一个 `sqlnet.ora` 文件。

**1. 设置环境变量**

您需要在您的 shell 配置文件（例如 `~/.zshrc`、`~/.bash_profile`）中设置以下环境变量：

-   `ORACLE_HOME`: 这应该指向您的 Oracle Instant Client 目录。
    ```bash
    export ORACLE_HOME=/path/to/your/instantclient_19_8
    ```

-   `TNS_ADMIN`: 这应该指向您的 Oracle 配置文件（`tnsnames.ora`、`sqlnet.ora`）所在的目录。通常将这些文件放在 `ORACLE_HOME` 目录中。
    ```bash
    export TNS_ADMIN=$ORACLE_HOME/network/admin
    ```
    请确保此目录存在。您可能需要创建它：`mkdir -p $ORACLE_HOME/network/admin`。

-   `DYLD_LIBRARY_PATH`: 在 macOS 上，此变量必须包含 Oracle Instant Client 目录，以便动态链接器可以找到 OCI 库。
    ```bash
    export DYLD_LIBRARY_PATH=$ORACLE_HOME:$DYLD_LIBRARY_PATH
    ```

**2. 配置 `sqlnet.ora`**

为获得最佳性能并避免潜在的连接问题，建议将以下参数添加到位于 `$TNS_ADMIN` 目录中的 `sqlnet.ora` 文件中。

创建或编辑 `$TNS_ADMIN/sqlnet.ora` 文件，并添加以下行：

```
TCP.NODELAY=YES
DISABLE_OOB=ON
```

这将确保 `TCP.NODELAY` 和 `DISABLE_OOB` 应用于从此客户端设置进行的所有连接。
