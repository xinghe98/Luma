import 'package:flutter/material.dart';

import '../../../shared/branding/brand_mark.dart';

void showAboutLumaDialog(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const BrandMark(),
      content: const Text(
        '轻影是一款连接家庭服务器的私有影像管理播放器。\n\n'
        '媒体数据由已连接的轻影服务器提供。',
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('知道了'),
        ),
      ],
    ),
  );
}
