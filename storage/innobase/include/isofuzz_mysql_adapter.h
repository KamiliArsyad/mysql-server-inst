#ifndef ISOFUZZ_MYSQL_ADAPTER_H
#define ISOFUZZ_MYSQL_ADAPTER_H

// MySQL's internal headers are needed here because the adapter's interface
// is defined in terms of MySQL types like trx_t.
#include "trx0trx.h"

// Include the public API of the generic library to get the enums and
// IsoFuzzObject struct. This is the ONLY dependency on the library in the
// adapter's public header.
#include "isofuzz.h"

/*
 * ========================================================================
 * Adapter Lifecycle
 * ========================================================================
 */

/** @brief Initializes the underlying IsoFuzz library. */
void adapter_init();

/** @brief Shuts down the underlying IsoFuzz library. */
void adapter_shutdown();

/*
 * ========================================================================
 * Transaction Boundary Hooks
 * ========================================================================
 */

/**
 * @brief Handles the start of a new transaction. Called from trx_start_low.
 * @param trx The MySQL transaction object.
 */
void adapter_trx_start(trx_t *trx);

/**
 * @brief Handles the commit of a transaction. Called from trx_commit_low.
 * @param trx The MySQL transaction object.
 */
void adapter_trx_commit(trx_t *trx);

/**
 * @brief Handles the promotion of a RO->RW transaction. Called from
 * trx_set_rw_mode.
 * @param trx The MySQL transaction object.
 */
void adapter_trx_promote(trx_t *trx);

/*
 * ========================================================================
 * Main Instrumentation Hook
 * ========================================================================
 */

void adapter_schedule_op(trx_t *trx, IsoFuzzSchedulerIntent intent);

void adapter_log_op(trx_t *trx, IsoFuzzOpType op_type,
                    const IsoFuzzObject &object, uint64_t last_writer_trx_id);

#endif  // ISOFUZZ_MYSQL_ADAPTER_H