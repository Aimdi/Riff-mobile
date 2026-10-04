import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/services/audiobookshelf_service.dart';
import '/ui/theme/riff_spacing.dart';
import '/ui/theme/riff_tokens.dart';
import '../../widgets/snackbar.dart';

void _toast(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
      .showSnackBar(snackbar(context, text, size: SanckBarSize.BIG));
}

/// Bottom sheet to upload a new audiobook to the connected Audiobookshelf
/// server: pick audio file(s), set title/author/series and target folder,
/// then POST /api/upload with a live progress bar.
class AudiobookUploadSheet extends StatefulWidget {
  const AudiobookUploadSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        useRootNavigator: true,
        builder: (_) => const AudiobookUploadSheet(),
      );

  @override
  State<AudiobookUploadSheet> createState() => _AudiobookUploadSheetState();
}

class _AudiobookUploadSheetState extends State<AudiobookUploadSheet> {
  final _title = TextEditingController();
  final _author = TextEditingController();
  final _series = TextEditingController();

  final List<AbsUploadFile> _files = [];
  String? _folderId;
  bool _uploading = false;
  double _progress = 0;
  CancelToken? _cancel;

  @override
  void initState() {
    super.initState();
    final lib = Get.find<AudiobookshelfService>().selectedLibrary;
    if (lib != null && lib.folders.isNotEmpty) {
      _folderId = lib.folders.first.id;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _author.dispose();
    _series.dispose();
    _cancel?.cancel();
    super.dispose();
  }

  Future<void> _pickFiles() async {
    // No `withData`: an audiobook is hundreds of megabytes and the picker
    // would decode every selected file into the heap before the upload even
    // starts. Paths only — dio streams the bytes off disk while sending.
    final res = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.audio,
      withData: false,
    );
    if (res == null) return;
    setState(() {
      for (final f in res.files) {
        final path = f.path;
        if (path != null && path.isNotEmpty) {
          _files.add(AbsUploadFile(filename: f.name, path: path));
        } else if (f.bytes != null) {
          _files.add(AbsUploadFile(filename: f.name, bytes: f.bytes!));
        }
      }
      // Default the title to the first file's name (without extension).
      if (_title.text.trim().isEmpty && _files.isNotEmpty) {
        final n = _files.first.filename;
        final dot = n.lastIndexOf('.');
        _title.text = dot > 0 ? n.substring(0, dot) : n;
      }
    });
  }

  Future<void> _submit() async {
    final abs = Get.find<AudiobookshelfService>();
    final lib = abs.selectedLibrary;
    if (_title.text.trim().isEmpty) {
      _toast(context, 'titleRequired'.tr);
      return;
    }
    if (_files.isEmpty) {
      _toast(context, 'noFilesSelected'.tr);
      return;
    }
    if (lib == null || _folderId == null) return;

    setState(() {
      _uploading = true;
      _progress = 0;
    });
    _cancel = CancelToken();
    try {
      await abs.uploadBook(
        libraryId: lib.id,
        folderId: _folderId!,
        title: _title.text.trim(),
        author: _author.text,
        series: _series.text,
        files: _files,
        cancelToken: _cancel,
        onProgress: (p) => setState(() => _progress = p),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      _toast(context, 'uploadComplete'.tr);
    } on StateError catch (e) {
      if (!mounted) return;
      // Known error keys are localized; anything else shows verbatim.
      final msg = e.message == 'absUploadForbidden'
          ? 'absUploadForbidden'.tr
          : '${'uploadFailed'.tr}: ${e.message}';
      setState(() => _uploading = false);
      _toast(context, msg);
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      _toast(context, '${'uploadFailed'.tr}: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lib = Get.find<AudiobookshelfService>().selectedLibrary;
    final folders = lib?.folders ?? const <AbsFolder>[];
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(
          left: RiffSpacing.lg,
          top: RiffSpacing.lg,
          right: RiffSpacing.lg,
          bottom: RiffSpacing.lg + bottomInset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.cloud_upload_outlined,
                    size: RiffComponentSizes.headerIcon),
                const SizedBox(width: RiffSpacing.md),
                Text('uploadAudiobook'.tr, style: theme.textTheme.titleLarge),
              ],
            ),
            const SizedBox(height: RiffSpacing.lg),
            OutlinedButton.icon(
              onPressed: _uploading ? null : _pickFiles,
              icon: const Icon(Icons.audio_file_outlined,
                  size: RiffComponentSizes.trailingIcon),
              label: Text('chooseFiles'.tr),
            ),
            if (_files.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: RiffSpacing.sm),
                child: Text('noFilesSelected'.tr,
                    style: theme.textTheme.bodySmall),
              )
            else
              Padding(
                padding: const EdgeInsets.only(top: RiffSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < _files.length; i++)
                      // File row: glyphs in the secondary colour, name
                      // in bodyMedium (the sheet itself is Phase 8).
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: RiffSpacing.xxs),
                        child: Row(
                          children: [
                            Icon(Icons.music_note,
                                size: RiffComponentSizes.chipLeadingIcon,
                                color: theme.colorScheme.onSurfaceVariant),
                            const SizedBox(width: RiffSpacing.sm),
                            Expanded(
                              child: Text(_files[i].filename,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.colorScheme.onSurface)),
                            ),
                            if (!_uploading)
                              InkWell(
                                onTap: () => setState(() => _files.removeAt(i)),
                                child: Padding(
                                  padding: const EdgeInsets.all(RiffSpacing.xs),
                                  child: Icon(Icons.close,
                                      size: RiffComponentSizes.chipLeadingIcon,
                                      color:
                                          theme.colorScheme.onSurfaceVariant),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: RiffSpacing.md),
            TextField(
              controller: _title,
              enabled: !_uploading,
              decoration: InputDecoration(
                labelText: 'title'.tr,
                isDense: true,
              ),
            ),
            const SizedBox(height: RiffSpacing.md),
            TextField(
              controller: _author,
              enabled: !_uploading,
              decoration: InputDecoration(
                labelText: 'author'.tr,
                isDense: true,
              ),
            ),
            const SizedBox(height: RiffSpacing.md),
            TextField(
              controller: _series,
              enabled: !_uploading,
              decoration: InputDecoration(
                labelText: 'series'.tr,
                isDense: true,
              ),
            ),
            if (folders.length > 1) ...[
              const SizedBox(height: RiffSpacing.md),
              DropdownButtonFormField<String>(
                value: _folderId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'targetFolder'.tr,
                  isDense: true,
                ),
                items: folders
                    .map((f) => DropdownMenuItem(
                          value: f.id,
                          child: Text(f.fullPath,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged:
                    _uploading ? null : (v) => setState(() => _folderId = v),
              ),
            ],
            const SizedBox(height: RiffSpacing.xl),
            if (_uploading) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(RiffRadii.xs),
                child: LinearProgressIndicator(
                  value: _progress == 0 ? null : _progress,
                ),
              ),
              const SizedBox(height: RiffSpacing.sm),
              Text('${'uploading'.tr} ${(_progress * 100).round()}%',
                  style: theme.textTheme.bodySmall),
              const SizedBox(height: RiffSpacing.sm),
              Center(
                child: TextButton(
                  onPressed: () => _cancel?.cancel(),
                  child: Text('cancel'.tr),
                ),
              ),
            ] else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text('cancel'.tr),
                    ),
                  ),
                  const SizedBox(width: RiffSpacing.md),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _submit,
                      icon: const Icon(Icons.cloud_upload,
                          size: RiffComponentSizes.trailingIcon),
                      label: Text('upload'.tr),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
