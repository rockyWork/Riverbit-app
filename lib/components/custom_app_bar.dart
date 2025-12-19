import 'package:flutter/material.dart';

class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final bool centerTitle;
  final bool showBackButton;
  final bool showCloseButton;
  final VoidCallback? onBackPressed;
  final VoidCallback? onClosePressed;
  final List<Widget>? actions;

  const CustomAppBar({
    super.key,
    required this.title,
    this.centerTitle = true,
    this.showBackButton = true,
    this.showCloseButton = false,
    this.onBackPressed,
    this.onClosePressed,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.black87,
        ),
      ),
      centerTitle: centerTitle,
      leading: showBackButton
          ? IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, size: 20, color: Colors.black87),
              onPressed: onBackPressed ?? () => Navigator.of(context).pop(),
            )
          : null,
      actions: [
        if (actions != null) ...actions!,
        if (showCloseButton)
          IconButton(
            icon: const Icon(Icons.close, size: 24, color: Colors.black87),
            onPressed: onClosePressed ?? () => Navigator.of(context).pop(),
          ),
        const SizedBox(width: 8),
      ],
      backgroundColor: Colors.white,
      elevation: 0,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1.0),
        child: Container(
          color: Colors.grey.shade200,
          height: 1.0,
        ),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

