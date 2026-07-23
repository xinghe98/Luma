package main

import (
	"net/http"
	"net/http/httptest"
	"reflect"
	"testing"
	"time"
)

func TestIssueFamilyTokenCreatesGrantsAndIssuesOnce(t *testing.T) {
	seen := []string{}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") != "Bearer root-token" {
			t.Fatalf("authorization = %q", r.Header.Get("Authorization"))
		}
		seen = append(seen, r.Method+" "+r.URL.Path)
		switch r.Method + " " + r.URL.Path {
		case "POST /api/v1/admin/users":
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(`{"id":"user_alice","name":"Alice"}`))
		case "PUT /api/v1/admin/users/user_alice/sources/source_a",
			"PUT /api/v1/admin/users/user_alice/sources/source_b":
			w.WriteHeader(http.StatusNoContent)
		case "POST /api/v1/admin/users/user_alice/tokens":
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(`{"id":"token_phone","token":"member-secret"}`))
		default:
			http.Error(w, "unexpected request", http.StatusNotFound)
		}
	}))
	defer server.Close()

	c := client{origin: server.URL, token: "root-token", http: &http.Client{Timeout: time.Second}}
	err := issueFamilyToken(c, []string{
		"-name", "Alice", "-source", "source_a", "-source", "source_b", "-token-name", "Alice phone",
	})
	if err != nil {
		t.Fatal(err)
	}
	want := []string{
		"POST /api/v1/admin/users",
		"PUT /api/v1/admin/users/user_alice/sources/source_a",
		"PUT /api/v1/admin/users/user_alice/sources/source_b",
		"POST /api/v1/admin/users/user_alice/tokens",
	}
	if !reflect.DeepEqual(seen, want) {
		t.Fatalf("requests = %#v, want %#v", seen, want)
	}
}

func TestIssueFamilyTokenValidatesIdentityAndSources(t *testing.T) {
	c := client{}
	for _, test := range []struct {
		name string
		args []string
	}{
		{name: "missing identity", args: []string{"-source", "source_a"}},
		{name: "two identities", args: []string{"-name", "Alice", "-user", "user_a", "-source", "source_a"}},
		{name: "missing source", args: []string{"-name", "Alice"}},
	} {
		t.Run(test.name, func(t *testing.T) {
			if err := issueFamilyToken(c, test.args); err == nil {
				t.Fatal("expected validation error")
			}
		})
	}
}
