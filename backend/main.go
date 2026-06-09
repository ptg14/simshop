// The original monolithic implementation has been refactored into a modular
// structure under the internal/ package. This file now only starts the server
// using the new server.Start function.

package main

import (
	"context"
	"log"
	"os"
	"os/signal"
	"syscall"

	"github.com/ptg14/simshop/backend/internal/server"
)

func main() {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Listen for interrupt/terminate signals and cancel context when received.
	sigs := make(chan os.Signal, 1)
	signal.Notify(sigs, os.Interrupt, syscall.SIGTERM)
	go func() {
		<-sigs
		log.Println("signal received, shutting down...")
		cancel()
	}()

	if err := server.Start(ctx); err != nil {
		log.Fatalf("server stopped with error: %v", err)
	}
}
