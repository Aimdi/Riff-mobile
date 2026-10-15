import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/services/search_spelling.dart';
import '/ui/theme/riff_spacing.dart';
import '../../Home/home_layout.dart';

/// YouTube Music's spelling help above the results, as its search page
/// (and Spotify's, Apple Music's) shows it: "Showing results for beyoncé"
/// with "Search instead for beyonse", or "Did you mean beyoncé".
class SearchSpellingLine extends StatelessWidget {
  const SearchSpellingLine({
    super.key,
    required this.spelling,
    required this.searched,
    required this.onCorrected,
    required this.onOriginal,
  });

  final SearchSpelling spelling;

  /// The words searched, when YouTube Music doesn't say them back.
  final String searched;

  /// Search YouTube Music's words.
  final VoidCallback onCorrected;

  /// Search the words as typed, exactly.
  final VoidCallback onOriginal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.only(
          left: HomeLayout.gutter,
          top: RiffSpacing.xs,
          right: HomeLayout.gutter),
      child: spelling.applied
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '${'searchShowingResultsFor'.tr} '),
                    TextSpan(
                        text: spelling.corrected,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(color: theme.colorScheme.onSurface)),
                  ]),
                  style: muted,
                ),
                TextButton(
                  onPressed: onOriginal,
                  child: Text('searchInsteadFor'
                      .trParams({'query': spelling.original ?? searched})),
                ),
              ],
            )
          : Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: RiffSpacing.xs,
              children: [
                Text('searchDidYouMean'.tr, style: muted),
                TextButton(
                  onPressed: onCorrected,
                  child: Text(spelling.corrected),
                ),
              ],
            ),
    );
  }
}
