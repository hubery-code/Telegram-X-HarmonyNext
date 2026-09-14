// BRG-001..004 - Node-API bridge over TDLib's global client C API.
//
// Exposes (contract: plan §5.2 TdNativeBridge + §5.4 ordering/backpressure):
//   getVersion(): string                      - TDLib version (synchronous)
//   execute(request): string|null             - td_execute (synchronous)
//   createClient(): number                    - td_create_client_id (int32)
//   send(clientId, request): void             - td_send (async fire-and-forget)
//   subscribeUpdates(sink): number            - BRG-003: subscription id
//   unsubscribe(subscriptionId): void         - BRG-003/004: stop & teardown
//   getMetrics(): object                      - BRG-004: queue/backpressure stats
//
// Event dispatch model (§5.4):
//   TDLib td_receive thread -> bounded queue (1024, backpressure by blocking
//   the receive thread; semantic events are never dropped) -> napi
//   threadsafe_function wakeup -> ArkTS thread drains the queue in batches and
//   invokes each subscriber sink once per event, strictly ordered per client.
//   Per-client monotonic sequence is assigned on the receive thread.
//
// Not yet implemented (later work packages): closeClient/shutdown lifecycle
// (BRG-005), request registry / @extra correlation (core/td_gateway layer),
// mergeable-event downsampling (download/upload progress, typing).
//
// TDLib C functions are declared manually (verified against `llvm-nm -D`
// libtdjson.so) to avoid pulling TD's generated export-macro headers in.

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <mutex>
#include <new>
#include <string>
#include <thread>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

#include "napi/native_api.h"

extern "C" {
int td_create_client_id(void);
void td_send(int client_id, const char *request);
const char *td_receive(double timeout);
const char *td_execute(const char *request);
}

namespace {

constexpr const char *kGetVersionRequest = "{\"@type\":\"getOption\",\"name\":\"version\"}";
constexpr size_t kQueueCapacity = 1024;       // §5.4: bounded; freeze thresholds after P0 soak
constexpr int kReceiveTimeoutSeconds = 0;     // td_receive poll granularity
constexpr double kReceiveTimeoutFraction = 0.1;
constexpr int32_t kEventSchemaVersion = 1;    // TdNativeEvent.schemaVersion

struct TdEvent {
  int32_t client_id;
  uint64_t sequence;
  std::string payload;
  int64_t received_at_monotonic_ms;
  uint64_t session_generation;
};

// Process-lifetime singleton (never destroyed) so the receive thread, TSFN
// callbacks and ArkTS thread can never observe a freed state object
// (use-after-free safety between unsubscribe/stop and in-flight callbacks).
struct BridgeState {
  // Bounded queue between the receive thread and the ArkTS dispatcher.
  std::mutex queue_mutex;
  std::condition_variable queue_not_full;
  std::deque<TdEvent> queue;

  // Metrics (queue-guarded where they describe the queue).
  uint64_t overflow_wait_count = 0;
  uint64_t dropped_count = 0;  // semantic guarantee: must stay 0
  uint64_t stale_dropped_count = 0;
  uint64_t events_forwarded = 0;

  // Subscriptions: touched ONLY on the ArkTS thread (subscribe/unsubscribe and
  // the TSFN call_js callback all run there), so no lock is required.
  std::unordered_map<uint32_t, napi_ref> sinks;
  uint32_t next_subscription_id = 1;

  // Reentrancy safety (P1-BRG-001):
  // When dispatching callbacks on the ArkTS thread, dispatch_depth > 0.
  // Any unsubscribe called during dispatch adds the id to pending_unsubscribes.
  // Sinks are only deleted and erased when dispatch_depth returns to 0.
  uint32_t dispatch_depth = 0;
  std::unordered_set<uint32_t> pending_unsubscribes;

  // Session Generation (P1-BRG-002): monotonic counter
  std::atomic<uint64_t> session_generation{1};

  // Receive thread + TSFN lifecycle.
  std::atomic<bool> running{false};
  std::thread receive_thread;
  napi_threadsafe_function tsfn = nullptr;
  napi_env env = nullptr;
};

BridgeState g_state;

int64_t MonotonicMillis() {
  return std::chrono::duration_cast<std::chrono::milliseconds>(
             std::chrono::steady_clock::now().time_since_epoch())
      .count();
}

// Parses the "@client_id" key that TDLib's global JSON API prepends to every
// response/update. Returns -1 when absent (should not happen for global API).
int32_t ParseClientId(const char *json) {
  if (json == nullptr) {
    return -1;
  }
  const char *key = std::strstr(json, "\"@client_id\":");
  if (key == nullptr) {
    return -1;
  }
  key += std::strlen("\"@client_id\":");
  while (*key == ' ') {
    key++;
  }
  char *end = nullptr;
  long value = std::strtol(key, &end, 10);
  return (end != key) ? static_cast<int32_t>(value) : -1;
}

// ---------------------------------------------------------------------------
// Receive thread: td_receive -> per-client sequence -> bounded queue -> TSFN.
// ---------------------------------------------------------------------------

void ReceiveLoop(BridgeState *state) {
  std::unordered_map<int32_t, uint64_t> sequence_by_client;
  while (state->running.load(std::memory_order_relaxed)) {
    const char *response =
        td_receive(kReceiveTimeoutSeconds + kReceiveTimeoutFraction);
    if (response == nullptr) {
      continue;  // timeout tick: re-check the stop flag
    }

    const int32_t client_id = ParseClientId(response);
    const uint64_t sequence = ++sequence_by_client[client_id];
    const uint64_t generation = state->session_generation.load(std::memory_order_relaxed);
    TdEvent event{client_id, sequence, response, MonotonicMillis(), generation};

    {
      std::unique_lock<std::mutex> lock(state->queue_mutex);
      if (state->queue.size() >= kQueueCapacity) {
        // Backpressure (§5.4): block the receive thread until the ArkTS side
        // drains. TDLib keeps its own buffers; semantic events are never
        // dropped, which is why dropped_count must remain 0.
        state->overflow_wait_count++;
        state->queue_not_full.wait(lock, [&] {
          return state->queue.size() < kQueueCapacity || !state->running.load(std::memory_order_relaxed);
        });
        if (!state->running.load(std::memory_order_relaxed)) {
          break;
        }
      }
      state->queue.push_back(std::move(event));
    }

    napi_status status = napi_call_threadsafe_function(state->tsfn, nullptr, napi_tsfn_blocking);
    if (status != napi_ok) {
      break;  // TSFN closing/closed during teardown
    }
  }
}

// Forward declaration
void StopDispatcherIfIdle(BridgeState *state);

// Runs on the ArkTS thread. Wakeup signal only (data stays in the bounded
// queue); drains everything currently queued, preserving receive order, and
// invokes every subscriber sink once per event. Batch dequeue + per-event
// callback: keeps the sink contract single-event and simple; batching of the
// TSFN wakeup itself happens naturally because drain-all coalesces signals.
void TsfnDispatch(napi_env env, napi_value /*unused_js_callback*/, void *context, void * /*data*/) {
  auto *state = static_cast<BridgeState *>(context);

  std::deque<TdEvent> batch;
  {
    std::lock_guard<std::mutex> lock(state->queue_mutex);
    batch.swap(state->queue);
  }
  state->queue_not_full.notify_all();

  state->dispatch_depth++;

  for (const TdEvent &event : batch) {
    const uint64_t current_generation = state->session_generation.load(std::memory_order_relaxed);
    if (event.session_generation != current_generation) {
      std::lock_guard<std::mutex> lock(state->queue_mutex);
      state->stale_dropped_count++;
      continue;
    }

    state->events_forwarded++;

    // Snapshot sinks before dispatching to allow safe reentrant unsubscribe/subscribe (P1-BRG-001).
    std::vector<std::pair<uint32_t, napi_ref>> current_sinks;
    current_sinks.reserve(state->sinks.size());
    for (const auto &[id, ref] : state->sinks) {
      if (state->pending_unsubscribes.find(id) == state->pending_unsubscribes.end()) {
        current_sinks.emplace_back(id, ref);
      }
    }

    for (const auto &[id, ref] : current_sinks) {
      // If unsubscribed in an earlier callback during this batch, skip.
      if (state->pending_unsubscribes.find(id) != state->pending_unsubscribes.end()) {
        continue;
      }

      napi_value sink = nullptr;
      if (napi_get_reference_value(env, ref, &sink) != napi_ok || sink == nullptr) {
        continue;
      }
      char sequence_buffer[24];
      std::snprintf(sequence_buffer, sizeof(sequence_buffer), "%llu",
                    static_cast<unsigned long long>(event.sequence));

      napi_value args[5];
      napi_create_int32(env, kEventSchemaVersion, &args[0]);
      napi_create_int32(env, event.client_id, &args[1]);
      napi_create_string_utf8(env, sequence_buffer, NAPI_AUTO_LENGTH, &args[2]);
      napi_create_string_utf8(env, event.payload.c_str(), event.payload.size(), &args[3]);
      napi_create_double(env, static_cast<double>(event.received_at_monotonic_ms), &args[4]);

      napi_value undefined = nullptr;
      napi_get_undefined(env, &undefined);
      napi_call_function(env, undefined, sink, 5, args, nullptr);

      // Guard against pending exceptions thrown in the JS callback to prevent disrupting other sinks.
      bool is_pending = false;
      if (napi_is_exception_pending(env, &is_pending) == napi_ok && is_pending) {
        napi_value fatal_err = nullptr;
        napi_get_and_clear_last_exception(env, &fatal_err);
      }
    }
  }

  state->dispatch_depth--;

  // Clean up pending unsubscribes when dispatch stack has completely unwound.
  if (state->dispatch_depth == 0) {
    if (!state->pending_unsubscribes.empty()) {
      for (uint32_t id : state->pending_unsubscribes) {
        auto it = state->sinks.find(id);
        if (it != state->sinks.end()) {
          napi_delete_reference(env, it->second);
          state->sinks.erase(it);
        }
      }
      state->pending_unsubscribes.clear();
    }
    StopDispatcherIfIdle(state);
  }
}

// Idempotent stop: join the receive thread, then release the TSFN. Called on
// the ArkTS thread when the last subscription goes away.
void StopDispatcherIfIdle(BridgeState *state) {
  if (state->dispatch_depth > 0) {
    return;
  }
  if (!state->sinks.empty() || !state->running.exchange(false)) {
    return;
  }
  state->queue_not_full.notify_all();
  if (state->receive_thread.joinable()) {
    state->receive_thread.join();
  }
  if (state->tsfn != nullptr) {
    napi_release_threadsafe_function(state->tsfn, napi_tsfn_release);
    state->tsfn = nullptr;
  }
  {
    std::lock_guard<std::mutex> lock(state->queue_mutex);
    state->stale_dropped_count += state->queue.size();
    state->queue.clear();
  }
  state->session_generation.fetch_add(1, std::memory_order_relaxed);
}

// Starts the receive thread + TSFN on first subscription. All on ArkTS thread.
bool EnsureDispatcher(BridgeState *state, napi_env env) {
  if (state->running.load(std::memory_order_relaxed)) {
    return true;
  }
  state->env = env;

  napi_value noop = nullptr;
  auto noop_fn = [](napi_env, napi_callback_info) -> napi_value { return nullptr; };
  if (napi_create_function(env, "tdcoreDispatch", NAPI_AUTO_LENGTH, noop_fn, nullptr, &noop) != napi_ok) {
    return false;
  }
  napi_value resource_name = nullptr;
  napi_create_string_utf8(env, "tdcore_napi", NAPI_AUTO_LENGTH, &resource_name);

  // max_queue_size = 0: the TSFN queue is an unlimited stream of empty wakeup
  // signals only; the real buffer is our bounded queue, so memory stays
  // bounded by kQueueCapacity regardless of TSFN internals.
  if (napi_create_threadsafe_function(env, noop, nullptr, resource_name, 0, 1, nullptr, nullptr,
                                      state, TsfnDispatch, &state->tsfn) != napi_ok) {
    state->tsfn = nullptr;
    return false;
  }

  state->running.store(true);
  state->receive_thread = std::thread(ReceiveLoop, state);
  return true;
}

// ---------------------------------------------------------------------------
// Helpers shared with the BRG-001/002 surface.
// ---------------------------------------------------------------------------

// Extracts the version string from a getOption response of the shape:
// {"@type":"option","name":"version","value":{"@type":"optionValueString","value":"1.8.67"}}
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

// Validates that a napi value is a non-empty string and returns a freshly
// allocated UTF-8 buffer (caller must delete[]) or nullptr after throwing.
const char *GetNonEmptyStringArg(napi_env env, napi_value value, const char *arg_name) {
  napi_valuetype type;
  napi_status status = napi_typeof(env, value, &type);
  if (status != napi_ok || type != napi_string) {
    napi_throw_type_error(env, nullptr,
                          (std::string(arg_name) + " must be a string").c_str());
    return nullptr;
  }
  size_t length = 0;
  status = napi_get_value_string_utf8(env, value, nullptr, 0, &length);
  if (status != napi_ok || length == 0) {
    napi_throw_type_error(env, nullptr,
                          (std::string(arg_name) + " must be a non-empty UTF-8 string").c_str());
    return nullptr;
  }
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
  return buffer;
}

// ---------------------------------------------------------------------------
// napi entry points.
// ---------------------------------------------------------------------------

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
    return nullptr;
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
    return nullptr;
  }

  td_send(client_id, request);
  delete[] request;

  napi_value undefined;
  napi_get_undefined(env, &undefined);
  return undefined;
}

// BRG-003: subscribeUpdates(sink) -> subscriptionId
// sink(schemaVersion, clientId, sequence /*decimal string*/, payloadUtf8,
//      receivedAtMonotonicMs)
napi_value SubscribeUpdates(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value argv[1];
  if (napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr) != napi_ok || argc < 1) {
    napi_throw_type_error(env, nullptr, "subscribeUpdates(sink: function) expects 1 argument");
    return nullptr;
  }
  napi_valuetype type;
  if (napi_typeof(env, argv[0], &type) != napi_ok || type != napi_function) {
    napi_throw_type_error(env, nullptr, "sink must be a function");
    return nullptr;
  }

  if (!EnsureDispatcher(&g_state, env)) {
    napi_throw_error(env, nullptr, "failed to start TDLib receive dispatcher");
    return nullptr;
  }

  napi_ref ref = nullptr;
  if (napi_create_reference(env, argv[0], 1, &ref) != napi_ok) {
    StopDispatcherIfIdle(&g_state);
    napi_throw_error(env, nullptr, "failed to retain sink reference");
    return nullptr;
  }
  const uint32_t id = g_state.next_subscription_id++;
  g_state.sinks.emplace(id, ref);

  napi_value result;
  napi_create_uint32(env, id, &result);
  return result;
}

// BRG-003/004: unsubscribe(subscriptionId). Stops the receive thread and
// releases the TSFN when the last subscription goes away.
// P1-BRG-001: reentrant calls during dispatch are queued to pending_unsubscribes.
napi_value Unsubscribe(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value argv[1];
  if (napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr) != napi_ok || argc < 1) {
    napi_throw_type_error(env, nullptr, "unsubscribe(subscriptionId: number) expects 1 argument");
    return nullptr;
  }
  uint32_t id = 0;
  if (napi_get_value_uint32(env, argv[0], &id) != napi_ok) {
    napi_throw_type_error(env, nullptr, "subscriptionId must be a number");
    return nullptr;
  }

  if (g_state.dispatch_depth > 0) {
    if (g_state.sinks.find(id) != g_state.sinks.end()) {
      g_state.pending_unsubscribes.insert(id);
    }
  } else {
    auto it = g_state.sinks.find(id);
    if (it != g_state.sinks.end()) {
      napi_delete_reference(env, it->second);
      g_state.sinks.erase(it);
    }
    StopDispatcherIfIdle(&g_state);
  }

  napi_value undefined;
  napi_get_undefined(env, &undefined);
  return undefined;
}

// P1-BRG-002: resetSession() clears the queue and bumps the session generation.
napi_value ResetSession(napi_env env, napi_callback_info /*info*/) {
  {
    std::lock_guard<std::mutex> lock(g_state.queue_mutex);
    g_state.stale_dropped_count += g_state.queue.size();
    g_state.queue.clear();
  }
  g_state.queue_not_full.notify_all();
  g_state.session_generation.fetch_add(1, std::memory_order_relaxed);

  napi_value undefined;
  napi_get_undefined(env, &undefined);
  return undefined;
}

// BRG-004: metrics snapshot for ArkTS dashboards/tests.
napi_value GetMetrics(napi_env env, napi_callback_info /*info*/) {
  size_t queue_size;
  uint64_t overflow_waits;
  uint64_t dropped;
  uint64_t stale_dropped;
  uint64_t forwarded;
  {
    std::lock_guard<std::mutex> lock(g_state.queue_mutex);
    queue_size = g_state.queue.size();
    overflow_waits = g_state.overflow_wait_count;
    dropped = g_state.dropped_count;
    stale_dropped = g_state.stale_dropped_count;
    forwarded = g_state.events_forwarded;
  }
  uint64_t session_gen = g_state.session_generation.load(std::memory_order_relaxed);

  size_t active_subs = g_state.sinks.size();
  if (active_subs >= g_state.pending_unsubscribes.size()) {
    active_subs -= g_state.pending_unsubscribes.size();
  } else {
    active_subs = 0;
  }

  napi_value obj = nullptr;
  napi_create_object(env, &obj);
  napi_value v_queue = nullptr;
  napi_create_uint32(env, static_cast<uint32_t>(queue_size), &v_queue);
  napi_set_named_property(env, obj, "queueSize", v_queue);
  napi_value v_overflow = nullptr;
  napi_create_double(env, static_cast<double>(overflow_waits), &v_overflow);
  napi_set_named_property(env, obj, "overflowWaitCount", v_overflow);
  napi_value v_dropped = nullptr;
  napi_create_double(env, static_cast<double>(dropped), &v_dropped);
  napi_set_named_property(env, obj, "droppedCount", v_dropped);
  napi_value v_stale = nullptr;
  napi_create_double(env, static_cast<double>(stale_dropped), &v_stale);
  napi_set_named_property(env, obj, "staleDroppedCount", v_stale);
  napi_value v_forwarded = nullptr;
  napi_create_double(env, static_cast<double>(forwarded), &v_forwarded);
  napi_set_named_property(env, obj, "eventsForwarded", v_forwarded);
  napi_value v_subs = nullptr;
  napi_create_uint32(env, static_cast<uint32_t>(active_subs), &v_subs);
  napi_set_named_property(env, obj, "subscriptions", v_subs);
  napi_value v_gen = nullptr;
  napi_create_double(env, static_cast<double>(session_gen), &v_gen);
  napi_set_named_property(env, obj, "sessionGeneration", v_gen);
  napi_value v_running = nullptr;
  napi_get_boolean(env, g_state.running.load(std::memory_order_relaxed), &v_running);
  napi_set_named_property(env, obj, "dispatcherRunning", v_running);
  return obj;
}

napi_value Init(napi_env env, napi_value exports) {
  napi_property_descriptor descriptors[] = {
      {"getVersion", nullptr, GetVersion, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"execute", nullptr, Execute, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"createClient", nullptr, CreateClient, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"send", nullptr, Send, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"subscribeUpdates", nullptr, SubscribeUpdates, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"unsubscribe", nullptr, Unsubscribe, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"resetSession", nullptr, ResetSession, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"getMetrics", nullptr, GetMetrics, nullptr, nullptr, nullptr, napi_default, nullptr},
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
