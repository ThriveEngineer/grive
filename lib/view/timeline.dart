import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skyclad/model/current_index.dart';
import 'package:skyclad/providers/providers.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:skyclad/view/notifications.dart';
import 'package:skyclad/view/user_profile.dart';
import 'package:skyclad/view/login.dart';
import 'package:skyclad/view/post_details.dart';
import 'package:skyclad/view/create_post.dart';
import 'package:skyclad/widgets/post_widget.dart';


class Timeline extends ConsumerStatefulWidget {
  const Timeline({Key? key}) : super(key: key);

  @override
  ConsumerState<Timeline> createState() => _TimelineState();
}

class _TimelineState extends ConsumerState<Timeline> {
  final GlobalKey<BlueskyTimelineState> blueskyTimelineKey =
      GlobalKey<BlueskyTimelineState>();

  @override
  Widget build(BuildContext context) {
    int currentIndex = ref.watch(currentIndexProvider);
    return MaterialApp(
      title: 'Skyclad',
      theme: ThemeData.dark(),
      home: Scaffold(
        appBar: _buildAppBar(currentIndex),
        body: _buildBody(currentIndex),
        floatingActionButton: _buildFloatingActionButton(context),
        bottomNavigationBar: _buildBottomNavigationBar(currentIndex),
        drawer: _buildDrawer(context),
        drawerEdgeDragWidth: 0, // ドロワーを開くジェスチャーを無効化
      ),
      locale: WidgetsBinding.instance.platformDispatcher.locales.first,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en'), // English
        Locale('de'), // German
      ],
    );
  }

  AppBar? _buildAppBar(int currentIndex) {
    if (currentIndex == 2) return null;
    return AppBar(
      centerTitle: true,
      title: Text([
        AppLocalizations.of(context)!.timeline,
        AppLocalizations.of(context)!.notifications,
        AppLocalizations.of(context)!.profile,
      ][currentIndex]),
      backgroundColor: Colors.blue[600],
    );
  }

  Widget _buildBody(int currentIndex) {
    return FutureBuilder<String>(
      future: ref.read(sharedPreferencesRepositoryProvider).getId(),
      builder: (BuildContext context, AsyncSnapshot<String> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const CircularProgressIndicator();
        } else if (snapshot.hasError) {
          return Text('Error: ${snapshot.error}');
        } else {
          final id = snapshot.data;
          return [
            BlueskyTimeline(
              timelineKey: blueskyTimelineKey,
            ),
            const NotificationScreen(),
            UserProfileScreen(actor: id ?? ''),
          ][currentIndex];
        }
      },
    );
  }

  // BottomNavigationBar
  BottomNavigationBar _buildBottomNavigationBar(int currentIndex) {
    return BottomNavigationBar(
      type: BottomNavigationBarType.fixed,
      items: <BottomNavigationBarItem>[
        BottomNavigationBarItem(
          icon: const Icon(Icons.home),
          label: AppLocalizations.of(context)!.timeline,
        ),
        BottomNavigationBarItem(
          icon: const Icon(Icons.notifications),
          label: AppLocalizations.of(context)!.notifications,
        ),
        BottomNavigationBarItem(
          icon: const Icon(Icons.account_circle),
          label: AppLocalizations.of(context)!.profile,
        ),
      ],
      currentIndex: currentIndex,
      selectedItemColor: Colors.white,
      unselectedItemColor: Colors.white38,
      showUnselectedLabels: true,
      onTap: (int index) {
        ref.read(currentIndexProvider.notifier).updateIndex(index);
      },
    );
  }

  // Drawer
  Drawer _buildDrawer(BuildContext context) {
    return Drawer(
      child: ListView(
        children: [
          const DrawerHeader(
            decoration: BoxDecoration(color: Colors.lightBlue),
            child: Text('Skyclad', style: TextStyle(fontSize: 24)),
          ),
          ListTile(
            title: Text(AppLocalizations.of(context)!.logout),
            onTap: () async {
              final sharedPreferences = await SharedPreferences.getInstance();
              sharedPreferences.remove('service');
              sharedPreferences.remove('id');
              sharedPreferences.remove('password');

              // ignore: use_build_context_synchronously
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (BuildContext context) => LoginScreen(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // FloatingActionButton
  FloatingActionButton _buildFloatingActionButton(BuildContext context) {
    return FloatingActionButton(
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (BuildContext context) => const CreatePostScreen(),
          ),
        );
      },
      backgroundColor: Colors.blue[600],
      child: const Icon(Icons.edit, color: Colors.white),
    );
  }
}

@immutable
class BlueskyTimeline extends ConsumerStatefulWidget {
  final GlobalKey<BlueskyTimelineState> timelineKey;

  const BlueskyTimeline({required this.timelineKey, Key? key})
      : super(key: key);

  @override
  BlueskyTimelineState createState() => BlueskyTimelineState();
}

class BlueskyTimelineState extends ConsumerState<BlueskyTimeline> {
  List<dynamic> _timelineData = [];
  String _cursor = "";
  bool _isLoading = true;
  bool _isFetchingMore = false;
  String? _nextCursor;
  final bool _hasMoreData = true;

  @override
  void initState() {
    super.initState();
    _fetchTimeline();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    PrimaryScrollController.of(context).addListener(_scrollListener);
  }

  void _scrollListener() {
    ScrollController controller = PrimaryScrollController.of(context);

    if (controller.position.pixels == controller.position.maxScrollExtent) {
      _loadMoreTimelineData();
    }
  }

  @override
  void deactivate() {
    super.deactivate();
    PrimaryScrollController.of(context).removeListener(_scrollListener);
  }

  Future<void> _fetchTimeline() async {
    final data = await _fetchTimelineData();

    if (!mounted) {
      return;
    }
    setState(() {
      _timelineData = data['feed'];
      _nextCursor = data['cursor'];
      _isLoading = false;
    });
  }

  Future<void> _refreshTimeline() async {
    final data = await _fetchTimelineData();
    setState(() {
      _timelineData = data['feed'];
      _cursor = data['cursor'];
    });
  }

  Future<void> _loadMoreTimelineData() async {
    if (!_isFetchingMore && _hasMoreData) {
      setState(() {
        _isFetchingMore = true;
      });

      final moreData = await _fetchTimelineData(cursor: _nextCursor);

      setState(() {
        _timelineData.addAll(moreData['feed']);
        _nextCursor = moreData['cursor'];
        _isFetchingMore = false;
      });
    }
  }

  Future<Map<String, dynamic>> _fetchTimelineData({String? cursor}) async {
    final bluesky = await ref.read(blueskySessionProvider.future);
    final feeds = await bluesky.feeds.findTimeline(limit: 100, cursor: cursor);

    final jsonFeeds = feeds.data.toJson()['feed'];

    _cursor = feeds.data.toJson()['cursor'];

    return {'feed': jsonFeeds, 'cursor': _cursor};
  }

  Widget _buildRepostedBy(Map<String, dynamic> feed) {
    if (feed['reason'] != null &&
        feed['reason']['\$type'] == 'app.bsky.feed.defs#reasonRepost') {
      final repostedBy = feed['reason']['by'];
      return Column(children: [
        const SizedBox(height: 8.0),
        Text(
          'Reposted by @${repostedBy['displayName']}',
          style: const TextStyle(color: Colors.white38, fontSize: 12.0),
        ),
      ]);
    }
    return const SizedBox.shrink();
  }

  Widget _buildRepliedBy(Map<String, dynamic> feed) {
    if (feed['reply'] != null) {
      final repliedTo = feed['reply']['parent']['author'];
      return Column(
        children: [
          const SizedBox(height: 8.0),
          Text(
            'Reply to ${repliedTo['displayName']}',
            style: const TextStyle(color: Colors.white38, fontSize: 12.0),
          ),
        ],
      );
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: () => _refreshTimeline(),
      child: ListView.builder(
        itemCount: _timelineData.length + 1,
        itemBuilder: (context, index) {
          if (index == _timelineData.length) {
            return _hasMoreData
                ? const Center(child: CircularProgressIndicator())
                : const SizedBox.shrink();
          }

          final feed = _timelineData[index];
          final post = feed['post'];
          final author = post['author'];
          final createdAt = DateTime.parse(post['indexedAt']).toLocal();

          String languageCode = Localizations.localeOf(context).languageCode;

          if (languageCode != 'ja') {
            languageCode = 'en';
          }

          return Column(children: [
            InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PostDetails(post: post),
                  ),
                );
              },
              child: Container(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => UserProfileScreen(
                                    actor: author['handle'],
                                  ),
                                ),
                              );
                            },
                            child: CircleAvatar(
                              backgroundImage: author['avatar'] != null
                                  ? NetworkImage(author['avatar'])
                                  : null,
                              radius: 24,
                              child: author['avatar'] == null
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(24),
                                      child: SvgPicture.asset(
                                          'assets/default_avatar.svg',
                                          width: 48,
                                          height: 48),
                                    )
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 8.0),
                          Flexible(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Expanded(
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            Flexible(
                                              child: Text(
                                                author['displayName'] ?? '',
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                    fontSize: 14.0,
                                                    fontWeight:
                                                        FontWeight.bold),
                                              ),
                                            ),
                                            const SizedBox(width: 8.0),
                                            Flexible(
                                              child: Text(
                                                '@${author['handle']}',
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                    color: Colors.white38),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8.0),
                                      Text(
                                        timeago.format(createdAt,
                                            locale: languageCode),
                                        style: const TextStyle(fontSize: 12.0),
                                        overflow: TextOverflow.clip,
                                      ),
                                    ],
                                  ),
                                  PostWidget(post: post),
                                  _buildRepostedBy(feed),
                                  _buildRepliedBy(feed)
                                ]),
                          ),
                        ],
                      ),
                    ],
                  )),
            ),
            const Divider(height: 1, thickness: 1, color: Colors.white12)
          ]);
        },
      ),
    );
  }
}
