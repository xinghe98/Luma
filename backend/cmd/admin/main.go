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
	username := global.String("username", os.Getenv("LUMA_ADMIN_USERNAME"), "administrator username")
	passwordFile := global.String("password-file", os.Getenv("LUMA_ADMIN_PASSWORD_FILE"), "file containing the administrator password")
	deviceKeyFile := global.String("device-key-file", os.Getenv("LUMA_ADMIN_DEVICE_KEY_FILE"), "file containing the installation device key")
	allowInsecure := global.Bool("allow-insecure", false, "allow plain HTTP to a non-loopback host")
	if err := global.Parse(args); err != nil {
		return err
	}
	remaining := global.Args()
	if len(remaining) < 2 {
		return errors.New("usage: luma-admin [global flags] sources|users|sessions|grants <action>")
	}
	origin, err := validateAdminOrigin(*server, *allowInsecure)
	if err != nil {
		return err
	}
	password, err := readAdminPassword(*passwordFile)
	if err != nil {
		return err
	}
	deviceKey, err := loadOrCreateAdminDeviceKey(*deviceKeyFile)
	if err != nil {
		return err
	}
	c := client{origin: origin, http: &http.Client{Timeout: 15 * time.Second}}
	if err := c.login(*username, password, deviceKey); err != nil {
		return err
	}
	defer func() { _ = c.logout() }()
	return dispatch(c, remaining[0], remaining[1], remaining[2:])
}
