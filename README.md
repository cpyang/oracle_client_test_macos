# Oracle Client C++ Test Program

This program is a simple C++ application to test connectivity to an Oracle database and measure the latency of basic database operations. It uses the Oracle C++ Call Interface (OCCI) and is designed to work on macOS (x86_64) and Linux with the Oracle Instant Client.

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

To build the program, simply run `make` in the project's root directory:

```bash
make
```

This will compile the C++ source and create an executable at `build/oracle_test`.

To clean the build artifacts, you can run:
```bash
make clean
```

## Usage

Run the executable with your database credentials and connection string:

```bash
./build/oracle_test <username> <password> <connect_string>
```

*   `<username>`: Your database username.
*   `<password>`: Your database password.
*   `<connect_string>`: The Oracle connection string (e.g., `//your-db-host:1521/your-service-name`).

### Example
```bash
./build/oracle_test myuser mypassword //db.example.com:1521/ORCL
```

