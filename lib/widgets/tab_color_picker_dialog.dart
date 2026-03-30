import 'package:flutter/material.dart';

import '../utils/tab_color.dart';

/// Returns picked `#RRGGBB`, `''` for default theme, or `null` if cancelled.
Future<String?> showTabColorPickerDialog(
  BuildContext context, {
  required String? currentHex,
}) {
  return showDialog<String>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: const Text('Tabbladkleur'),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'Kies een kleur zodat leerlingen dit tabblad van andere kunnen onderscheiden.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: <Widget>[
                  _PresetOrb(
                    label: 'Standaard',
                    fill: null,
                    selected: currentHex == null || currentHex.trim().isEmpty,
                    onTap: () => Navigator.of(context).pop(''),
                  ),
                  for (final String hex in kTabColorPresets)
                    _PresetOrb(
                      fill: parseTabColorHex(hex),
                      selected: normalizeTabColorHex(currentHex ?? '') ==
                          normalizeTabColorHex(hex),
                      onTap: () => Navigator.of(context).pop(hex),
                    ),
                ],
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annuleren'),
          ),
        ],
      );
    },
  );
}

class _PresetOrb extends StatelessWidget {
  const _PresetOrb({
    required this.selected,
    required this.onTap,
    this.fill,
    this.label,
  });

  final Color? fill;
  final String? label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const double size = 44;
    return Semantics(
      button: true,
      label: label ?? 'Kleur',
      selected: selected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? theme.colorScheme.primary : theme.dividerColor,
                width: selected ? 3 : 1,
              ),
              color: fill,
            ),
            child: fill == null
                ? Icon(
                    Icons.format_color_reset_rounded,
                    color: theme.colorScheme.onSurfaceVariant,
                    size: 22,
                  )
                : null,
          ),
        ),
      ),
    );
  }
}
