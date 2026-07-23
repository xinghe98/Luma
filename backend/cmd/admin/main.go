// Package main 提供只通过管理 API 操作成员、令牌和媒体源授权的 CLI。
package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"path"
	"strings"
	"time"
)

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, "luma-admin:", err)
		os.Exit(1)
	}
}

type client struct {
	origin string
	token  string
	http   *http.Client
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

// stringListFlag 允许 family issue 重复传入 -source，而不要求调用方拼接分隔符。
type stringListFlag []string

func (values *stringListFlag) String() string { return strings.Join(*values, ",") }

func (values *stringListFlag) Set(value string) error {
	value = strings.TrimSpace(value)
	if value == "" {
		return errors.New("source id must not be empty")
	}
	*values = append(*values, value)
	return nil
}

// issueFamilyToken 将创建成员、来源授权和令牌签发组合成一个统一工作流。
// 各 HTTP 操作仍逐项提交；失败时会返回已完成阶段，便于管理员安全重试。
func issueFamilyToken(c client, args []string) error {
	flags := flag.NewFlagSet("family issue", flag.ContinueOnError)
	name := flags.String("name", "", "new member display name")
	userID := flags.String("user", "", "existing member id; skips member creation")
	tokenName := flags.String("token-name", "家庭设备", "token name")
	expires := flags.String("expires", "", "optional RFC3339 expiry")
	var sources stringListFlag
	flags.Var(&sources, "source", "source id to grant; repeat for multiple sources")
	if err := flags.Parse(args); err != nil {
		return err
	}
	if strings.TrimSpace(*userID) == "" && strings.TrimSpace(*name) == "" {
		return errors.New("-name is required when -user is not provided")
	}
	if strings.TrimSpace(*userID) != "" && strings.TrimSpace(*name) != "" {
		return errors.New("provide either -name for a new member or -user for an existing member, not both")
	}
	if len(sources) == 0 {
		return errors.New("at least one -source is required")
	}
	if strings.TrimSpace(*tokenName) == "" {
		return errors.New("-token-name is required")
	}

	created := false
	resolvedUserID := strings.TrimSpace(*userID)
	if resolvedUserID == "" {
		var user struct {
			ID string `json:"id"`
		}
		if err := c.callJSON(http.MethodPost, "/api/v1/admin/users", map[string]any{"name": *name}, &user); err != nil {
			return fmt.Errorf("create member: %w", err)
		}
		if user.ID == "" {
			return errors.New("create member response did not contain an id")
		}
		resolvedUserID = user.ID
		created = true
	}

	granted := make([]string, 0, len(sources))
	for _, sourceID := range sources {
		endpoint := "/api/v1/admin/users/" + url.PathEscape(resolvedUserID) + "/sources/" + url.PathEscape(sourceID)
		if _, err := c.request(http.MethodPut, endpoint, nil); err != nil {
			return fmt.Errorf("grant source %s to user %s (member_created=%t, granted=%v): %w",
				sourceID, resolvedUserID, created, granted, err)
		}
		granted = append(granted, sourceID)
	}

	body := map[string]any{"name": strings.TrimSpace(*tokenName)}
	if strings.TrimSpace(*expires) != "" {
		body["expires_at"] = strings.TrimSpace(*expires)
	}
	var issued map[string]any
	if err := c.callJSON(http.MethodPost, "/api/v1/admin/users/"+url.PathEscape(resolvedUserID)+"/tokens", body, &issued); err != nil {
		return fmt.Errorf("issue token for user %s (member_created=%t, granted=%v): %w",
			resolvedUserID, created, granted, err)
	}
	return printJSON(map[string]any{
		"user_id":        resolvedUserID,
		"member_created": created,
		"source_ids":     granted,
		"issued_token":   issued,
	})
}

func (c client) call(method, endpoint string, body any) error {
	data, err := c.request(method, endpoint, body)
	if err != nil {
		return err
	}
	if len(data) == 0 {
		fmt.Println("ok")
		return nil
	}
	var value any
	if json.Unmarshal(data, &value) == nil {
		return printJSON(value)
	}
	fmt.Println(string(data))
	return nil
}

func (c client) callJSON(method, endpoint string, body, target any) error {
	data, err := c.request(method, endpoint, body)
	if err != nil {
		return err
	}
	if err := json.Unmarshal(data, target); err != nil {
		return fmt.Errorf("decode response JSON: %w", err)
	}
	return nil
}

func (c client) request(method, endpoint string, body any) ([]byte, error) {
	var reader io.Reader
	if body != nil {
		data, err := json.Marshal(body)
		if err != nil {
			return nil, err
		}
		reader = bytes.NewReader(data)
	}
	request, err := http.NewRequest(method, c.origin+endpoint, reader)
	if err != nil {
		return nil, err
	}
	request.Header.Set("Authorization", "Bearer "+c.token)
	if body != nil {
		request.Header.Set("Content-Type", "application/json")
	}
	response, err := c.http.Do(request)
	if err != nil {
		return nil, err
	}
	defer response.Body.Close()
	data, err := io.ReadAll(io.LimitReader(response.Body, 1<<20))
	if err != nil {
		return nil, err
	}
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		return nil, fmt.Errorf("HTTP %s: %s", response.Status, strings.TrimSpace(string(data)))
	}
	return data, nil
}

func printJSON(value any) error {
	pretty, err := json.MarshalIndent(value, "", "  ")
	if err != nil {
		return err
	}
	fmt.Println(string(pretty))
	return nil
}

func readAdminToken(filename string) (string, error) {
	if value := strings.TrimSpace(os.Getenv("LUMA_ADMIN_TOKEN")); value != "" {
		return value, nil
	}
	if strings.TrimSpace(filename) == "" {
		return "", errors.New("set LUMA_ADMIN_TOKEN or provide -token-file")
	}
	data, err := os.ReadFile(filename)
	if err != nil {
		return "", err
	}
	value := strings.TrimSpace(string(data))
	if value == "" {
		return "", errors.New("administrator token file is empty")
	}
	return value, nil
}

func validateAdminOrigin(raw string, allowInsecure bool) (string, error) {
	parsed, err := url.Parse(strings.TrimSpace(raw))
	if err != nil || parsed.Host == "" || (parsed.Scheme != "http" && parsed.Scheme != "https") {
		return "", errors.New("-server must be an absolute http(s) origin")
	}
	if parsed.Scheme == "http" && !allowInsecure && !isLoopback(parsed.Hostname()) {
		return "", errors.New("plain HTTP management is limited to loopback; use HTTPS or -allow-insecure")
	}
	parsed.Path = path.Clean("/" + strings.Trim(parsed.Path, "/"))
	if parsed.Path == "/" {
		parsed.Path = ""
	}
	parsed.RawQuery, parsed.Fragment = "", ""
	return strings.TrimSuffix(parsed.String(), "/"), nil
}

func isLoopback(host string) bool {
	if strings.EqualFold(host, "localhost") {
		return true
	}
	ip := net.ParseIP(host)
	return ip != nil && ip.IsLoopback()
}
