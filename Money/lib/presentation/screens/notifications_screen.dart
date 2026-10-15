import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:money/money.dart';
import 'package:money/data/services/app_notification_service.dart';

class NotificationsScreen extends StatefulWidget {
  final bool active;
  final bool showAppBar;
  const NotificationsScreen({
    super.key,
    this.active = true,
    this.showAppBar = true,
  });
  static void open(BuildContext context) =>
      AppSidebarScope.maybeOf(context)?.openNotifications?.call();
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final service = AppNotificationService.instance;
  bool loading = true;
  String? error;
  @override
  void initState() {
    super.initState();
    service.historyOpen = widget.active;
    if (widget.active) _load();
  }

  @override
  void didUpdateWidget(covariant NotificationsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    service.historyOpen = widget.active;
    if (widget.active && !oldWidget.active) _load();
  }

  @override
  void dispose() {
    service.historyOpen = false;
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        loading = true;
        error = null;
      });
    }
    try {
      await service.start();
      await service.refresh();
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              error = 'Não foi possível carregar. Puxe para tentar novamente.',
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.colors.background,
    appBar: widget.showAppBar
        ? const HomeAppBar(
            title: 'Notificações',
            leading: AppSidebarMenuButton(),
          )
        : null,
    body: AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final items = service.items;
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: loading && items.isEmpty
                ? const CircularProgressIndicator()
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      children: [
                        Text(
                          'Últimas 24 horas',
                          style: TextStyle(
                            color: context.colors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (error != null) Text(error!),
                        if (items.isEmpty && error == null)
                          const Padding(
                            padding: EdgeInsets.all(32),
                            child: Text(
                              'Nenhuma notificação nas últimas 24 horas.',
                              style: TextStyle(fontSize: 12),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        for (final item in items)
                          Card(
                            color: context.colors.surface,
                            child: ListTile(
                              dense: true,
                              leading: Icon(
                                item.kind == 'PAYMENT'
                                    ? Icons.pix
                                    : Icons.flag_outlined,
                                color: context.colors.primary,
                                size: 22,
                              ),
                              title: Text(
                                item.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                              subtitle: Text(
                                '${item.body}\n${DateFormat('dd/MM HH:mm').format(item.createdAt.toLocal())}',
                                style: TextStyle(
                                  fontSize: 11,
                                  height: 1.4,
                                  color: context.colors.textSecondary,
                                ),
                              ),
                              isThreeLine: true,
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
        );
      },
    ),
  );
}

class NotificationPreferencesCard extends StatefulWidget {
  const NotificationPreferencesCard({super.key});
  @override
  State<NotificationPreferencesCard> createState() =>
      _NotificationPreferencesCardState();
}

class _NotificationPreferencesCardState
    extends State<NotificationPreferencesCard> {
  final service = AppNotificationService.instance;
  bool busy = false;
  Future<void> _change(bool payment, bool enabled) async {
    setState(() => busy = true);
    try {
      await service.setPreference(payment: payment, enabled: enabled);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: service,
    builder: (context, _) => SettingCard(
      title: 'NOTIFICAÇÕES',
      children: [
        SettingTile(
          title: 'Pagamentos PIX',
          subtitle: 'Avisar sobre pagamentos recebidos nas suas regiões.',
          materialIcon: Icons.pix,
          hasDivider: true,
          trailing: Transform.scale(
            scale: .75,
            child: Switch(
              value: service.payments,
              onChanged: busy ? null : (v) => _change(true, v),
            ),
          ),
        ),
        SettingTile(
          title: 'Metas atingidas',
          subtitle: 'Avisar quando uma meta das suas regiões for alcançada.',
          materialIcon: Icons.flag_outlined,
          trailing: Transform.scale(
            scale: .75,
            child: Switch(
              value: service.goals,
              onChanged: busy ? null : (v) => _change(false, v),
            ),
          ),
        ),
      ],
    ),
  );
}
