import 'package:flutter/material.dart';

import '../core/grid.dart';
import '../core/theme.dart';
import '../state/meeting_cubit.dart';
import 'participant_tile.dart';

/// The paged grid of faces.
///
/// The page size is decided from the measured stage rather than the head count, which
/// is `livekit-fe`'s rule and the reason six people on a phone in landscape are not
/// drawn at the size of six people in portrait. Twelve is the ceiling regardless: past
/// that a tile is a coloured square with a name on it.
class MeetingGrid extends StatefulWidget {
  const MeetingGrid({super.key, required this.people, this.cap = 12});

  final List<MeetingTile> people;
  final int cap;

  @override
  State<MeetingGrid> createState() => _MeetingGridState();
}

class _MeetingGridState extends State<MeetingGrid> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final aspect = box.maxWidth > box.maxHeight
            ? tileAspectLandscape
            : tileAspectPortrait;
        final perPage = tilesPerPage(
          width: box.maxWidth,
          height: box.maxHeight,
          aspect: aspect,
          cap: widget.cap,
        );
        final people = _pulled(widget.people, perPage);
        final pages = (people.length / perPage).ceil().clamp(1, 99);

        if (_page >= pages) {
          // Somebody left and took a page with them. Correcting it after this frame
          // keeps the controller and the build in step.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _controller.hasClients) {
              _controller.jumpToPage(pages - 1);
            }
          });
        }

        return Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _controller,
                physics: pages == 1
                    ? const NeverScrollableScrollPhysics()
                    : null,
                itemCount: pages,
                onPageChanged: (p) => setState(() => _page = p),
                itemBuilder: (context, page) {
                  final slice = people.skip(page * perPage).take(perPage).toList();
                  final layout = gridLayout(
                    count: slice.length,
                    width: box.maxWidth,
                    height: box.maxHeight,
                    aspect: aspect,
                  );
                  return Center(
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      runAlignment: WrapAlignment.center,
                      spacing: tileGap,
                      runSpacing: tileGap,
                      children: [
                        for (final tile in slice)
                          SizedBox(
                            width: layout.measured ? layout.tileWidth : null,
                            height: layout.measured ? layout.tileHeight : null,
                            child: ParticipantTile(tile: tile),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
            if (pages > 1) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < pages; i++)
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i == _page
                            ? AppStage.onStage
                            : AppStage.onStageMuted.withValues(alpha: 0.4),
                      ),
                    ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }

  /// Pulls whoever is talking onto the first page.
  ///
  /// Being told who is speaking matters more than a grid that never moves — and the
  /// local participant stays first, because a person looking for themselves looks in
  /// the same place every time.
  static List<MeetingTile> _pulled(List<MeetingTile> people, int perPage) {
    if (people.length <= perPage) return people;
    final talking = people.indexWhere((t) => t.speaking && !t.isLocal);
    if (talking < 0 || talking < perPage) return people;
    final out = [...people];
    out.insert(perPage - 1, out.removeAt(talking));
    return out;
  }
}
