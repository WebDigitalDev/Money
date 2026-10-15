import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:money/money.dart';

const double appMobileFilterDrawerWidthFactor = .70;

Future<T?> showAppSideDrawer<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  double maxWidth = 560,
  bool fromStart = false,
  double compactInset = 0,
  bool barrierDismissible = false,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: 'Fechar painel lateral',
    barrierColor: Colors.black.withValues(alpha: 0.42),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (dialogContext, _, _) {
      final Size screenSize = MediaQuery.sizeOf(dialogContext);
      final bool compact = screenSize.width < 600;
      final double availableWidth = math.max(
        280,
        screenSize.width - (compact ? compactInset : 0),
      );
      final double preferredWidth = compact
          ? availableWidth
          : math.max(480, screenSize.width * 0.38);
      final double drawerWidth = math.min(
        availableWidth,
        math.min(maxWidth, preferredWidth),
      );
      return SafeArea(
        left: fromStart,
        right: !fromStart,
        child: Align(
          alignment: fromStart
              ? AlignmentDirectional.centerStart
              : AlignmentDirectional.centerEnd,
          child: Material(
            color: dialogContext.colors.surface,
            elevation: 20,
            shadowColor: Colors.black.withValues(alpha: 0.26),
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadiusDirectional.horizontal(
                start: fromStart ? Radius.zero : const Radius.circular(24),
                end: fromStart ? const Radius.circular(24) : Radius.zero,
              ),
            ),
            child: SizedBox(
              width: drawerWidth,
              height: double.infinity,
              child: builder(dialogContext),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (_, animation, _, child) => SlideTransition(
      position: Tween<Offset>(
        begin: Offset(fromStart ? -1 : 1, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
      child: child,
    ),
  );
}

Future<T?> showAppDialog<T>({
  required BuildContext context,
  required String title,
  required String subtitle,
  required IconData icon,
  required WidgetBuilder builder,
  double maxWidth = 680,
  double? maxHeight,
  bool barrierDismissible = false,
  ValueListenable<bool>? canCloseListenable,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierColor: Colors.black.withValues(alpha: 0.48),
    builder: (dialogContext) {
      final Size screenSize = MediaQuery.sizeOf(dialogContext);
      final bool compact = screenSize.width < 600;
      final double horizontalInset = compact ? 20 : 32;
      final double verticalInset = compact ? 18 : 32;
      final double dialogWidth = math.min(
        maxWidth,
        screenSize.width - (horizontalInset * 2),
      );
      final double availableHeight = math.max(
        240,
        screenSize.height -
            (verticalInset * 2) -
            MediaQuery.viewInsetsOf(dialogContext).vertical,
      );
      final double dialogHeight = maxHeight == null
          ? availableHeight
          : math.min(maxHeight, availableHeight);

      final Widget dialog = Dialog(
        insetPadding: EdgeInsets.symmetric(
          horizontal: horizontalInset,
          vertical: verticalInset,
        ),
        clipBehavior: Clip.antiAlias,
        backgroundColor: dialogContext.colors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 18,
        shadowColor: Colors.black.withValues(alpha: 0.24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(compact ? 24 : 22),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: dialogWidth,
            maxHeight: dialogHeight,
          ),
          child: SizedBox(
            width: dialogWidth,
            height: maxHeight == null ? null : dialogHeight,
            child: AppDialogPanel(
              title: title,
              subtitle: subtitle,
              icon: icon,
              compact: compact,
              canCloseListenable: canCloseListenable,
              child: builder(dialogContext),
            ),
          ),
        ),
      );
      if (canCloseListenable == null) return dialog;
      return ValueListenableBuilder<bool>(
        valueListenable: canCloseListenable,
        child: dialog,
        builder: (_, canClose, child) =>
            PopScope<void>(canPop: canClose, child: child!),
      );
    },
  );
}

Future<T?> showAppBottomSheet<T>({
  required BuildContext context,
  required String title,
  required String subtitle,
  required IconData icon,
  required WidgetBuilder builder,
  double heightFactor = 0.82,
  bool compact = true,
  bool desktopDialog = false,
}) {
  final double effectiveHeight = compact
      ? (heightFactor * .90).clamp(.38, .88)
      : heightFactor;
  final Size screenSize = MediaQuery.sizeOf(context);
  final bool desktop = desktopDialog && kIsWeb && screenSize.width >= 1024;
  if (desktop) {
    final double dialogHeight = math.min(
      screenSize.height - 64,
      math.max(380, screenSize.height * effectiveHeight),
    );
    return showDialog<T>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.48),
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.all(32),
        clipBehavior: Clip.antiAlias,
        backgroundColor: dialogContext.colors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 18,
        shadowColor: Colors.black.withValues(alpha: 0.24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        child: SizedBox(
          width: math.min(620, screenSize.width - 64),
          height: dialogHeight,
          child: AppBottomSheet(
            title: title,
            subtitle: subtitle,
            icon: icon,
            compact: compact,
            child: builder(dialogContext),
          ),
        ),
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    enableDrag: true,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    elevation: 0,
    barrierColor: Colors.black.withValues(alpha: 0.42),
    builder: (sheetContext) => FractionallySizedBox(
      widthFactor: 1,
      heightFactor: effectiveHeight,
      child: AppBottomSheet(
        title: title,
        subtitle: subtitle,
        icon: icon,
        compact: compact,
        child: builder(sheetContext),
      ),
    ),
  );
}

class AppDialogPanel extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;
  final bool compact;
  final ValueListenable<bool>? canCloseListenable;

  const AppDialogPanel({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
    this.compact = false,
    this.canCloseListenable,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.surface,
      elevation: 18,
      shadowColor: Colors.black.withValues(alpha: 0.22),
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 14 : 17,
              compact ? 11 : 14,
              compact ? 7 : 10,
              compact ? 9 : 11,
            ),
            child: Row(
              children: [
                Container(
                  width: compact ? 38 : 42,
                  height: compact ? 38 : 42,
                  decoration: BoxDecoration(
                    color: context.colors.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    icon,
                    size: compact ? 20 : 22,
                    color: context.colors.primary,
                  ),
                ),
                SizedBox(width: compact ? 10 : 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.colors.textPrimary,
                          fontSize: compact ? 16 : 17,
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.colors.textSecondary,
                          fontSize: compact ? 10.5 : 11.5,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 5),
                if (canCloseListenable == null)
                  _closeButton(context, enabled: true)
                else
                  ValueListenableBuilder<bool>(
                    valueListenable: canCloseListenable!,
                    builder: (_, canClose, _) =>
                        _closeButton(context, enabled: canClose),
                  ),
              ],
            ),
          ),
          Flexible(child: SafeArea(top: false, child: child)),
        ],
      ),
    );
  }

  Widget _closeButton(BuildContext context, {required bool enabled}) =>
      IconButton(
        onPressed: enabled ? () => Navigator.pop(context) : null,
        color: context.colors.textSecondary,
        disabledColor: context.colors.disabled,
        padding: const EdgeInsets.all(5),
        constraints: const BoxConstraints.tightFor(width: 32, height: 32),
        visualDensity: VisualDensity.compact,
        tooltip: enabled ? 'Fechar' : 'Aguarde a conclusão',
        icon: const Icon(Icons.close_rounded, size: 21),
      );
}

Future<String?> showAppTextInputBottomSheet({
  required BuildContext context,
  required String title,
  required String subtitle,
  required String label,
  required IconData icon,
  String actionLabel = 'Salvar',
  TextInputType? keyboardType,
}) {
  return showAppBottomSheet<String>(
    context: context,
    title: title,
    subtitle: subtitle,
    icon: icon,
    heightFactor: .46,
    builder: (_) => _AppTextInputSheet(
      label: label,
      actionLabel: actionLabel,
      keyboardType: keyboardType,
    ),
  );
}

Future<DateTime?> showAppDatePickerBottomSheet({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  String title = 'Selecionar data',
  String subtitle = 'Escolha a data desejada.',
  Locale? locale,
  bool desktopDialog = false,
}) {
  return showAppBottomSheet<DateTime>(
    context: context,
    title: title,
    subtitle: subtitle,
    icon: Icons.calendar_month_outlined,
    heightFactor: .72,
    desktopDialog: desktopDialog,
    builder: (_) => _AppDatePickerSheet(
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      locale: locale,
    ),
  );
}

Future<DateTime?> showAppDatePickerDialog({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  String title = 'Selecionar data',
  String subtitle = 'Escolha a data desejada.',
  Locale? locale,
}) {
  return showAppDialog<DateTime>(
    context: context,
    title: title,
    subtitle: subtitle,
    icon: Icons.calendar_month_outlined,
    maxWidth: 400,
    maxHeight: 455,
    builder: (_) => _AppDatePickerSheet(
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      locale: locale,
      dialogStyle: true,
    ),
  );
}

class _AppDatePickerSheet extends StatefulWidget {
  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final Locale? locale;
  final bool dialogStyle;

  const _AppDatePickerSheet({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    this.locale,
    this.dialogStyle = false,
  });

  @override
  State<_AppDatePickerSheet> createState() => _AppDatePickerSheetState();
}

class _AppDatePickerSheetState extends State<_AppDatePickerSheet> {
  late DateTime _selected;
  late DateTime _visibleMonth;
  final ScrollController _yearScrollController = ScrollController();
  bool _selectingYear = false;

  static const List<String> _monthNames = [
    'janeiro',
    'fevereiro',
    'março',
    'abril',
    'maio',
    'junho',
    'julho',
    'agosto',
    'setembro',
    'outubro',
    'novembro',
    'dezembro',
  ];

  @override
  void initState() {
    super.initState();
    final DateTime initial = DateUtils.dateOnly(widget.initialDate);
    final DateTime first = DateUtils.dateOnly(widget.firstDate);
    final DateTime last = DateUtils.dateOnly(widget.lastDate);
    _selected = initial.isBefore(first)
        ? first
        : initial.isAfter(last)
        ? last
        : initial;
    _visibleMonth = DateTime(_selected.year, _selected.month);
  }

  @override
  void dispose() {
    _yearScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget calendar = Localizations.override(
      context: context,
      locale: widget.locale,
      child: CalendarDatePicker(
        initialDate: _selected,
        firstDate: DateUtils.dateOnly(widget.firstDate),
        lastDate: DateUtils.dateOnly(widget.lastDate),
        onDateChanged: (value) => setState(() => _selected = value),
      ),
    );

    if (widget.dialogStyle) {
      return Material(
        color: context.colors.surface,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 2, 12, 12),
          child: Column(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: context.colors.background,
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: context.colors.divider),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _buildCompactCalendar(context),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 40,
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: context.colors.textPrimary,
                          side: BorderSide(color: context.colors.divider),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('CANCELAR'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(context, _selected),
                        style: FilledButton.styleFrom(
                          backgroundColor: context.colors.primary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('CONFIRMAR'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Material(
      color: context.colors.background,
      child: Column(
        children: [
          Expanded(child: calendar),
          Divider(height: 1, color: context.colors.divider),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('CANCELAR'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, _selected),
                    child: const Text('SELECIONAR'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactCalendar(BuildContext context) {
    final DateTime firstMonth = DateTime(
      widget.firstDate.year,
      widget.firstDate.month,
    );
    final DateTime lastMonth = DateTime(
      widget.lastDate.year,
      widget.lastDate.month,
    );
    final bool canGoBack = _visibleMonth.isAfter(firstMonth);
    final bool canGoForward = _visibleMonth.isBefore(lastMonth);

    return Column(
      children: [
        SizedBox(
          height: 42,
          child: Row(
            children: [
              const SizedBox(width: 6),
              TextButton(
                onPressed: _toggleYearSelection,
                style: TextButton.styleFrom(
                  foregroundColor: context.colors.textPrimary,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  visualDensity: VisualDensity.compact,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${_monthNames[_visibleMonth.month - 1]} de ${_visibleMonth.year}',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                    const SizedBox(width: 3),
                    Icon(
                      _selectingYear
                          ? Icons.arrow_drop_up_rounded
                          : Icons.arrow_drop_down_rounded,
                      size: 18,
                    ),
                  ],
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Mês anterior',
                onPressed: canGoBack ? () => _changeMonth(-1) : null,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.chevron_left_rounded, size: 20),
              ),
              IconButton(
                tooltip: 'Próximo mês',
                onPressed: canGoForward ? () => _changeMonth(1) : null,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.chevron_right_rounded, size: 20),
              ),
              const SizedBox(width: 2),
            ],
          ),
        ),
        Divider(height: 1, color: context.colors.divider),
        Expanded(
          child: _selectingYear
              ? _buildYearGrid(context)
              : _buildDayGrid(context),
        ),
      ],
    );
  }

  Widget _buildYearGrid(BuildContext context) {
    final int firstYear = widget.firstDate.year;
    final int lastYear = widget.lastDate.year;
    final int yearCount = lastYear - firstYear + 1;
    return Scrollbar(
      controller: _yearScrollController,
      thumbVisibility: true,
      child: GridView.builder(
        controller: _yearScrollController,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        physics: const ClampingScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 2.15,
          crossAxisSpacing: 8,
          mainAxisSpacing: 5,
        ),
        itemCount: yearCount,
        itemBuilder: (context, index) {
          final int year = firstYear + index;
          final bool selected = year == _visibleMonth.year;
          return Center(
            child: InkWell(
              onTap: () => _selectYear(year),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                constraints: const BoxConstraints(minWidth: 66, minHeight: 34),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: selected ? context.colors.primary : null,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$year',
                  style: TextStyle(
                    color: selected ? Colors.white : context.colors.textPrimary,
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _toggleYearSelection() {
    final bool selectingYear = !_selectingYear;
    setState(() => _selectingYear = selectingYear);
    if (selectingYear) _scrollToSelectedYear();
  }

  void _scrollToSelectedYear() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_selectingYear || !_yearScrollController.hasClients) {
        return;
      }
      final int selectedIndex = _visibleMonth.year - widget.firstDate.year;
      final int selectedRow = selectedIndex ~/ 3;
      final double availableWidth = (context.size?.width ?? 400) - 52;
      final double itemWidth = availableWidth / 3;
      final double rowExtent = (itemWidth / 2.15) + 5;
      final ScrollPosition position = _yearScrollController.position;
      final double target =
          (selectedRow * rowExtent) -
          ((position.viewportDimension - rowExtent) / 2);
      _yearScrollController.jumpTo(target.clamp(0.0, position.maxScrollExtent));
    });
  }

  Widget _buildDayGrid(BuildContext context) {
    const List<String> weekdays = ['D', 'S', 'T', 'Q', 'Q', 'S', 'S'];
    final DateTime firstDay = DateTime(_visibleMonth.year, _visibleMonth.month);
    final int leadingDays = firstDay.weekday % DateTime.daysPerWeek;
    final int daysInMonth = DateTime(
      _visibleMonth.year,
      _visibleMonth.month + 1,
      0,
    ).day;
    final DateTime today = DateUtils.dateOnly(DateTime.now());
    final DateTime firstAllowed = DateUtils.dateOnly(widget.firstDate);
    final DateTime lastAllowed = DateUtils.dateOnly(widget.lastDate);

    return Column(
      children: [
        SizedBox(
          height: 32,
          child: Row(
            children: [
              for (final String weekday in weekdays)
                Expanded(
                  child: Center(
                    child: Text(
                      weekday,
                      style: TextStyle(
                        color: context.colors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(7, 0, 7, 7),
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 1.15,
            ),
            itemCount: 42,
            itemBuilder: (context, index) {
              final int day = index - leadingDays + 1;
              if (day < 1 || day > daysInMonth) {
                return const SizedBox.shrink();
              }
              final DateTime date = DateTime(
                _visibleMonth.year,
                _visibleMonth.month,
                day,
              );
              final bool allowed =
                  !date.isBefore(firstAllowed) && !date.isAfter(lastAllowed);
              final bool selected = DateUtils.isSameDay(date, _selected);
              final bool isToday = DateUtils.isSameDay(date, today);
              return Center(
                child: InkWell(
                  onTap: allowed
                      ? () => setState(() => _selected = date)
                      : null,
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 31,
                    height: 31,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected ? context.colors.primary : null,
                      shape: BoxShape.circle,
                      border: isToday && !selected
                          ? Border.all(color: context.colors.primary)
                          : null,
                    ),
                    child: Text(
                      '$day',
                      style: TextStyle(
                        color: !allowed
                            ? context.colors.disabled.withValues(alpha: 0.55)
                            : selected
                            ? Colors.white
                            : context.colors.textPrimary,
                        fontSize: 12,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _changeMonth(int offset) {
    final DateTime candidate = DateTime(
      _visibleMonth.year,
      _visibleMonth.month + offset,
    );
    final DateTime firstMonth = DateTime(
      widget.firstDate.year,
      widget.firstDate.month,
    );
    final DateTime lastMonth = DateTime(
      widget.lastDate.year,
      widget.lastDate.month,
    );
    setState(() {
      _visibleMonth = candidate.isBefore(firstMonth)
          ? firstMonth
          : candidate.isAfter(lastMonth)
          ? lastMonth
          : candidate;
      _selectingYear = false;
    });
  }

  void _selectYear(int year) {
    final DateTime candidate = DateTime(year, _visibleMonth.month);
    final DateTime firstMonth = DateTime(
      widget.firstDate.year,
      widget.firstDate.month,
    );
    final DateTime lastMonth = DateTime(
      widget.lastDate.year,
      widget.lastDate.month,
    );
    setState(() {
      _visibleMonth = candidate.isBefore(firstMonth)
          ? firstMonth
          : candidate.isAfter(lastMonth)
          ? lastMonth
          : candidate;
      _selectingYear = false;
    });
  }
}

class _AppTextInputSheet extends StatefulWidget {
  final String label;
  final String actionLabel;
  final TextInputType? keyboardType;

  const _AppTextInputSheet({
    required this.label,
    required this.actionLabel,
    this.keyboardType,
  });

  @override
  State<_AppTextInputSheet> createState() => _AppTextInputSheetState();
}

class _AppTextInputSheetState extends State<_AppTextInputSheet> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.background,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          14,
          16,
          14,
          14 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: widget.keyboardType,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(labelText: widget.label),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _submit,
            child: Text(widget.actionLabel.toUpperCase()),
          ),
          const SizedBox(height: 6),
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCELAR'),
          ),
        ],
      ),
    );
  }

  void _submit() => Navigator.pop(context, _controller.text);
}

class AppBottomSheet extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;
  final bool compact;

  const AppBottomSheet({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
    this.compact = true,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppPanelHeader(
            title: title,
            subtitle: subtitle,
            icon: icon,
            compact: compact,
            onClose: () => Navigator.pop(context),
          ),
          Expanded(child: SafeArea(top: false, child: child)),
        ],
      ),
    );
  }
}

class AppPanelHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onClose;
  final bool compact;

  const AppPanelHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onClose,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border(
          bottom: BorderSide(
            color: context.colors.divider.withValues(alpha: .7),
          ),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        compact ? 14 : 16,
        compact ? 9 : 13,
        compact ? 7 : 9,
        compact ? 9 : 12,
      ),
      child: Row(
        children: [
          Container(
            width: compact ? 36 : 42,
            height: compact ? 36 : 42,
            decoration: BoxDecoration(
              color: context.colors.primary.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(compact ? 10 : 12),
              border: Border.all(
                color: context.colors.primary.withValues(alpha: .10),
              ),
            ),
            child: Icon(
              icon,
              color: context.colors.primary,
              size: compact ? 19 : 22,
            ),
          ),
          SizedBox(width: compact ? 10 : 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: compact ? 15 : 16.5,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: compact ? 10 : 11,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onClose,
            color: context.colors.textSecondary,
            padding: const EdgeInsets.all(5),
            constraints: const BoxConstraints.tightFor(width: 34, height: 34),
            visualDensity: VisualDensity.compact,
            tooltip: 'Fechar',
            icon: const Icon(Icons.close_rounded, size: 21),
          ),
        ],
      ),
    );
  }
}

class AppFilterSectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;
  final bool expandChild;

  const AppFilterSectionCard({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
    this.expandChild = false,
  });

  @override
  Widget build(BuildContext context) {
    final Widget content = Column(
      mainAxisSize: expandChild ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: context.colors.primary.withValues(alpha: .09),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 16, color: context.colors.primary),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 6), trailing!],
          ],
        ),
        const SizedBox(height: 9),
        if (expandChild) Expanded(child: child) else child,
      ],
    );

    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          context.colors.surface.withValues(alpha: .78),
          context.colors.background,
        ),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: context.colors.divider.withValues(alpha: .75),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: context.isDark ? .12 : .035),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: content,
    );
  }
}

class AppFilterActionBar extends StatelessWidget {
  final VoidCallback onClear;
  final VoidCallback onApply;
  final bool equalWidths;

  const AppFilterActionBar({
    super.key,
    required this.onClear,
    required this.onApply,
    this.equalWidths = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border(
          top: BorderSide(color: context.colors.divider.withValues(alpha: .7)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 40,
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onClear,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.colors.textPrimary,
                    side: BorderSide(color: context.colors.divider),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('LIMPAR'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: equalWidths ? 1 : 2,
                child: FilledButton(
                  onPressed: onApply,
                  style: FilledButton.styleFrom(
                    backgroundColor: context.colors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('APLICAR'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ModalBottomSheet extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsetsGeometry? padding;
  final MainAxisAlignment mainAxisAlignment;
  final CrossAxisAlignment crossAxisAlignment;
  final double? heightFactor;

  const ModalBottomSheet({
    super.key,
    required this.children,
    this.mainAxisAlignment = MainAxisAlignment.start,
    this.crossAxisAlignment = CrossAxisAlignment.center,
    this.heightFactor,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FractionallySizedBox(
        widthFactor: 1,
        heightFactor: heightFactor,
        child: Padding(
          padding: padding ?? const EdgeInsets.only(top: 20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: mainAxisAlignment,
            crossAxisAlignment: crossAxisAlignment,
            children: children,
          ),
        ),
      ),
    );
  }
}
