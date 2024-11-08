import 'dart:convert';
import 'dart:math';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:bluesky/bluesky.dart' as bsky;
import 'package:skyclad/view/liked_by.dart';
import 'package:skyclad/view/reposted_by.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:flutter/gestures.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:card_swiper/card_swiper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skyclad/providers/providers.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:skyclad/view/user_profile.dart';
import 'package:skyclad/view/create_post.dart';

class PostDetails extends ConsumerStatefulWidget {
  final Map<String, dynamic> post;

  const PostDetails({required this.post, Key? key}) : super(key: key);

  @override
  ConsumerState<PostDetails> createState() => _PostDetailsState();
}

class _PostDetailsState extends ConsumerState<PostDetails> {
  Future<Map<String, dynamic>?>? _fetchPost;
  late Map<String, dynamic> _post;
  bool? _isLiked;
  bool? _isReposted;

  @override
  void initState() {
    super.initState();
    _post = widget.post;
    _fetchPost = _fetchPostDetails();
  }


  Future<Map<String, dynamic>?> _fetchPostDetails() async {
    final String postUri = widget.post['uri'];
    final bluesky = await ref.read(blueskySessionProvider.future);
    final feeds =
        await bluesky.feeds.findPosts(uris: [bsky.AtUri.parse(postUri)]);
    final postsList = feeds.data.toJson()['posts'];
    final detailedPost =
        (postsList != null && postsList.isNotEmpty) ? postsList[0] : null;

    if (detailedPost == null) {

      return {};
    }
    setState(() {
      _post = detailedPost;
      _isLiked = detailedPost['viewer']['like'] != null;
      _isReposted = detailedPost['viewer']['repost'] != null;
    });

    return detailedPost;
  }


  void _showImageDialog(BuildContext context, List<String> imageUrls) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        final screenWidth = MediaQuery.of(context).size.width;
        final screenHeight = MediaQuery.of(context).size.height;

        return AlertDialog(
          contentPadding: EdgeInsets.zero,
          insetPadding: EdgeInsets.zero,
          content: Stack(
            children: [
              MediaQuery(
                data: MediaQuery.of(context),
                child: Dismissible(
                  key: UniqueKey(),
                  direction: DismissDirection.vertical,
                  onDismissed: (direction) {
                    Navigator.pop(context);
                  },
                  child: SizedBox(
                    width: screenWidth,
                    height: screenHeight,
                    child: Swiper(
                      itemBuilder: (BuildContext context, int index) {
                        return Image.network(
                          imageUrls[index],
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            return const Center(
                              child: Icon(Icons.error),
                            );
                          },
                        );
                      },
                      itemCount: imageUrls.length,
                      loop: false,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 0,
                right: 0,
                child: IconButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
              ),
            ],
          ),
        );
      },
    );
  }


  Widget _buildPostContent(Map<String, dynamic> post) {
    List<Widget> contentWidgets = [];
    List<InlineSpan> spans = [];

    final text = post['record']?['text'] ?? '';


    final facets = post['record']['facets'] as List? ?? [];


    final facetBytes = utf8.encode(text);
    var lastFacetEndByte = 0;


    for (final facet in facets) {
      for (final feature in facet['features']) {
        final byteStart = facet['index']['byteStart'];


        final byteEnd = min<int>(facet['index']['byteEnd'], facetBytes.length);

        final facetText = utf8.decode(
          facetBytes.sublist(
            byteStart,
            byteEnd,
          ),
        );

        if (facet['index']['byteStart'] > lastFacetEndByte) {
          spans.add(
            TextSpan(
                text: utf8.decode(facetBytes.sublist(
                    lastFacetEndByte, facet['index']['byteStart']))),
          );
        }

        if (feature['\$type'] == 'app.bsky.richtext.facet#link') {
          spans.add(
            TextSpan(
              text: facetText,
              style: const TextStyle(color: Colors.blue),
              recognizer: TapGestureRecognizer()
                ..onTap = () async {
                  final messenger = ScaffoldMessenger.of(context);
                  if (await canLaunchUrl(Uri.parse(feature['uri']))) {
                    await launchUrl(Uri.parse(feature['uri']),
                        mode: LaunchMode.externalApplication);
                  } else {
                    messenger.showSnackBar(
                      SnackBar(content: Text(
                          // ignore: use_build_context_synchronously
                          AppLocalizations.of(context)!.errorFailedToOpenUrl)),
                    );
                  }
                },
            ),
          );
        }

        else if (feature['\$type'] == 'app.bsky.richtext.facet#mention') {
          spans.add(
            TextSpan(
              text: facetText,
              style: const TextStyle(color: Colors.blue),
              recognizer: TapGestureRecognizer()
                ..onTap = () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          UserProfileScreen(actor: feature['did']),
                    ),
                  );
                },
            ),
          );
        }
        else {
          spans.add(TextSpan(text: facetText));
        }

        lastFacetEndByte = facet['index']['byteEnd'];
      }
    }

    spans
        .add(TextSpan(text: utf8.decode(facetBytes.sublist(lastFacetEndByte))));

    contentWidgets.add(
      SelectableText.rich(
        TextSpan(
          children: spans,
          style: const TextStyle(fontSize: 15.0, color: Colors.white),
        ),
      ),
    );

    if (post['embed'] != null &&
        post['embed']['\$type'] == 'app.bsky.embed.images#view') {
      contentWidgets.add(const SizedBox(height: 10.0));

      List<String> imageUrls = post['embed']['images']
          .map<String>((dynamic image) => image['fullsize'] as String)
          .toList();

      contentWidgets.add(
        GestureDetector(
          onTap: () => _showImageDialog(context, imageUrls),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: post['embed']['images']
                  .map<Widget>((image) => Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8.0),
                          child: Image.network(
                            image['thumb'],
                            width: 100,
                            height: 100,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return const Center(
                                child: Icon(Icons.error),
                              );
                            },
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ),
        ),
      );
    }


    contentWidgets.add(_buildQuotedPost(post));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: contentWidgets,
    );
  }

  Widget _buildQuotedPost(Map<String, dynamic> post) {
    if (post['embed'] != null &&
        post['embed']['\$type'] == 'app.bsky.embed.record#view') {
      final quotedPost = post['embed']['record'];
      final quotedAuthor = quotedPost['author'];
      final createdAt = DateTime.parse(quotedPost['indexedAt']).toLocal();

      String languageCode = Localizations.localeOf(context).languageCode;

      if (languageCode != 'ja') {
        languageCode = 'en';
      }

      return InkWell(
        onTap: () async {
          final uri = quotedPost['uri'];

          final bluesky = await ref.read(blueskySessionProvider.future);
          final feeds =
              await bluesky.feeds.findPosts(uris: [bsky.AtUri.parse(uri)]);

          final jsonFeed = feeds.data.toJson()['posts'][0];

          // ignore: use_build_context_synchronously
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PostDetails(post: jsonFeed),
            ),
          );
        },
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white38),
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.all(8.0),
          margin: const EdgeInsets.only(top: 8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      quotedAuthor['displayName'] ?? '',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13.0, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Flexible(
                    child: Text(
                      '@${quotedAuthor['handle']}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 12.0),
                    ),
                  ),
                  Text(
                    timeago.format(createdAt, locale: languageCode),
                    style: const TextStyle(fontSize: 12.0),
                    overflow: TextOverflow.clip,
                  ),
                ],
              ),
              const SizedBox(height: 10.0),
              Text(
                quotedPost['value']['text'] ?? '',
                style: const TextStyle(fontSize: 14.0),
              ),
            ],
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }


  Future<Widget> _buildParentPost(
      BuildContext context, Map<String, dynamic> post) async {
    if (post['record']['reply'] == null) {
      return const SizedBox.shrink();
    }

    final parentUri = post['record']['reply']['parent']['uri'];

    final bluesky = await ref.read(blueskySessionProvider.future);
    final feeds =
        await bluesky.feeds.findPosts(uris: [bsky.AtUri.parse(parentUri)]);

    final parent = feeds.data.toJson()['posts'][0];

    if (parent == null) {
      return const SizedBox.shrink();
    }

    final author = parent['author'];
    final content = parent['record']['text'];

    final createdAt = DateTime.parse(_post['indexedAt']).toLocal();
    String dateStr;
    // ignore: use_build_context_synchronously
    String locale = Localizations.localeOf(context).toLanguageTag();

    if (locale == 'ja') {
      DateFormat format = DateFormat('yyyy/MM/dd HH:mm');
      dateStr = format.format(createdAt);
    } else {
      DateFormat format = DateFormat('MM/dd/yyyy h:mm a');
      dateStr = format.format(createdAt);
    }

    return InkWell(
      onTap: () {
        // ignore: use_build_context_synchronously
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PostDetails(
              post: parent,
            ),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                          child: SvgPicture.asset('assets/default_avatar.svg',
                              width: 48, height: 48),
                        )
                      : null,
                ),
              ),
              const SizedBox(width: 10.0),
              Expanded(
                child: Text(
                  '${author['displayName'] ?? ''} (@${author['handle']})',
                  style: const TextStyle(
                    fontSize: 14.0,
                    fontWeight: FontWeight.bold,
                    color: Colors.white60,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5.0),
          Text(
            content,
            style: const TextStyle(fontSize: 14.0, color: Colors.white),
          ),
          const SizedBox(height: 5.0),
          Text(
            dateStr,
            style: const TextStyle(fontSize: 12.0, color: Colors.white38),
          ),
          const SizedBox(height: 15.0),
          const Divider(color: Colors.white38, height: 1.0),
          const SizedBox(height: 15.0)
        ],
      ),
    );
  }

  Future<Widget> _buildThreadPost(
      BuildContext context, Map<String, dynamic> post) async {
    final recordUri = post['uri'];

    final bluesky = await ref.read(blueskySessionProvider.future);
    final thread =
        await bluesky.feeds.findPostThread(uri: bsky.AtUri.parse(recordUri));

    final replies = thread.data.toJson()['thread']['replies'];

    if (replies == null) {
      return const SizedBox.shrink();
    }

    return ListView.builder(
      itemCount: replies.length,
      itemBuilder: (context, index) {
        final feed = replies[index];
        final post = feed['post'];
        final author = post['author'];

        final createdAt = DateTime.parse(_post['indexedAt']).toLocal();
        String dateStr;
        // ignore: use_build_context_synchronously
        String locale = Localizations.localeOf(context).toLanguageTag();

        if (locale == 'ja') {
          DateFormat format = DateFormat('yyyy/MM/dd HH:mm');
          dateStr = format.format(createdAt);
        } else {
          DateFormat format = DateFormat('MM/dd/yyyy h:mm a');
          dateStr = format.format(createdAt);
        }

        return Column(
          children: [
            if (index != 0) const Divider(color: Colors.white38, height: 1.0),
            InkWell(
              onTap: () {

                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PostDetails(
                      post: post,
                    ),
                  ),
                );
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(color: Colors.white38, height: 1.0),
                  const SizedBox(height: 15.0),
                  Row(
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
                      const SizedBox(width: 10.0),
                      Expanded(
                        child: Text(
                          '${author['displayName'] ?? ''} (@${author['handle']})',
                          style: const TextStyle(
                            fontSize: 14.0,
                            fontWeight: FontWeight.bold,
                            color: Colors.white60,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5.0),
                  Text(
                    post['record']['text'],
                    style: const TextStyle(fontSize: 14.0, color: Colors.white),
                  ),
                  const SizedBox(height: 15.0),
                  Text(
                    dateStr,
                    style: const TextStyle(
                      fontSize: 12.0,
                      color: Colors.white60,
                    ),
                  ),
                  const SizedBox(height: 15.0)
                ],
              ),
            )
          ],
        );
      },
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _fetchPost,
      builder: (BuildContext context,
          AsyncSnapshot<Map<String, dynamic>?> snapshot) {
        Map<String, dynamic> post;

        if (snapshot.connectionState == ConnectionState.waiting) {
          post = widget.post;
        } else if (snapshot.hasError) {
          return Text('Error: ${snapshot.error}');
        } else if (snapshot.hasData && snapshot.data != null) {
          post = snapshot.data!;
        } else {
          post = widget.post;
        }

        final author = post['author'];

        final createdAt = DateTime.parse(post['indexedAt']).toLocal();
        String dateStr;
        // ignore: use_build_context_synchronously
        String locale = Localizations.localeOf(context).toLanguageTag();

        if (locale == 'ja') {
          DateFormat format = DateFormat('yyyy/MM/dd HH:mm');
          dateStr = format.format(createdAt);
        } else {
          DateFormat format = DateFormat('MM/dd/yyyy h:mm a');
          dateStr = format.format(createdAt);
        }

        bool isLiked = post['viewer'] != null && post['viewer']['like'] != null;
        bool isReposted =
            post['viewer'] != null && post['viewer']['repost'] != null;

        return Scaffold(
          appBar: AppBar(
            centerTitle: true,
            title: Text(author['displayName'] ?? ''),
            backgroundColor: Colors.blue[600],
          ),
          body: Padding(
            padding: const EdgeInsets.all(8.0),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FutureBuilder(
                    future: _buildParentPost(context, post),
                    builder:
                        (BuildContext context, AsyncSnapshot<Widget> snapshot) {
                      if (snapshot.connectionState == ConnectionState.done) {
                        if (snapshot.data != null) {
                          return snapshot.data!;
                        } else {
                          return const SizedBox.shrink();
                        }
                      } else {
                        return const SizedBox.shrink();
                      }
                    },
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: () async {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => UserProfileScreen(
                                actor: post['author']['handle'],
                              ),
                            ),
                          );
                        },
                        child: CircleAvatar(
                          backgroundImage: post['author']['avatar'] != null
                              ? NetworkImage(post['author']['avatar'])
                              : null,
                          radius: 24,
                          child: post['author']['avatar'] == null
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
                      const SizedBox(width: 10.0),
                      Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              author['displayName'] ?? '',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 15.0, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              '@${author['handle']}',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white38),
                            ),
                          ]),
                    ],
                  ),
                  const SizedBox(height: 10.0),
                  _buildPostContent(post),
                  const SizedBox(height: 15.0),
                  Text(
                    dateStr,
                    style:
                        const TextStyle(fontSize: 14.0, color: Colors.white38),
                  ),
                  const SizedBox(height: 10.0),
                  const Divider(height: 1, thickness: 1, color: Colors.white12),
                  Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.reply),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => CreatePostScreen(
                                  replyJson: post,
                                ),
                              ),
                            );
                          },
                        ),
                        Column(children: [
                          Material(
                            type: MaterialType.transparency,
                            child: IconButton(
                              icon: (_isReposted ?? false)
                                  ? const Icon(Icons.cached,
                                      color: Colors.green)
                                  : const Icon(Icons.cached_outlined),
                              onPressed: () {
                                showModalBottomSheet(
                                  context: context,
                                  builder: (BuildContext context) {
                                    return Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: <Widget>[
                                        ListTile(
                                          leading: const Icon(Icons.cached),
                                          title: (_isReposted ?? false)
                                              ? Text(
                                                  AppLocalizations.of(context)!
                                                      .undoRepost)
                                              : Text(
                                                  AppLocalizations.of(context)!
                                                      .doRepost),
                                          onTap: () async {
                                            final bluesky = await ref.read(
                                                blueskySessionProvider.future);

                                            if (isReposted) {

                                              await bluesky.repositories
                                                  .deleteRecord(
                                                uri: bsky.AtUri.parse(
                                                    post['viewer']['repost']),
                                              );

                                              setState(() {
                                                _isReposted = false;
                                              });
                                            } else {

                                              final repostedRecord =
                                                  await bluesky.feeds
                                                      .createRepost(
                                                cid: post['cid'],
                                                uri: bsky.AtUri.parse(
                                                    post['uri']),
                                              );

                                              post['viewer']['repost'] =
                                                  repostedRecord.data.uri
                                                      .toString();

                                              setState(() {
                                                _isReposted = true;
                                              });
                                            }

                                            // ignore: use_build_context_synchronously
                                            Navigator.of(context)
                                                .pop(); // BottomSheet
                                          },
                                        ),
                                        ListTile(
                                          leading:
                                              const Icon(Icons.format_quote),
                                          title: Text(
                                              AppLocalizations.of(context)!
                                                  .quote),
                                          onTap: () {
                                            Navigator.of(context)
                                                .pop(); // BottomSheet
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (context) =>
                                                    CreatePostScreen(
                                                        quoteJson: post),
                                              ),
                                            );
                                          },
                                        ),
                                      ],
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                        ]),
                        Column(children: [
                          IconButton(
                            icon: (_isLiked ?? false)
                                ? const Icon(Icons.favorite)
                                : const Icon(Icons.favorite_border),
                            color: (_isLiked ?? false) ? Colors.red : null,
                            onPressed: () async {
                              setState(() {
                                _isLiked = !(_isLiked ?? false);
                                if (_isLiked!) {
                                  post['likeCount'] += 1;
                                } else {
                                  post['likeCount'] -= 1;
                                }
                              });

                              final bluesky =
                                  await ref.read(blueskySessionProvider.future);

                              if (isLiked) {

                                await bluesky.repositories.deleteRecord(
                                  uri: bsky.AtUri.parse(post['viewer']['like']),
                                );
                              } else {
                                final likedRecord =
                                    await bluesky.feeds.createLike(
                                  cid: post['cid'],
                                  uri: bsky.AtUri.parse(post['uri']),
                                );
                                post['viewer']
                                    ['like'] = {'uri': likedRecord.data.uri};
                              }
                            },
                          ),
                        ]),
                        Column(children: [
                          PopupMenuButton<String>(
                            icon: const Icon(Icons.more_horiz),
                            onSelected: (value) {
                              if (value == "report") {
                                // ignore: use_build_context_synchronously
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(AppLocalizations.of(context)!
                                        .postReported),
                                    backgroundColor: Colors.white,
                                  ),
                                );
                              }
                            },
                            itemBuilder: (BuildContext context) =>
                                <PopupMenuEntry<String>>[
                              PopupMenuItem<String>(
                                value: "report",
                                child: ListTile(
                                  title: Text(
                                      AppLocalizations.of(context)!.reportPost),
                                ),
                              ),
                            ],
                          ),
                        ]),
                      ]),
                  const Divider(height: 1, thickness: 1, color: Colors.white12),
                  const SizedBox(height: 10.0),
                  Row(
                    children: [
                      const SizedBox(width: 30.0),
                      Row(
                        children: [
                          const SizedBox(width: 10.0),
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      RepostedByScreen(uri: post['uri']),
                                ),
                              );
                            },
                            child: Column(
                              children: [
                                Text(
                                  post['repostCount'].toString(),
                                  style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 2.0),
                                Text(
                                  2 <= post['repostCount']
                                      ? AppLocalizations.of(context)!.reposts
                                      : AppLocalizations.of(context)!.repost,
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.white60),
                                )
                              ],
                            ),
                          ),
                          const SizedBox(width: 43.0),
                          const SizedBox(
                            height: 50,
                            child: VerticalDivider(
                                width: 1, thickness: 1, color: Colors.white30),
                          ),
                          const SizedBox(width: 43.0),
                          GestureDetector(
                            onTap: () {
                              // いいねの数字がタップされたときの処理をここに追加します
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      LikedByScreen(uri: post['uri']),
                                ),
                              );
                            },
                            child: Column(
                              children: [
                                Text(post['likeCount'].toString(),
                                    style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold)),
                                const SizedBox(height: 2.0),
                                Text(
                                    // いいね数が2以上のときは複数形を表示する
                                    2 <= post['likeCount']
                                        ? AppLocalizations.of(context)!.likes
                                        : AppLocalizations.of(context)!.like,
                                    style: const TextStyle(
                                        fontSize: 12, color: Colors.white60)),
                              ],
                            ),
                          )
                        ],
                      )
                    ],
                  ),
                  const SizedBox(height: 10.0),
                  FutureBuilder(
                    future: _buildThreadPost(context, post),
                    builder:
                        (BuildContext context, AsyncSnapshot<Widget> snapshot) {
                      if (snapshot.connectionState == ConnectionState.done) {
                        if (snapshot.data != null) {
                          return snapshot.data!;
                        } else {
                          return const SizedBox.shrink();
                        }
                      } else {
                        return const SizedBox.shrink();
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
