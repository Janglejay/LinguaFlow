#include "LinguaFlowRimeBridge.h"

#include <rime_api.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct LFRimeSession {
    RimeSessionId identifier;
};

static RimeApi *g_api = NULL;
static int g_initialized = 0;
static char g_last_error[256] = {0};

static void set_error(const char *message) {
    snprintf(g_last_error, sizeof(g_last_error), "%s", message ? message : "Unknown Rime error");
}

static char *copy_string(const char *value) {
    if (!value || !value[0]) {
        return NULL;
    }
    size_t length = strlen(value);
    char *copy = malloc(length + 1);
    if (!copy) {
        set_error("Unable to allocate a Rime string");
        return NULL;
    }
    memcpy(copy, value, length + 1);
    return copy;
}

int lf_rime_initialize(
    const char *shared_data_dir,
    const char *user_data_dir,
    const char *log_dir
) {
    if (g_initialized) {
        return 1;
    }
    if (!shared_data_dir || !user_data_dir) {
        set_error("Rime data directories are required");
        return 0;
    }

    g_api = rime_get_api();
    if (!g_api) {
        set_error("Unable to load the librime API");
        return 0;
    }

    RimeTraits traits = {0};
    RIME_STRUCT_INIT(RimeTraits, traits);
    traits.shared_data_dir = shared_data_dir;
    traits.user_data_dir = user_data_dir;
    traits.distribution_name = "LinguaFlow";
    traits.distribution_code_name = "linguaflow";
    traits.distribution_version = "0.2.0";
    traits.app_name = "rime.linguaflow";
    traits.min_log_level = 2;
    traits.log_dir = log_dir ? log_dir : "";

    g_api->setup(&traits);
    g_api->initialize(&traits);
    if (g_api->start_maintenance(True)) {
        g_api->join_maintenance_thread();
    }

    g_initialized = 1;
    g_last_error[0] = '\0';
    return 1;
}

void lf_rime_finalize(void) {
    if (!g_initialized || !g_api) {
        return;
    }
    g_api->cleanup_all_sessions();
    g_api->finalize();
    g_api = NULL;
    g_initialized = 0;
}

const char *lf_rime_last_error(void) {
    return g_last_error;
}

LFRimeSession *lf_rime_session_create(void) {
    if (!g_initialized || !g_api) {
        set_error("Rime is not initialized");
        return NULL;
    }

    RimeSessionId identifier = g_api->create_session();
    if (!identifier) {
        set_error("Unable to create a Rime session");
        return NULL;
    }

    LFRimeSession *session = calloc(1, sizeof(LFRimeSession));
    if (!session) {
        g_api->destroy_session(identifier);
        set_error("Unable to allocate a Rime session");
        return NULL;
    }
    session->identifier = identifier;
    return session;
}

void lf_rime_session_destroy(LFRimeSession *session) {
    if (!session) {
        return;
    }
    if (g_api && session->identifier) {
        g_api->destroy_session(session->identifier);
    }
    free(session);
}

int lf_rime_session_select_schema(LFRimeSession *session, const char *schema_id) {
    return session && g_api && schema_id
        ? g_api->select_schema(session->identifier, schema_id)
        : 0;
}

int lf_rime_session_process_key(LFRimeSession *session, int keycode, int modifiers) {
    return session && g_api
        ? g_api->process_key(session->identifier, keycode, modifiers)
        : 0;
}

int lf_rime_session_commit_composition(LFRimeSession *session) {
    return session && g_api
        ? g_api->commit_composition(session->identifier)
        : 0;
}

void lf_rime_session_clear(LFRimeSession *session) {
    if (session && g_api) {
        g_api->clear_composition(session->identifier);
    }
}

char *lf_rime_session_take_commit(LFRimeSession *session) {
    if (!session || !g_api) {
        return NULL;
    }

    RimeCommit commit = {0};
    RIME_STRUCT_INIT(RimeCommit, commit);
    if (!g_api->get_commit(session->identifier, &commit)) {
        return NULL;
    }
    char *text = copy_string(commit.text);
    g_api->free_commit(&commit);
    return text;
}

char *lf_rime_session_copy_preedit(LFRimeSession *session) {
    if (!session || !g_api) {
        return NULL;
    }

    RimeContext context = {0};
    RIME_STRUCT_INIT(RimeContext, context);
    if (!g_api->get_context(session->identifier, &context)) {
        return NULL;
    }
    char *text = copy_string(context.composition.preedit);
    g_api->free_context(&context);
    return text;
}

int lf_rime_session_candidate_count(LFRimeSession *session) {
    if (!session || !g_api) {
        return 0;
    }

    RimeContext context = {0};
    RIME_STRUCT_INIT(RimeContext, context);
    if (!g_api->get_context(session->identifier, &context)) {
        return 0;
    }
    int count = context.menu.num_candidates;
    g_api->free_context(&context);
    return count;
}

int lf_rime_session_highlighted_candidate_index(LFRimeSession *session) {
    if (!session || !g_api) {
        return 0;
    }

    RimeContext context = {0};
    RIME_STRUCT_INIT(RimeContext, context);
    if (!g_api->get_context(session->identifier, &context)) {
        return 0;
    }
    int index = context.menu.highlighted_candidate_index;
    g_api->free_context(&context);
    return index;
}

static char *copy_candidate_field(LFRimeSession *session, int index, int copy_comment) {
    if (!session || !g_api || index < 0) {
        return NULL;
    }

    RimeContext context = {0};
    RIME_STRUCT_INIT(RimeContext, context);
    if (!g_api->get_context(session->identifier, &context)) {
        return NULL;
    }

    char *value = NULL;
    if (index < context.menu.num_candidates) {
        RimeCandidate *candidate = &context.menu.candidates[index];
        value = copy_string(copy_comment ? candidate->comment : candidate->text);
    }
    g_api->free_context(&context);
    return value;
}

char *lf_rime_session_copy_candidate(LFRimeSession *session, int index) {
    return copy_candidate_field(session, index, 0);
}

char *lf_rime_session_copy_candidate_comment(LFRimeSession *session, int index) {
    return copy_candidate_field(session, index, 1);
}

int lf_rime_session_select_candidate(LFRimeSession *session, int index) {
    return session && g_api && index >= 0
        ? g_api->select_candidate_on_current_page(session->identifier, (size_t)index)
        : 0;
}

void lf_rime_string_free(char *value) {
    free(value);
}
