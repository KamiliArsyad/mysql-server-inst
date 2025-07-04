#include "isofuzz_mysql_adapter.h"
#include <mutex>
#include <unordered_map>

static std::mutex g_trx_map_mutex;
static std::unordered_map<trx_t *, isofuzz_trx_t> g_trx_map;

// A set to track which transactions we have already promoted.
// This prevents sending redundant PROMOTE events to the logger.
static std::mutex g_promoted_set_mutex;
static std::unordered_set<trx_t *> g_promoted_transactions;

/**
 * @brief Gets the IsoFuzz handle for a MySQL transaction and performs a
 * "just-in-time" promotion if needed.
 *
 * This function is the single, synchronized entry point for all operations.
 * It checks if a permanent trx->id has been assigned since the transaction
 * started. If it finds a new, un-promoted ID, it notifies the IsoFuzz library
 * exactly once.
 *
 * @param trx The MySQL transaction object.
 * @return The synchronized opaque handle, or nullptr if the trx is invalid.
 */
static isofuzz_trx_t sync_and_get_handle(trx_t *trx) {
  if (!trx) return nullptr;

  isofuzz_trx_t handle;
  {
    std::lock_guard<std::mutex> lock(g_trx_map_mutex);
    auto it = g_trx_map.find(trx);
    if (it == g_trx_map.end()) {
      return nullptr;  // Should not happen for an active transaction
    }
    handle = it->second;
  }

  // Just-in-Time Promotion Check:
  // If the transaction now has a real ID, and we haven't promoted it yet...
  if (trx->id != 0) {
    std::lock_guard<std::mutex> lock(g_promoted_set_mutex);
    if (g_promoted_transactions.find(trx) == g_promoted_transactions.end()) {
      // ...then promote it now.
      isofuzz_trx_promote(handle, trx->id);
      // And remember that we've done so.
      g_promoted_transactions.insert(trx);
    }
  }

  return handle;
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
  isofuzz_trx_t handle = sync_and_get_handle(trx);
  if (!handle) return;
  isofuzz_trx_commit(handle);
  isofuzz_trx_end(handle);
  {
    std::lock_guard<std::mutex> lock(g_trx_map_mutex);
    g_trx_map.erase(trx);
  }
  {
    std::lock_guard<std::mutex> lock(g_promoted_set_mutex);
    g_promoted_transactions.erase(trx);
  }
}

void adapter_trx_promote(trx_t *trx) {
  sync_and_get_handle(trx);
}

void adapter_schedule_op(trx_t *trx, IsoFuzzSchedulerIntent intent) {
  isofuzz_trx_t handle = sync_and_get_handle(trx);
  if (handle) {
    isofuzz_schedule_op(handle, intent);
  }
}

void adapter_log_op(trx_t *trx, IsoFuzzOpType op_type,
                    const IsoFuzzObject &object, uint64_t last_writer_trx_id) {
  isofuzz_trx_t handle = sync_and_get_handle(trx);
  if (handle) {
    isofuzz_log_op(handle, op_type, object, last_writer_trx_id);
  }
}