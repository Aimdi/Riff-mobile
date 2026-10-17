import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/ui/theme/riff_spacing.dart';
import 'common_dialog_widget.dart';

/// Asks for a bookmark's note ([note] to edit, if it has one): the text on
/// Save, null on Cancel. [subtitle] says which moment (a quote, a chapter).
Future<String?> askBookmarkNote(BuildContext context,
        {String? note, String? subtitle}) =>
    showDialog<String>(
      context: context,
      useRootNavigator: true,
      builder: (_) => BookmarkNoteDialog(note: note, subtitle: subtitle),
    );

/// The note editor. Owns its text controller: disposing it as soon as
/// showDialog returned (the dialog is still animating out, its field still
/// focused) threw "A TextEditingController was used after being disposed".
/// Pops with the text on Save, null on Cancel.
class BookmarkNoteDialog extends StatefulWidget {
  const BookmarkNoteDialog({super.key, this.note, this.subtitle});
  final String? note;
  final String? subtitle;

  @override
  State<BookmarkNoteDialog> createState() => _BookmarkNoteDialogState();
}

class _BookmarkNoteDialogState extends State<BookmarkNoteDialog> {
  late final _ctrl = TextEditingController(text: widget.note ?? '');

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext d) {
    return CommonDialog(
      child: Padding(
        padding: const EdgeInsets.only(
            left: RiffSpacing.xl,
            top: RiffSpacing.xxl,
            right: RiffSpacing.xl,
            bottom: RiffSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RiffDialogTitle(
                widget.note == null
                    ? 'bookmarkAddNote'.tr
                    : 'bookmarkEditNote'.tr,
                icon: Icons.edit_note_rounded,
                subtitle: widget.subtitle),
            const SizedBox(height: RiffSpacing.md),
            TextField(
              controller: _ctrl,
              autofocus: true,
              minLines: 2,
              maxLines: 5,
              maxLength: 500,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'bookmarkNoteHint'.tr,
              ),
            ),
            const SizedBox(height: RiffSpacing.sm),
            RiffDialogButton('save'.tr,
                onPressed: () => Navigator.of(d).pop(_ctrl.text)),
            RiffDialogButton('cancel'.tr,
                primary: false, onPressed: () => Navigator.of(d).pop()),
          ],
        ),
      ),
    );
  }
}
