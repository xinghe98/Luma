import 'package:flutter/material.dart';

abstract final class LibraryKindPresentation {
  static String label(String kind) => switch (kind) {
    'movies' => '电影',
    'tv' => '电视剧',
    _ => '个人视频',
  };

  static IconData icon(String kind) => switch (kind) {
    'movies' => Icons.movie_outlined,
    'tv' => Icons.tv_outlined,
    _ => Icons.video_library_outlined,
  };
}
