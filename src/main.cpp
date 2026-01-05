#include <iostream>
#include <string>
#include <chrono>
#include <occi.h>

using namespace oracle::occi;

// Global OCCI objects
Environment *env;
Connection *conn;
Statement *stmt;
ResultSet *rs;

// Function to measure and print latency
template<typename F>
void measure_latency(const std::string& step_name, F&& func) {
    auto start = std::chrono::high_resolution_clock::now();
    func();
    auto end = std::chrono::high_resolution_clock::now();
    std::chrono::duration<double, std::milli> duration = end - start;
    std::cout << "Latency for " << step_name << ": " << duration.count() << " ms" << std::endl;
}

void create_connection(const std::string& user, const std::string& pass, const std::string& db) {
    try {
        conn = env->createConnection(user, pass, db);
        std::cout << "Connection successful." << std::endl;
    } catch (SQLException &ex) {
        std::cerr << "Error connecting: " << ex.getMessage() << std::endl;
        exit(1);
    }
}

void prepare_statement(const std::string& sql) {
    try {
        stmt = conn->createStatement(sql);
        std::cout << "Statement prepared." << std::endl;
    } catch (SQLException &ex) {
        std::cerr << "Error preparing statement: " << ex.getMessage() << std::endl;
        exit(1);
    }
}

void execute_sql() {
    try {
        rs = stmt->executeQuery();
        std::cout << "SQL executed." << std::endl;
    } catch (SQLException &ex) {
        std::cerr << "Error executing SQL: " << ex.getMessage() << std::endl;
        exit(1);
    }
}

void get_result_set() {
    try {
        while (rs->next()) {
            std::cout << "Result: " << rs->getString(1) << std::endl;
        }
        std::cout << "Result set fetched." << std::endl;
    } catch (SQLException &ex) {
        std::cerr << "Error fetching result set: " << ex.getMessage() << std::endl;
        exit(1);
    }
}

void terminate_connection() {
    if (rs) {
        stmt->closeResultSet(rs);
    }
    if (stmt) {
        conn->terminateStatement(stmt);
    }
    if (conn) {
        env->terminateConnection(conn);
    }
    std::cout << "Connection terminated and resources released." << std::endl;
}

int main(int argc, char* argv[]) {
    if (argc != 4) {
        std::cerr << "Usage: " << argv[0] << " <username> <password> <connect_string>" << std::endl;
        return 1;
    }

    std::string username = argv[1];
    std::string password = argv[2];
    std::string connect_string = argv[3];
    std::string sql = "SELECT 'Hello World!' FROM DUAL";

    std::cout << "Oracle Client Test Program" << std::endl;

    env = Environment::createEnvironment(Environment::DEFAULT);

    measure_latency("Create Connection", [&](){ create_connection(username, password, connect_string); });
    measure_latency("Prepare Statement", [&](){ prepare_statement(sql); });
    measure_latency("Execute SQL", execute_sql);
    measure_latency("Get Result Set", get_result_set);
    
    terminate_connection();

    Environment::terminateEnvironment(env);

    return 0;
}
