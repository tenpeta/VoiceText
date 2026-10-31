#include "RimeBridge.h"
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#ifndef VT_SMOKE_ITERATIONS
#define VT_SMOKE_ITERATIONS 1000
#endif

int main(int argc, char **argv) {
  if (argc != 4 || !vt_rime_start(argv[1], argv[2], argv[3])) return 1;
  for (int iteration = 0; iteration < VT_SMOKE_ITERATIONS; iteration++) {
    VTSessionID session = vt_rime_session();
    if (!session) return 2;
    vt_rime_option(session, "simplification", 1);
    const char *pinyin = "nihao";
    for (const char *key = pinyin; *key; key++) vt_rime_key(session, *key, 0);
    VTSnapshot snapshot = {0};
    if (!vt_rime_snapshot(session, &snapshot) || snapshot.count == 0) return 3;
    if (iteration == 0) printf("nihao candidate: %s\n", snapshot.candidates[0].text);
    vt_rime_free_snapshot(&snapshot);
    if (!vt_rime_select(session, 0)) return 4;
    char *commit = vt_rime_take_commit(session);
    if (!commit || !strstr(commit, "你好")) return 5;
    vt_rime_free_string(commit); vt_rime_destroy(session);
  }
  VTSessionID expanded = vt_rime_session();
  vt_rime_option(expanded, "simplification", 1);
  for (const char *key = "shi"; *key; key++) vt_rime_key(expanded, *key, 0);
  VTSnapshot expanded_list = {0}, normal_list = {0}, offset_list = {0};
  if (!vt_rime_snapshot(expanded, &normal_list) || !normal_list.count) return 11;
  if (!vt_rime_expanded_snapshot(expanded, 0, 36, &expanded_list) || expanded_list.count < 10) return 12;
  if (strcmp(normal_list.candidates[0].text, expanded_list.candidates[0].text)) return 13;
  if (!vt_rime_expanded_snapshot(expanded, 9, 36, &offset_list) || !offset_list.count ||
      strcmp(offset_list.candidates[0].text, expanded_list.candidates[9].text)) return 14;
  char *expected = strdup(expanded_list.candidates[9].text);
  if (!vt_rime_select_global(expanded, 9)) return 15;
  char *chosen = vt_rime_take_commit(expanded);
  if (!chosen || strcmp(chosen, expected)) return 16;
  vt_rime_free_string(chosen); free(expected);
  vt_rime_free_snapshot(&normal_list); vt_rime_free_snapshot(&expanded_list); vt_rime_free_snapshot(&offset_list);
  vt_rime_destroy(expanded);
  VTSessionID raw = vt_rime_session();
  for (const char *key = "nihao"; *key; key++) vt_rime_key(raw, *key, 0);
  vt_rime_key(raw, 0xff0d, 0);
  char *raw_commit = vt_rime_take_commit(raw);
  if (!raw_commit || strcmp(raw_commit, "nihao")) return 10;
  vt_rime_free_string(raw_commit);
  vt_rime_destroy(raw);
  VTSessionID traditional = vt_rime_session();
  VTSessionID simplified = vt_rime_session();
  if (!traditional || !simplified) return 6;
  vt_rime_option(traditional, "simplification", 0);
  vt_rime_option(simplified, "simplification", 1);
  for (const char *key = "hanyu"; *key; key++) {
    vt_rime_key(traditional, *key, 0); vt_rime_key(simplified, *key, 0);
  }
  VTSnapshot t = {0}, s = {0};
  if (!vt_rime_snapshot(traditional, &t) || !vt_rime_snapshot(simplified, &s)) return 7;
  if (!t.count || !s.count || strcmp(t.candidates[0].text, "漢語") || strcmp(s.candidates[0].text, "汉语")) return 8;
  vt_rime_free_snapshot(&t); vt_rime_free_snapshot(&s);
  if (!vt_rime_key(simplified, 0xff54, 0) || !vt_rime_snapshot(simplified, &s) || s.highlighted != 1) return 9;
  vt_rime_free_snapshot(&s);
  vt_rime_destroy(traditional); vt_rime_destroy(simplified);
  vt_rime_finalize();
  printf("Rime %d-session smoke test, isolated simplified/traditional sessions and arrow selection passed.\n", VT_SMOKE_ITERATIONS);
  return 0;
}
