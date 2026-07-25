// Family token issuance composes member creation, grants, and token issuance.
// It keeps partial-progress errors intact so administrators can safely retry the workflow.
package main

import (
	"errors"
	"flag"
	"fmt"
	"net/http"
	"net/url"
	"strings"
)

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
