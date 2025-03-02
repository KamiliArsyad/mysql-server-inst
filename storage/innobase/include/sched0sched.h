//
// Created by arkamili on 2/27/25.
//

#ifndef SCHED0SCHED_H
#define SCHED0SCHED_H

#include "trx0trx.h"

void init_scheduler_if_needed();

void trx_scheduler_request(trx_t *trx, event_type_t event_type);

void trx_scheduler_release(trx_t *trx);

#endif //SCHED0SCHED_H
