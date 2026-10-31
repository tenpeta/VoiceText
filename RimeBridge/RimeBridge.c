#include "RimeBridge.h"
#include <rime_api.h>
#include <stdlib.h>
#include <string.h>

static RimeApi *api;
static char *shared_path, *user_path, *log_path;
static int running;

int vt_rime_start(const char *shared, const char *user, const char *logs) {
  if (running) return 1;
  api = rime_get_api();
  shared_path = strdup(shared); user_path = strdup(user); log_path = strdup(logs);
  if (!shared_path || !user_path || !log_path) { vt_rime_finalize(); return 0; }
  RIME_STRUCT(RimeTraits, traits);
  traits.shared_data_dir = shared_path; traits.user_data_dir = user_path;
  traits.log_dir = log_path; traits.app_name = "voicetext";
  traits.distribution_name = "VoiceText"; traits.distribution_code_name = "voicetext";
  traits.distribution_version = "0.1.0"; traits.min_log_level = 2;
  api->setup(&traits); api->initialize(NULL); running = 1;
  // Called on a dedicated initialization queue before any session is exposed.
  if (api->start_maintenance(False)) api->join_maintenance_thread();
  return 1;
}
void vt_rime_finalize(void) {
  if (running) { api->cleanup_all_sessions(); api->finalize(); }
  running = 0;
  free(shared_path); free(user_path); free(log_path);
  shared_path = user_path = log_path = NULL;
}
VTSessionID vt_rime_session(void) {
  if (!running) return 0;
  VTSessionID session = api->create_session();
  if (session && !api->select_schema(session, "voicetext_pinyin")) {
    api->destroy_session(session); return 0;
  }
  return session;
}
void vt_rime_destroy(VTSessionID s) { if (running && s) api->destroy_session(s); }
int vt_rime_key(VTSessionID s, int key, int modifiers) { return running && s && api->process_key(s,key,modifiers); }
int vt_rime_select(VTSessionID s, size_t index) { return running && s && api->select_candidate_on_current_page(s,index); }
int vt_rime_select_global(VTSessionID s, size_t index) { return running && s && api->select_candidate(s,index); }
int vt_rime_page(VTSessionID s, int backwards) { return running && s && api->change_page(s,backwards); }
void vt_rime_option(VTSessionID s, const char *name, int value) { if (running && s) api->set_option(s,name,value); }
int vt_rime_commit(VTSessionID s) { return running && s && api->commit_composition(s); }
void vt_rime_clear(VTSessionID s) { if (running && s) api->clear_composition(s); }
char *vt_rime_take_commit(VTSessionID s) {
  RIME_STRUCT(RimeCommit, commit);
  if (!running || !s || !api->get_commit(s, &commit)) return NULL;
  char *text = commit.text ? strdup(commit.text) : NULL;
  api->free_commit(&commit); return text;
}
char *vt_rime_input(VTSessionID s) {
  if (!running || !s) return NULL;
  const char *input = api->get_input(s);
  return input ? strdup(input) : NULL;
}
int vt_rime_snapshot(VTSessionID s, VTSnapshot *output) {
  memset(output, 0, sizeof(*output));
  RIME_STRUCT(RimeContext, context);
  if (!running || !s || !api->get_context(s, &context)) return 0;
  output->preedit = strdup(context.composition.preedit ? context.composition.preedit : "");
  output->cursor = context.composition.cursor_pos;
  output->selection_start = context.composition.sel_start;
  output->selection_end = context.composition.sel_end;
  output->count = context.menu.num_candidates;
  output->highlighted = context.menu.highlighted_candidate_index;
  output->page = context.menu.page_no; output->last_page = context.menu.is_last_page;
  if (output->count > 0) {
    output->candidates = calloc((size_t)output->count, sizeof(VTCandidate));
    if (!output->candidates) { api->free_context(&context); vt_rime_free_snapshot(output); return 0; }
    for (int i = 0; i < output->count; i++) {
      output->candidates[i].text = strdup(context.menu.candidates[i].text ?: "");
      output->candidates[i].comment = strdup(context.menu.candidates[i].comment ?: "");
    }
  }
  api->free_context(&context); return 1;
}
int vt_rime_expanded_snapshot(VTSessionID s, int start, int limit, VTSnapshot *output) {
  if (start < 0 || limit <= 0 || limit > 36 || !vt_rime_snapshot(s, output)) return 0;
  for (int i = 0; i < output->count; i++) {
    free(output->candidates[i].text); free(output->candidates[i].comment);
  }
  free(output->candidates);
  output->count = 0;
  output->candidates = calloc((size_t)limit, sizeof(VTCandidate));
  if (!output->candidates) { vt_rime_free_snapshot(output); return 0; }
  output->page = start / limit; output->highlighted = 0; output->last_page = 1;
  RimeCandidateListIterator iterator = {0};
  if (api->candidate_list_from_index(s, &iterator, start)) {
    while (api->candidate_list_next(&iterator)) {
      if (output->count == limit) { output->last_page = 0; break; }
      VTCandidate *candidate = &output->candidates[output->count++];
      candidate->text = strdup(iterator.candidate.text ?: "");
      candidate->comment = strdup(iterator.candidate.comment ?: "");
    }
    api->candidate_list_end(&iterator);
  }
  return 1;
}
void vt_rime_free_snapshot(VTSnapshot *snapshot) {
  free(snapshot->preedit);
  if (snapshot->candidates) {
    for (int i = 0; i < snapshot->count; i++) {
      free(snapshot->candidates[i].text); free(snapshot->candidates[i].comment);
    }
    free(snapshot->candidates);
  }
  memset(snapshot,0,sizeof(*snapshot));
}
void vt_rime_free_string(char *string) { free(string); }
