# Oracle Client C++ and Objective-C Test Programs

This project contains two simple applications to test connectivity to an Oracle database and measure the latency of basic database operations.
*   A C++ application using the Oracle C++ Call Interface (OCCI).
*   An Objective-C application using the Oracle Call Interface (OCI).

They are designed to work on macOS (x86_64) and Linux with the Oracle Instant Client.

## Prerequisites

1.  **Oracle Instant Client:** Download and install the Oracle Instant Client and the Instant Client SDK for your platform (macOS/Linux).
    *   [Oracle Instant Client Downloads](https://www.oracle.com/database/technologies/instant-client/downloads.html)

2.  **Environment Variables:** Set the `ORACLE_HOME` environment variable to the path where you installed the Instant Client. This is crucial for the `Makefile` to find the necessary headers and libraries.

    For example, if you unzipped the client to `/opt/oracle/instantclient_19_8`, you would set it as follows:

    ```bash
    export ORACLE_HOME=/opt/oracle/instantclient_19_8
    ```

    On Linux, you also need to set `LD_LIBRARY_PATH`:
    ```bash
    export LD_LIBRARY_PATH=$ORACLE_HOME:$LD_LIBRARY_PATH
    ```
    On macOS, you might need to set `DYLD_LIBRARY_PATH`:
    ```bash
    export DYLD_LIBRARY_PATH=$ORACLE_HOME:$DYLD_LIBRARY_PATH
    ```


## Build

To build both the C++ and Objective-C programs, run `make` in the project's root directory:

```bash
make
```

This will compile the C++ and Objective-C sources and create two executables:
*   `build/oracle_test` (C++)
*   `build/oracle_test_objc` (Objective-C)

To build only one of the versions, you can specify the target:
*   C++ only: `make build/oracle_test`
*   Objective-C only: `make build/oracle_test_objc`

To clean the build artifacts, you can run:
```bash
make clean
```

## Usage

### C++ Version

Run the C++ executable with your database credentials and connection string:

```bash
./build/oracle_test <username> <password> <connect_string>
```

*   `<username>`: Your database username.
*   `<password>`: Your database password.
*   `<connect_string>`: The Oracle connection string (e.g., `//your-db-host:1521/your-service-name`).

#### Example
```bash
./build/oracle_test myuser mypassword //db.example.com:1521/ORCL
```

### Objective-C Version

Run the Objective-C executable with your database credentials and connection string:

```bash
./build/oracle_test_objc <username> <password> <connect_string>
```

*   `<username>`: Your database username.
*   `<password>`: Your database password.
*   `<connect_string>`: The Oracle connection string (e.g., `//your-db-host:1521/your-service-name`).

#### Example
```bash
./build/oracle_test_objc myuser mypassword //db.example.com:1521/ORCL
```

### Environment Setup on macOS

To run this application, you need to configure several environment variables and potentially a `sqlnet.ora` file.

**1. Set Environment Variables**

You need to set the following environment variables in your shell profile (e.g., `~/.zshrc`, `~/.bash_profile`):

-   `ORACLE_HOME`: This should point to your Oracle Instant Client directory.
    ```bash
    export ORACLE_HOME=/path/to/your/instantclient_19_8
    ```

-   `TNS_ADMIN`: This should point to the directory where your Oracle configuration files (`tnsnames.ora`, `sqlnet.ora`) are located. It's common to place these inside your `ORACLE_HOME` directory.
    ```bash
    export TNS_ADMIN=$ORACLE_HOME/network/admin
    ```
    Ensure this directory exists. You might need to create it: `mkdir -p $ORACLE_HOME/network/admin`.

-   `DYLD_LIBRARY_PATH`: On macOS, this variable must include the Oracle Instant Client directory so that the dynamic linker can find the OCI libraries.
    ```bash
    export DYLD_LIBRARY_PATH=$ORACLE_HOME:$DYLD_LIBRARY_PATH
    ```

**2. Configure `sqlnet.ora`**

For optimal performance and to avoid potential connection issues, it is recommended to add the following parameters to a `sqlnet.ora` file located in your `$TNS_ADMIN` directory.

Create or edit the file at `$TNS_ADMIN/sqlnet.ora` and add the following lines:

```
TCP.NODELAY=YES
DISABLE_OOB=ON
```

This will ensure that `TCP.NODELAY` and `DISABLE_OOB` are applied to all connections made from this client setup.