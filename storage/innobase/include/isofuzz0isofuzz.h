#ifndef ISOFUZZ0ISOFUZZ_H
#define ISOFUZZ0ISOFUZZ_H

#include <cstdint>

typedef void *isofuzz_trx_handle_t;

enum class IsoFuzzOpType { READ, WRITE_UPDATE, WRITE_INSERT };

struct IsoFuzzObject {
  const char *table_name;
  const char *column_name;
  uint64_t row_identifier;
};

/***********************************************************************/ /**
 Schedules a logical data operation. This function is the "gatekeeper" and
 will block the calling thread until the central fuzzer scheduler allows
 it to proceed. This should be called ONCE per logical operation (e.g.,
 once for an entire UPDATE statement).

 @param[in]  handle            The opaque handle to the current transaction.
 */
void isofuzz_schedule_operation(isofuzz_trx_handle_t handle);

/***********************************************************************/ /**
 Logs the details of a specific data dependency. This function DOES NOT
 schedule and will not block. It is meant to be called after
 isofuzz_schedule_operation has returned, to record the fine-grained
 details of an operation (e.g., which columns were read or written).

 @param[in]  handle            The opaque handle to the current transaction.
 @param[in]  op_type           The type of operation.
 @param[in]  object            A description of the specific data object.
 @param[in]  last_writer_trx_id The transaction ID of the data's writer.
 */
void isofuzz_log_column_operation(isofuzz_trx_handle_t handle,
                                  IsoFuzzOpType op_type,
                                  const IsoFuzzObject &object,
                                  uint64_t last_writer_trx_id);

#endif  // ISOFUZZ0ISOFUZZ_H