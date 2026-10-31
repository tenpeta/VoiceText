#ifndef VOICETEXT_RIME_BRIDGE_H
#define VOICETEXT_RIME_BRIDGE_H
#include <stddef.h>
#include <stdint.h>
typedef uintptr_t VTSessionID;
typedef struct { char *text; char *comment; } VTCandidate;
typedef struct {
  char *preedit;
  int cursor, selection_start, selection_end;
  int count, highlighted, page, last_page;
  VTCandidate *candidates;
} VTSnapshot;
int vt_rime_start(const char *shared, const char *user, const char *logs);
void vt_rime_finalize(void);
VTSessionID vt_rime_session(void);
void vt_rime_destroy(VTSessionID session);
int vt_rime_key(VTSessionID session, int key, int modifiers);
int vt_rime_select(VTSessionID session, size_t index);
int vt_rime_select_global(VTSessionID session, size_t index);
int vt_rime_expanded_snapshot(VTSessionID session, int start, int limit, VTSnapshot *snapshot);
int vt_rime_page(VTSessionID session, int backward);
void vt_rime_option(VTSessionID session, const char *name, int value);
int vt_rime_commit(VTSessionID session);
void vt_rime_clear(VTSessionID session);
char *vt_rime_take_commit(VTSessionID session);
char *vt_rime_input(VTSessionID session);
int vt_rime_snapshot(VTSessionID session, VTSnapshot *snapshot);
void vt_rime_free_snapshot(VTSnapshot *snapshot);
void vt_rime_free_string(char *string);
#endif
