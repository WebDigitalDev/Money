import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:money/money.dart';

class AppSidebarMenu extends StatelessWidget {
  final VoidCallback onOpenUsers;
  final VoidCallback onOpenRegions;
  final VoidCallback onOpenClients;
  final VoidCallback onOpenLoans;
  final VoidCallback onOpenFinancialGoals;
  final VoidCallback onOpenRoutes;
  final VoidCallback onOpenReports;
  final VoidCallback onOpenBankingApi;
  final VoidCallback onOpenWhatsappApi;
  final Future<void> Function() onLogout;

  const AppSidebarMenu({
    super.key,
    required this.onOpenUsers,
    required this.onOpenRegions,
    required this.onOpenClients,
    required this.onOpenLoans,
    required this.onOpenFinancialGoals,
    required this.onOpenRoutes,
    required this.onOpenReports,
    required this.onOpenBankingApi,
    required this.onOpenWhatsappApi,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final bool isAdministrator =
        AuthService().currentSession?.administrator ?? false;
    final managementItems = [
      if (isAdministrator)
        _SidebarItemData(
          label: context.tr!.sidebar_users,
          icon: AppIcons.family,
          onTap: onOpenUsers,
          color: const Color(0xFF7C8CFF),
        ),
      _SidebarItemData(
        label: context.tr!.sidebar_regions,
        icon: AppIcons.home,
        onTap: onOpenRegions,
        color: const Color(0xFF34C0FF),
      ),
      _SidebarItemData(
        label: context.tr!.sidebar_clients,
        icon: AppIcons.person,
        onTap: onOpenClients,
        color: const Color(0xFF59D7A1),
      ),
      _SidebarItemData(
        label: context.tr!.sidebar_loans,
        icon: AppIcons.loan,
        onTap: onOpenLoans,
        color: const Color(0xFFFF8E6E),
      ),
      _SidebarItemData(
        label: context.tr!.sidebar_financial_goals,
        icon: AppIcons.financialSummary,
        onTap: onOpenFinancialGoals,
        color: const Color(0xFFF4C95D),
      ),
      _SidebarItemData(
        label: 'Rotas',
        icon: AppIcons.report,
        onTap: onOpenRoutes,
        color: const Color(0xFFEE8B3A),
      ),
      if (isAdministrator)
        _SidebarItemData(
          label: context.tr!.sidebar_banking_api,
          icon: AppIcons.bank,
          onTap: onOpenBankingApi,
          color: const Color(0xFF52B6FF),
        ),
      if (isAdministrator)
        _SidebarItemData(
          label: context.tr!.sidebar_whatsapp_api,
          icon: AppIcons.telecommunications,
          onTap: onOpenWhatsappApi,
          color: const Color(0xFF43D17A),
        ),
      _SidebarItemData(
        label: context.tr!.sidebar_reports,
        icon: AppIcons.report,
        onTap: onOpenReports,
        color: const Color(0xFFA98BFF),
      ),
      _SidebarItemData(
        label: context.tr!.sidebar_logout,
        icon: AppIcons.logout,
        onTap: () => _confirmLogout(context),
        color: const Color(0xFFFF8E6E),
      ),
    ];

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF10281F), Color(0xFF4B7D60), Color(0xFF76B475)],
          stops: [0, 0.52, 1],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Opacity(
                        opacity: 0.60,
                        child: Image.asset(
                          AppImages.moneyBr,
                          width: 156,
                          fit: BoxFit.contain,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        context.tr!.sidebar_slogan,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.58),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (var i = 0; i < managementItems.length; i++) ...[
                        _SidebarMenuTile(item: managementItems[i]),
                        if (i != managementItems.length - 1)
                          Padding(
                            padding: const EdgeInsetsDirectional.only(
                              start: 58,
                              end: 14,
                            ),
                            child: Divider(
                              height: 0,
                              color: Colors.white.withValues(alpha: 0.08),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final bool? confirmed = await showAppCupertinoDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return CupertinoAlertDialog(
          title: const Text('Sair do Money?'),
          content: const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Sua sessão será encerrada e será necessário informar a senha novamente.',
            ),
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Sair'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await onLogout();
    }
  }
}

class _SidebarMenuTile extends StatelessWidget {
  final _SidebarItemData item;

  const _SidebarMenuTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final arrowIcon = context.isRtl ? AppIcons.angleLeft : AppIcons.angleRight;

    return InkWell(
      onTap: item.onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 14, 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: item.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: SvgIcon(icon: item.icon, width: 15, color: item.color),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  height: 1.15,
                ),
              ),
            ),
            if (item.onTap != null) ...[
              const SizedBox(width: 8),
              SvgIcon(
                icon: arrowIcon,
                width: 11,
                color: Colors.white.withValues(alpha: 0.42),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SidebarItemData {
  final String label;
  final String icon;
  final VoidCallback? onTap;
  final Color color;

  const _SidebarItemData({
    required this.label,
    required this.icon,
    this.onTap,
    required this.color,
  });
}
