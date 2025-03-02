#include "srv0srv.h"
#include "sched0sched.h"

#include <atomic>
#include <condition_variable>
#include <mutex>
#include <queue>
#include <unordered_map>

static std::mutex scheduler_mutex;
static std::condition_variable scheduler_cv;

static std::queue<trx_t *> scheduler_queue;
static std::unordered_map<trx_t*, bool> scheduler_blocked;

static std::thread scheduler_thread;
static std::atomic<bool> scheduler_running;
//
// static void trx_schedule_waker_run() {
//   while (scheduler_running.load(std::memory_order_acquire)) {
//
//   }
// }
//
static void trx_scheduler_run() {
  while (scheduler_running.load(std::memory_order_acquire)) {
    std::unique_lock lock(scheduler_mutex);

    scheduler_cv.wait(lock,
      [] {
        return !scheduler_queue.empty() || !scheduler_running.load();
      });

    trx_t* next_trx = scheduler_queue.front();  scheduler_queue.pop();
    scheduler_blocked.erase(next_trx);

    scheduler_cv.notify_all();
  }
}

void init_scheduler_if_needed() {
  if (!scheduler_running.exchange(true, std::memory_order_acq_rel)) {
    scheduler_thread = std::thread(&trx_scheduler_run);
  }
}

void trx_scheduler_request(trx_t *trx, event_type_t event_type) {
  init_scheduler_if_needed();
  std::unique_lock lock(scheduler_mutex);

  // Put into queue if not yet
  if (!scheduler_blocked.contains(trx)) {
    scheduler_queue.push(trx);
    scheduler_blocked[trx] = true;
    scheduler_cv.notify_all();
  }

  scheduler_cv.wait(
    lock,
    [&] {
      return !scheduler_blocked.contains(trx);
    });
}

void trx_scheduler_release(trx_t *trx) {
  std::unique_lock lock(scheduler_mutex);

  scheduler_blocked.erase(trx);
  scheduler_cv.notify_all();
}