#ifndef LINGUAFLOW_RIME_BRIDGE_H
#define LINGUAFLOW_RIME_BRIDGE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct LFRimeSession LFRimeSession;

int lf_rime_initialize(
    const char *shared_data_dir,
    const char *user_data_dir,
    const char *log_dir
);
void lf_rime_finalize(void);
const char *lf_rime_last_error(void);

LFRimeSession *lf_rime_session_create(void);
void lf_rime_session_destroy(LFRimeSession *session);
int lf_rime_session_select_schema(LFRimeSession *session, const char *schema_id);
int lf_rime_session_process_key(LFRimeSession *session, int keycode, int modifiers);
int lf_rime_session_commit_composition(LFRimeSession *session);
void lf_rime_session_clear(LFRimeSession *session);

char *lf_rime_session_take_commit(LFRimeSession *session);
char *lf_rime_session_copy_preedit(LFRimeSession *session);
int lf_rime_session_candidate_count(LFRimeSession *session);
int lf_rime_session_highlighted_candidate_index(LFRimeSession *session);
char *lf_rime_session_copy_candidate(LFRimeSession *session, int index);
char *lf_rime_session_copy_candidate_comment(LFRimeSession *session, int index);
int lf_rime_session_select_candidate(LFRimeSession *session, int index);

void lf_rime_string_free(char *value);

enum {
    LF_RIME_KEY_BACKSPACE = 0xff08,
    LF_RIME_KEY_RETURN = 0xff0d,
    LF_RIME_KEY_ESCAPE = 0xff1b,
    LF_RIME_KEY_HOME = 0xff50,
    LF_RIME_KEY_LEFT = 0xff51,
    LF_RIME_KEY_UP = 0xff52,
    LF_RIME_KEY_RIGHT = 0xff53,
    LF_RIME_KEY_DOWN = 0xff54,
    LF_RIME_KEY_END = 0xff57,
    LF_RIME_KEY_PAGE_UP = 0xff55,
    LF_RIME_KEY_PAGE_DOWN = 0xff56,
};

#ifdef __cplusplus
}
#endif

#endif
