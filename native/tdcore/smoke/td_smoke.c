// TDN-002 smoke test for the HarmonyOS arm64 TDLib build.
//
// Links against libtdjson.so and exercises only the synchronous global client
// API (td_execute) - no network, no account, no filesystem required:
//   1. getOption("version")  -> proves TDLib core is alive, prints its version
//   2. getTextEntities       -> exercises the TL/JSON pipeline end to end
//
// Exit code 0 and the two expected JSON payloads on stdout = PASS.

#include <stdio.h>
#include <string.h>

#include "td/telegram/td_json_client.h"

static int check(const char *label, const char *response, const char *needle) {
  if (response == NULL) {
    printf("FAIL %s: NULL response\n", label);
    return 1;
  }
  printf("%s: %s\n", label, response);
  if (strstr(response, needle) == NULL) {
    printf("FAIL %s: expected to contain '%s'\n", label, needle);
    return 1;
  }
  return 0;
}

int main(void) {
  int failed = 0;

  failed |= check("getOption(version)",
                  td_execute("{\"@type\":\"getOption\",\"name\":\"version\"}"),
                  "\"value\":\"1.8.67\"");

  failed |= check("getTextEntities",
                  td_execute("{\"@type\":\"getTextEntities\",\"text\":\"hello @telegram\"}"),
                  "\"@type\":\"textEntity\"");

  printf(failed ? "SMOKE RESULT: FAIL\n" : "SMOKE RESULT: PASS\n");
  return failed;
}
