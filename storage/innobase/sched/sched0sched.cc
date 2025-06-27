#include "sched0sched.h"
#include "srv0srv.h"

#include <atomic>
#include <condition_variable>
#include <mutex>
#include <queue>
#include <random>
#include <string>
#include <thread>
#include <unordered_map>

// A struct to manage the waiting state for a single transaction.
struct TrxWaitInfo {
  std::mutex mtx;
  std::condition_variable cv;
  bool is_ready = false;
};

// A queue entry for the scheduler.
typedef std::pair<int, trx_t *> TrxPriority;

// Global scheduler state
static std::thread scheduler_thread;
static std::atomic<bool> scheduler_running(false);

// Mutex protecting the main scheduler_queue and the trx_wait_map
static std::mutex scheduler_global_mutex;

// Condition variable to wake up the scheduler thread when new work arrives.
static std::condition_variable scheduler_wakeup_cv;

// Map from a transaction to its personal waiting-room (CV and mutex).
static std::unordered_map<trx_t *, std::unique_ptr<TrxWaitInfo>> trx_wait_map;

// The main priority queue of transactions waiting for their turn.
struct CompareTrxPriority {
  bool operator()(const TrxPriority &a, const TrxPriority &b) const {
    return a.first > b.first;
  }
};
static std::priority_queue<TrxPriority, std::vector<TrxPriority>,
                           CompareTrxPriority>
    scheduler_queue;

// --- RNG Initialization ---
static std::mt19937 rng;
static std::atomic<bool> rng_initialized(false);

static void init_rng() {
  if (rng_initialized.load(std::memory_order_acquire)) return;

  const char *seed_str = std::getenv("RANDOM_SEED");
  int seed = 42;
  if (seed_str != nullptr) {
    try {
      seed = std::stoi(seed_str);
    } catch (const std::exception &) {
      // Keep default seed if conversion fails
    }
  }
  rng.seed(seed);
  rng_initialized.store(true, std::memory_order_release);
}

static int get_random_priority() {
  if (!rng_initialized.load(std::memory_order_acquire)) {
    init_rng();
  }
  std::uniform_int_distribution<int> dist(0, INT_MAX);
  return dist(rng);
}

// --- Main Scheduler Thread Logic ---
static void trx_scheduler_run() {
  while (scheduler_running.load(std::memory_order_acquire)) {
    std::unique_ptr<TrxWaitInfo> wait_info_ptr;
    trx_t *next_trx = nullptr;

    {
      std::unique_lock lock(scheduler_global_mutex);
      scheduler_wakeup_cv.wait(lock, [] {
        return !scheduler_running.load(std::memory_order_acquire) ||
               !scheduler_queue.empty();
      });

      if (!scheduler_running.load(std::memory_order_acquire)) {
        break;
      }

      if (!scheduler_queue.empty()) {
        next_trx = scheduler_queue.top().second;
        scheduler_queue.pop();

        // Find the transaction's personal wait info.
        auto it = trx_wait_map.find(next_trx);
        if (it != trx_wait_map.end()) {
          wait_info_ptr = std::move(it->second);
          // The transaction is now being processed, remove it from the map.
          trx_wait_map.erase(it);
        }
      }
    }

    // Unblock the chosen transaction outside the global lock.
    if (wait_info_ptr && next_trx) {
      std::unique_lock trx_lock(wait_info_ptr->mtx);
      wait_info_ptr->is_ready = true;
      trx_lock.unlock();
      wait_info_ptr->cv.notify_one();  // Wake up ONLY the chosen thread.
    }
  }
}

void init_scheduler_if_needed() {
  bool already_running =
      scheduler_running.exchange(true, std::memory_order_acq_rel);
  if (!already_running) {
    scheduler_thread = std::thread(trx_scheduler_run);
  }
}

void trx_scheduler_request(trx_t *trx) {
  init_scheduler_if_needed();

  // Create a new wait info struct for this request.
  auto wait_info = std::make_unique<TrxWaitInfo>();
  // Get a pointer to it to wait on.
  TrxWaitInfo *wait_info_ptr = wait_info.get();

  {
    std::lock_guard lock(scheduler_global_mutex);
    // Add the transaction to the main queue.
    scheduler_queue.push({get_random_priority(), trx});
    // Store its personal wait info in the map.
    trx_wait_map[trx] = std::move(wait_info);
  }

  // Notify the scheduler thread that there is new work.
  scheduler_wakeup_cv.notify_one();

  // Block this thread in its personal waiting room.
  std::unique_lock trx_lock(wait_info_ptr->mtx);
  wait_info_ptr->cv.wait(trx_lock,
                         [wait_info_ptr] { return wait_info_ptr->is_ready; });
}

// This function is now deprecated and does nothing, as the scheduler manages
// the state. It is kept for now to avoid breaking existing instrumentation
// calls, but will be removed.
void trx_scheduler_release(trx_t * /*trx*/) {
  // NO-OP
}

void trx_shutdown_scheduler() {
  if (scheduler_running.exchange(false, std::memory_order_acq_rel)) {
    // Wake up the scheduler thread so it can exit its loop.
    scheduler_wakeup_cv.notify_one();
    if (scheduler_thread.joinable()) {
      scheduler_thread.join();
    }
    // Clean up any remaining waiters to prevent deadlocks on shutdown.
    std::lock_guard lock(scheduler_global_mutex);
    for (auto &pair : trx_wait_map) {
      pair.second->is_ready = true;
      pair.second->cv.notify_all();
    }
    trx_wait_map.clear();
  }
}