import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ProceedButton extends StatelessWidget {
  const ProceedButton({
    super.key,
    required this.buttonText,
    required this.onPressed,
  });
  final String buttonText;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.secondary,
          foregroundColor: Colors.black,
          minimumSize: const Size(110, 46),
          shape: const StadiumBorder()),
      child: Text(buttonText,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
    );
  }
}

class CancelButton extends StatelessWidget {
  const CancelButton({super.key, this.onPressed});
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      style: TextButton.styleFrom(
          foregroundColor: Theme.of(context).textTheme.titleMedium?.color,
          minimumSize: const Size(110, 46),
          shape: const StadiumBorder()),
      child: Text("cancel".tr,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      onPressed: () {
        Navigator.of(context).pop();
        if (onPressed != null) {
          onPressed!();
        }
      },
    );
  }
}
