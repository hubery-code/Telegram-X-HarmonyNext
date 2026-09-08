// BRG-001/002 - minimal Node-API bridge over TDLib's global client C API.
//
// Exposes (contract: plan §5.2 TdNativeBridge, minimal subset):
//   getVersion(): string        - TDLib version via synchronous getOption
//   execute(request): string|null - td_execute (synchronous)
//   createClient(): number      - td_create_client_id (int32)
//   send(clientId, request): void - td_send (asynchronous fire-and-forget)
//
// Not yet implemented (later work packages): receive/subscribe (BRG-003),
// close/shutdown lifecycle (BRG-005), request registry / @extra (core layer).
//
// TDLib C functions are declared manually (verified against `llvm-nm -D`
// libtdjson.so) to avoid pulling TD's generated export-macro headers in.

#include <cstdint>
#include <cstring>
#include <new>
#include <string>

#include "napi/native_api.h"

extern "C" {
int td_create_client_id(void);
void td_send(int client_id, const char *request);
const char *td_receive(double timeout);
const char *td_execute(const char *request);
}

namespace {

constexpr const char *kGetVersionRequest = "{\"@type\":\"getOption\",\"name\":\"version\"}";

// Extracts the version string from a getOption response of the shape:
// {"@type":"option","name":"version","value":{"@type":"optionValueString","value":"1.8.67"}}
// Returns an empty string when parsing fails (caller falls back to raw JSON).
const char *ExtractOptionStringValue(const char *json, char *out, size_t out_size) {
  if (json == nullptr || out == nullptr || out_size == 0) {
    return nullptr;
  }
  const char *marker = std::strstr(json, "\"optionValueString\"");
  if (marker == nullptr) {
    return nullptr;
  }
  const char *value_key = std::strstr(marker, "\"value\":\"");
  if (value_key == nullptr) {
    return nullptr;
  }
  value_key += std::strlen("\"value\":\"");
  const char *end = std::strchr(value_key, '"');
  if (end == nullptr || end == value_key) {
    return nullptr;
  }
  size_t len = static_cast<size_t>(end - value_key);
  if (len >= out_size) {
    len = out_size - 1;
  }
  std::memcpy(out, value_key, len);
  out[len] = '\0';
  return out;
}

// Minimal sanity check for a JSON object request. Full JSON validation is
// delegated to TDLib itself, which answers malformed input with a TDLib
// error object, not a crash.
bool LooksLikeJsonObject(const char *request) {
  if (request == nullptr) {
    return false;
  }
  const char *first = request;
  while (*first == ' ' || *first == '\t' || *first == '\n' || *first == '\r') {
    first++;
  }
  return *first == '{';
}

// Validates that a napi value is a non-empty string; returns the UTF-8 buffer
// (owned by the caller's napi_string allocation) or nullptr after throwing.
const char *GetNonEmptyStringArg(napi_env env, napi_value value, const char *arg_name) {
  napi_valuetype type;
  napi_status status = napi_typeof(env, value, &type);
  if (status != napi_ok || type != napi_string) {
    napi_throw_type_error(env, nullptr, (std::string(arg_name) + " must be a string").c_str());
    return nullptr;
  }
  size_t length = 0;
  status = napi_get_value_string_utf8(env, value, nullptr, 0, &length);
  if (status != napi_ok || length == 0) {
    napi_throw_type_error(env, nullptr, (std::string(arg_name) + " must be a non-empty UTF-8 string").c_str());
    return nullptr;
  }
  // length excludes the NUL terminator; add one and allocate.
  char *buffer = new (std::nothrow) char[length + 1];
  if (buffer == nullptr) {
    napi_throw_error(env, nullptr, "out of memory");
    return nullptr;
  }
  size_t copied = 0;
  status = napi_get_value_string_utf8(env, value, buffer, length + 1, &copied);
  if (status != napi_ok) {
    delete[] buffer;
    napi_throw_error(env, nullptr, "failed to read UTF-8 string");
    return nullptr;
  }
  return buffer;  // freed by the caller after use
}

napi_value GetVersion(napi_env env, napi_callback_info /*info*/) {
  const char *response = td_execute(kGetVersionRequest);
  if (response == nullptr) {
    napi_value null_value;
    napi_get_null(env, &null_value);
    return null_value;
  }
  char version[64] = {0};
  if (ExtractOptionStringValue(response, version, sizeof(version)) != nullptr) {
    napi_value result;
    napi_create_string_utf8(env, version, NAPI_AUTO_LENGTH, &result);
    return result;
  }
  // Fallback: return the raw option JSON so nothing is silently lost.
  napi_value result;
  napi_create_string_utf8(env, response, NAPI_AUTO_LENGTH, &result);
  return result;
}

napi_value Execute(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value argv[1];
  napi_status status = napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
  if (status != napi_ok || argc < 1) {
    napi_throw_type_error(env, nullptr, "execute(request: string) expects 1 argument");
    return nullptr;
  }

  const char *request = GetNonEmptyStringArg(env, argv[0], "request");
  if (request == nullptr) {
    return nullptr;  // exception already pending
  }

  if (!LooksLikeJsonObject(request)) {
    delete[] request;
    napi_value result;
    napi_create_string_utf8(env,
                            "{\"@type\":\"error\",\"code\":400,\"message\":\"request must be a "
                            "JSON object starting with '{'\"}",
                            NAPI_AUTO_LENGTH, &result);
    return result;
  }

  const char *response = td_execute(request);
  delete[] request;

  if (response == nullptr) {
    napi_value null_value;
    napi_get_null(env, &null_value);
    return null_value;
  }
  napi_value result;
  napi_create_string_utf8(env, response, NAPI_AUTO_LENGTH, &result);
  return result;
}

napi_value CreateClient(napi_env env, napi_callback_info /*info*/) {
  int32_t client_id = td_create_client_id();
  napi_value result;
  napi_create_int32(env, client_id, &result);
  return result;
}

napi_value Send(napi_env env, napi_callback_info info) {
  size_t argc = 2;
  napi_value argv[2];
  napi_status status = napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
  if (status != napi_ok || argc < 2) {
    napi_throw_type_error(env, nullptr, "send(clientId: number, request: string) expects 2 arguments");
    return nullptr;
  }

  napi_valuetype id_type;
  status = napi_typeof(env, argv[0], &id_type);
  int32_t client_id = -1;
  if (status != napi_ok || id_type != napi_number || napi_get_value_int32(env, argv[0], &client_id) != napi_ok ||
      client_id < 0) {
    napi_throw_type_error(env, nullptr, "clientId must be a non-negative int32");
    return nullptr;
  }

  const char *request = GetNonEmptyStringArg(env, argv[1], "request");
  if (request == nullptr) {
    return nullptr;  // exception already pending
  }

  td_send(client_id, request);
  delete[] request;

  napi_value undefined;
  napi_get_undefined(env, &undefined);
  return undefined;
}

napi_value Init(napi_env env, napi_value exports) {
  napi_property_descriptor descriptors[] = {
      {"getVersion", nullptr, GetVersion, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"execute", nullptr, Execute, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"createClient", nullptr, CreateClient, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"send", nullptr, Send, nullptr, nullptr, nullptr, napi_default, nullptr},
  };
  napi_define_properties(env, exports, sizeof(descriptors) / sizeof(descriptors[0]), descriptors);
  return exports;
}

napi_module g_tdcoreModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "tdcore_napi",
    .nm_priv = nullptr,
    .reserved = {nullptr},
};

}  // namespace

extern "C" __attribute__((constructor)) void RegisterTdcoreNapiModule(void) {
  napi_module_register(&g_tdcoreModule);
}
