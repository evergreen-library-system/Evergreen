#ifndef OILS_CONSTANTS_H
#define OILS_CONSTANTS_H

#ifdef __cplusplus
extern "C" {
#endif

/* Settings ------------------------------------------------------ */
#define OILS_ORG_SETTING_OPAC_TIMEOUT "auth.opac_timeout"
#define OILS_ORG_SETTING_STAFF_TIMEOUT "auth.staff_timeout"
#define OILS_ORG_SETTING_TEMP_TIMEOUT "auth.temp_timeout"


/* Events ------------------------------------------------------ */
#define OILS_EVENT_SUCCESS "SUCCESS"
#define OILS_EVENT_AUTH_FAILED "LOGIN_FAILED"
#define OILS_EVENT_PERM_FAILURE "PERM_FAILURE"
#define OILS_EVENT_NO_SESSION "NO_SESSION"

#ifdef __cplusplus
}
#endif

#endif
