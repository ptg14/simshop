package db

import (
	"context"
	"database/sql"
	"errors"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/ptg14/simshop/backend/internal/config"
)

// counter records the number of calls and lets each call return a
// pre-programmed error sequence. Once the sequence is exhausted it
// returns nil, simulating "DB became reachable after N attempts".
// Satisfies the unexported `pinger` interface declared in db.go.
type counter struct {
	calls   int32
	failN   int32 // first failN calls return errFail; subsequent return nil
	errFail error
}

func (c *counter) PingContext(_ context.Context) error {
	n := atomic.AddInt32(&c.calls, 1)
	if n <= c.failN {
		return c.errFail
	}
	return nil
}

// TestPingWithRetrySucceedsFirstTry verifies the happy path: one
// successful ping → one call, no sleep, no error.
func TestPingWithRetrySucceedsFirstTry(t *testing.T) {
	c := &counter{failN: 0}
	err := pingWithRetry(asPinger(c), &config.Config{
		DBRetryAttempts: 5,
		DBRetryInterval: time.Millisecond,
	})
	if err != nil {
		t.Fatalf("expected nil error, got %v", err)
	}
	if got := atomic.LoadInt32(&c.calls); got != 1 {
		t.Fatalf("expected 1 ping call, got %d", got)
	}
}

// TestPingWithRetryEventualSuccess verifies the retry loop: first
// failN attempts return an error, the (failN+1)th returns nil. Total
// call count must equal failN+1.
func TestPingWithRetryEventualSuccess(t *testing.T) {
	c := &counter{failN: 3, errFail: errors.New("boom")}
	start := time.Now()
	err := pingWithRetry(asPinger(c), &config.Config{
		DBRetryAttempts: 10,
		DBRetryInterval: 5 * time.Millisecond,
	})
	elapsed := time.Since(start)
	if err != nil {
		t.Fatalf("expected nil error after retry, got %v", err)
	}
	if got := atomic.LoadInt32(&c.calls); got != 4 {
		t.Fatalf("expected 4 ping calls, got %d", got)
	}
	// 3 sleeps of 5ms each = 15ms minimum; allow generous slack for
	// CI scheduler jitter.
	if elapsed < 10*time.Millisecond {
		t.Fatalf("expected ≥10ms elapsed for 3 retries, got %v", elapsed)
	}
}

// TestPingWithRetryExhausted verifies that when every attempt
// fails, the function returns a non-nil error whose message includes
// the configured attempt count and the underlying cause.
func TestPingWithRetryExhausted(t *testing.T) {
	c := &counter{failN: 100, errFail: errors.New("db down")}
	err := pingWithRetry(asPinger(c), &config.Config{
		DBRetryAttempts: 3,
		DBRetryInterval: time.Millisecond,
	})
	if err == nil {
		t.Fatal("expected error after exhausting retries, got nil")
	}
	if !strings.Contains(err.Error(), "3 attempts") {
		t.Fatalf("expected error to mention attempt count, got: %v", err)
	}
	if !strings.Contains(err.Error(), "db down") {
		t.Fatalf("expected error to wrap underlying cause, got: %v", err)
	}
	if got := atomic.LoadInt32(&c.calls); got != 3 {
		t.Fatalf("expected 3 ping calls (one per attempt), got %d", got)
	}
}

// TestPingWithRetryDefaultsApplied covers the guard rails: a
// misconfigured 0 or negative attempt count is clamped to 1, and
// a non-positive interval is clamped to 1s. We can't observe the
// interval clamp directly in a unit test (sleeping 1s in tests is
// unacceptable) but we CAN observe that a 0-attempt config still
// performs exactly one ping before returning.
func TestPingWithRetryDefaultsApplied(t *testing.T) {
	c := &counter{failN: 5, errFail: errors.New("nope")}
	err := pingWithRetry(asPinger(c), &config.Config{
		DBRetryAttempts: 0,            // → clamped to 1
		DBRetryInterval: -time.Second, // → clamped to 1s (not exercised here)
	})
	if err == nil {
		t.Fatal("expected error from 1 attempt against always-failing pinger")
	}
	if got := atomic.LoadInt32(&c.calls); got != 1 {
		t.Fatalf("expected 1 ping call (attempts clamped to 1), got %d", got)
	}
}

// asPinger widens a *counter to the pinger interface expected by
// pingWithRetry. The interface itself is unexported, so the test
// cannot declare one of its own; the function-local adapter keeps
// the production API clean while letting the test inject a stub.
func asPinger(c *counter) pinger { return c }

// Compile-time check: *sql.DB's PingContext signature matches pinger,
// confirming the production call site at New() is type-correct after
// the refactor that introduced the pinger interface.
var _ pinger = (*sql.DB)(nil)
