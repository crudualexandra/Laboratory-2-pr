# Laboratory 2

Class: Network Programming

# **Concurrent HTTP File Server**

## **Purpose**

We extended our previous single-threaded server by adding a thread pool for concurrency, a request counter to illustrate race conditions and locks, and a rate-limiting system per IP to protect against spam. Each feature was validated with dedicated tests and screenshots.

## **Theoretical notes**

When learning about concurrency, beware that there are many conflicting definitions, examples and analogies floating around, some of which are misleading and might cause you unnecessary suffering. I recommend starting with the resources linked above.

Note that high-level programmers define concurrency differently from low-level programmers. Therefore, there are two “correct” definitions of concurrency:

- In the **OS** (low-level) tradition:
    - Concurrency = tasks overlap in time (including by interleaving)
    - Parallelism = tasks run simultaneously (on multiple processors)
    - Parallel **implies** Concurrent
        - All parallel tasks are also concurrent
        - Not all concurrent tasks are parallel
- In the [**PLT**](https://en.wikipedia.org/wiki/Programming_language_theory) (high-level) tradition:
    - Concurrency is a language concept: constructing a program as independent parts
    - Parallelism is a hardware concept: executing computations on multiple processors simultaneously
    - Parallelism and Concurrency are **orthogonal**
        - A concurrent program may or may not execute in parallel
        - A parallel computation may or may not have the notion of concurrency in its structure.

As a consequence, the answer to “does parallel imply concurrent?” depends on the school of thought. As you will see, all the linked resources abide by the second school of thought. In general, the high-level view of concurrency is becoming more predominant, so it is important that you are aware of it and prove your understanding when answering the questions.

To make it clear, if your answer is along the lines of “concurrency is a more general form of parallelism” or “concurrency is when tasks *seemingly* execute at the same time”, I will consider your answer **wrong**. You must at least mention the second definition.

## **Work progress**

**Key new features**

1. **Multithreading (ThreadPoolExecutor)**
    - Handles multiple connections in parallel.
    - Controlled via --workers (e.g., 8).
    - Adds time.sleep(1) to simulate work.
2. **Request Counter (per-file)**
    - A shared Counter dictionary increments each time a file is requested.
    - Implemented *first naively* (no lock → race condition).
    - Then fixed using threading.Lock() around the update → thread-safe.
3. **Rate Limiting (per client IP)**
    - Keeps timestamps of each request from an IP.
    - Allows ~5 requests/second.
    - If exceeded → returns HTTP 429 “Too Many Requests”.
    - Thread-safe using a lock.

**Build once**
```bash

docker compose build

```

![image.png](Laboratory%202/image.png)

## **A) Baseline: single-thread server (delay ≈ 1s)**

Start a **one-off container** so it not needed to edit compose for each variant:

```bash

CID=$(docker compose run -d -p 8001:8001 web \
python [server.py](http://server.py/) /app/site --host 0.0.0.0 --port 8001 \
--workers 1 --delay 1 --counter-mode locked --rate 0)
docker inspect $CID --format '{{.Args}}'
docker logs -f $CID | sed -n '1,3p'

```

![image.png](Laboratory%202/image%201.png)

### Verifying args and basic reachability:

```bash

docker inspect $CID --format '{{.Args}}'

docker logs -f $CID | sed -n '1,3p’
curl -i [http://localhost:8001/](http://localhost:8000/)

```

![image.png](Laboratory%202/image%202.png)

![image.png](Laboratory%202/image%203.png)

![image.png](Laboratory%202/image%204.png)

### **Measure baseline (10 concurrent GETs to /books/):**

```bash

time N=10 bash tests/spawn_client_requests.sh localhost 8001 /books/

```

![image.png](Laboratory%202/image%2018.png)



The server runs single-threaded and handles 10 concurrent requests sequentially (≈ N×delay total), establishing the baseline.

**Requirement:** ✅ Baseline for comparison is demonstrated.

## **B) Multithreaded server (workers=8, delay=1s)**

```bash

CID=$(docker compose run -d -p 8001:8001 web \
python [server.py](http://server.py/) /app/site --host 0.0.0.0 --port 8001 \
--workers 8 --delay 1 --counter-mode locked --rate 0)
docker inspect $CID --format '{{.Args}}'

```

![image.png](Laboratory%202/image%207.png)

![image.png](Laboratory%202/image%208.png)

**Wall-time with same 10 requests:**

```bash

time N=10 bash tests/spawn_client_requests.sh localhost 8001 /books/

```

![image.png](Laboratory%202/image%2019.png)

The server runs with a thread pool and completes the same 10 concurrent requests faster than the baseline, proving parallel handling.

**Requirement:** ✅ Concurrent, multithreaded processing is demonstrated.

## **C) Counter feature — race vs lock**

**C1) Naive counter (race on purpose)**
```bash

CID=$(docker compose run -d -p 8001:8001 web \
python [server.py](http://server.py/) /app/site --host 0.0.0.0 --port 8001 \
--workers 8 --delay 0 --counter-mode naive --counter-sleep 0.002 --rate 0)

```

![image.png](Laboratory%202/image%2010.png)

Check current listing (note “Hits” for a file, e.g., /books/sample.pdf):0

```bash

curl -s [http://localhost:8001/](http://localhost:8001/) | sed -n '1,140p'

```

After the command +1 hit

![image.png](Laboratory%202/image%2011.png)

Hammer the same file 10× concurrently:

```bash

N=10 bash tests/spawn_client_requests.sh localhost 8001 /books/sample.pdf
curl -s [http://localhost:8001/](http://localhost:8001/) | sed -n '1,140p'

```

Expect the Hits **increase by less than 10** (lost increments).(it got only 2 more)

![image.png](Laboratory%202/image%2012.png)

Listing above showing **incorrect** Hits total (race condition).

Under concurrent requests the Hits value increases by less than the actual request count (e.g., 3 after 10), showing a race condition.

**Requirement:** ✅ Race condition on shared state is clearly demonstrated.

**C2) Locked counter (race fixed)**
```bash

CID=$(docker compose run -d -p 8001:8001 web \
python [server.py](http://server.py/) /app/site --host 0.0.0.0 --port 8001 \
--workers 8 --delay 0 --counter-mode locked --counter-sleep 0.002 --rate 0)

```

![image.png](Laboratory%202/image%2013.png)

Running 10:

```bash

N=10 bash tests/spawn_client_requests.sh localhost 8001 /books/sample.pdf
curl -s [http://localhost:8001/](http://localhost:8001/) | sed -n '1,140p'

```

![image.png](Laboratory%202/image%2014.png)

Now hits equal exactly +10.

With locking enabled the Hits value increases exactly by the number of requests (e.g., +10), removing the race.

**Requirement:** ✅ Synchronization fix is demonstrated.

## **D) Rate limiting per IP (~5 req/s)**

Start with limiter enabled:

```bash

CID=$(docker compose run -d -p 8001:8001 web \
python [server.py](http://server.py/) /app/site --host 0.0.0.0 --port 8001 \
--workers 16 --delay 0 --counter-mode locked --rate 5)
docker logs -f $CID | sed -n '1,3p'

```

### **Polite client (~4 rps):**

```bash

python3 tests/rate_limit_benchmark.py --label polite \
--url [http://localhost:8001/books/sample.pdf](http://localhost:8001/books/sample.pdf) --rps 4 --duration 10

```

![image.png](Laboratory%202/image%2015.png)

A client sending ~4 rps achieves nearly all 200 OKs with 0× 429, showing that traffic below the 5 rps limit is allowed.

**Requirement:** ✅ Behavior below the limit is correct.

### **Spam client (~20 rps)** — run in **another terminal:**

```bash

python3 tests/rate_limit_benchmark.py --label spam \
--url [http://localhost:8001/books/sample.pdf](http://localhost:8001/books/sample.pdf) --rps 20 --duration 10

```

![image.png](Laboratory%202/image%2016.png)

A client sending ~20 rps is capped to ~5 ok/s and receives many 429 responses, proving the per-IP limiter works.

**Requirement:** ✅ Throttling above the limit is enforced.

| **Client** | **Target rps** | **Duration** | **Requests sent** | **OK/s** | **429/s** | **OK total** | **429 total** | **Verdict** |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Polite | 4 rps | 10 s | 41 | **4.10** | **0.00** | ~41 | 0 | ✅ Below the limit: nearly all requests succeed. |
| Spam | 20 rps | 10 s | 201 | **5.40** | **14.70** | ~54 | ~147 | ✅ Above the limit: successes cap ≈5 rps, excess get 429. |

 The token-bucket limiter allows fair throughput (~5 rps OK) while throttling a spammer with 429 responses.

[https://www.notion.so](https://www.notion.so)

## **Conclusion**

By implementing both a single-threaded and a multithreaded HTTP server, then measuring wall-time for 10 concurrent requests with a controlled 1-second delay, you directly observed the core benefit of concurrency: **throughput scales roughly with the number of worker threads** (ceil(N/workers)×delay), while the single thread processes strictly in sequence. Adding the **Hits counter** first without synchronization exposed a classic **race condition** (lost increments), and then fixing it with a **lock** demonstrated how shared state must be protected to ensure correctness under parallel execution. Finally, the **per-IP rate limiter** (token-bucket style) showed how concurrency needs **fairness and back-pressure** so one noisy client can’t starve others, reinforcing the difference between **performance** (more workers) and **control** (bounded request rate). Packaging and testing everything in **Docker** made results reproducible, while the scripts built a habit of **measuring** rather than guessing. Together, these steps give a practical, end-to-end understanding of threads, synchronization, and concurrency control in real networked systems.
