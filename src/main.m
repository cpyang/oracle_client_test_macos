#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <oci.h>

#import <Foundation/Foundation.h>
#include <mach/mach_time.h>
#include <sys/time.h>
#include <errno.h>

// Define the clock ID if the header is missing it (common in old SDKs)
#ifndef CLOCK_MONOTONIC
#define CLOCK_MONOTONIC 0
#endif

int clock_gettime(int clock_id, struct timespec *ts) {
    if (clock_id != CLOCK_MONOTONIC) {
        // For REALTIME, we fall back to gettimeofday
        struct timeval tv;
        if (gettimeofday(&tv, NULL) != 0) return -1;
        ts->tv_sec = tv.tv_sec;
        ts->tv_nsec = tv.tv_usec * 1000;
        return 0;
    }

    // Mach Absolute Time handling for MONOTONIC
    static mach_timebase_info_data_t info;
    if (info.denom == 0) {
        mach_timebase_info(&info);
    }

    uint64_t now = mach_absolute_time();
    uint64_t nanos = now * info.numer / info.denom;

    ts->tv_sec = nanos / 1000000000UL;
    ts->tv_nsec = nanos % 1000000000UL;
    
    return 0;
}


// Global context for wrapper functions
OCIEnv *g_envhp = NULL;
OCIError *g_errhp = NULL;
OCISvcCtx *g_svchp = NULL; // For non-pooled connection
const char* g_username = NULL;
const char* g_password = NULL;
const char* g_connect_string = NULL;
//const char* g_sql = "SELECT * FROM ver";
const char* g_sql = "SELECT DISTINCT s.client_version FROM v$session_connect_info s WHERE s.sid = SYS_CONTEXT('USERENV', 'SID')";

OCISPool *g_poolhp = NULL; 
OraText *g_pool_name = NULL; // To store the pool name returned by OCISessionPoolCreate
ub4 g_pool_name_len = 0;

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
        printf("Result: %s\n", result); // Suppress for performance test
    }
    OCIHandleFree(stmthp, OCI_HTYPE_STMT);
}

// Wrapper functions for non-pooled test
void wrapper_create_connection() {
    checkerr(g_errhp, OCILogon(g_envhp, g_errhp, &g_svchp, (text*)g_username, (ub4)strlen(g_username), (text*)g_password, (ub4)strlen(g_password), (text*)g_connect_string, (ub4)strlen(g_connect_string)), "logon");
}

void wrapper_execute_sql_non_pooled() {
    printf("SQL: %s\n", g_sql);
    run_query_on_svcctx(g_envhp, g_errhp, g_svchp, g_sql);
}

void wrapper_terminate_connection() {
    checkerr(g_errhp, OCILogoff(g_svchp, g_errhp), "logoff");
}

// Wrapper functions for pooled test
void wrapper_create_session_pool() {
    // Corrected arguments for OCISessionPoolCreate based on provided ociap.h
    // Arguments: envhp, errhp, spoolhp, poolName, poolNameLen, connStr, connStrLen, sessMin, sessMax, sessIncr, userid, useridLen, password, passwordLen, mode
    checkerr(g_errhp, OCISessionPoolCreate(g_envhp, g_errhp, g_poolhp, // Removed & from g_poolhp
                                        &g_pool_name, &g_pool_name_len, // OUT parameters for pool name
                                        (OraText*)g_connect_string, (ub4)strlen(g_connect_string), // connStr, connStrLen
                                        1, 5, 1, // sessMin, sessMax, sessIncr (example values, adjust as needed)
                                        (OraText*)g_username, (ub4)strlen(g_username), // userid, useridLen
                                        (OraText*)g_password, (ub4)strlen(g_password), // password, passwordLen
                                        OCI_DEFAULT), "session pool create"); // mode
}

void wrapper_get_session_from_pool() {
    boolean found = FALSE;
    OraText *ret_tag_info = NULL;
    ub4 ret_tag_info_len = 0;
    
    // Corrected arguments for OCISessionGet based on provided ociap.h
    // Arguments: envhp, errhp, svchp, authhp, poolName, poolName_len, tagInfo, tagInfo_len, retTagInfo, retTagInfo_len, found, mode
    checkerr(g_errhp, OCISessionGet(g_envhp, g_errhp, &g_pooled_svchp, 
                                    g_authp,
                                    g_pool_name, g_pool_name_len, // poolName, poolName_len
                                    NULL, 0, // tagInfo, tagInfo_len (for specific session tag)
                                    &ret_tag_info, &ret_tag_info_len, // retTagInfo, retTagInfo_len
                                    &found, // found (OUT)
                                    OCI_SESSGET_SPOOL), "session get from pool");
    
    // If ret_tag_info is allocated by OCI, it should be freed appropriately.
    // Given the issues with OCIFree, we'll omit explicit freeing here for now
    // and assume OCI cleans it up when the session/pool is destroyed, or that
    // this memory is part of the handle itself.
    // if (ret_tag_info) OCIFree(g_envhp, g_errhp, ret_tag_info, OCI_HTYPE_KPR);
}

void wrapper_execute_sql_pooled() {
    printf("SQL: %s\n", g_sql);
    run_query_on_svcctx(g_envhp, g_errhp, g_pooled_svchp, g_sql);
}

void wrapper_release_session_to_pool() {
    // ub4 mode is the last argument, not sb4 *status
    checkerr(g_errhp, OCISessionRelease(g_pooled_svchp, g_errhp, 
                                        NULL, 0, // tag, tagLen
                                        OCI_DEFAULT), "session release to pool"); 
}

void wrapper_terminate_session_pool() {
    // ub4 mode is the last argument, not sb4 *status
    checkerr(g_errhp, OCISessionPoolDestroy(g_poolhp, g_errhp, OCI_DEFAULT), "session pool destroy"); 
}


int main(int argc, const char * argv[]) {
    if (argc != 4) {
        fprintf(stderr, "Usage: %s <username> <password> <connect_string>\n", argv[0]);
        return 1;
    }

    g_username = argv[1];
    g_password = argv[2];
    const char* connect_string_arg = argv[3];
    
    // Use the connect string directly from the command-line argument
    char* final_connect_string_buffer = (char*)malloc(strlen(connect_string_arg) + 1);
    strcpy(final_connect_string_buffer, connect_string_arg);
    g_connect_string = final_connect_string_buffer;

    printf("Connect String: %s\n", g_connect_string);

    printf("Oracle Client Test Program (Objective-C)\n");
    printf("----------------------------------------\n");

    checkerr(g_errhp, OCIEnvCreate(&g_envhp, OCI_THREADED, NULL, NULL, NULL, NULL, 0, NULL), "environment create");
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
    checkerr(g_errhp, OCIHandleAlloc((dvoid *) g_envhp, (dvoid **) &g_poolhp, OCI_HTYPE_SPOOL, (size_t) 0, (dvoid **) 0),"pool handle alloc");

    // Create Session Pool
    measure_latency("Create Session Pool", wrapper_create_session_pool);
    printf("Session pool %s created.\n",g_pool_name);

    for (int i = 0; i < 5; ++i) {
        printf("Iteration %d\n", i + 1);
        measure_latency("Get Session from Pool", wrapper_get_session_from_pool);

        if (g_pooled_svchp) {
            measure_latency("Execute SQL", wrapper_execute_sql_pooled);
            measure_latency("Release Session to Pool", wrapper_release_session_to_pool);
            // The service context handle from a session pool should not be freed by the application.
            // It is managed by the pool. Releasing it is sufficient.
            g_pooled_svchp = NULL;
        }
        printf("\n");
    }

    // --- Cleanup ---
    printf("--- Test Complete. Cleaning up. ---\n\n");
    measure_latency("Terminate Session Pool", wrapper_terminate_session_pool);
    printf("Session pool terminated.\n");

    if (g_poolhp) OCIHandleFree(g_poolhp, OCI_HTYPE_SPOOL);
    if (g_authp) OCIHandleFree(g_authp, OCI_HTYPE_AUTHINFO);
    if (g_errhp) OCIHandleFree(g_errhp, OCI_HTYPE_ERROR);
    if (g_envhp) OCIHandleFree(g_envhp, OCI_HTYPE_ENV);
    free((void*)g_connect_string);

    printf("Environment terminated.\n");

    return 0;
}
