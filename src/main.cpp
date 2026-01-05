#include <iostream>
#include <string>
#include <chrono>
#include <occi.h>

using namespace oracle::occi;

// Function to measure and print latency
template<typename F>
void measure_latency(const std::string& step_name, F&& func) {
    auto start = std::chrono::high_resolution_clock::now();
    func();
    auto end = std::chrono::high_resolution_clock::now();
    std::chrono::duration<double, std::milli> duration = end - start;
    std::cout << "Latency for " << step_name << ": " << duration.count() << " ms" << std::endl;
}

void run_query_on_connection(Connection *conn, const std::string& sql) {
    try {
        Statement *stmt = conn->createStatement(sql);
        ResultSet *rs = stmt->executeQuery();
        while (rs->next()) {
            // In a real app, you'd process the result. Here we just fetch.
        }
        stmt->closeResultSet(rs);
        conn->terminateStatement(stmt);
    } catch (SQLException &ex) {
        std::cerr << "Error during query execution: " << ex.getMessage() << std::endl;
    }
}

void create_connection_func(Environment *env, Connection **conn_out, const std::string& user, const std::string& pass, const std::string& db) {
    try {
        *conn_out = env->createConnection(user, pass, db);
    } catch (SQLException &ex) {
        std::cerr << "Error connecting: " << ex.getMessage() << std::endl;
        exit(1);
    }
}

void terminate_connection_func(Environment *env, Connection *conn) {
    if (conn) {
        try {
            env->terminateConnection(conn);
        } catch (SQLException &ex) {
            std::cerr << "Error terminating connection: " << ex.getMessage() << std::endl;
        }
    }
}

int main(int argc, char* argv[]) {
    if (argc != 4) {
        std::cerr << "Usage: " << argv[0] << " <username> <password> <connect_string>" << std::endl;
        return 1;
    }

    std::string username = argv[1];
    std::string password = argv[2];
    std::string connect_string_base = argv[3];
    std::string sql = "SELECT 'Hello World!' FROM DUAL";

    // Add parameters to the connection string
    std::string connect_string = connect_string_base;
    std::string params_to_add = "(TCP.NODELAY=YES)(DISABLE_OOB=ON)";
    size_t description_pos = connect_string.find("(DESCRIPTION=");
    if (description_pos != std::string::npos) {
        connect_string.insert(description_pos + strlen("(DESCRIPTION="), params_to_add);
    }

    std::cout << "Oracle Client Test Program" << std::endl;
    std::cout << "--------------------------" << std::endl;

    Environment *env = Environment::createEnvironment(Environment::DEFAULT);

    // --- Non-Pooled Connection Test ---
    std::cout << "\n--- Running Non-Pooled Connection Test (5 iterations) ---\n" << std::endl;
    for (int i = 0; i < 5; ++i) {
        std::cout << "Iteration " << i + 1 << std::endl;
        Connection *conn = nullptr;
        measure_latency("Create Connection", [&]() {
            create_connection_func(env, &conn, username, password, connect_string);
        });

        if (conn) {
            measure_latency("Execute SQL", [&]() { run_query_on_connection(conn, sql); });
            measure_latency("Terminate Connection", [&]() {
                terminate_connection_func(env, conn);
            });
        }
        std::cout << std::endl;
    }

    // --- Pooled Connection Test ---
    std::cout << "\n--- Running Pooled Connection Test (5 iterations) ---\n" << std::endl;
    StatelessConnectionPool *pool = nullptr;
    try {
        // min, max, incr
        pool = env->createStatelessConnectionPool(username, password, connect_string, 2, 10, 2);
        std::cout << "Connection pool created." << std::endl;
    } catch (SQLException &ex) {
        std::cerr << "Error creating connection pool: " << ex.getMessage() << std::endl;
        Environment::terminateEnvironment(env);
        return 1;
    }
    
    for (int i = 0; i < 5; ++i) {
        std::cout << "Iteration " << i + 1 << std::endl;
        Connection *conn = nullptr;
        measure_latency("Get Connection from Pool", [&]() {
            try {
                conn = pool->getConnection();
            } catch (SQLException &ex) {
                std::cerr << "Error getting connection from pool: " << ex.getMessage() << std::endl;
            }
        });

        if (conn) {
            measure_latency("Execute SQL", [&]() { run_query_on_connection(conn, sql); });
            measure_latency("Release Connection to Pool", [&]() {
                try {
                    pool->releaseConnection(conn);
                } catch (SQLException &ex) {
                    std::cerr << "Error releasing connection: " << ex.getMessage() << std::endl;
                }
            });
        }
        std::cout << std::endl;
    }

    // --- Cleanup ---
    std::cout << "--- Test Complete. Cleaning up. ---\n" << std::endl;
    try {
        env->terminateStatelessConnectionPool(pool);
        std::cout << "Connection pool terminated." << std::endl;
    } catch (SQLException &ex) {
        std::cerr << "Error terminating pool: " << ex.getMessage() << std::endl;
    }
    
    Environment::terminateEnvironment(env);
    std::cout << "Environment terminated." << std::endl;

    return 0;
}