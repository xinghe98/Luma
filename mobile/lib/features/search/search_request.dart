// 跨页面发起搜索的一次性请求；由 AppDependencies.searchRequest 传递。
// 请求只描述意图，不持有搜索结果；搜索页消费后需把 notifier 置回 null。
import 'package:flutter/foundation.dart';

/// 请求搜索页应用某个条件：纯文字查询或具体标签。
@immutable
class SearchRequest {
  const SearchRequest({required this.label, this.tagId});

  /// 展示给用户或写入查询框的文本。
  final String label;

  /// 非空时按标签 id 过滤，label 仅用于展示；为空时按 label 文本查询。
  final String? tagId;
}
