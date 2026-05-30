import 'dart:io';

import 'package:flutter/material.dart';

import '../core/enums.dart';

class PersonAvatar extends StatelessWidget {
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

  IconData get _fallbackIcon {
    switch (type) {
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
    if (avatarPath != null && avatarPath!.isNotEmpty && File(avatarPath!).existsSync()) {
      avatar = CircleAvatar(
        radius: radius,
        backgroundImage: FileImage(File(avatarPath!)),
      );
    } else {
      avatar = CircleAvatar(
        radius: radius,
        backgroundColor: colorScheme.primaryContainer,
        child: Icon(_fallbackIcon, color: colorScheme.onPrimaryContainer, size: radius),
      );
    }

    if (onTap == null) return avatar;
    return GestureDetector(onTap: onTap, child: avatar);
  }
}
