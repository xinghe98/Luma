package main

import (
	"errors"
	"flag"
	"fmt"
	"net/http"
	"net/url"
)

func dispatch(c client, group, action string, args []string) error {
	switch group + "/" + action {
	case "family/issue":
		return issueFamilyToken(c, args)
	case "sources/list":
		return c.call(http.MethodGet, "/api/v1/sources", nil)
	case "users/list":
		return c.call(http.MethodGet, "/api/v1/admin/users", nil)
	case "users/create":
		flags := flag.NewFlagSet("users create", flag.ContinueOnError)
		name := flags.String("name", "", "member display name")
		if err := flags.Parse(args); err != nil {
			return err
		}
		return c.call(http.MethodPost, "/api/v1/admin/users", map[string]any{"name": *name})
	case "users/update":
		flags := flag.NewFlagSet("users update", flag.ContinueOnError)
		id := flags.String("id", "", "user id")
		name := flags.String("name", "", "new display name")
		enabled := flags.String("enabled", "", "true or false")
		if err := flags.Parse(args); err != nil {
			return err
		}
		body := map[string]any{}
		if *name != "" {
			body["name"] = *name
		}
		if *enabled != "" {
			if *enabled != "true" && *enabled != "false" {
				return errors.New("-enabled must be true or false")
			}
			body["enabled"] = *enabled == "true"
		}
		return c.call(http.MethodPatch, "/api/v1/admin/users/"+url.PathEscape(*id), body)
	case "tokens/list":
		flags, user, _, _, err := tokenFlags(action, args)
		if err != nil {
			return err
		}
		_ = flags
		return c.call(http.MethodGet, "/api/v1/admin/users/"+url.PathEscape(user)+"/tokens", nil)
	case "tokens/create":
		_, user, name, expires, err := tokenFlags(action, args)
		if err != nil {
			return err
		}
		body := map[string]any{"name": name}
		if expires != "" {
			body["expires_at"] = expires
		}
		return c.call(http.MethodPost, "/api/v1/admin/users/"+url.PathEscape(user)+"/tokens", body)
	case "tokens/revoke":
		flags := flag.NewFlagSet("tokens revoke", flag.ContinueOnError)
		id := flags.String("id", "", "token id")
		if err := flags.Parse(args); err != nil {
			return err
		}
		return c.call(http.MethodDelete, "/api/v1/admin/tokens/"+url.PathEscape(*id), nil)
	case "grants/list", "grants/add", "grants/remove":
		flags := flag.NewFlagSet(group+" "+action, flag.ContinueOnError)
		user := flags.String("user", "", "user id")
		source := flags.String("source", "", "source id")
		if err := flags.Parse(args); err != nil {
			return err
		}
		endpoint := "/api/v1/admin/users/" + url.PathEscape(*user) + "/sources"
		if action == "list" {
			return c.call(http.MethodGet, endpoint, nil)
		}
		if *source == "" {
			return errors.New("-source is required")
		}
		endpoint += "/" + url.PathEscape(*source)
		method := http.MethodPut
		if action == "remove" {
			method = http.MethodDelete
		}
		return c.call(method, endpoint, nil)
	default:
		return fmt.Errorf("unknown command %s %s", group, action)
	}
}

func tokenFlags(action string, args []string) (*flag.FlagSet, string, string, string, error) {
	flags := flag.NewFlagSet("tokens "+action, flag.ContinueOnError)
	user := flags.String("user", "", "user id")
	name := flags.String("name", "", "token name, e.g. Alice phone")
	expires := flags.String("expires", "", "optional RFC3339 expiry")
	if err := flags.Parse(args); err != nil {
		return flags, "", "", "", err
	}
	if *user == "" {
		return flags, "", "", "", errors.New("-user is required")
	}
	return flags, *user, *name, *expires, nil
}
