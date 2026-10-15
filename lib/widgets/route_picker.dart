import 'package:flutter/material.dart';

import '../pricing.dart';

Future<Json?> showRoutePicker(
  BuildContext context,
  String title,
  List<Json> options,
  String Function(Json) label,
) => showModalBottomSheet<Json>(
  context: context,
  useSafeArea: true,
  isScrollControlled: true,
  builder: (context) =>
      _RoutePicker(title: title, options: options, label: label),
);

class _RoutePicker extends StatefulWidget {
  const _RoutePicker({
    required this.title,
    required this.options,
    required this.label,
  });
  final String title;
  final List<Json> options;
  final String Function(Json) label;
  @override
  State<_RoutePicker> createState() => _RoutePickerState();
}

class _RoutePickerState extends State<_RoutePicker> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final filtered = widget.options
        .where(
          (r) => widget.label(r).toLowerCase().contains(query.toLowerCase()),
        )
        .toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .72,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close ramp choices',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            if (widget.options.length > 6)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: SearchBar(
                  hintText: 'Search ramps',
                  leading: const Icon(Icons.search),
                  onChanged: (value) => setState(() => query = value),
                ),
              ),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(child: Text('No matching ramps'))
                  : ListView.separated(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) => ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 8,
                        ),
                        title: Text(widget.label(filtered[i])),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.pop(context, filtered[i]),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
