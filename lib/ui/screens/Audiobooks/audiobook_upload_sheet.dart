import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/services/audiobookshelf_service.dart';
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
    );
    if (res == null) return;
    setState(() {
      _files.addAll(absUploadFilesFromPicked(
          res.files.map((f) => (name: f.name, path: f.path))));
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
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.cloud_upload_outlined),
                const SizedBox(width: 10),
                Text('uploadAudiobook'.tr,
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _uploading ? null : _pickFiles,
              icon: const Icon(Icons.audio_file_outlined, size: 20),
              label: Text('chooseFiles'.tr),
            ),
            if (_files.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('noFilesSelected'.tr,
                    style: theme.textTheme.bodySmall),
              )
            else
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < _files.length; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            const Icon(Icons.music_note, size: 16),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(_files[i].filename,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall),
                            ),
                            if (!_uploading)
                              InkWell(
                                onTap: () =>
                                    setState(() => _files.removeAt(i)),
                                child: const Padding(
                                  padding: EdgeInsets.all(4),
                                  child: Icon(Icons.close, size: 16),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 14),
            TextField(
              controller: _title,
              enabled: !_uploading,
              decoration: InputDecoration(
                labelText: 'title'.tr,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _author,
              enabled: !_uploading,
              decoration: InputDecoration(
                labelText: 'author'.tr,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _series,
              enabled: !_uploading,
              decoration: InputDecoration(
                labelText: 'series'.tr,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                isDense: true,
              ),
            ),
            if (folders.length > 1) ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _folderId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'targetFolder'.tr,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  isDense: true,
                ),
                items: folders
                    .map((f) => DropdownMenuItem(
                          value: f.id,
                          child: Text(f.fullPath,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: _uploading
                    ? null
                    : (v) => setState(() => _folderId = v),
              ),
            ],
            const SizedBox(height: 20),
            if (_uploading) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _progress == 0 ? null : _progress,
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 8),
              Text('${'uploading'.tr} ${(_progress * 100).round()}%',
                  style: theme.textTheme.bodySmall),
              const SizedBox(height: 8),
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
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _submit,
                      icon: const Icon(Icons.cloud_upload, size: 18),
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
