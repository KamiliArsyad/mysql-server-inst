#include "isofuzz0isofuzz.h"
#include "sched0sched.h"
#include "trx0trx.h"

#include <fstream>
#include <iostream>
#include <mutex>
#include <sstream>
#include <thread>

// Internal Logging State
static std::ofstream g_file;
static std::mutex file_lock;

static std::ostream &get_out_stream() {
  static bool init = false;
  static std::ostream *out_ptr = &std::cout;
  if (!init) {
    init = true;
    const char *path = std::getenv("OUT_FILE");
    if (path) {
      g_file.open(path, std::ios::out | std::ios::app);
      if (g_file.is_open()) {
        out_ptr = &g_file;
      }
    }
  }
  return *out_ptr;
}

static const char *op_type_to_string(IsoFuzzOpType op_type) {
  switch (op_type) {
    case IsoFuzzOpType::READ:
      return "READ";
    case IsoFuzzOpType::WRITE_UPDATE:
      return "UPDATE";
    case IsoFuzzOpType::WRITE_INSERT:
      return "INSERT";
    default:
      return "UNKNOWN";
  }
}

// --- API Implementation ---

void isofuzz_schedule_operation(isofuzz_trx_handle_t handle) {
  trx_t *trx = static_cast<trx_t *>(handle);
  if (trx == nullptr) {
    return;
  }
  // This is the gatekeeper. It calls the scheduler and blocks.
  trx_scheduler_request(trx);
}

void isofuzz_log_column_operation(isofuzz_trx_handle_t handle,
                                  IsoFuzzOpType op_type,
                                  const IsoFuzzObject &object,
                                  uint64_t last_writer_trx_id) {
  trx_t *trx = static_cast<trx_t *>(handle);
  if (trx == nullptr) {
    return;
  }

  // This function only logs. It does not schedule.
  std::basic_stringstream<char> result;
  result << std::this_thread::get_id() << "\t" << trx->id << "\t"
         << op_type_to_string(op_type) << "\t" << object.table_name << "\t"
         << (object.column_name ? object.column_name : "N/A") << "\t"
         << object.row_identifier << "\t";

  if (op_type == IsoFuzzOpType::READ ||
      op_type == IsoFuzzOpType::WRITE_UPDATE) {
    result << last_writer_trx_id;
  }

  result << std::endl;

  std::unique_lock lock(file_lock);
  get_out_stream() << result.str();
}