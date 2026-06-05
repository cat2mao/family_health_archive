import 'dart:io';

import 'package:flutter/material.dart';

import '../core/enums.dart';

class PersonAvatar extends StatefulWidget {
  const PersonAvatar({
    super.key,
    this.avatarPath,
    required this.name,
    required this.type,
    this.radius = 22,
    this.onTap,
  });

  final String? avatarPath;
  final String name;
  final PersonType type;
  final double radius;
  final VoidCallback? onTap;

  @override
  State<PersonAvatar> createState() => _PersonAvatarState();
}

class _PersonAvatarState extends State<PersonAvatar> {
  bool _avatarExists = false;
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    _checkAvatar();
  }

  @override
  void didUpdateWidget(covariant PersonAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.avatarPath != widget.avatarPath) {
      _checkAvatar();
    }
  }

  Future<void> _checkAvatar() async {
    final path = widget.avatarPath;
    if (path != null && path.isNotEmpty) {
      _avatarExists = await File(path).exists();
    } else {
      _avatarExists = false;
    }
    if (mounted) setState(() => _checked = true);
  }

  IconData get _fallbackIcon {
    switch (widget.type) {
      case PersonType.cat:
        return Icons.pets;
      case PersonType.dog:
        return Icons.pets;
      case PersonType.otherPet:
        return Icons.cruelty_free;
      case PersonType.human:
        return Icons.person;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    Widget avatar;
    if (_checked && _avatarExists) {
      avatar = CircleAvatar(
        radius: widget.radius,
        backgroundImage: FileImage(File(widget.avatarPath!)),
      );
    } else {
      avatar = CircleAvatar(
        radius: widget.radius,
        backgroundColor: colorScheme.primaryContainer,
        child: Icon(_fallbackIcon, color: colorScheme.onPrimaryContainer, size: widget.radius),
      );
    }

    if (widget.onTap == null) return avatar;
    return GestureDetector(onTap: widget.onTap, child: avatar);
  }
}
