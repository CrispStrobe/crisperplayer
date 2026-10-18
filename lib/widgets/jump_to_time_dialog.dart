import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/format.dart';

Future<Duration?> showJumpToTimeDialog(
  BuildContext context, {
  required Duration position,
  required Duration duration,
  bool wholeBook = true,
}) => showDialog<Duration>(
  context: context,
  builder: (_) => JumpToTimeDialog(
    position: position,
    duration: duration,
    wholeBook: wholeBook,
  ),
);

class JumpToTimeDialog extends StatefulWidget {
  final Duration position, duration;
  final bool wholeBook;
  const JumpToTimeDialog({
    super.key,
    required this.position,
    required this.duration,
    this.wholeBook = true,
  });
  @override
  State<JumpToTimeDialog> createState() => _JumpToTimeDialogState();
}

class _JumpToTimeDialogState extends State<JumpToTimeDialog> {
  late final controller =
      TextEditingController(text: formatDuration(widget.position))
        ..selection = TextSelection(
          baseOffset: 0,
          extentOffset: formatDuration(widget.position).length,
        );
  String? error;
  void submit() {
    try {
      final target = parseTimecode(controller.text);
      if (target > widget.duration) {
        throw FormatException(
          'Enter a time up to ${formatDuration(widget.duration)}.',
        );
      }
      Navigator.pop(context, target);
    } on FormatException catch (e) {
      setState(() => error = e.message);
    }
  }

  void adjust(int seconds) {
    Duration current;
    try {
      current = parseTimecode(controller.text);
    } on FormatException {
      current = widget.position;
    }
    final target = (current.inSeconds + seconds).clamp(
      0,
      widget.duration.inSeconds,
    );
    controller.text = formatDuration(Duration(seconds: target));
    setState(() => error = null);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Jump to time'),
    content: SizedBox(
      width: 360,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.wholeBook
                  ? 'Position from the start of the book'
                  : 'Position in the current track',
            ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('jump-time-input'),
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.datetime,
              autocorrect: false,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9:.]')),
              ],
              decoration: InputDecoration(
                labelText: 'Time',
                helperText: 'HH:MM:SS, MM:SS or seconds',
                errorText: error,
                errorMaxLines: 3,
              ),
              onChanged: (_) {
                if (error != null) setState(() => error = null);
              },
              onSubmitted: (_) => submit(),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () => adjust(-30),
                  child: const Text('−30 seconds'),
                ),
                OutlinedButton(
                  onPressed: () => adjust(30),
                  child: const Text('+30 seconds'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Duration ${formatDuration(widget.duration)}'),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: submit, child: const Text('Jump')),
    ],
  );
}
