import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../core/motion.dart';
import '../../core/widgets/medicyn_chrome.dart';
import '../../core/widgets/medicyn_layout.dart';
import '../../core/widgets/medicyn_motion.dart';
import '../../core/widgets/medicyn_platform.dart';

/// A page rendered at roughly this many pixels per PDF point (72 dpi) --
/// about 180 dpi, the same ballpark document-scanning apps use for OCR
/// quality without producing an enormous bitmap per page.
const _renderScale = 2.5;

/// Reject anything longer than this outright rather than rendering and
/// OCR'ing dozens of pages one at a time -- the resulting text is exactly
/// as untrusted as a label photo's is today, and this bounds the work
/// before any of it starts.
const _maxPages = 20;

/// Upload path for a prescription that spans more than one page: pick a
/// `.pdf`, render every page to an image on-device, and run the same
/// on-device OCR [OcrCaptureScreen] already uses on each one. Only the
/// extracted text ever leaves this screen -- the PDF and every rendered
/// page image are deleted immediately after reading them, the same
/// "stays on your device, discarded immediately" handling the camera path
/// already promises for a photographed label.
///
/// Pops with the combined text (pages joined with a "PAGE n OF m" marker
/// so the model can reason about document structure), or null if closed
/// without choosing a file.
class PdfPrescriptionCaptureScreen extends StatefulWidget {
  const PdfPrescriptionCaptureScreen({super.key});

  @override
  State<PdfPrescriptionCaptureScreen> createState() =>
      _PdfPrescriptionCaptureScreenState();
}

enum _Status { idle, opening, rendering, error }

class _PdfPrescriptionCaptureScreenState
    extends State<PdfPrescriptionCaptureScreen> {
  _Status _status = _Status.idle;
  String? _error;
  int _pageDone = 0;
  int _pageTotal = 0;

  Future<void> _choosePdf() async {
    setState(() {
      _status = _Status.opening;
      _error = null;
      _pageDone = 0;
      _pageTotal = 0;
    });

    FilePickerResult? result;
    try {
      result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = _Status.error;
        _error = 'Could not open the file picker.';
      });
      return;
    }

    if (!mounted) return;
    final path = result?.files.singleOrNull?.path;
    if (path == null) {
      // Cancelled -- back to idle, not an error.
      setState(() => _status = _Status.idle);
      return;
    }

    await _process(path);
  }

  Future<void> _process(String pdfPath) async {
    await pdfrxFlutterInitialize();

    PdfDocument? document;
    final pageFiles = <String>[];
    try {
      try {
        document = await PdfDocument.openFile(pdfPath);
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _status = _Status.error;
          _error = 'Could not open that PDF. It may be damaged or password-protected.';
        });
        return;
      }

      final pages = document.pages;
      if (pages.isEmpty) {
        if (!mounted) return;
        setState(() {
          _status = _Status.error;
          _error = 'That PDF has no pages.';
        });
        return;
      }
      if (pages.length > _maxPages) {
        if (!mounted) return;
        setState(() {
          _status = _Status.error;
          _error =
              'That PDF has ${pages.length} pages -- please split it to $_maxPages pages or fewer.';
        });
        return;
      }

      if (!mounted) return;
      setState(() {
        _status = _Status.rendering;
        _pageTotal = pages.length;
      });

      final tempDir = await getTemporaryDirectory();
      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final pageTexts = <String>[];
      try {
        for (var i = 0; i < pages.length; i++) {
          final pagePath = await _renderPageToFile(pages[i], tempDir.path, i);
          pageFiles.add(pagePath);
          try {
            final result = await recognizer.processImage(
              InputImage.fromFilePath(pagePath),
            );
            pageTexts.add(result.text);
          } catch (e) {
            // One unreadable page should not sink the whole document --
            // the model still gets whatever the other pages produced, and
            // the review screen's own "could not understand automatically"
            // fallback covers the case where none of them did.
            pageTexts.add('');
          } finally {
            await _deleteFile(pagePath);
          }
          if (!mounted) return;
          setState(() => _pageDone = i + 1);
        }
      } finally {
        await recognizer.close();
      }

      final combined = [
        for (var i = 0; i < pageTexts.length; i++)
          'PAGE ${i + 1} OF ${pageTexts.length}\n${pageTexts[i]}',
      ].join('\n\n---\n\n');

      if (!mounted) return;
      Navigator.of(context).pop(combined);
    } finally {
      await document?.dispose();
      // Best-effort: any page file already removed in the loop above is a
      // no-op here; this only matters if an early return skipped cleanup.
      for (final path in pageFiles) {
        await _deleteFile(path);
      }
      await _deleteFile(pdfPath);
    }
  }

  Future<String> _renderPageToFile(
    PdfPage page,
    String tempDirPath,
    int index,
  ) async {
    final fullWidth = page.width * _renderScale;
    final fullHeight = page.height * _renderScale;
    final pdfImage = await page.render(
      fullWidth: fullWidth,
      fullHeight: fullHeight,
    );
    if (pdfImage == null) {
      throw StateError('page $index failed to render');
    }
    ui.Image image;
    try {
      image = await pdfImage.createImage();
    } finally {
      pdfImage.dispose();
    }
    final ByteData? pngData;
    try {
      pngData = await image.toByteData(format: ui.ImageByteFormat.png);
    } finally {
      image.dispose();
    }
    if (pngData == null) {
      throw StateError('page $index failed to encode');
    }
    final path = p.join(tempDirPath, 'rx_page_$index.png');
    await File(path).writeAsBytes(pngData.buffer.asUint8List());
    return path;
  }

  Future<void> _deleteFile(String path) async {
    try {
      await File(path).delete();
    } catch (_) {
      // Best-effort cleanup; nothing to do if it's already gone.
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final busy = _status == _Status.opening || _status == _Status.rendering;
    return Scaffold(
      appBar: AppBar(
        leading: MedicynAdaptiveBackButton(
          tooltip: 'Close',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const MedicynBrandMark(compact: true),
        centerTitle: true,
      ),
      body: SafeArea(
        child: MedicynContent(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: MedicynFadeIn(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Upload a Prescription',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Choose a PDF of the prescription. Every page is read on this device.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 24),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: ColoredBox(
                              color: scheme.surfaceContainer,
                              child: Center(
                                child: _status == _Status.rendering
                                    ? Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          CircularProgressIndicator(
                                            color: scheme.primary,
                                            value: _pageTotal == 0
                                                ? null
                                                : _pageDone / _pageTotal,
                                          ),
                                          const SizedBox(height: 16),
                                          Text(
                                            _pageTotal == 0
                                                ? 'Opening…'
                                                : 'Reading page $_pageDone of $_pageTotal…',
                                            style: Theme.of(
                                              context,
                                            ).textTheme.bodyMedium,
                                          ),
                                        ],
                                      )
                                    : _status == _Status.opening
                                    ? CircularProgressIndicator(
                                        color: scheme.primary,
                                      )
                                    : Icon(
                                        Icons.picture_as_pdf_outlined,
                                        size: 64,
                                        color: scheme.primaryContainer,
                                      ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        AmbientCard(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.lock_outline, color: scheme.primary),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'The file stays on your device and is securely discarded immediately after reading it.',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                AnimatedSize(
                  duration: MedicynMotion.duration(
                    context,
                    MedicynMotion.fast,
                  ),
                  curve: MedicynMotion.decelerate,
                  alignment: Alignment.topCenter,
                  child: _error == null
                      ? const SizedBox(width: double.infinity)
                      : Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: scheme.error),
                          ),
                        ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: busy ? null : _choosePdf,
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: Text(
                    _status == _Status.error ? 'Choose a different file' : 'Choose PDF',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
