package main

import (
	"errors"
	"flag"
	"fmt"
	"net/http"
	"os"
	"time"
)

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, "luma-admin:", err)
		os.Exit(1)
	}
}

func run(args []string) error {
	global := flag.NewFlagSet("luma-admin", flag.ContinueOnError)
	server := global.String("server", "http://127.0.0.1:8080", "Luma server origin")
	tokenFile := global.String("token-file", os.Getenv("LUMA_ADMIN_TOKEN_FILE"), "file containing the administrator token")
	allowInsecure := global.Bool("allow-insecure", false, "allow plain HTTP to a non-loopback host")
	if err := global.Parse(args); err != nil {
		return err
	}
	remaining := global.Args()
	if len(remaining) < 2 {
		return errors.New("usage: luma-admin [global flags] family issue | sources|users|tokens|grants <action>")
	}
	origin, err := validateAdminOrigin(*server, *allowInsecure)
	if err != nil {
		return err
	}
	token, err := readAdminToken(*tokenFile)
	if err != nil {
		return err
	}
	c := client{origin: origin, token: token, http: &http.Client{Timeout: 15 * time.Second}}
	return dispatch(c, remaining[0], remaining[1], remaining[2:])
}
