// Stable route-name constants are shared by route builders and feature navigation.
// They remain exported through app_router.dart for existing callers.
abstract final class AppRoute {
  static const connection = 'connection';
  static const mediaDetail = 'media-detail';
  static const catalogDetail = 'catalog-detail';
  static const movieCollection = 'movie-collection';
  static const seriesCollection = 'series-collection';
  static const personalVideos = 'personal-videos';
  static const player = 'player';
  static const librarySources = 'library-sources';
  static const organization = 'organization';
  static const organizationEditor = 'organization-editor';
  static const accessManagement = 'access-management';
  static const newMember = 'new-member';
  static const memberDetail = 'member-detail';
  static const issueToken = 'issue-token';
}


