import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/theme.dart';
import '../../../shared/interaction/tv_key_bindings.dart';

/// 显示确认操作弹窗；取消、返回键和点击遮罩都返回 false。
/// [destructive] 为 true 时确认按钮使用警示色，TV 默认焦点仍在「取消」。
Future<bool> showConfirmationDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final television =
      AppScope.maybeOf(context)?.deviceProfile.isTelevision ?? false;
  return await showDialog<bool>(
        context: context,
        animationStyle: AnimationStyle.noAnimation,
        builder: (context) {
          final scheme = Theme.of(context).colorScheme;
          final actions = [
            TextButton(
              autofocus: television,
              style: television
                  ? TextButton.styleFrom(
                      minimumSize: const Size(
                        96,
                        LumaTvLayout.controlMinHeight,
                      ),
                    )
                  : null,
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              style:
                  (television
                          ? FilledButton.styleFrom(
                              minimumSize: const Size(
                                96,
                                LumaTvLayout.controlMinHeight,
                              ),
                            )
                          : FilledButton.styleFrom())
                      .copyWith(
                        backgroundColor: destructive
                            ? WidgetStatePropertyAll(scheme.error)
                            : null,
                        foregroundColor: destructive
                            ? WidgetStatePropertyAll(scheme.onError)
                            : null,
                      ),
              onPressed: () => Navigator.pop(context, true),
              child: Text(confirmLabel),
            ),
          ];
          if (television) {
            return TvKeyBindings(
              child: AlertDialog(
                constraints: const BoxConstraints(minWidth: 480, maxWidth: 640),
                insetPadding: const EdgeInsets.all(LumaSpacing.lg),
                scrollable: true,
                title: Text(title),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(message),
                    const SizedBox(height: LumaSpacing.lg),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: LumaSpacing.sm,
                      runSpacing: LumaSpacing.sm,
                      children: actions,
                    ),
                  ],
                ),
              ),
            );
          }
          return AlertDialog(
            scrollable: true,
            title: Text(title),
            content: Text(message),
            actions: actions,
          );
        },
      ) ??
      false;
}
