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
    // Corrected arguments for OCISessionPoolCreate
    checkerr(g_errhp, OCISessionPoolCreate(g_envhp, g_errhp, &g_poolhp, 
                                        (text*)g_username, (ub4)strlen(g_username), 
                                        (text*)g_password, (ub4)strlen(g_password), 
                                        (text*)g_connect_string, (ub4)strlen(g_connect_string), 
                                        OCI_DEFAULT, // mode
                                        NULL, 0, // poolParams, poolParamsLen
                                        NULL, 0, // options, optionsLen
                                        NULL), "session pool create"); // sb4 *status is the last argument, passing NULL as we check with checkerr 
}

void wrapper_get_session_from_pool() {
    // Corrected arguments for OCISessionGet
    checkerr(g_errhp, OCISessionGet(g_envhp, g_errhp, &g_pooled_svchp, g_authp, 
                                    (text*)g_connect_string, (ub4)strlen(g_connect_string), 
                                    NULL, 0, // tag, tagLen
                                    NULL, // sessionhp
                                    0, // sessionhpLen
                                    OCI_DEFAULT, // mode
                                    NULL), "session get from pool"); // sb4 *status is the last argument, passing NULL as we check with checkerr
}

void wrapper_execute_sql_pooled() {
    run_query_on_svcctx(g_envhp, g_errhp, g_pooled_svchp, g_sql);
}

void wrapper_release_session_to_pool() {
    // Corrected arguments for OCISessionRelease
    checkerr(g_errhp, OCISessionRelease(g_pooled_svchp, g_errhp, 
                                        NULL, 0, // tag, tagLen
                                        OCI_DEFAULT), "session release to pool"); // ub4 mode is the last argument
}

void wrapper_terminate_session_pool() {
    // Corrected arguments for OCISessionPoolDestroy
    checkerr(g_errhp, OCISessionPoolDestroy(g_poolhp, g_errhp, OCI_DEFAULT), "session pool destroy"); // ub4 mode is the last argument
}


int main(int argc, const char * argv[]) {
    if (argc != 4) {
        fprintf(stderr, "Usage: %s <username> <password> <connect_string>\n", argv[0]);
        return 1;
    }

    g_username = argv[1];
    g_password = argv[2];
    const char* connect_string_arg = argv[3];
    
    // Determine if the connect_string_arg is a full DESCRIPTION or a simple TNS alias/Easy Connect string
    const char* params_to_add = "(TCP.NODELAY=YES)(DISABLE_OOB=ON)";
    char* final_connect_string_buffer = NULL;

    if (strstr(connect_string_arg, "(DESCRIPTION=") != NULL) {
        // It's a full DESCRIPTION, modify it
        size_t final_connect_string_len = strlen(connect_string_arg) + strlen(params_to_add) + 1;
        final_connect_string_buffer = (char*)malloc(final_connect_string_len); 
        strcpy(final_connect_string_buffer, connect_string_arg);
        
        char* description_pos = strstr(final_connect_string_buffer, "(DESCRIPTION=");
        size_t desc_tag_len = strlen("(DESCRIPTION=");
        size_t params_len = strlen(params_to_add);
        size_t suffix_len = strlen(description_pos + desc_tag_len);
        
        memmove(description_pos + desc_tag_len + params_len, 
                description_pos + desc_tag_len, 
                suffix_len + 1); // +1 for null terminator
        memcpy(description_pos + desc_tag_len, params_to_add, params_len);
        
        g_connect_string = final_connect_string_buffer;
    } else {
        // It's a simple TNS alias or Easy Connect string, use as is
        // Still need to allocate and copy to g_connect_string
        final_connect_string_buffer = (char*)malloc(strlen(connect_string_arg) + 1);
        strcpy(final_connect_string_buffer, connect_string_arg);
        g_connect_string = final_connect_string_buffer;
    }

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