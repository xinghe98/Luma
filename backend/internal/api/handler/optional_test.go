package handler

import (
	"encoding/json"
	"testing"
)

func TestOptionalJSONPreservesMissingNullAndValue(t *testing.T) {
	type body struct {
		Title optionalJSON[string] `json:"title"`
	}
	var missing body
	if err := json.Unmarshal([]byte(`{}`), &missing); err != nil {
		t.Fatal(err)
	}
	if missing.Title.Set {
		t.Fatal("缺失字段不应标记为 Set")
	}
	var null body
	if err := json.Unmarshal([]byte(`{"title":null}`), &null); err != nil {
		t.Fatal(err)
	}
	if !null.Title.Set || !null.Title.Null || null.Title.patchField().Value != nil {
		t.Fatalf("null=%#v", null.Title)
	}
	var value body
	if err := json.Unmarshal([]byte(`{"title":"标题"}`), &value); err != nil {
		t.Fatal(err)
	}
	field := value.Title.patchField()
	if !field.Set || field.Value == nil || *field.Value != "标题" {
		t.Fatalf("value=%#v field=%#v", value.Title, field)
	}
}
