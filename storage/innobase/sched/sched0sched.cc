#include "srv0srv.h"
#include "sched0sched.h"

#include <atomic>
#include <condition_variable>
#include <mutex>
#include <queue>
#include <unordered_map>

typedef std::pair<int, trx_t *> TrxPriority;

static std::mt19937 rng;
static std::atomic<bool> rng_initialized;
static std::mutex scheduler_mutex;
static std::condition_variable scheduler_cv;

static std::unordered_map<trx_t*, bool> scheduler_blocked;

static std::thread scheduler_thread;
static std::atomic<bool> scheduler_running;

struct CompareTrxPriority {
  bool operator()(const TrxPriority &a, const TrxPriority &b) const {
    return a.first > b.first;
  }
};

static std::priority_queue<TrxPriority, std::vector<TrxPriority>, CompareTrxPriority> scheduler_queue;

// The initialization will race, but it is fine as they are storing the same thing.
static void init_rng() {
  if (rng_initialized.load(std::memory_order::acq_rel)) return;

  const char* seed_str = std::getenv("RANDOM_SEED");
  int seed = 42;
  if (seed_str != nullptr) seed = std::stoi(seed_str);

  rng.seed(seed);
  rng_initialized.store(true, std::memory_order::acq_rel);
}

static int get_random_priority() {
  init_rng();
  std::uniform_int_distribution dist(0, INT_MAX);

  return dist(rng);
}

constexpr int PERIODIC_WAKE = 10;

static void trx_scheduler_run() {
  while (scheduler_running.load(std::memory_order_acquire)) {
    std::unique_lock lock(scheduler_mutex);

    scheduler_cv.wait(lock,
      [] {
        return !scheduler_queue.empty() || !scheduler_running.load();
      });

    trx_t* next_trx = scheduler_queue.top().second;  scheduler_queue.pop();
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
    int rnd_priority = get_random_priority();
    scheduler_queue.push({rnd_priority, trx});
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