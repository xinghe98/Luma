import '../models/media_item.dart';
import '../models/media_types.dart';

List<MediaItem> buildMediaFixtures() {
  final now = DateTime(2026, 7, 19);
  const videoTitles = [
    '海边的一天',
    'Silent Forest',
    '沿江夜行',
    'Tokyo in Rain',
    '夏日家庭影像',
    'The Last Train',
    '城市呼吸',
    'Weekend Notes',
    '岛屿来信',
    'A Quiet Morning',
    '山谷公路',
    'Kitchen Stories',
    '春日散步',
    'Light & Shadow',
    '旧城下午',
    'Across the Lake',
    '冬天的窗',
    'Home Archive 2025',
    '风经过房间',
    'Northbound',
  ];
  const imageTitles = [
    '晨光落在桌面',
    'Blue Hour',
    '雨后的街道',
    'Portrait No. 07',
    '夏日树影',
    'Window Seat',
    '海风与白墙',
    'Family Album',
    '夜色中的桥',
    'Still Life',
    '在路上',
    'Soft Light',
  ];

  final videos = List.generate(videoTitles.length, (index) {
    const progress = [0.0, 0.18, 0.47, 0.72, 1.0];
    return MediaItem(
      id: 'video-$index',
      title: videoTitles[index],
      type: MediaType.video,
      duration: Duration(minutes: 7 + index * 4, seconds: index * 7 % 60),
      resolution: index % 4 == 0 ? '4K' : '1080p',
      format: index % 3 == 0 ? 'MKV' : 'MP4',
      fileSize: '${(1.2 + index * 0.37).toStringAsFixed(1)} GB',
      directory: '/家庭媒体/视频/${index < 6 ? '旅行' : '生活记录'}',
      tags: [index.isEven ? '旅行' : '生活', index % 3 == 0 ? '夜景' : '纪实'],
      addedAt: now.subtract(Duration(days: index)),
      artSeed: index,
      aspectRatio: index % 6 == 0 ? 9 / 16 : 16 / 9,
      isFavorite: index % 4 == 0,
      progress: progress[index % progress.length],
      note: index == 2 ? '剪辑节奏很好，保留这一版。' : '',
    );
  });

  final images = List.generate(imageTitles.length, (index) {
    return MediaItem(
      id: 'image-$index',
      title: imageTitles[index],
      type: MediaType.image,
      duration: Duration.zero,
      resolution: index.isEven ? '6000 × 4000' : '3024 × 4032',
      format: index % 3 == 0 ? 'PNG' : 'JPG',
      fileSize: '${4 + index * 2} MB',
      directory: '/家庭媒体/照片/${index < 4 ? '精选' : '随拍'}',
      tags: [index.isEven ? '风景' : '人像', index % 3 == 0 ? '夜景' : '日常'],
      addedAt: now.subtract(Duration(days: index + 2, hours: 3)),
      artSeed: index + 20,
      aspectRatio: index.isOdd ? 3 / 4 : 3 / 2,
      isFavorite: index % 3 == 0,
    );
  });
  return [...videos, ...images];
}
