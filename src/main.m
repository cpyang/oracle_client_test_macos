#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <oci.h>

// OCI Handles
OCIEnv *envhp;
OCIServer *srvhp;
OCIError *errhp;
OCISvcCtx *svchp;
OCIStmt *stmthp;
OCIDefine *defnp = NULL;

// Function to measure and print latency
void measure_latency(const char* step_name, void (*func)()) {
    struct timespec start, end;
    clock_gettime(CLOCK_MONOTONIC, &start);
    func();
    clock_gettime(CLOCK_MONOTONIC, &end);
    double duration = (end.tv_sec - start.tv_sec) * 1000.0 + (end.tv_nsec - start.tv_nsec) / 1000000.0;
    printf("Latency for %s: %f ms\n", step_name, duration);
}

void checkerr(OCIError *errhp, sword status) {
    text errbuf[512];
    sb4 errcode = 0;

    switch (status) {
        case OCI_SUCCESS:
            break;
        case OCI_SUCCESS_WITH_INFO:
            OCIErrorGet(errhp, 1, NULL, &errcode, errbuf, sizeof(errbuf), OCI_HTYPE_ERROR);
            printf("Error - OCI_SUCCESS_WITH_INFO - %s\n", errbuf);
            break;
        case OCI_NEED_DATA:
            printf("Error - OCI_NEED_DATA\n");
            break;
        case OCI_NO_DATA:
            printf("Error - OCI_NO_DATA\n");
            break;
        case OCI_ERROR:
            OCIErrorGet(errhp, 1, NULL, &errcode, errbuf, sizeof(errbuf), OCI_HTYPE_ERROR);
            printf("Error - %s\n", errbuf);
            exit(1);
        case OCI_INVALID_HANDLE:
            printf("Error - OCI_INVALID_HANDLE\n");
            exit(1);
        case OCI_STILL_EXECUTING:
            printf("Error - OCI_STILL_EXECUTING\n");
            break;
        case OCI_CONTINUE:
            printf("Error - OCI_CONTINUE\n");
            break;
        default:
            break;
    }
}

// Global variables to hold data for the functions
const char* g_user;
const char* g_pass;
const char* g_db;
const char* g_sql;

void do_create_connection() {
    checkerr(errhp, OCILogon(envhp, errhp, &svchp, (text*)g_user, strlen(g_user), (text*)g_pass, strlen(g_pass), (text*)g_db, strlen(g_db)));
    printf("Connection successful.\n");
}

void do_prepare_statement() {
    checkerr(errhp, OCIStmtPrepare(stmthp, errhp, (text*)g_sql, (ub4)strlen(g_sql), (ub4)OCI_NTV_SYNTAX, (ub4)OCI_DEFAULT));
    printf("Statement prepared.\n");
}

void do_execute_sql() {
    checkerr(errhp, OCIStmtExecute(svchp, stmthp, errhp, (ub4)0, (ub4)0, NULL, NULL, OCI_DEFAULT));
    printf("SQL executed.\n");
}

void do_get_result_set() {
    char result[100];
    checkerr(errhp, OCIDefineByPos(stmthp, &defnp, errhp, 1, (dvoid *)result, 100, SQLT_STR, (dvoid *)0, (ub2 *)0, (ub2 *)0, OCI_DEFAULT));
    
    sword status = OCIStmtFetch2(stmthp, errhp, 1, OCI_FETCH_NEXT, 0, OCI_DEFAULT);
    if (status == OCI_SUCCESS || status == OCI_SUCCESS_WITH_INFO) {
        printf("Result: %s\n", result);
    }
    printf("Result set fetched.\n");
}

void do_terminate_connection() {
    if (svchp) OCILogoff(svchp, errhp);
    printf("Connection terminated and resources released.\n");
}


void init_oci() {
    OCIEnvCreate(&envhp, OCI_DEFAULT, NULL, NULL, NULL, NULL, 0, NULL);
    OCIHandleAlloc(envhp, (dvoid **)&errhp, OCI_HTYPE_ERROR, 0, NULL);
    OCIHandleAlloc(envhp, (dvoid **)&srvhp, OCI_HTYPE_SERVER, 0, NULL);
    OCIHandleAlloc(envhp, (dvoid **)&svchp, OCI_HTYPE_SVCCTX, 0, NULL);
    OCIHandleAlloc(envhp, (dvoid **)&stmthp, OCI_HTYPE_STMT, 0, NULL);
}

void cleanup_oci() {
    if (stmthp) OCIHandleFree(stmthp, OCI_HTYPE_STMT);
    if (svchp) OCIHandleFree(svchp, OCI_HTYPE_SVCCTX);
    if (srvhp) OCIHandleFree(srvhp, OCI_HTYPE_SERVER);
    if (errhp) OCIHandleFree(errhp, OCI_HTYPE_ERROR);
    if (envhp) OCIHandleFree(envhp, OCI_HTYPE_ENV);
}

int main(int argc, const char * argv[]) {
    if (argc != 4) {
        fprintf(stderr, "Usage: %s <username> <password> <connect_string>\n", argv[0]);
        return 1;
    }

    g_user = argv[1];
    g_pass = argv[2];
    g_db = argv[3];
    g_sql = "SELECT 'Hello World!' FROM DUAL";

    printf("Oracle Client Test Program (Objective-C)\n");

    init_oci();

    measure_latency("Create Connection", do_create_connection);
    measure_latency("Prepare Statement", do_prepare_statement);
    measure_latency("Execute SQL", do_execute_sql);
    measure_latency("Get Result Set", do_get_result_set);
    measure_latency("Terminate Connection", do_terminate_connection);
    
    cleanup_oci();

    return 0;
}
