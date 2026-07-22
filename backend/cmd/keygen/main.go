// Command keygen mints a fresh Ed25519 keypair for admin auth.
//
// Usage:
//
//	go run ./cmd/keygen
//	c -pub admin.key.pub
//
// By default the secret key is written to ./admin.key and the public
// key to ./admin.key.pub, both with 0600 permissions. The same hex
// values are also printed to stdout so you can verify the files
// round-tripped correctly. To skip writing entirely and only print,
// pass `-stdout` (handy for piping into another tool).
//
// SECURITY: treat admin.key as a credential. Anyone with the file
// can authenticate as admin on a server whose ADMIN_PUBLIC_KEY
// matches. Store it offline (USB, password manager attachment) and
// never commit it. The backend only ever sees the public key
// (hex-encoded in ADMIN_PUBLIC_KEY); the secret key only ever
// lives on the admin's device.
//
// This is intentionally a one-shot helper — it doesn't read any env
// vars, doesn't touch the DB, and doesn't print the secret key
// without also writing it (so you can't accidentally leak via a
// terminal scrollback without realising you have a file to chmod).
package main

import (
	"crypto/ed25519"
	"encoding/hex"
	"flag"
	"fmt"
	"os"
)

func main() {
	out := flag.String("out", "admin.key", "path for the secret key file (binary 64 bytes); pass -stdout to skip writing")
	pubOut := flag.String("pub", "admin.key.pub", "path for the public key file (binary 32 bytes)")
	stdoutOnly := flag.Bool("stdout", false, "print hex to stdout instead of writing binary files (advanced)")
	flag.Parse()

	pub, priv, err := ed25519.GenerateKey(nil)
	if err != nil {
		fmt.Fprintln(os.Stderr, "keygen:", err)
		os.Exit(1)
	}

	secretHex := hex.EncodeToString(priv)
	pubHex := hex.EncodeToString(pub)

	if *stdoutOnly {
		fmt.Println("=== Admin Ed25519 keypair (stdout only, nothing written) ===")
		fmt.Println()
		fmt.Println("Secret key (hex):")
		fmt.Println(secretHex)
		fmt.Println()
		fmt.Println("Public key (hex) — set as ADMIN_PUBLIC_KEY in backend/.env:")
		fmt.Println(pubHex)
		return
	}

	if err := os.WriteFile(*out, priv, 0600); err != nil {
		fmt.Fprintln(os.Stderr, "keygen: write secret:", err)
		os.Exit(1)
	}
	if err := os.WriteFile(*pubOut, pub, 0600); err != nil {
		fmt.Fprintln(os.Stderr, "keygen: write public:", err)
		os.Exit(1)
	}

	fmt.Println("=== Admin Ed25519 keypair ===")
	fmt.Println()
	fmt.Printf("Secret key: %s (binary, %d bytes, mode 0600)\n", *out, len(priv))
	fmt.Printf("Public key: %s (binary, %d bytes, mode 0600)\n", *pubOut, len(pub))
	fmt.Println()
	fmt.Println("Hex (verify the files round-trip):")
	fmt.Println("  secret:", secretHex)
	fmt.Println("  public:", pubHex)
	fmt.Println()
	fmt.Println("Next steps:")
	fmt.Println("  1. Back up admin.key somewhere offline (USB, password manager).")
	fmt.Printf("  2. Set ADMIN_PUBLIC_KEY=%s in backend/.env.\n", pubHex)
	fmt.Println("  3. Upload admin.key via the admin auth gate in the Flutter app.")
}
