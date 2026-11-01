#include "RimeBridge.h"
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#ifndef VT_SMOKE_ITERATIONS
#define VT_SMOKE_ITERATIONS 1000
#endif

static int check_candidates(const char *input, const char *expected, const char *after, int first) {
  VTSessionID session = vt_rime_session();
  vt_rime_option(session, "traditionalization", 0);
  for (const char *key = input; *key; key++) vt_rime_key(session, *key, 0);
  VTSnapshot list = {0};
  vt_rime_expanded_snapshot(session, 0, 100, &list);
  int found = -1, later = -1;
  printf("%s:", input);
  for (int i = 0; i < list.count; i++) {
    if (i < 8) printf(" %s", list.candidates[i].text);
    if (!strcmp(list.candidates[i].text, expected)) found = i;
    if (after && !strcmp(list.candidates[i].text, after)) later = i;
  }
  printf("\n");
  vt_rime_free_snapshot(&list);
  vt_rime_destroy(session);
  return found >= 0 && (!first || found == 0) && (!after || later > found);
}

int main(int argc, char **argv) {
  if (argc != 4 || !vt_rime_start(argv[1], argv[2], argv[3])) return 1;
  if (!check_candidates("xiangmu", "项目", NULL, 0) ||
      !check_candidates("xaingmu", "项目", NULL, 0) ||
      !check_candidates("kuai", "快", NULL, 0) ||
      !check_candidates("kaui", "快", NULL, 0) ||
      !check_candidates("hsi", "是", NULL, 0) ||
      !check_candidates("hci", "吃", NULL, 0) ||
      !check_candidates("hate", "哈特", "hate", 0) ||
      !check_candidates("hello", "hello", NULL, 1) ||
      !check_candidates("world", "world", NULL, 1) ||
      !check_candidates("shagnhai", "上海", NULL, 0) ||
      !check_candidates("pegn", "朋", NULL, 0) ||
      !check_candidates("zhognwen", "中文", NULL, 0) ||
      !check_candidates("yign", "应", NULL, 0) ||
      !check_candidates("shou", "手", "说", 0) ||
      !check_candidates("shuo", "说", "手", 0) ||
      !check_candidates("lei", "类", "列", 0) ||
      !check_candidates("lie", "列", "类", 0) ||
      !check_candidates("shujuku", "数据库", NULL, 0)) return 19;
  for (int iteration = 0; iteration < VT_SMOKE_ITERATIONS; iteration++) {
    VTSessionID session = vt_rime_session();
    if (!session) return 2;
    vt_rime_option(session, "traditionalization", 0);
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
  vt_rime_option(expanded, "traditionalization", 0);
  for (const char *key = "shi"; *key; key++) vt_rime_key(expanded, *key, 0);
  VTSnapshot expanded_list = {0}, normal_list = {0}, offset_list = {0};
  if (!vt_rime_snapshot(expanded, &normal_list) || !normal_list.count) return 11;
  if (!vt_rime_expanded_snapshot(expanded, 0, 36, &expanded_list) || expanded_list.count < 10) return 12;
  if (strcmp(normal_list.candidates[0].text, expanded_list.candidates[0].text)) return 13;
  if (!vt_rime_expanded_snapshot(expanded, 9, 36, &offset_list) || !offset_list.count ||
      strcmp(offset_list.candidates[0].text, expanded_list.candidates[9].text)) return 14;
  VTSnapshot continuous_list = {0};
  if (!vt_rime_expanded_snapshot(expanded, 0, 108, &continuous_list) ||
      continuous_list.count <= 36) return 17;
  for (int i = 0; i < expanded_list.count; i++) {
    if (strcmp(expanded_list.candidates[i].text, continuous_list.candidates[i].text)) return 18;
  }
  vt_rime_free_snapshot(&continuous_list);
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
  vt_rime_option(traditional, "traditionalization", 1);
  vt_rime_option(simplified, "traditionalization", 0);
  for (const char *key = "hanyu"; *key; key++) {
    vt_rime_key(traditional, *key, 0); vt_rime_key(simplified, *key, 0);
  }
  VTSnapshot t = {0}, s = {0};
  if (!vt_rime_snapshot(traditional, &t) || !vt_rime_snapshot(simplified, &s)) return 7;
  if (!t.count || !s.count || strcmp(t.candidates[0].text, "漢語") || strcmp(s.candidates[0].text, "汉语")) return 8;
  vt_rime_free_snapshot(&t); vt_rime_free_snapshot(&s);
  // Converted and original forms must not coexist after normalization/deduplication.
  VTSnapshot normalized = {0};
  vt_rime_expanded_snapshot(simplified, 0, 100, &normalized);
  for (int i = 0; i < normalized.count; i++) {
    if (strstr(normalized.candidates[i].text, "漢")) return 20;
  }
  vt_rime_free_snapshot(&normalized);
  if (!vt_rime_key(simplified, 0xff54, 0) || !vt_rime_snapshot(simplified, &s) || s.highlighted != 1) return 9;
  vt_rime_free_snapshot(&s);
  vt_rime_destroy(traditional); vt_rime_destroy(simplified);
  vt_rime_finalize();
  printf("Rime %d-session smoke test, isolated simplified/traditional sessions and arrow selection passed.\n", VT_SMOKE_ITERATIONS);
  return 0;
}
