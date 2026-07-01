package models_test

import (
	"testing"

	"github.com/ptg14/simshop/backend/models"
)

// TestEventApplyToPercent verifies percent discount math.
func TestEventApplyToPercent(t *testing.T) {
	e := models.Event{
		DiscountType:  models.DiscountPercent,
		DiscountValue: 20,
	}
	if got := e.ApplyTo(100000); got != 80000 {
		t.Errorf("ApplyTo(100000) = %v, want 80000", got)
	}
}

// TestEventApplyToFixed verifies flat-amount discount math.
func TestEventApplyToFixed(t *testing.T) {
	e := models.Event{
		DiscountType:  models.DiscountFixed,
		DiscountValue: 50000,
	}
	if got := e.ApplyTo(200000); got != 150000 {
		t.Errorf("ApplyTo(200000) = %v, want 150000", got)
	}
}

// TestEventApplyToClampsAtZero makes sure a discount larger than the
// price never produces a negative price tag.
func TestEventApplyToClampsAtZero(t *testing.T) {
	e := models.Event{
		DiscountType:  models.DiscountFixed,
		DiscountValue: 999999,
	}
	if got := e.ApplyTo(100); got != 0 {
		t.Errorf("ApplyTo(100) with huge discount = %v, want 0", got)
	}

	// Percent case: -200% would also go negative.
	big := models.Event{
		DiscountType:  models.DiscountPercent,
		DiscountValue: 200,
	}
	if got := big.ApplyTo(100); got != 0 {
		t.Errorf("ApplyTo(100) with 200%% discount = %v, want 0", got)
	}
}

// TestEventApplyToUnknownTypeLeavesPriceUnchanged is a defense-in-depth
// check — an empty DiscountType shouldn't accidentally zero the price.
func TestEventApplyToUnknownTypeLeavesPriceUnchanged(t *testing.T) {
	e := models.Event{
		DiscountType:  "",
		DiscountValue: 50,
	}
	if got := e.ApplyTo(1000); got != 1000 {
		t.Errorf("ApplyTo with unknown type = %v, want 1000 (unchanged)", got)
	}
}

// TestEventIsActive_NoEndTime: nil end_time means the event never expires.
func TestEventIsActive_NoEndTime(t *testing.T) {
	e := models.Event{EndTime: nil}
	if !e.IsActive(1700000000) {
		t.Error("event with nil EndTime should be active")
	}
}

// TestEventIsActive_FutureEndTime: end_time in the future is active.
func TestEventIsActive_FutureEndTime(t *testing.T) {
	e := models.Event{EndTime: ptrInt64(2000)}
	if !e.IsActive(1000) {
		t.Error("event ending after now should be active")
	}
}

// TestEventIsActive_PastEndTime: end_time strictly in the past is inactive.
// The boundary case (end_time == now) must also be inactive.
func TestEventIsActive_PastEndTime(t *testing.T) {
	e := models.Event{EndTime: ptrInt64(1000)}
	if e.IsActive(2000) {
		t.Error("event with past EndTime should be inactive")
	}
	if e.IsActive(1000) {
		t.Error("event whose EndTime == now should be inactive (boundary)")
	}
}

func ptrInt64(v int64) *int64 { return &v }