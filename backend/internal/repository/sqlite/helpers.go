package sqlite

// nullableText 将空字符串转换为数据库 NULL。
func nullableText(value string) any {
	if value == "" {
		return nil
	}
	return value
}
