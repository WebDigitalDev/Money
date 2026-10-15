import 'package:flutter/material.dart';
import 'package:money/money.dart';

class MenuModalBottomSheet extends StatelessWidget {
  final VoidCallback onNewLoan;
  final VoidCallback onRegisterClient;
  final Key? newLoanKey;

  const MenuModalBottomSheet({
    super.key,
    required this.onNewLoan,
    required this.onRegisterClient,
    this.newLoanKey,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FractionallySizedBox(
        widthFactor: 1,
        child: Stack(
          children: [
            Container(
              margin: EdgeInsets.only(left: 15, right: 15, bottom: 95),
              padding: const EdgeInsets.all(10.0),
              child: Material(
                color: context.colors.surface,
                borderRadius: BorderRadius.circular(20),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MenuTile(
                      key: newLoanKey,
                      title: context.tr!.new_loan,
                      subtitle: context.tr!.new_loan_description,
                      icon: AppIcons.loan,
                      iconColor: const Color(0xFFF39C12),
                      hasDivider: true,
                      onTap: () => _select(context, onNewLoan),
                    ),
                    MenuTile(
                      title: context.tr!.register_client,
                      subtitle: context.tr!.register_client_description,
                      icon: AppIcons.person,
                      iconColor: const Color(0xFF16A085),
                      hasDivider: false,
                      onTap: () => _select(context, onRegisterClient),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              bottom: 28,
              left: MediaQuery.of(context).size.width / 2 - 28,
              child: CustomFloatingActionButton(
                onPressed: () => Navigator.pop(context),
                iconData: Icons.close_outlined,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _select(BuildContext context, VoidCallback action) {
    // Atualiza o destino enquanto o menu inicia o fechamento. Assim a página
    // correspondente já fica pronta por baixo da animação do bottom sheet.
    action();
    Navigator.pop(context);
  }
}
