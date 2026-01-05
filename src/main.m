#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <oci.h>

// Global context for wrapper functions
OCIEnv *g_envhp = NULL;
OCIError *g_errhp = NULL;
OCISvcCtx *g_svchp = NULL; // For non-pooled connection
const char* g_username = NULL;
const char* g_password = NULL;
const char* g_connect_string = NULL;
const char* g_sql = "SELECT 'Hello World!' FROM DUAL";

OCISPool *g_poolhp = NULL; // Corrected type from OCISessionPool to OCISPool
OCIAuthInfo *g_authp = NULL;
OCISvcCtx *g_pooled_svchp = NULL; // For pooled connection

// Function to measure and print latency
void measure_latency(const char* step_name, void (*func)()) {
    struct timespec start, end;
    clock_gettime(CLOCK_MONOTONIC, &start);
    func();
    clock_gettime(CLOCK_MONOTONIC, &end);
    double duration = (end.tv_sec - start.tv_sec) * 1000.0 + (end.tv_nsec - start.tv_nsec) / 1000000.0;
    printf("Latency for %s: %f ms\n", step_name, duration);
}

void checkerr(OCIError *errhp, sword status, const char* action) {
    text errbuf[512];
    sb4 errcode = 0;

    switch (status) {
        case OCI_SUCCESS:
            break;
        case OCI_SUCCESS_WITH_INFO:
            OCIErrorGet(errhp, 1, NULL, &errcode, errbuf, sizeof(errbuf), OCI_HTYPE_ERROR);
            fprintf(stderr, "Error - OCI_SUCCESS_WITH_INFO during %s: %s\n", action, errbuf);
            break;
        case OCI_ERROR:
            OCIErrorGet(errhp, 1, NULL, &errcode, errbuf, sizeof(errbuf), OCI_HTYPE_ERROR);
            fprintf(stderr, "Error during %s: %s\n", action, errbuf);
            exit(1);
        default:
            break;
    }
}

void run_query_on_svcctx(OCIEnv *envhp, OCIError *errhp, OCISvcCtx *svchp, const char* sql) {
    OCIStmt *stmthp = NULL;
    OCIDefine *defnp = NULL;
    char result[100];

    checkerr(errhp, OCIHandleAlloc(envhp, (dvoid **)&stmthp, OCI_HTYPE_STMT, 0, NULL), "statement handle alloc");
    checkerr(errhp, OCIStmtPrepare(stmthp, errhp, (text*)sql, (ub4)strlen(sql), (ub4)OCI_NTV_SYNTAX, (ub4)OCI_DEFAULT), "statement prepare");
    checkerr(errhp, OCIStmtExecute(svchp, stmthp, errhp, (ub4)0, (ub4)0, NULL, NULL, OCI_DEFAULT), "statement execute");
    checkerr(errhp, OCIDefineByPos(stmthp, &defnp, errhp, 1, (dvoid *)result, 100, SQLT_STR, (dvoid *)0, (ub2 *)0, (ub2 *)0, OCI_DEFAULT), "define by pos");
    
    sword status = OCIStmtFetch2(stmthp, errhp, 1, OCI_FETCH_NEXT, 0, OCI_DEFAULT);
    if (status == OCI_SUCCESS || status == OCI_SUCCESS_WITH_INFO) {
        // printf("Result: %s\n", result); // Suppress for performance test
    }
    OCIHandleFree(stmthp, OCI_HTYPE_STMT);
}

// Wrapper functions for non-pooled test
void wrapper_create_connection() {
    checkerr(g_errhp, OCILogon(g_envhp, g_errhp, &g_svchp, (text*)g_username, (ub4)strlen(g_username), (text*)g_password, (ub4)strlen(g_password), (text*)g_connect_string, (ub4)strlen(g_connect_string)), "logon");
}

void wrapper_execute_sql_non_pooled() {
    run_query_on_svcctx(g_envhp, g_errhp, g_svchp, g_sql);
}

void wrapper_terminate_connection() {
    checkerr(g_errhp, OCILogoff(g_svchp, g_errhp), "logoff");
}

// Wrapper functions for pooled test
void wrapper_create_session_pool() {
    sb4 oci_status = 0; // Local status variable
    checkerr(g_errhp, OCISessionPoolCreate(g_envhp, g_errhp, &g_poolhp, 
                                        (text*)g_username, (ub4)strlen(g_username), 
                                        (text*)g_password, (ub4)strlen(g_password), 
                                        (text*)g_connect_string, (ub4)strlen(g_connect_string), 
                                        NULL, 0, // session tag, tag len
                                        OCI_DEFAULT, // mode
                                        NULL, 0, // poolParams, poolParamsLen
                                        NULL, 0, // options, optionsLen
                                        &oci_status), "session pool create"); // Pass address of local status variable
}

void wrapper_get_session_from_pool() {
    sb4 oci_status = 0; // Local status variable
    checkerr(g_errhp, OCISessionGet(g_envhp, g_errhp, &g_pooled_svchp, g_authp, 
                                    (text*)g_connect_string, (ub4)strlen(g_connect_string), 
                                    NULL, 0, // session tag, tag len
                                    NULL, // sessionhp
                                    0, // sessionhpLen
                                    OCI_DEFAULT, // mode
                                    &oci_status), "session get from pool"); // Pass address of local status variable
}

void wrapper_execute_sql_pooled() {
    run_query_on_svcctx(g_envhp, g_errhp, g_pooled_svchp, g_sql);
}

void wrapper_release_session_to_pool() {
    sb4 oci_status = 0; // Local status variable
    checkerr(g_errhp, OCISessionRelease(g_pooled_svchp, g_errhp, 
                                        NULL, 0, // tag, tagLen
                                        &oci_status), "session release to pool"); // Pass address of local status variable
}

void wrapper_terminate_session_pool() {
    sb4 oci_status = 0; // Local status variable
    checkerr(g_errhp, OCISessionPoolDestroy(g_poolhp, g_errhp, &oci_status), "session pool destroy"); // Pass address of local status variable
}


int main(int argc, const char * argv[]) {
    if (argc != 4) {
        fprintf(stderr, "Usage: %s <username> <password> <connect_string>\n", argv[0]);
        return 1;
    }

    g_username = argv[1];
    g_password = argv[2];
    const char* connect_string_arg = argv[3];
    
    // Add parameters to the connection string
    char* final_connect_string = (char*)malloc(strlen(connect_string_arg) + strlen("(TCP.NODELAY=YES)(DISABLE_OOB=ON)") + strlen("(DESCRIPTION=)") + 1); // Sufficient size for params
    strcpy(final_connect_string, connect_string_arg);
    const char* params_to_add = "(TCP.NODELAY=YES)(DISABLE_OOB=ON)";
    char* description_pos = strstr(final_connect_string, "(DESCRIPTION=");
    if (description_pos != NULL) {
        // Shift existing content to make space for params_to_add
        char* temp_suffix = (char*)malloc(strlen(description_pos + strlen("(DESCRIPTION=")) + 1);
        strcpy(temp_suffix, description_pos + strlen("(DESCRIPTION="));
        memmove(description_pos + strlen("(DESCRIPTION=") + strlen(params_to_add), description_pos + strlen("(DESCRIPTION="), strlen(temp_suffix) + 1);
        memcpy(description_pos + strlen("(DESCRIPTION="), params_to_add, strlen(params_to_add));
        free(temp_suffix);
    } else {
        // If (DESCRIPTION= is not found, prepend to connect string
        char* original_connect_string = (char*)malloc(strlen(final_connect_string) + 1);
        strcpy(original_connect_string, final_connect_string);
        free(final_connect_string);
        final_connect_string = (char*)malloc(strlen(original_connect_string) + strlen(params_to_add) + strlen("(DESCRIPTION=)") + 1);
        strcpy(final_connect_string, "(DESCRIPTION=");
        strcat(final_connect_string, params_to_add);
        strcat(final_connect_string, original_connect_string);
        free(original_connect_string);
    }
    g_connect_string = final_connect_string;

    printf("Oracle Client Test Program (Objective-C)\n");
    printf("----------------------------------------\n");

    checkerr(g_errhp, OCIEnvCreate(&g_envhp, OCI_DEFAULT, NULL, NULL, NULL, NULL, 0, NULL), "environment create");
    checkerr(g_errhp, OCIHandleAlloc(g_envhp, (dvoid **)&g_errhp, OCI_HTYPE_ERROR, 0, NULL), "error handle alloc");
    // No need to allocate srvhp for direct connection/session pool

    // --- Non-Pooled Connection Test ---
    printf("\n--- Running Non-Pooled Connection Test (5 iterations) ---\n\n");
    for (int i = 0; i < 5; ++i) {
        printf("Iteration %d\n", i + 1);
        measure_latency("Create Connection", wrapper_create_connection);
        
        if (g_svchp) {
            measure_latency("Execute SQL", wrapper_execute_sql_non_pooled);
            measure_latency("Terminate Connection", wrapper_terminate_connection);
            OCIHandleFree(g_svchp, OCI_HTYPE_SVCCTX); // Free service context handle
            g_svchp = NULL;
        }
        printf("\n");
    }

    // --- Pooled Connection Test ---
    printf("\n--- Running Pooled Connection Test (5 iterations) ---\n\n");
    
    // Allocate AuthInfo handle
    checkerr(g_errhp, OCIHandleAlloc(g_envhp, (dvoid **)&g_authp, OCI_HTYPE_AUTHINFO, 0, NULL), "authinfo handle alloc");
    checkerr(g_errhp, OCIAttrSet(g_authp, OCI_HTYPE_AUTHINFO, (dvoid *)g_username, (ub4)strlen(g_username), OCI_ATTR_USERNAME, g_errhp), "set username");
    checkerr(g_errhp, OCIAttrSet(g_authp, OCI_HTYPE_AUTHINFO, (dvoid *)g_password, (ub4)strlen(g_password), OCI_ATTR_PASSWORD, g_errhp), "set password");

    // Create Session Pool
    measure_latency("Create Session Pool", wrapper_create_session_pool);
    printf("Session pool created.\n");

    for (int i = 0; i < 5; ++i) {
        printf("Iteration %d\n", i + 1);
        measure_latency("Get Session from Pool", wrapper_get_session_from_pool);

        if (g_pooled_svchp) {
            measure_latency("Execute SQL", wrapper_execute_sql_pooled);
            measure_latency("Release Session to Pool", wrapper_release_session_to_pool);
            OCIHandleFree(g_pooled_svchp, OCI_HTYPE_SVCCTX); // Free service context handle
            g_pooled_svchp = NULL;
        }
        printf("\n");
    }

    // --- Cleanup ---
    printf("--- Test Complete. Cleaning up. ---\n\n");
    measure_latency("Terminate Session Pool", wrapper_terminate_session_pool);
    printf("Session pool terminated.\n");

    if (g_authp) OCIHandleFree(g_authp, OCI_HTYPE_AUTHINFO);
    // if (g_srvhp) OCIHandleFree(g_srvhp, OCI_HTYPE_SERVER); // Not used in this refactored code
    if (g_errhp) OCIHandleFree(g_errhp, OCI_HTYPE_ERROR);
    if (g_envhp) OCIHandleFree(g_envhp, OCI_HTYPE_ENV);
    free((void*)g_connect_string);

    printf("Environment terminated.\n");

    return 0;
}