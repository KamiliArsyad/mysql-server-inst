#include "isofuzz_mysql_adapter.h"
#include <mutex>
#include <unordered_map>

static std::mutex g_trx_map_mutex;
static std::unordered_map<trx_t *, isofuzz_trx_t> g_trx_map;

static isofuzz_trx_t get_trx_handle(trx_t *trx) {
  if (!trx) return nullptr;
  std::lock_guard<std::mutex> lock(g_trx_map_mutex);
  auto it = g_trx_map.find(trx);
  return (it != g_trx_map.end()) ? it->second : nullptr;
}

void adapter_init() { isofuzz_init(); }
void adapter_shutdown() { isofuzz_shutdown(); }

void adapter_trx_start(trx_t *trx) {
  if (!trx) return;
  isofuzz_trx_t handle = isofuzz_trx_begin();
  if (!handle) return;
  {
    std::lock_guard<std::mutex> lock(g_trx_map_mutex);
    g_trx_map[trx] = handle;
  }
}

void adapter_trx_commit(trx_t *trx) {
  isofuzz_trx_t handle = get_trx_handle(trx);
  if (!handle) return;
  isofuzz_trx_commit(handle);
  isofuzz_trx_end(handle);
  {
    std::lock_guard<std::mutex> lock(g_trx_map_mutex);
    g_trx_map.erase(trx);
  }
}

void adapter_trx_promote(trx_t *trx) {
  if (!trx || trx->id == 0) return;
  isofuzz_trx_t handle = get_trx_handle(trx);
  if (handle) {
    isofuzz_trx_promote(handle, trx->id);
  }
}

void adapter_schedule_op(trx_t *trx, IsoFuzzSchedulerIntent intent) {
  isofuzz_trx_t handle = get_trx_handle(trx);
  if (handle) {
    isofuzz_schedule_op(handle, intent);
  }
}

void adapter_log_op(trx_t *trx, IsoFuzzOpType op_type,
                    const IsoFuzzObject &object, uint64_t last_writer_trx_id) {
  isofuzz_trx_t handle = get_trx_handle(trx);
  if (handle) {
    isofuzz_log_op(handle, op_type, object, last_writer_trx_id);
  }
}