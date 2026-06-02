// The original monolithic implementation has been refactored into a modular
// structure under the internal/ package. This file now only starts the server
// using the new server.Start function.

package main

import (
    "log"

    "github.com/ptg14/simshop/backend/internal/server"
)

func main() {
    if err := server.Start(); err != nil {
        log.Fatalf("server stopped with error: %v", err)
    }
}
