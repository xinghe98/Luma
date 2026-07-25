// 管理命令通过账号登录获取设备会话，不支持旧 Token 签发或管理。
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
	case "sources/list":
		return c.call(http.MethodGet, "/api/v1/sources", nil)
	case "users/list":
		return c.call(http.MethodGet, "/api/v1/admin/users", nil)
	case "users/create":
		flags := flag.NewFlagSet("users create", flag.ContinueOnError)
		name := flags.String("name", "", "member display name")
		username := flags.String("username", "", "member username")
		passwordFile := flags.String("password-file", "", "file containing the member password")
		if err := flags.Parse(args); err != nil {
			return err
		}
		password, err := readAdminPassword(*passwordFile)
		if err != nil {
			return err
		}
		return c.call(http.MethodPost, "/api/v1/admin/users", map[string]any{"name": *name, "username": *username, "password": password})
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
	case "users/reset-password":
		flags := flag.NewFlagSet("users reset-password", flag.ContinueOnError)
		id := flags.String("id", "", "user id")
		passwordFile := flags.String("password-file", "", "file containing the new password")
		if err := flags.Parse(args); err != nil {
			return err
		}
		password, err := readAdminPassword(*passwordFile)
		if err != nil {
			return err
		}
		return c.call(http.MethodPut, "/api/v1/admin/users/"+url.PathEscape(*id)+"/password", map[string]string{"password": password})
	case "sessions/list":
		flags := flag.NewFlagSet("sessions list", flag.ContinueOnError)
		user := flags.String("user", "", "user id")
		if err := flags.Parse(args); err != nil {
			return err
		}
		if *user == "" {
			return errors.New("-user is required")
		}
		return c.call(http.MethodGet, "/api/v1/admin/users/"+url.PathEscape(*user)+"/sessions", nil)
	case "sessions/revoke":
		flags := flag.NewFlagSet("sessions revoke", flag.ContinueOnError)
		id := flags.String("id", "", "session id")
		if err := flags.Parse(args); err != nil {
			return err
		}
		if *id == "" {
			return errors.New("-id is required")
		}
		return c.call(http.MethodDelete, "/api/v1/admin/sessions/"+url.PathEscape(*id), nil)
	case "grants/list", "grants/add", "grants/remove":
		flags := flag.NewFlagSet(group+" "+action, flag.ContinueOnError)
		user := flags.String("user", "", "user id")
		source := flags.String("source", "", "source id")
		if err := flags.Parse(args); err != nil {
			return err
		}
		if *user == "" {
			return errors.New("-user is required")
		}
		endpoint := "/api/v1/admin/users/" + url.PathEscape(*user) + "/sources"
		if action == "list" {
			return c.call(http.MethodGet, endpoint, nil)
		}
		if *source == "" {
			return errors.New("-source is required")
		}
		method := http.MethodPut
		if action == "remove" {
			method = http.MethodDelete
		}
		return c.call(method, endpoint+"/"+url.PathEscape(*source), nil)
	default:
		return fmt.Errorf("unknown command %s %s", group, action)
	}
}
